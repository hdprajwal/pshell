package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// Fireworks serverless usage. Tokens come from the billing API grouped by day
// and model for the last 30 days. Fireworks does not expose its prepaid
// ledger, so the record carries an estimated balance rather than rate limits:
// the credits named in the config minus rated account costs since the funding
// date.

const (
	fireworksID       = "fireworks"
	fireworksName     = "Fireworks"
	fireworksAuthHelp = "Set FIREWORKS_API_KEY, run `firectl set-api-key`, or sign in to Fireworks in opencode."
	fireworksAPIBase  = "https://api.fireworks.ai"
)

// fireworksError is a message meant for the panel's footnote, not a stack
// trace. Every one of these strings is shown to the user as-is.
type fireworksError struct{ message string }

func (e *fireworksError) Error() string { return e.message }

func fwError(format string, args ...any) error {
	return &fireworksError{message: fmt.Sprintf(format, args...)}
}

// ------------------------------------------------------------------- money

// Money arrives as {units, nanos} and is compared against a configured credit
// figure. Doing that in float64 would let a cent drift in and out of the
// balance between runs, so it is all integer nano-units until the record is
// written.
func moneyNanos(value any) int64 {
	entry, ok := value.(map[string]any)
	if !ok {
		return 0
	}
	units, _ := pyFloat(firstTruthy(entry["units"], float64(0)))
	nanos, _ := pyFloat(firstTruthy(entry["nanos"], float64(0)))
	return int64(units)*1_000_000_000 + int64(nanos)
}

func nanosToFloat(nanos int64) float64 {
	return float64(nanos) / 1e9
}

// parseDecimalNanos reads a plain decimal figure into nano-units. Written by
// hand rather than through ParseFloat so that "12.34" is exactly 12.34 and
// not the nearest double to it.
func parseDecimalNanos(text string) (int64, bool) {
	text = strings.TrimSpace(text)
	if text == "" {
		return 0, false
	}
	sign := int64(1)
	switch text[0] {
	case '+':
		text = text[1:]
	case '-':
		sign = -1
		text = text[1:]
	}
	whole, frac, _ := strings.Cut(text, ".")
	if whole == "" && frac == "" {
		return 0, false
	}
	if whole == "" {
		whole = "0"
	}
	units := int64(0)
	if whole != "" {
		parsed, err := strconv.ParseInt(whole, 10, 64)
		if err != nil {
			return 0, false
		}
		units = parsed
	}
	// Nine digits of fraction, padded or truncated -- the same resolution the
	// API's nanos field carries.
	if len(frac) > 9 {
		frac = frac[:9]
	}
	for len(frac) < 9 {
		frac += "0"
	}
	nanos := int64(0)
	if frac != "" {
		parsed, err := strconv.ParseUint(frac, 10, 64)
		if err != nil {
			return 0, false
		}
		nanos = int64(parsed)
	}
	return sign * (units*1_000_000_000 + nanos), true
}

// ------------------------------------------------------------ config & auth

// fireworksConfigPaths is where the credit figures behind the estimated
// balance are read from, in order. The first is pshell's own. The second is
// where Omarchy's collector read them, and it is here because the alternative
// is a user who set fundedAmount once, months ago, watching their balance
// quietly become nothing after an upgrade -- with no error to search for,
// because an absent config is a supported state. The note says to copy the
// file across; this means forgetting to costs nothing.
func fireworksConfigPaths() []string {
	config := xdgDir("XDG_CONFIG_HOME", ".config")
	return []string{
		filepath.Join(config, "pshell", "agents", "fireworks.json"),
		filepath.Join(config, "omarchy", "agents", "fireworks.json"),
	}
}

func readFireworksConfig() map[string]any {
	for _, path := range fireworksConfigPaths() {
		content, err := os.ReadFile(path)
		if err != nil {
			continue
		}
		var parsed map[string]any
		if json.Unmarshal(content, &parsed) != nil || parsed == nil {
			// A file that is there but unreadable is not a reason to fall
			// through to an older one: the newer file is the answer, and
			// silently using a stale figure instead would be worse than
			// reporting no balance.
			return map[string]any{}
		}
		return parsed
	}
	return map[string]any{}
}

