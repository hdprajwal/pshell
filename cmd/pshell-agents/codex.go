package main

import (
	"bufio"
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"
)

// Codex's usage: native CLI session files, pi/omp sessions that ran through
// openai-codex, and opencode sessions that ran on an OpenAI provider. The
// plan and the rate limits come from the Codex app-server, which speaks
// JSON-RPC over a pipe.

const (
	codexID       = "codex"
	codexName     = "Codex"
	codexAuthHelp = "Run `codex login` to authenticate."

	// A scan this recent is only reused to dedup concurrent runs; every
	// periodic widget refresh lands a real rescan however low the interval is
	// set. --limits-only promises only fresh limits, so it may reuse a scan
	// for far longer.
	codexScanReuse       = 20 * time.Second
	codexLimitsOnlyReuse = 900 * time.Second

	// Native sessions older than this are not read. Codex keeps years of
	// them and the panel shows a month.
	codexSessionMaxAge = 30 * 24 * time.Hour
)

func codexHome() string {
	if value := strings.TrimSpace(os.Getenv("CODEX_HOME")); value != "" {
		return value
	}
	return filepath.Join(homeDir(), ".codex")
}

// codexPath is the PATH the collector looks for `codex` and `rg` on. A shell
// widget inherits whatever environment the compositor was started with, which
// on a machine that installs its tools through npm or mise is missing the
// directory the binary actually lives in.
func codexPath() string {
	home := homeDir()
	parts := []string{
		os.Getenv("PATH"),
		filepath.Join(home, ".local", "bin"),
		filepath.Join(home, ".npm-global", "bin"),
		filepath.Join(home, ".local", "share", "mise", "shims"),
	}
	kept := make([]string, 0, len(parts))
	for _, part := range parts {
		if part != "" {
			kept = append(kept, part)
		}
	}
	return strings.Join(kept, string(os.PathListSeparator))
}

func lookPathIn(name, searchPath string) (string, bool) {
	for _, dir := range filepath.SplitList(searchPath) {
		if dir == "" {
			continue
		}
		candidate := filepath.Join(dir, name)
		info, err := os.Stat(candidate)
		if err != nil || info.IsDir() || info.Mode()&0o111 == 0 {
			continue
		}
		return candidate, true
	}
	return "", false
}

// --------------------------------------------------------------- pi and omp

var (
	piProviderPattern = regexp.MustCompile(`"provider"\s*:\s*"openai-codex"`)
	piAPIPattern      = regexp.MustCompile(`"api"\s*:\s*"openai-codex`)
)

// looksBinary keeps this out of whatever else lives under a session root.
// The original shelled out to ripgrep, which refuses a file whose head holds
// a NUL byte; a walk of its own has to make the same call or it will try to
// parse a database as JSON lines.
func looksBinary(path string) bool {
	file, err := os.Open(path)
	if err != nil {
		return true
	}
	defer file.Close()
	head := make([]byte, 8192)
	n, _ := file.Read(head)
	return bytes.IndexByte(head[:n], 0) >= 0
}

func scanCodexPiSessions(counts *tally, now time.Time) {
	seen := map[string]struct{}{}
	for _, root := range piSessionRoots() {
		walkFiles(root, func(path string, info fs.FileInfo) {
			if looksBinary(path) {
				return
			}
			eachLine(path, func(lineNumber int, line string) error {
				if !piProviderPattern.MatchString(line) && !piAPIPattern.MatchString(line) {
					return nil
				}
				var entry map[string]any
				if json.Unmarshal([]byte(line), &entry) != nil {
					return nil
				}
				if pyStr(entry["type"]) != "message" {
					return nil
				}
				key := path + ":" + pyStr(firstTruthy(entry["id"], ""))
				if _, done := seen[key]; done {
					return nil
				}
				seen[key] = struct{}{}

				message, _ := entry["message"].(map[string]any)
				if pyStr(message["role"]) != "assistant" {
					return nil
				}
				provider := pyStr(firstTruthy(message["provider"], ""))
				api := pyStr(firstTruthy(message["api"], ""))
				if provider != "openai-codex" && !strings.HasPrefix(api, "openai-codex") {
					return nil
				}
				usage, _ := message["usage"].(map[string]any)
				if len(usage) == 0 {
					return nil
				}

				total := codexNumber(usage["totalTokens"])
				input := codexNumber(usage["input"])
				output := codexNumber(usage["output"])
				cacheRead := codexNumber(usage["cacheRead"])
				cacheWrite := codexNumber(usage["cacheWrite"])
				if total != 0 && input == 0 && output == 0 && cacheRead == 0 && cacheWrite == 0 {
					// A session that only reported a grand total still spent
					// the tokens; file the lot as input rather than nothing.
					input = total
				}
				if input == 0 && output == 0 && cacheRead == 0 && cacheWrite == 0 {
					return nil
				}

				day := localDay(firstTruthy(entry["timestamp"], message["timestamp"]), now)
				counts.add(day, path, codexModelName(message["model"]), input, output, cacheRead, cacheWrite)
				return nil
			})
		})
	}
}

