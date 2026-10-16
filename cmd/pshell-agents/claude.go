package main

import (
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// Claude Code's usage, from five places that each know part of it: the
// transcripts under ~/.claude/projects, the aggregate counters Claude Code
// keeps for machines that have none, pi/omp sessions that ran on an
// Anthropic provider, opencode sessions that did the same, and the
// authoritative rate limits from Anthropic's OAuth usage endpoint.

const (
	claudeID            = "claude"
	claudeName          = "Claude Code"
	claudeAuthHelp      = "Run `claude auth login` to restore authoritative usage."
	claudeUsageEndpoint = "https://api.anthropic.com/api/oauth/usage"
	// A panel opened and shut repeatedly must not become a request per flick,
	// so a probe this recent is reused.
	claudeProbeMinInterval = 15 * time.Second
)

func claudeConfigDir() string {
	value := strings.TrimSpace(os.Getenv("CLAUDE_CONFIG_DIR"))
	if value == "" {
		value = filepath.Join(homeDir(), ".claude")
	}
	return resolvePath(value)
}

// resolvePath is Python's expanduser + expandvars + resolve. A path that does
// not exist still resolves to an absolute one, which is what the originals
// relied on: the projects directory is allowed to be missing.
func resolvePath(value string) string {
	value = os.ExpandEnv(value)
	if value == "~" {
		value = homeDir()
	} else if strings.HasPrefix(value, "~/") {
		value = filepath.Join(homeDir(), value[2:])
	}
	if resolved, err := filepath.EvalSymlinks(value); err == nil {
		value = resolved
	}
	if absolute, err := filepath.Abs(value); err == nil {
		return absolute
	}
	return value
}

// ---------------------------------------------------------------- transcripts

func scanClaudeProjects(projectsPath string, now time.Time) Stats {
	counts := newTally(now)
	seen := map[string]struct{}{}

	walkJSONL(projectsPath, func(path string, info fs.FileInfo) {
		err := eachLine(path, func(lineNumber int, line string) error {
			// A cheap substring test before the JSON parse. Transcripts carry
			// far more lines without usage than with it, and parsing a
			// megabyte of tool output to learn that costs more than the scan.
			if !strings.Contains(line, `"usage":`) {
				return nil
			}
			var entry map[string]any
			if json.Unmarshal([]byte(line), &entry) != nil {
				return nil
			}
			message, _ := entry["message"].(map[string]any)

			if pyStr(entry["type"]) != "assistant" && pyStr(message["role"]) != "assistant" {
				return nil
			}
			usage, ok := firstTruthy(message["usage"], entry["usage"]).(map[string]any)
			if !ok {
				return nil
			}

			// One assistant message can appear in several transcripts -- a
			// resumed session, a compacted one -- and its id is what tells
			// the copies apart. Lines without an id fall back to a key that
			// is unique within the file.
			messageID := firstTruthy(message["id"], entry["messageId"], "")
			var uniqueKey string
			if truthy(messageID) {
				uniqueKey = pyStr(messageID)
			} else {
				local := firstTruthy(entry["uuid"], entry["requestId"], float64(lineNumber))
				uniqueKey = fmt.Sprintf("%s:%s", path, pyStr(local))
			}
			if _, done := seen[uniqueKey]; done {
				return nil
			}
			seen[uniqueKey] = struct{}{}

			input := usageToken(usage, "input_tokens", "inputTokens")
			output := usageToken(usage, "output_tokens", "outputTokens")
			cacheRead := usageToken(usage, "cache_read_input_tokens", "cacheReadInputTokens")
			cacheWrite := usageToken(usage, "cache_creation_input_tokens", "cacheCreationInputTokens")
			if input+output+cacheRead+cacheWrite <= 0 {
				return nil
			}

			model := pyStr(firstTruthy(message["model"], entry["model"], "claude"))
			day := localDay(firstTruthy(entry["timestamp"], message["timestamp"]), now)
			session := pyStr(firstTruthy(entry["sessionId"], path))
			counts.add(day, session, model, input, output, cacheRead, cacheWrite)
			return nil
		})
		if err != nil {
			warnf("Ignoring unreadable Claude project file %s: %v", path, err)
		}
	})

	return counts.stats()
}

func claudeScanCachePaths(projectsPath string) (string, string, error) {
	root, err := cacheRoot()
	if err != nil {
		return "", "", err
	}
	digest := sha1.Sum([]byte(projectsPath))
	name := "claude-scan-" + hex.EncodeToString(digest[:])[:16]
	return filepath.Join(root, name+".json"), filepath.Join(root, name+".lock"), nil
}

// statsEnvelope is how every Claude usage cache is stored: the stats plus the
// local date they were scanned on. Stats is nil when a source was checked and
// had nothing to report.
type statsEnvelope struct {
	ScanDate string `json:"scanDate"`
	Stats    *Stats `json:"stats"`
}

// readTodaysCachedStats is readFreshJSON plus the date check codex.go makes.
// The today* fields only mean "today" on the day they were scanned, so a
// cache written at 23:55 and read at 00:05 is a miss however young its mtime
// is; otherwise yesterday's tokens show up as today's until it expires. A
// cache from before the date was recorded has no ScanDate and misses too.
func readTodaysCachedStats(cacheFile string, maxAge time.Duration, today string) (*Stats, bool) {
	var cached statsEnvelope
	if !readFreshJSON(cacheFile, maxAge, &cached) || cached.ScanDate != today {
		return nil, false
	}
	return cached.Stats, true
}

func cachedClaudeScan(projectsPath string, maxAge time.Duration, now time.Time) Stats {
	cacheFile, lockFile, err := claudeScanCachePaths(projectsPath)
	if err != nil {
		warnf("claude: cache unavailable (%v); scanning directly", err)
		return scanClaudeProjects(projectsPath, now)
	}

	// The transcript scan always produces stats, so a hit without any is a
	// damaged file rather than an empty answer.
	today := dateString(now)
	if cached, ok := readTodaysCachedStats(cacheFile, maxAge, today); ok && cached != nil {
		return *cached
	}

	var stats Stats
	withLock(lockFile, func() {
		if cached, ok := readTodaysCachedStats(cacheFile, maxAge, today); ok && cached != nil {
			stats = *cached
			return
		}
		stats = scanClaudeProjects(projectsPath, now)
		if err := writeJSONAtomic(cacheFile, statsEnvelope{ScanDate: today, Stats: &stats}, 0o644); err != nil {
			warnf("claude: could not write usage cache (%v)", err)
		}
	})
	return stats
}

// ------------------------------------------------------------ local fallback
//
// A machine without transcripts on disk can still know its history: Claude
// Code keeps aggregate counters in stats-cache.json and per-prompt history in
// history.jsonl. Only consulted when the transcript scan comes back empty.

func claudeStatsCacheFallback(claudeDir string, now time.Time) (Stats, bool) {
	content, err := os.ReadFile(filepath.Join(claudeDir, "stats-cache.json"))
	if err != nil {
		return Stats{}, false
	}
	var data map[string]any
	if json.Unmarshal(content, &data) != nil {
		return Stats{}, false
	}

	today := dateString(now)
	todayTokens := map[string]int64{}
	if rows, ok := data["dailyModelTokens"].([]any); ok {
		for _, raw := range rows {
			entry, ok := raw.(map[string]any)
			if !ok || pyStr(entry["date"]) != today {
				continue
			}
			if byModel, ok := entry["tokensByModel"].(map[string]any); ok {
				for model, count := range byModel {
					todayTokens[model] = claudeNumber(count)
				}
			}
			break
		}
	}

	dailyActivity := []map[string]any{}
	if rows, ok := data["dailyActivity"].([]any); ok {
		for _, raw := range rows {
			if entry, ok := raw.(map[string]any); ok {
				dailyActivity = append(dailyActivity, entry)
			}
		}
	}

	dates := map[string]struct{}{}
	for _, entry := range dailyActivity {
		if claudeNumber(entry["messageCount"]) > 0 && truthy(entry["date"]) {
			dates[pyStr(entry["date"])] = struct{}{}
		}
	}
	activeDates := sortedKeys(dates)

	recent := dailyActivity
	if len(recent) > 7 {
		recent = recent[len(recent)-7:]
	}
	days := make([]Day, 0, len(recent))
	for _, entry := range recent {
		days = append(days, Day{Date: pyStr(entry["date"]), MessageCount: claudeNumber(entry["messageCount"])})
	}

	usage := map[string]*Bucket{}
	if byModel, ok := data["modelUsage"].(map[string]any); ok {
		for model, raw := range byModel {
			bucket, ok := raw.(map[string]any)
			if !ok {
				continue
			}
			usage[model] = &Bucket{
				InputTokens:              claudeNumber(bucket["inputTokens"]),
				OutputTokens:             claudeNumber(bucket["outputTokens"]),
				CacheReadInputTokens:     claudeNumber(bucket["cacheReadInputTokens"]),
				CacheCreationInputTokens: claudeNumber(bucket["cacheCreationInputTokens"]),
			}
		}
	}

	var total int64
	for _, count := range todayTokens {
		total += count
	}
	prompts, sessions := claudeTodayFromHistory(claudeDir, now)

	return Stats{
		TodayPrompts:       prompts,
		TodaySessions:      sessions,
		TodayTotalTokens:   total,
		TodayTokensByModel: todayTokens,
		RecentDays:         days,
		TotalPrompts:       int(claudeNumber(data["totalMessages"])),
		TotalSessions:      int(claudeNumber(data["totalSessions"])),
		ActiveDays:         len(activeDates),
		ActiveDates:        activeDates,
		ModelUsage:         usage,
	}, true
}

// claudeTodayFromHistory counts today's prompts from history.jsonl, walking
// backwards and stopping at the first entry older than local midnight. The
// file is append-ordered, so the tail is today and the rest is not worth
// reading.
func claudeTodayFromHistory(claudeDir string, now time.Time) (int, int) {
	content, err := os.ReadFile(filepath.Join(claudeDir, "history.jsonl"))
	if err != nil {
		return 0, 0
	}
	year, month, day := now.Date()
	startOfDay := float64(time.Date(year, month, day, 0, 0, 0, 0, now.Location()).UnixNano()) / 1e6

	lines := strings.Split(string(content), "\n")
	prompts := 0
	sessions := map[string]struct{}{}
	for index := len(lines) - 1; index >= 0; index-- {
		line := strings.TrimSpace(lines[index])
		if line == "" {
			continue
		}
		var entry map[string]any
		if json.Unmarshal([]byte(line), &entry) != nil {
			continue
		}
		if float64(claudeNumber(entry["timestamp"])) < startOfDay {
			break
		}
		prompts++
		if truthy(entry["sessionId"]) {
			sessions[pyStr(entry["sessionId"])] = struct{}{}
		}
	}
	return prompts, len(sessions)
}

// --------------------------------------------------------------- pi and omp
//
// These agents can spend a Claude subscription without writing a native
// Claude Code transcript. Their session format carries the provider, model
// and token usage on every assistant message.

func piSessionRoots() []string {
	return []string{
		filepath.Join(homeDir(), ".pi", "agent", "sessions"),
		filepath.Join(homeDir(), ".omp", "agent", "sessions"),
	}
}

func scanClaudePiUsage(maxAge time.Duration, now time.Time) *Stats {
	root, err := cacheRoot()
	if err != nil {
		warnf("claude: cache unavailable (%v); scanning pi sessions directly", err)
		return scanClaudePiSessions(now)
	}
	cacheFile := filepath.Join(root, "claude-pi-sessions.json")

	today := dateString(now)
	if cached, ok := readTodaysCachedStats(cacheFile, maxAge, today); ok {
		return cached
	}

	stats := scanClaudePiSessions(now)
	// Written even when nothing was found: "checked recently, nothing there"
	// is an answer worth caching too.
	if err := writeJSONAtomic(cacheFile, statsEnvelope{ScanDate: today, Stats: stats}, 0o644); err != nil {
		warnf("claude: could not write pi usage cache (%v)", err)
	}
	return stats
}

func scanClaudePiSessions(now time.Time) *Stats {
	counts := newTally(now)
	seen := map[string]struct{}{}

	for _, root := range piSessionRoots() {
		walkJSONL(root, func(path string, info fs.FileInfo) {
			eachLine(path, func(lineNumber int, line string) error {
				if !strings.Contains(line, `"usage"`) || !strings.Contains(line, `"assistant"`) {
					return nil
				}
				var entry map[string]any
				if json.Unmarshal([]byte(line), &entry) != nil {
					return nil
				}
				message, _ := entry["message"].(map[string]any)
				if pyStr(entry["type"]) != "message" || pyStr(message["role"]) != "assistant" {
					return nil
				}
				// Only Anthropic-provider messages spend this subscription.
				if pyStr(message["provider"]) != "anthropic" {
					return nil
				}
				key := fmt.Sprintf("%s:%s", path, pyStr(firstTruthy(entry["id"], float64(lineNumber))))
				if _, done := seen[key]; done {
					return nil
				}
				seen[key] = struct{}{}

				usage, _ := message["usage"].(map[string]any)
				input := usageToken(usage, "input", "inputTokens")
				output := usageToken(usage, "output", "outputTokens")
				cacheRead := usageToken(usage, "cacheRead", "cache_read_input_tokens")
				cacheWrite := usageToken(usage, "cacheWrite", "cache_creation_input_tokens")
				total := input + output + cacheRead + cacheWrite
				if total <= 0 {
					// A session that only reported a grand total still spent
					// the tokens; file the lot as input rather than nothing.
					total = claudeNumber(usage["totalTokens"])
					input = total
				}
				if total <= 0 {
					return nil
				}

				model := pyStr(firstTruthy(message["model"], "claude"))
				day := localDay(firstTruthy(entry["timestamp"], message["timestamp"]), now)
				counts.add(day, path, model, input, output, cacheRead, cacheWrite)
				return nil
			})
		})
	}

	if counts.prompts == 0 {
		return nil
	}
	stats := counts.stats()
	return &stats
}

// ----------------------------------------------------------------- opencode

func scanClaudeOpencodeUsage(maxAge time.Duration, now time.Time) *Stats {
	db := opencodeDBPath()
	if info, err := os.Stat(db); err != nil || !info.Mode().IsRegular() {
		return nil
	}

	root, err := cacheRoot()
	if err != nil {
		warnf("claude: cache unavailable (%v); scanning opencode directly", err)
		return scanClaudeOpencode(now)
	}
	digest := sha1.Sum([]byte(db))
	cacheFile := filepath.Join(root, "claude-opencode-"+hex.EncodeToString(digest[:])[:16]+".json")

	// The same freshness contract as the transcript scan: --limits-only
	// promises to reuse recent local stats, and a large opencode history
	// walked on every panel open would break that promise.
	today := dateString(now)
	if cached, ok := readTodaysCachedStats(cacheFile, maxAge, today); ok {
		return cached
	}

	stats := scanClaudeOpencode(now)
	if err := writeJSONAtomic(cacheFile, statsEnvelope{ScanDate: today, Stats: stats}, 0o644); err != nil {
		warnf("claude: could not write opencode usage cache (%v)", err)
	}
	return stats
}

func scanClaudeOpencode(now time.Time) *Stats {
	rows, ok := readOpencodeRows("anthropic")
	if !ok {
		return nil
	}
	counts := newTally(now)
	today := dateString(now)

	for _, row := range rows {
		input := claudeNumber(row.Input)
		// opencode keeps thinking tokens out of output; both are generated.
		output := claudeNumber(row.Output) + claudeNumber(row.Reasoning)
		cacheRead := claudeNumber(row.CacheRead)
		cacheWrite := claudeNumber(row.CacheWrite)
		if input+output+cacheRead+cacheWrite <= 0 {
			continue
		}

		created := claudeNumber(row.Created)
		day := today
		if created > 0 {
			day = dateString(time.UnixMilli(created).In(time.Local))
		}
		model := lastPathSegment(pyStr(firstTruthy(row.ModelID, "claude")))
		counts.add(day, "opencode:"+row.SessionID, model, input, output, cacheRead, cacheWrite)
	}

	if counts.prompts == 0 {
		return nil
	}
	stats := counts.stats()
	return &stats
}

// ------------------------------------------------------------------- limits

// claudeOAuthLogin returns the access token, its expiry and the display-safe
// plan label. Nothing else leaves the credential store: the token goes
// nowhere but the Authorization header of the limits probe, and only the plan
// label may travel into the printed record.
func claudeOAuthLogin(claudeDir string) (string, int64, string) {
	content, err := os.ReadFile(filepath.Join(claudeDir, ".credentials.json"))
	if err != nil {
		return "", 0, ""
	}
	var data map[string]any
	if json.Unmarshal(content, &data) != nil {
		return "", 0, ""
	}
	login, ok := data["claudeAiOauth"].(map[string]any)
	if !ok {
		return "", 0, ""
	}
	plan := claudePlanLabel(pyStr(firstTruthy(login["rateLimitTier"], "")), pyStr(firstTruthy(login["subscriptionType"], "")))
	return pyStr(firstTruthy(login["accessToken"], "")), claudeNumber(login["expiresAt"]), plan
}

var maxTierPattern = regexp.MustCompile(`(?i)max_(\d+x)`)

func claudePlanLabel(tier, subscription string) string {
	if tier != "" {
		if match := maxTierPattern.FindStringSubmatch(tier); match != nil {
			return "Max " + match[1]
		}
	}
	if subscription != "" {
		runes := []rune(subscription)
		return strings.ToUpper(string(runes[0])) + string(runes[1:])
	}
	return ""
}

// parseUtilization is float(str(value).strip().replace("%", "")), returning
// NaN where that would have raised.
func parseUtilization(value any) float64 {
	text := strings.ReplaceAll(strings.TrimSpace(pyStr(value)), "%", "")
	n, err := strconv.ParseFloat(strings.TrimSpace(text), 64)
	if err != nil {
		return math.NaN()
	}
	return n
}

// normalizeUtilization turns whatever the endpoint reported into a 0..1
// fraction, or -1 for "no number here".
//
// Anthropic's OAuth usage endpoint currently reports percentages (37.0, or
// 1.0). Older payloads sometimes used fractions (0.37). A payload containing
// any value at or above 1 is percent-scaled, so 1.0 renders as 1%, not 100%.
func normalizeUtilization(value any, percentScale bool) float64 {
	n := parseUtilization(value)
	if !(n >= 0) {
		return -1
	}
	if percentScale || n > 1 {
		return math.Min(1, n/100)
	}
	return math.Min(1, n)
}

// pyISOFormat is Python's datetime.isoformat(): six fractional digits, or
// none at all when the microsecond is zero. Reproduced rather than replaced
// because these strings go into the record beside timestamps the endpoint
// wrote, and AgentUsage.qml's parseTime already trims them.
func pyISOFormat(when time.Time) string {
	if when.Nanosecond()/1000 == 0 {
		return when.Format("2006-01-02T15:04:05-07:00")
	}
	return when.Format("2006-01-02T15:04:05.000000-07:00")
}

var digitsOnly = regexp.MustCompile(`^\d+$`)

func normalizeResetAt(value any) string {
	if value == nil {
		return ""
	}
	raw := strings.TrimSpace(pyStr(value))
	if raw == "" {
		return ""
	}
	if digitsOnly.MatchString(raw) {
		ts, err := strconv.ParseInt(raw, 10, 64)
		if err != nil {
			return raw
		}
		// Seconds and milliseconds both turn up; a value below 10^12 is too
		// small to be milliseconds this century.
		if ts < 1_000_000_000_000 {
			ts *= 1000
		}
		return pyISOFormat(time.UnixMilli(ts).UTC())
	}
	when, ok := parseISO(raw)
	if !ok {
		return raw
	}
	return pyISOFormat(when)
}

// scopedWindow names the window an entry's `kind` describes
// ("weekly_scoped", "five_hour_scoped"). The panel would otherwise have to
// read a window out of free text, which cannot survive a model name like
// "Opus 5 (1M context)" -- the "1M" reads as a one-minute window -- so the
// window is settled here and travels as an explicit title.
func scopedWindow(kind string) string {
	text := strings.ToLower(kind)
	switch {
	case strings.Contains(text, "month"):
		return "Monthly"
	case strings.Contains(text, "week"), strings.Contains(text, "day"):
		return "Weekly"
	case strings.Contains(text, "hour"), strings.Contains(text, "session"):
		return "Session"
	}
	return ""
}

// scopedLimits reads the payload's `limits` array, which is the only place a
// model-scoped allowance shows up -- a weekly window only Fable draws from,
// say. The matching legacy keys (`seven_day_opus`, `seven_day_sonnet`) stayed
// behind at null, so reading the flat buckets alone silently drops a limit
// the account is really spending against. A model can hold more than one
// scoped window, so both the model and the window make the title and the key
// that keeps a repeat out.
func scopedLimits(payload map[string]any, percentScale bool) []Limit {
	entries, ok := payload["limits"].([]any)
	if !ok {
		return nil
	}
	var out []Limit
	seen := map[string]struct{}{}
	for _, raw := range entries {
		entry, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		scope, _ := entry["scope"].(map[string]any)
		model, ok := scope["model"].(map[string]any)
		if !ok {
			continue
		}
		// A display name is what the panel wants, but an entry carrying only
		// an id still names a window worth showing.
		name := strings.TrimSpace(pyStr(firstTruthy(model["display_name"], model["id"], "")))
		kind := strings.TrimSpace(pyStr(firstTruthy(entry["kind"], "")))
		key := name + "\x00" + kind
		if name == "" {
			continue
		}
		if _, done := seen[key]; done {
			continue
		}
		percent := normalizeUtilization(entry["percent"], percentScale)
		if percent < 0 {
			continue
		}
		seen[key] = struct{}{}

		title := name
		if window := scopedWindow(kind); window != "" {
			title = name + " " + window
		}
		out = append(out, Limit{
			Label:    title,
			Title:    title,
			Percent:  percent,
			ResetsAt: normalizeResetAt(entry["resets_at"]),
		})
	}
	return out
}

type probeResult struct {
	ok        bool
	transport bool
	limits    []Limit
	helpText  string
}

func probeClaudeLimits(endpoint, accessToken string) probeResult {
	client := &http.Client{Timeout: 10 * time.Second}
	request, err := http.NewRequest(http.MethodGet, endpoint, nil)
	if err != nil {
		return probeResult{transport: true, helpText: claudeTransportHelp}
	}
	request.Header.Set("Authorization", "Bearer "+accessToken)
	request.Header.Set("anthropic-beta", "oauth-2025-04-20")
	request.Header.Set("Accept", "application/json")

	response, err := client.Do(request)
	if err != nil {
		// A transport failure reached no server at all -- no route, no DNS.
		// Any real answer, including an error status, is a server we should
		// stop pestering; this is not.
		return probeResult{transport: true, helpText: claudeTransportHelp}
	}
	defer response.Body.Close()

	if response.StatusCode >= 400 {
		if response.StatusCode == http.StatusTooManyRequests {
			retryAfter := response.Header.Get("retry-after")
			help := "Anthropic's usage endpoint is rate limiting checks right now"
			if retryAfter != "" {
				help += fmt.Sprintf(" (retry after %ss)", retryAfter)
			}
			return probeResult{helpText: help + ". Local Claude Code stats are still shown."}
		}
		return probeResult{helpText: fmt.Sprintf(
			"Anthropic's usage endpoint returned status %d. Local Claude Code stats are still shown.", response.StatusCode)}
	}

	body, err := io.ReadAll(response.Body)
	if err != nil {
		return probeResult{transport: true, helpText: claudeTransportHelp}
	}
	var payload map[string]any
	if json.Unmarshal(body, &payload) != nil {
		return probeResult{transport: true, helpText: claudeTransportHelp}
	}

	weekly, _ := firstTruthy(payload["seven_day_oauth_apps"], payload["seven_day"]).(map[string]any)
	session, _ := payload["five_hour"].(map[string]any)

	// One payload speaks one convention, so the scoped entries settle the
	// scale alongside the flat buckets rather than assuming their own.
	raw := []any{nil, nil}
	if session != nil {
		raw[0] = session["utilization"]
	}
	if weekly != nil {
		raw[1] = weekly["utilization"]
	}
	if entries, ok := payload["limits"].([]any); ok {
		for _, item := range entries {
			if entry, ok := item.(map[string]any); ok {
				raw = append(raw, entry["percent"])
			}
		}
	}
	percentScale := false
	for _, value := range raw {
		if parseUtilization(value) >= 1 {
			percentScale = true
			break
		}
	}

	limits := []Limit{}
	if session != nil {
		if percent := normalizeUtilization(session["utilization"], percentScale); percent >= 0 {
			limits = append(limits, Limit{Label: "Session (5-hour)", Percent: percent, ResetsAt: normalizeResetAt(session["resets_at"])})
		}
	}
	if weekly != nil {
		if percent := normalizeUtilization(weekly["utilization"], percentScale); percent >= 0 {
			limits = append(limits, Limit{Label: "Weekly (7-day)", Percent: percent, ResetsAt: normalizeResetAt(weekly["resets_at"])})
		}
	}
	limits = append(limits, scopedLimits(payload, percentScale)...)

	if len(limits) == 0 {
		return probeResult{helpText: "Anthropic's usage endpoint returned no limits. Local Claude Code stats are still shown."}
	}
	return probeResult{ok: true, limits: limits}
}

const claudeTransportHelp = "Couldn't reach Anthropic's usage endpoint. Retrying shortly. Local Claude Code stats are still shown."

type limitsCache struct {
	FetchedAtMs int64   `json:"fetchedAtMs"`
	Limits      []Limit `json:"limits"`
}

// limitWindowOpen decides whether a cached percentage still describes
// anything. A measured figure outlives the probe that took it, but only until
// its window rolls over: once a window has reset, a stale 78% misreports an
// allowance that is now untouched. A window with no reset time, or one that
// will not parse, is kept -- an unreadable timestamp is no reason to throw
// away a real number.
func limitWindowOpen(limit Limit, now time.Time) bool {
	if limit.ResetsAt == "" {
		return true
	}
	when, ok := parseISO(limit.ResetsAt)
	if !ok {
		return true
	}
	return when.After(now)
}

func usableCachedLimits(cached limitsCache, now time.Time) []Limit {
	out := []Limit{}
	for _, limit := range cached.Limits {
		if limitWindowOpen(limit, now) {
			out = append(out, limit)
		}
	}
	return out
}

type claudeLimits struct {
	limits          []Limit
	usageStatusText string
	authHelpText    string
	retryAdvised    bool
}

func collectClaudeLimits(endpoint, accessToken string, expiresAtMs int64, force bool, now time.Time) claudeLimits {
	result := claudeLimits{limits: []Limit{}, authHelpText: claudeAuthHelp}

	var cached limitsCache
	cacheFile := ""
	if root, err := cacheRoot(); err == nil {
		cacheFile = filepath.Join(root, "claude-limits.json")
		readJSONAnyAge(cacheFile, &cached)
	}
	fallback := usableCachedLimits(cached, now)

	// Probing needs a live token and only the Claude Code CLI can mint one:
	// it refreshes the credential file when it runs, so a machine left alone
	// long enough finds the saved token lapsed. Say so -- an empty limits
	// list with nothing else set hides the whole section and explains
	// nothing -- and keep showing the last numbers whose window has not
	// since reset.
	if accessToken == "" {
		result.limits = fallback
		result.usageStatusText = "Waiting for auth"
		return result
	}
	if expiresAtMs > 0 && expiresAtMs <= now.UnixMilli() {
		result.limits = fallback
		result.usageStatusText = "Sign-in expired"
		tail := "."
		if len(fallback) > 0 {
			tail = " — showing the last known limits."
		}
		result.authHelpText = "Claude Code's saved sign-in expired" + tail +
			" Start Claude Code, or run `claude auth login`, to refresh it."
		return result
	}

	// --force is a person asking for fresh numbers, so it skips the reuse
	// window entirely; the interval absorbs repeated panel opens, it does not
	// overrule someone who pressed refresh.
	if len(fallback) > 0 && !force {
		if now.Sub(time.UnixMilli(cached.FetchedAtMs)) < claudeProbeMinInterval {
			result.limits = fallback
			return result
		}
	}

	probe := probeClaudeLimits(endpoint, accessToken)
	if probe.ok {
		result.limits = probe.limits
		if cacheFile != "" {
			if err := writeJSONAtomic(cacheFile, limitsCache{FetchedAtMs: now.UnixMilli(), Limits: probe.limits}, 0o644); err != nil {
				warnf("claude: could not write limits cache (%v)", err)
			}
		}
		return result
	}

	// The first probe after login often fires before DHCP has handed out a
	// route. Ask the shell to try again sooner than its regular interval.
	if probe.transport {
		result.retryAdvised = true
	}
	if len(fallback) > 0 {
		result.limits = fallback
	} else {
		result.usageStatusText = "Claude limits unavailable"
		result.authHelpText = probe.helpText
	}
	return result
}

// ------------------------------------------------------------------- record

func collectClaude(opts options) (Record, error) {
	now := opts.now
	claudeDir := claudeConfigDir()
	stats := cachedClaudeScan(filepath.Join(claudeDir, "projects"), opts.scanAge(), now)

	if stats.TotalPrompts <= 0 {
		if fallback, ok := claudeStatsCacheFallback(claudeDir, now); ok {
			stats = fallback
		} else {
			// No transcripts and no aggregate cache, but history.jsonl alone
			// can still put numbers on today.
			prompts, sessions := claudeTodayFromHistory(claudeDir, now)
			if prompts > 0 || sessions > 0 {
				stats.TodayPrompts = prompts
				stats.TodaySessions = sessions
			}
		}
	}

	if pi := scanClaudePiUsage(opts.scanAge(), now); pi != nil {
		stats = mergeStats(stats, *pi)
	}
	if opencode := scanClaudeOpencodeUsage(opts.scanAge(), now); opencode != nil {
		stats = mergeStats(stats, *opencode)
	}

	accessToken, expiresAtMs, plan := claudeOAuthLogin(claudeDir)
	limits := collectClaudeLimits(claudeUsageEndpoint, accessToken, expiresAtMs, opts.force, now)

	return Record{
		SchemaVersion:   schemaVersion,
		ID:              claudeID,
		Name:            claudeName,
		UpdatedAt:       pyISOFormat(now.UTC()),
		Ready:           stats.TotalPrompts > 0 || len(limits.limits) > 0,
		HasLocalStats:   true,
		TierLabel:       plan,
		UsageStatusText: limits.usageStatusText,
		AuthHelpText:    limits.authHelpText,
		RetryAdvised:    limits.retryAdvised,
		Limits:          limits.limits,
		Stats:           stats,
	}, nil
}