func fireworksAuthPath() string {
	if value := strings.TrimSpace(os.Getenv("FIREWORKS_AUTH_PATH")); value != "" {
		return resolvePath(value)
	}
	return filepath.Join(homeDir(), ".fireworks", "auth.ini")
}

// readAuthFile pulls the key and account out of firectl's INI file. Any
// section will do: firectl has written them under several names and the file
// is small enough to read whole.
func readAuthFile(path string) (string, string) {
	file, err := os.Open(path)
	if err != nil {
		return "", ""
	}
	defer file.Close()

	apiKey, accountID := "", ""
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "[") {
			continue
		}
		name, value, found := strings.Cut(line, "=")
		if !found {
			continue
		}
		value = strings.TrimSpace(value)
		switch strings.ToLower(strings.TrimSpace(name)) {
		case "api_key", "api-key":
			if apiKey == "" {
				apiKey = value
			}
		case "account_id", "account-id":
			if accountID == "" {
				accountID = value
			}
		}
	}
	return apiKey, accountID
}

func readOpencodeFireworksKey() string {
	path := filepath.Join(xdgDir("XDG_DATA_HOME", ".local/share"), "opencode", "auth.json")
	content, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	var parsed map[string]any
	if json.Unmarshal(content, &parsed) != nil {
		return ""
	}
	entry, ok := parsed["fireworks-ai"].(map[string]any)
	if !ok {
		return ""
	}
	return strings.TrimSpace(pyStr(firstTruthy(entry["key"], "")))
}

func fireworksCredentials(authPath string, config map[string]any) (string, string) {
	fileKey, fileAccount := readAuthFile(authPath)
	// opencode is the last resort: an explicit key or a firectl login should
	// win over whatever another tool happens to be signed in with.
	apiKey := strings.TrimSpace(os.Getenv("FIREWORKS_API_KEY"))
	if apiKey == "" {
		apiKey = fileKey
	}
	if apiKey == "" {
		apiKey = readOpencodeFireworksKey()
	}

	accountID := strings.TrimSpace(os.Getenv("FIREWORKS_ACCOUNT_ID"))
	if accountID == "" {
		accountID = strings.TrimSpace(pyStr(firstTruthy(config["accountId"], "")))
	}
	if accountID == "" {
		accountID = fileAccount
	}
	return apiKey, accountID
}

func normalizeAccountID(value string) string {
	return strings.Trim(strings.TrimPrefix(strings.TrimSpace(value), "accounts/"), "/")
}

// ------------------------------------------------------------------- clock

// timezoneName is what the billing API buckets days by. Without it the API
// picks UTC and every local evening is filed under the following day.
func timezoneName() string {
	if configured := strings.TrimSpace(os.Getenv("TZ")); configured != "" {
		return configured
	}
	if target, err := filepath.EvalSymlinks("/etc/localtime"); err == nil {
		const marker = "/zoneinfo/"
		if index := strings.Index(target, marker); index >= 0 {
			return target[index+len(marker):]
		}
	}
	return "UTC"
}

// localMidnightUTC expresses a local midnight in UTC. The API buckets by the
// requested timezone, so the window has to run between local midnights -- a
// bare date with a Z suffix shifts the window by the offset and clips today's
// tail west of Greenwich.
func localMidnightUTC(day time.Time) string {
	year, month, date := day.Date()
	midnight := time.Date(year, month, date, 0, 0, 0, 0, time.Local)
	return midnight.UTC().Format("2006-01-02T15:04:05Z")
}

// fireworksTimestamp normalises a configured funding date into the UTC
// instant the cost query wants.
func fireworksTimestamp(value string) (string, error) {
	raw := strings.TrimSpace(value)
	if raw == "" {
		return "", nil
	}
	if len(raw) == 10 {
		if when, err := time.Parse("2006-01-02", raw); err == nil {
			return when.UTC().Format("2006-01-02T15:04:05Z"), nil
		}
		return "", fwError("Fireworks fundedAt must be an ISO date such as 2026-07-01")
	}
	when, ok := parseISO(raw)
	if !ok {
		return "", fwError("Fireworks fundedAt must be an ISO date such as 2026-07-01")
	}
	return when.UTC().Format("2006-01-02T15:04:05Z"), nil
}