func codexModelName(raw any) string {
	if !truthy(raw) {
		return "codex"
	}
	name := pyStr(raw)
	if name == "" {
		return "codex"
	}
	return name
}

// ------------------------------------------------------------ native sessions

func scanNativeCodexSessions(counts *tally, now time.Time) {
	home := codexHome()
	cutoff := now.Add(-codexSessionMaxAge)

	var files []string
	for _, root := range []string{filepath.Join(home, "sessions"), filepath.Join(home, "archived_sessions")} {
		walkJSONL(root, func(path string, info fs.FileInfo) {
			if !info.ModTime().Before(cutoff) {
				files = append(files, path)
			}
		})
	}

	for _, path := range files {
		fileInfo, statErr := os.Stat(path)
		currentModel := "codex"
		eachLine(path, func(lineNumber int, line string) error {
			var entry map[string]any
			if json.Unmarshal([]byte(line), &entry) != nil {
				return nil
			}
			kind := pyStr(entry["type"])
			if kind == "turn_context" {
				payload, _ := entry["payload"].(map[string]any)
				currentModel = codexModelName(firstTruthy(payload["model"], payload["model_slug"], currentModel))
				return nil
			}

			var payload map[string]any
			if inner, ok := entry["payload"].(map[string]any); ok && len(inner) > 0 {
				payload = inner
			} else {
				payload = entry
			}
			if kind == "response_item" {
				if inner, ok := payload["payload"].(map[string]any); ok && len(inner) > 0 {
					payload = inner
				}
			}
			if pyStr(payload["type"]) != "token_count" {
				return nil
			}

			info, _ := payload["info"].(map[string]any)
			// total_token_usage is cumulative for the session. Adding every
			// snapshot makes usage grow quadratically, so count the last turn.
			usage, _ := info["last_token_usage"].(map[string]any)
			cacheRead := codexNumber(usage["cached_input_tokens"])
			cacheWrite := codexNumber(usage["cache_write_input_tokens"])
			// Cached tokens are included in input_tokens, and reasoning
			// tokens in output_tokens. Keep the cache split without counting
			// either category twice.
			input := codexNumber(usage["input_tokens"]) - cacheRead - cacheWrite
			if input < 0 {
				input = 0
			}
			output := codexNumber(usage["output_tokens"])
			if input == 0 && output == 0 && cacheRead == 0 && cacheWrite == 0 {
				return nil
			}

			var stamp any
			if truthy(entry["timestamp"]) {
				stamp = entry["timestamp"]
			} else if statErr == nil {
				stamp = float64(fileInfo.ModTime().UnixNano()) / 1e9
			}
			counts.add(localDay(stamp, now), path, currentModel, input, output, cacheRead, cacheWrite)
			return nil
		})
	}
}

// ----------------------------------------------------------------- opencode

// scanCodexOpencodeSessions returns whether the read ran to completion. A
// scan cut short still contributes what it read, but must not be cached as if
// it were the whole story.
func scanCodexOpencodeSessions(counts *tally, now time.Time) bool {
	rows, complete := readOpencodeRows("openai")
	for _, row := range rows {
		input := codexNumber(row.Input)
		// opencode keeps thinking tokens out of output; both are generated.
		output := codexNumber(row.Output) + codexNumber(row.Reasoning)
		cacheRead := codexNumber(row.CacheRead)
		cacheWrite := codexNumber(row.CacheWrite)
		if input == 0 && output == 0 && cacheRead == 0 && cacheWrite == 0 {
			continue
		}
		model := codexModelName(lastPathSegment(pyStr(firstTruthy(row.ModelID, ""))))
		counts.add(localDay(row.Created, now), "opencode:"+row.SessionID, model, input, output, cacheRead, cacheWrite)
	}
	return complete
}

// -------------------------------------------------------------------- cache

// codexCacheEnvelope is versioned around the stats so a corrupted or
// foreign-shaped file is a cache miss -- rescan and rewrite -- rather than a
// crash or a garbage record.
type codexCacheEnvelope struct {
	SchemaVersion int    `json:"schemaVersion"`
	ScanDate      string `json:"scanDate"`
	Stats         *Stats `json:"stats"`
}