// ------------------------------------------------------------------ client

type fireworksClient struct {
	apiKey  string
	baseURL string
	http    *http.Client
}

func newFireworksClient(apiKey, baseURL string) *fireworksClient {
	return &fireworksClient{
		apiKey:  apiKey,
		baseURL: strings.TrimRight(baseURL, "/"),
		http:    &http.Client{Timeout: 15 * time.Second},
	}
}

// quoteAll percent-encodes everything outside the unreserved set, so an
// account id containing a slash cannot walk out of its path segment.
func quoteAll(value string) string {
	var out strings.Builder
	for i := 0; i < len(value); i++ {
		c := value[i]
		if (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') ||
			c == '-' || c == '_' || c == '.' || c == '~' {
			out.WriteByte(c)
			continue
		}
		fmt.Fprintf(&out, "%%%02X", c)
	}
	return out.String()
}

func (c *fireworksClient) request(path string, query url.Values, body map[string]any) (map[string]any, error) {
	target := c.baseURL + path
	if len(query) > 0 {
		target += "?" + query.Encode()
	}

	var reader io.Reader
	method := http.MethodGet
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return nil, fwError("Fireworks returned an invalid billing response")
		}
		reader = bytes.NewReader(encoded)
		method = http.MethodPost
	}

	request, err := http.NewRequest(method, target, reader)
	if err != nil {
		return nil, fwError("Could not reach the Fireworks API")
	}
	request.Header.Set("Authorization", "Bearer "+c.apiKey)
	request.Header.Set("Accept", "application/json")
	request.Header.Set("Content-Type", "application/json")

	response, err := c.http.Do(request)
	if err != nil {
		return nil, fwError("Could not reach the Fireworks API")
	}
	defer response.Body.Close()

	if response.StatusCode >= 400 {
		switch response.StatusCode {
		case http.StatusUnauthorized:
			return nil, fwError("Fireworks rejected the API key")
		case http.StatusForbidden:
			return nil, fwError("The Fireworks API key cannot read billing data")
		case http.StatusNotFound:
			return nil, fwError("Fireworks account not found")
		}
		return nil, fwError("Fireworks API returned HTTP %d", response.StatusCode)
	}

	content, err := io.ReadAll(response.Body)
	if err != nil {
		return nil, fwError("Fireworks returned an invalid billing response")
	}
	var decoded any
	if json.Unmarshal(content, &decoded) != nil {
		return nil, fwError("Fireworks returned an invalid billing response")
	}
	if parsed, ok := decoded.(map[string]any); ok {
		return parsed, nil
	}
	return map[string]any{}, nil
}

func (c *fireworksClient) discoverAccount() (string, map[string]any, error) {
	payload, err := c.request("/v1/accounts", url.Values{"pageSize": {"100"}}, nil)
	if err != nil {
		return "", nil, err
	}
	raw, _ := payload["accounts"].([]any)
	var accounts []map[string]any
	for _, item := range raw {
		if account, ok := item.(map[string]any); ok {
			accounts = append(accounts, account)
		}
	}
	if len(accounts) == 1 {
		return normalizeAccountID(pyStr(firstTruthy(accounts[0]["name"], ""))), accounts[0], nil
	}
	if len(accounts) == 0 {
		return "", nil, fwError("No Fireworks account is available for this API key")
	}
	return "", nil, fwError("Set accountId in fireworks.json when the API key can access multiple accounts")
}

func (c *fireworksClient) account(accountID string) (map[string]any, error) {
	return c.request("/v1/accounts/"+quoteAll(normalizeAccountID(accountID)), nil, nil)
}