func codexScanCachePaths() (string, string, error) {
	root, err := cacheRoot()
	if err != nil {
		return "", "", err
	}
	// The digest covers every data path the scan reads: the Codex session
	// roots, the opencode database, and (via the home directory) the pi and
	// omp session roots.
	seed := homeDir() + "\n" + codexHome() + "\n" + opencodeDBPath()
	digest := sha1.Sum([]byte(seed))
	name := "codex-scan-" + hex.EncodeToString(digest[:])[:16]
	return filepath.Join(root, name+".json"), filepath.Join(root, name+".lock"), nil
}

func readCodexCachedStats(cacheFile string, maxAge time.Duration, today string) *Stats {
	var cached codexCacheEnvelope
	if !readFreshJSON(cacheFile, maxAge, &cached) {
		return nil
	}
	if cached.SchemaVersion != schemaVersion || cached.Stats == nil {
		return nil
	}
	// today* fields only mean "today" on the day they were scanned. A cache
	// from another local date -- midnight passed, or the clock moved -- is a
	// miss, not merely old, whatever its mtime says.
	if cached.ScanDate != today {
		return nil
	}
	return cached.Stats
}

func runCodexLocalScans(now time.Time) (Stats, bool) {
	counts := newTally(now)
	scanCodexPiSessions(counts, now)
	scanNativeCodexSessions(counts, now)
	complete := scanCodexOpencodeSessions(counts, now)
	return counts.stats(), complete
}

// cachedCodexLocalStats treats the cache as a pure optimisation: any
// cache-layer failure degrades to a direct scan and a warning on stderr. The
// record is the contract; the cache is not.
func cachedCodexLocalStats(maxAge time.Duration, now time.Time) Stats {
	today := dateString(now)
	cacheFile, lockFile, err := codexScanCachePaths()
	if err != nil {
		warnf("codex: cache unavailable (%v); scanning directly", err)
		stats, _ := runCodexLocalScans(now)
		return stats
	}

	if cached := readCodexCachedStats(cacheFile, maxAge, today); cached != nil {
		return *cached
	}

	var stats Stats
	withLock(lockFile, func() {
		if cached := readCodexCachedStats(cacheFile, maxAge, today); cached != nil {
			stats = *cached
			return
		}
		var complete bool
		stats, complete = runCodexLocalScans(now)
		// An interrupted scan still serves this run, but caching it would
		// suppress the missing usage for every reader until it expires.
		if complete {
			envelope := codexCacheEnvelope{SchemaVersion: schemaVersion, ScanDate: today, Stats: &stats}
			if err := writeJSONAtomic(cacheFile, envelope, 0o644); err != nil {
				warnf("codex: could not write usage cache (%v)", err)
			}
		}
	})
	return stats
}

// ---------------------------------------------------------------- app-server

type codexRPC struct {
	limits          []Limit
	tierLabel       string
	usageStatusText string
	authHelpText    string
}

type rpcSession struct {
	stdin  *os.File
	lines  chan string
	closed chan struct{}
}