func (c *fireworksClient) usage(accountID string, startDay, endDay time.Time) (map[string]any, error) {
	quoted := quoteAll(normalizeAccountID(accountID))
	query := url.Values{
		"startTime": {localMidnightUTC(startDay)},
		"endTime":   {localMidnightUTC(endDay)},
		"usageType": {"SERVERLESS"},
		"timezone":  {timezoneName()},
		"groupBy":   {"model_name"},
	}

	// Thirty days grouped by model can exceed one page; follow the
	// continuation tokens or heavy accounts lose their tail. The bound is a
	// runaway stop, not an expected page count.
	rows := []any{}
	for page := 0; page < 20; page++ {
		payload, err := c.request("/v1/accounts/"+quoted+"/billingUsage", query, nil)
		if err != nil {
			return nil, err
		}
		if items, ok := payload["serverlessCosts"].([]any); ok {
			rows = append(rows, items...)
		}
		token := pyStr(firstTruthy(payload["nextPageToken"], ""))
		if token == "" {
			break
		}
		next := url.Values{}
		for key, values := range query {
			next[key] = values
		}
		next.Set("pageToken", token)
		query = next
	}
	return map[string]any{"serverlessCosts": rows}, nil
}

func (c *fireworksClient) spent(accountID, startAt, endAt string) (int64, error) {
	quoted := quoteAll(normalizeAccountID(accountID))
	payload, err := c.request("/v1/accounts/"+quoted+"/usageCosts:query", nil, map[string]any{
		"startTime": startAt,
		"endTime":   endAt,
		"scope":     "ACCOUNT",
	})
	if err == nil {
		if _, ok := payload["subtotal"].(map[string]any); ok {
			return moneyNanos(payload["subtotal"]), nil
		}
		err = fwError("Fireworks cost response did not include a subtotal")
	}

	// The cost query is newer than the summary endpoint and not every key can
	// reach it; the summary's line items add up to the same figure.
	when, ok := parseISO(endAt)
	if !ok {
		return 0, err
	}
	summaryEnd := when.UTC().AddDate(0, 0, 1).Format("2006-01-02") + "T00:00:00Z"
	summary, summaryErr := c.request("/v1/accounts/"+quoted+"/billing/summary",
		url.Values{"startTime": {startAt}, "endTime": {summaryEnd}}, nil)
	if summaryErr != nil {
		return 0, summaryErr
	}
	items, _ := summary["lineItems"].([]any)
	total := int64(0)
	for _, raw := range items {
		if item, ok := raw.(map[string]any); ok {
			total += moneyNanos(item["totalCost"])
		}
	}
	return total, nil
}

// liveBalance asks for the prepaid balance directly. The endpoint is
// permission-gated -- keys without the billing role get PERMISSION_DENIED --
// and its response shape is undocumented, so a Money object is accepted at
// the top level or under any plausible field name.
func (c *fireworksClient) liveBalance(accountID string) (int64, bool) {
	payload, err := c.request("/v1/accounts/"+quoteAll(normalizeAccountID(accountID))+":getBalance", nil, nil)
	if err != nil {
		return 0, false
	}
	candidates := []any{payload}
	for _, field := range []string{"balance", "creditBalance", "prepaidBalance", "amount"} {
		candidates = append(candidates, payload[field])
	}
	for _, value := range candidates {
		entry, ok := value.(map[string]any)
		if !ok {
			continue
		}
		_, hasUnits := entry["units"]
		_, hasNanos := entry["nanos"]
		if hasUnits || hasNanos {
			return moneyNanos(entry), true
		}
	}
	return 0, false
}

// ------------------------------------------------------------------ parsing

// fireworksModelID is the billing row's model, reduced to the name the panel
// ranks by. Fireworks spells decimal points in model names as "p", so
// "llama-v3p1-70b" is really "llama-v3.1-70b".
func fireworksModelID(row map[string]any) string {
	group, _ := row["group"].(map[string]any)
	raw := firstTruthy(group["model_name"], row["modelName"], "unknown")
	name := lastPathSegment(pyStr(raw))
	if name == "" {
		name = "unknown"
	}
	return unspellDecimalPoint(name)
}

func unspellDecimalPoint(name string) string {
	out := []byte(name)
	for i := 1; i+1 < len(out); i++ {
		if out[i] == 'p' && out[i-1] >= '0' && out[i-1] <= '9' && out[i+1] >= '0' && out[i+1] <= '9' {
			out[i] = '.'
		}
	}
	return string(out)
}

// fireworksRowDate recovers the local day a billing bucket names. The query
// asks for day buckets in the local timezone but the API reports each
// bucket's boundary in UTC: local Aug 7 starts at Aug 6 22:00Z east of
// Greenwich, so taking the raw date prefix files every day under its
// predecessor.
func fireworksRowDate(row map[string]any) string {
	raw := pyStr(firstTruthy(row["startTime"], ""))
	if raw == "" {
		return ""
	}
	when, ok := parseISO(raw)
	if !ok {
		if len(raw) >= 10 {
			return raw[:10]
		}
		return ""
	}
	return dateString(when.In(time.Local))
}

func summarizeFireworksUsage(payload map[string]any, today time.Time) Stats {
	dates := recentDateStrings(today)
	recent := map[string]int64{}
	for _, day := range dates {
		recent[day] = 0
	}
	todayString := dateString(today)
	todayByModel := map[string]int64{}
	modelUsage := map[string]*Bucket{}
	activeDates := map[string]struct{}{}

	rows, _ := payload["serverlessCosts"].([]any)
	for _, item := range rows {
		row, ok := item.(map[string]any)
		if !ok {
			continue
		}
		day := fireworksRowDate(row)
		model := fireworksModelID(row)

		prompt := fireworksNumber(row["promptTokens"])
		cached := fireworksNumber(row["cachedPromptTokens"])
		if cached > prompt {
			cached = prompt
		}
		uncached := fireworksNumber(row["uncachedPromptTokens"])
		if _, present := row["uncachedPromptTokens"]; !present {
			// Older rows report only the total; the uncached half is what is
			// left after the cache hits.
			uncached = prompt - cached
			if uncached < 0 {
				uncached = 0
			}
		}
		output := fireworksNumber(row["completionTokens"])
		total := uncached + cached + output
		if total <= 0 {
			continue
		}

		bucket := modelUsage[model]
		if bucket == nil {
			bucket = &Bucket{}
			modelUsage[model] = bucket
		}
		// Fireworks has no cache-creation charge, so that bucket stays zero.
		bucket.add(uncached, output, cached, 0)

		if day != "" {
			activeDates[day] = struct{}{}
		}
		if _, ok := recent[day]; ok {
			recent[day] += total
		}
		if day == todayString {
			todayByModel[model] += total
		}
	}

	days := make([]Day, 0, len(dates))
	for _, day := range dates {
		days = append(days, Day{Date: day, MessageCount: recent[day]})
	}
	var todayTotal int64
	for _, count := range todayByModel {
		todayTotal += count
	}

	stats := emptyStats()
	stats.TodayTotalTokens = todayTotal
	stats.TodayTokensByModel = todayByModel
	stats.RecentDays = days
	stats.ActiveDays = len(activeDates)
	stats.ActiveDates = sortedKeys(activeDates)
	stats.ModelUsage = modelUsage
	return stats
}

// ------------------------------------------------------------------- record

func fireworksBaseRecord(now time.Time) Record {
	hasPromptStats := false
	return Record{
		SchemaVersion: schemaVersion,
		ID:            fireworksID,
		Name:          fireworksName,
		UpdatedAt:     pyISOFormat(now.UTC()),
		Ready:         false,
		HasLocalStats: false,
		// Billing-API numbers are account-global, not machine-local: every
		// synced device reports the same truth, so aggregation must not sum
		// them.
		Scope: "account",
		// The billing API reports tokens, never prompt or session counts; the
		// panel keeps those numbers out of today's tooltip when this is false.
		HasPromptStats:  &hasPromptStats,
		TierLabel:       "Prepaid",
		UsageStatusText: "",
		AuthHelpText:    "",
		Limits:          []Limit{},
		Stats:           emptyStats(),
	}
}