func (s *rpcSession) request(id int, method string, params map[string]any, timeout time.Duration) (map[string]any, error) {
	payload := map[string]any{"id": id, "method": method, "params": map[string]any{}}
	if params != nil {
		payload["params"] = params
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	if _, err := s.stdin.Write(append(encoded, '\n')); err != nil {
		return nil, err
	}

	deadline := time.NewTimer(timeout)
	defer deadline.Stop()
	for {
		select {
		case line, ok := <-s.lines:
			if !ok {
				return nil, errors.New(method)
			}
			var message map[string]any
			if json.Unmarshal([]byte(line), &message) != nil {
				continue
			}
			if claudeNumber(message["id"]) == int64(id) && truthy(message["id"]) {
				return message, nil
			}
		case <-deadline.C:
			return nil, errors.New(method)
		}
	}
}

func (s *rpcSession) notify(method string) error {
	encoded, err := json.Marshal(map[string]any{"method": method, "params": map[string]any{}})
	if err != nil {
		return err
	}
	_, err = s.stdin.Write(append(encoded, '\n'))
	return err
}

// codexLimitWindow turns one of the app-server's rate-limit windows into a
// Limit. A window with no usedPercent is not a window the panel can draw.
func codexLimitWindow(raw any) *Limit {
	window, ok := raw.(map[string]any)
	if !ok {
		return nil
	}
	used, present := window["usedPercent"]
	if !present || used == nil {
		return nil
	}
	percent, ok := pyFloat(used)
	if !ok {
		return nil
	}

	mins := codexNumber(window["windowDurationMins"])
	label := "Limit"
	switch {
	case mins == 10080:
		label = "Weekly (7-day)"
	case mins != 0 && mins%60 == 0:
		label = fmt.Sprintf("%dh window", mins/60)
	case mins != 0:
		label = fmt.Sprintf("%dm window", mins)
	}

	resetsAt := ""
	if reset := window["resetsAt"]; truthy(reset) {
		resetsAt = pyISOFormat(time.Unix(codexNumber(reset), 0).UTC())
	}
	return &Limit{Label: label, Percent: percent / 100.0, ResetsAt: resetsAt}
}

func fetchCodexRPC() codexRPC {
	result := codexRPC{limits: []Limit{}, authHelpText: codexAuthHelp}

	searchPath := codexPath()
	binary, found := lookPathIn("codex", searchPath)
	if !found {
		result.usageStatusText = "Codex unavailable"
		result.authHelpText = "codex not found in PATH"
		return result
	}

	// Read-only and untrusted: this asks the app-server two questions about
	// the account and must not be able to do anything else.
	cmd := exec.Command(binary, "-s", "read-only", "-a", "untrusted", "app-server")
	cmd.Env = append(os.Environ(), "PATH="+searchPath)
	stdinRead, stdinWrite, err := os.Pipe()
	if err != nil {
		result.usageStatusText = "Codex unavailable"
		result.authHelpText = err.Error()
		return result
	}
	stdoutRead, stdoutWrite, err := os.Pipe()
	if err != nil {
		stdinRead.Close()
		stdinWrite.Close()
		result.usageStatusText = "Codex unavailable"
		result.authHelpText = err.Error()
		return result
	}
	cmd.Stdin = stdinRead
	cmd.Stdout = stdoutWrite
	cmd.Stderr = nil

	if err := cmd.Start(); err != nil {
		stdinRead.Close()
		stdinWrite.Close()
		stdoutRead.Close()
		stdoutWrite.Close()
		result.usageStatusText = "Codex unavailable"
		result.authHelpText = err.Error()
		return result
	}
	stdinRead.Close()
	stdoutWrite.Close()

	session := &rpcSession{stdin: stdinWrite, lines: make(chan string, 32)}
	go func() {
		defer close(session.lines)
		reader := bufio.NewReaderSize(stdoutRead, 1<<16)
		for {
			line, err := reader.ReadString('\n')
			if line != "" {
				session.lines <- line
			}
			if err != nil {
				return
			}
		}
	}()

	defer func() {
		stdinWrite.Close()
		if cmd.Process != nil {
			cmd.Process.Signal(syscall.SIGTERM)
			done := make(chan struct{})
			go func() { cmd.Wait(); close(done) }()
			select {
			case <-done:
			case <-time.After(time.Second):
				cmd.Process.Kill()
				<-done
			}
		}
		stdoutRead.Close()
	}()

	fail := func(err error) codexRPC {
		result.usageStatusText = "Codex limits unavailable"
		result.authHelpText = err.Error()
		return result
	}

	if _, err := session.request(1, "initialize", map[string]any{
		"clientInfo": map[string]any{"name": "pshell-agents", "version": "1"},
	}, 8*time.Second); err != nil {
		return fail(err)
	}
	if err := session.notify("initialized"); err != nil {
		return fail(err)
	}
	accountMsg, err := session.request(2, "account/read", nil, 4*time.Second)
	if err != nil {
		return fail(err)
	}
	limitsMsg, err := session.request(3, "account/rateLimits/read", nil, 4*time.Second)
	if err != nil {
		return fail(err)
	}

	accountResult, _ := accountMsg["result"].(map[string]any)
	account, _ := accountResult["account"].(map[string]any)
	limitsResult, _ := limitsMsg["result"].(map[string]any)
	limits, _ := limitsResult["rateLimits"].(map[string]any)

	plan := firstTruthy(limits["planType"], account["planType"], account["type"], "")
	if truthy(plan) {
		result.tierLabel = pyStr(plan)
	}

	for _, key := range []string{"primary", "secondary"} {
		if entry := codexLimitWindow(limits[key]); entry != nil {
			result.limits = append(result.limits, *entry)
		}
	}
	return result
}

// ------------------------------------------------------------------- record

func collectCodex(opts options) (Record, error) {
	now := opts.now
	stats := cachedCodexLocalStats(opts.scanAge(), now)
	rpc := fetchCodexRPC()

	return Record{
		SchemaVersion:   schemaVersion,
		ID:              codexID,
		Name:            codexName,
		UpdatedAt:       pyISOFormat(now.UTC()),
		Ready:           true,
		HasLocalStats:   true,
		TierLabel:       rpc.tierLabel,
		UsageStatusText: rpc.usageStatusText,
		AuthHelpText:    rpc.authHelpText,
		Limits:          rpc.limits,
		Stats:           stats,
	}, nil
}