func estimatedFireworksBalance(client *fireworksClient, accountID string, account map[string]any, config map[string]any) (*Balance, error) {
	fundedText := pyStr(firstTruthy(config["fundedAmount"], "0"))
	if number, ok := pyFloat(fundedText); ok && (math.IsNaN(number) || math.IsInf(number, 0)) {
		return nil, fwError("Fireworks fundedAmount must be a finite number")
	}
	funded, ok := parseDecimalNanos(fundedText)
	if !ok {
		return nil, fwError("Fireworks fundedAmount must be a number")
	}
	if funded <= 0 {
		return nil, nil
	}

	fundedAt, err := fireworksTimestamp(pyStr(firstTruthy(config["fundedAt"], "")))
	if err != nil {
		return nil, err
	}
	if fundedAt == "" {
		if len(account) == 0 {
			fetched, err := client.account(accountID)
			if err != nil {
				return nil, err
			}
			account = fetched
		}
		fundedAt, err = fireworksTimestamp(pyStr(firstTruthy(account["createTime"], "")))
		if err != nil {
			return nil, err
		}
	}
	if fundedAt == "" {
		return nil, fwError("Set fundedAt because the Fireworks account creation date is unavailable")
	}

	endAt := time.Now().UTC().Format("2006-01-02T15:04:05.000000Z")
	spent, err := client.spent(accountID, fundedAt, endAt)
	if err != nil {
		return nil, err
	}
	if spent < 0 {
		spent = 0
	}
	remaining := funded - spent
	if remaining < 0 {
		remaining = 0
	}
	return &Balance{
		Remaining: nanosToFloat(remaining),
		Funded:    nanosToFloat(funded),
		Spent:     nanosToFloat(spent),
		Currency:  "USD",
		Estimated: true,
	}, nil
}

func scanFireworks(baseURL, authPath string, now time.Time) (Record, error) {
	config := readFireworksConfig()
	apiKey, accountID := fireworksCredentials(authPath, config)
	if apiKey == "" {
		record := fireworksBaseRecord(now)
		record.UsageStatusText = "Fireworks unavailable"
		record.AuthHelpText = fireworksAuthHelp
		return record, nil
	}

	client := newFireworksClient(apiKey, baseURL)
	account := map[string]any{}
	if accountID != "" {
		accountID = normalizeAccountID(accountID)
	} else {
		discovered, found, err := client.discoverAccount()
		if err != nil {
			return Record{}, err
		}
		accountID, account = discovered, found
	}

	usage, err := client.usage(accountID, now.AddDate(0, 0, -29), now.AddDate(0, 0, 1))
	if err != nil {
		return Record{}, err
	}
	record := fireworksBaseRecord(now)
	record.Ready = true
	record.HasLocalStats = true
	record.Stats = summarizeFireworksUsage(usage, now)

	if live, ok := client.liveBalance(accountID); ok {
		funded, parsed := parseDecimalNanos(pyStr(firstTruthy(config["fundedAmount"], "0")))
		if !parsed || funded < 0 {
			funded = 0
		}
		spent := funded - live
		if spent < 0 {
			spent = 0
		}
		record.Balance = &Balance{
			Remaining: nanosToFloat(live),
			Funded:    nanosToFloat(funded),
			Spent:     nanosToFloat(spent),
			Currency:  "USD",
			Estimated: false,
		}
		return record, nil
	}

	balance, err := estimatedFireworksBalance(client, accountID, account, config)
	if err != nil {
		var known *fireworksError
		if !errors.As(err, &known) {
			return Record{}, err
		}
		record.UsageStatusText = "Balance unavailable"
		record.AuthHelpText = err.Error()
		return record, nil
	}
	if balance != nil {
		record.Balance = balance
	}
	return record, nil
}

func collectFireworks(opts options) (Record, error) {
	baseURL := strings.TrimSpace(os.Getenv("FIREWORKS_API_BASE_URL"))
	if baseURL == "" {
		baseURL = fireworksAPIBase
	}

	record, err := scanFireworks(baseURL, fireworksAuthPath(), opts.now)
	if err == nil {
		return record, nil
	}

	// Every failure still produces a record. A provider that cannot report is
	// a state the panel draws, not a reason to leave a stale file behind.
	record = fireworksBaseRecord(opts.now)
	record.UsageStatusText = "Fireworks unavailable"
	var known *fireworksError
	if errors.As(err, &known) {
		record.AuthHelpText = known.Error()
	} else {
		record.AuthHelpText = "Fireworks usage scan failed"
		warnf("fireworks: %v", err)
	}
	return record, nil
}
