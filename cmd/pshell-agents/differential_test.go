package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

// The differential harness.
//
// The Python collectors this program replaces are an executable oracle, and
// one that expires: they are on this machine now, and the phase that
// uninstalls Omarchy makes any drift between them and this port undiscoverable
// forever. So the real verification is not "does the Go look right", it is
// "does the Go print the same record the Python prints, given the same
// inputs".
//
// Run it with:
//
//	go test ./cmd/pshell-agents -run TestDifferentialAgainstOmarchy -v
//
// Each scenario builds a HOME of its own, runs one Omarchy collector into a
// buffer and this program into a scratch state directory, and compares the two
// records field by field. Nothing writes to the real state directory and
// nothing invokes omarchy-agent-usage-update, which is the one collector that
// writes files.
//
// Fields excluded from the comparison, and why -- an excluded field is an
// unverified field, so the list is short and printed on every run:
//
//   - updatedAt. Both sides stamp their own record with the moment it was
//     written and the two runs are seconds apart. The format is asserted
//     separately in TestUpdatedAtMatchesPythonIsoformat.
//   - limits[].resetsAt, compared with a tolerance rather than dropped.
//     Anthropic's usage endpoint computes this field per request: three
//     probes taken five seconds apart return three different sub-second
//     values that track the request instant. Two runs cannot agree on it
//     exactly, so the harness parses both and requires them within a minute,
//     which is far tighter than any real window error.
const resetsAtTolerance = time.Minute

func omarchyCollector(agent string) string {
	return filepath.Join(homeDir(), ".local", "bin", "omarchy-agent-usage-"+agent)
}

// haveCollectors skips loudly rather than silently. A reviewer running this on
// a machine where Omarchy is already gone must be told the oracle is missing,
// not shown a green tick that verified nothing.
func haveCollectors(t *testing.T, agents ...string) {
	t.Helper()
	var missing []string
	for _, agent := range agents {
		if info, err := os.Stat(omarchyCollector(agent)); err != nil || info.Mode()&0o111 == 0 {
			missing = append(missing, omarchyCollector(agent))
		}
	}
	if len(missing) > 0 {
		t.Skipf("SKIPPING DIFFERENTIAL: the Omarchy collectors are the oracle and these are not present:\n  %s\n"+
			"Nothing was verified against them by this run.", strings.Join(missing, "\n  "))
	}
}

// buildBinary compiles the program under test once per run.
func buildBinary(t *testing.T) string {
	t.Helper()
	binary := filepath.Join(t.TempDir(), "pshell-agents")
	build := exec.Command("go", "build", "-o", binary, ".")
	build.Stderr = os.Stderr
	if err := build.Run(); err != nil {
		t.Fatalf("go build: %v", err)
	}
	return binary
}

type fixture struct {
	home    string
	path    string
	extra   []string
	agents  []string
	binary  string
	timeout time.Duration
}

func (r fixture) env(extra ...string) []string {
	// Deliberately not os.Environ(): the point of a scenario is that both
	// sides see exactly the same environment, and an inherited XDG_CACHE_HOME
	// or CLAUDE_CONFIG_DIR would quietly aim one of them somewhere else.
	env := []string{
		"HOME=" + r.home,
		"PATH=" + r.path,
		"TZ=" + os.Getenv("TZ"),
		"LANG=" + os.Getenv("LANG"),
	}
	env = append(env, r.extra...)
	return append(env, extra...)
}

// omarchyRecord runs one Python collector and parses the record it prints.
// Only the per-agent collectors are ever invoked; omarchy-agent-usage-update
// writes into the real state directory and is never run.
func (r fixture) omarchyRecord(t *testing.T, agent string) map[string]any {
	t.Helper()
	cache := filepath.Join(r.home, ".cache-omarchy")
	cmd := exec.Command(omarchyCollector(agent), "--force")
	cmd.Env = r.env("XDG_CACHE_HOME=" + cache)
	cmd.Stderr = os.Stderr
	output, err := cmd.Output()
	if err != nil {
		t.Fatalf("omarchy-agent-usage-%s: %v", agent, err)
	}
	var record map[string]any
	if err := json.Unmarshal(output, &record); err != nil {
		t.Fatalf("omarchy-agent-usage-%s printed unparseable JSON: %v", agent, err)
	}
	return record
}

// pshellRecords runs this program and reads back the files it wrote.
func (r fixture) pshellRecords(t *testing.T) map[string]map[string]any {
	t.Helper()
	state := filepath.Join(r.home, ".state-pshell")
	cache := filepath.Join(r.home, ".cache-pshell")
	args := append([]string{"--force"}, r.agents...)
	cmd := exec.Command(r.binary, args...)
	cmd.Env = r.env("XDG_STATE_HOME="+state, "XDG_CACHE_HOME="+cache)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		t.Fatalf("pshell-agents: %v", err)
	}

	records := map[string]map[string]any{}
	for _, agent := range r.agents {
		content, err := os.ReadFile(filepath.Join(state, "pshell", "agents", "usage", agent+".json"))
		if err != nil {
			t.Fatalf("pshell-agents wrote no record for %s: %v", agent, err)
		}
		var record map[string]any
		if err := json.Unmarshal(content, &record); err != nil {
			t.Fatalf("pshell-agents wrote unparseable JSON for %s: %v", agent, err)
		}
		records[agent] = record
	}
	return records
}

// compare walks both records together and reports every difference, so a
// failure names the field rather than dumping two JSON blobs.
func compare(t *testing.T, agent string, omarchy, pshell map[string]any) {
	t.Helper()
	var differences []string
	walkCompare("", omarchy, pshell, &differences)
	if len(differences) == 0 {
		t.Logf("%s: identical (excluding updatedAt; resetsAt within %s)", agent, resetsAtTolerance)
		return
	}
	t.Errorf("%s: %d difference(s) against omarchy-agent-usage-%s:\n%s",
		agent, len(differences), agent, strings.Join(differences, "\n"))
}

func walkCompare(path string, omarchy, pshell any, out *[]string) {
	if path == "updatedAt" {
		return
	}
	if strings.HasPrefix(path, "limits[") && strings.HasSuffix(path, "].resetsAt") {
		compareResetsAt(path, omarchy, pshell, out)
		return
	}

	left, leftIsMap := omarchy.(map[string]any)
	right, rightIsMap := pshell.(map[string]any)
	if leftIsMap && rightIsMap {
		keys := map[string]struct{}{}
		for key := range left {
			keys[key] = struct{}{}
		}
		for key := range right {
			keys[key] = struct{}{}
		}
		for _, key := range sortedKeys(keys) {
			child := key
			if path != "" {
				child = path + "." + key
			}
			leftValue, hasLeft := left[key]
			rightValue, hasRight := right[key]
			switch {
			case !hasLeft:
				*out = append(*out, fmt.Sprintf("  + %s = %s (only pshell-agents)", child, brief(rightValue)))
			case !hasRight:
				*out = append(*out, fmt.Sprintf("  - %s = %s (only omarchy)", child, brief(leftValue)))
			default:
				walkCompare(child, leftValue, rightValue, out)
			}
		}
		return
	}

	leftList, leftIsList := omarchy.([]any)
	rightList, rightIsList := pshell.([]any)
	if leftIsList && rightIsList {
		if len(leftList) != len(rightList) {
			*out = append(*out, fmt.Sprintf("  ~ %s length %d vs %d", path, len(leftList), len(rightList)))
		}
		for index := 0; index < len(leftList) && index < len(rightList); index++ {
			walkCompare(fmt.Sprintf("%s[%d]", path, index), leftList[index], rightList[index], out)
		}
		return
	}

	if !reflect.DeepEqual(omarchy, pshell) {
		*out = append(*out, fmt.Sprintf("  ~ %s: omarchy=%s pshell=%s", path, brief(omarchy), brief(pshell)))
	}
}

func compareResetsAt(path string, omarchy, pshell any, out *[]string) {
	left, leftOK := omarchy.(string)
	right, rightOK := pshell.(string)
	if !leftOK || !rightOK || left == "" || right == "" {
		if !reflect.DeepEqual(omarchy, pshell) {
			*out = append(*out, fmt.Sprintf("  ~ %s: omarchy=%s pshell=%s", path, brief(omarchy), brief(pshell)))
		}
		return
	}
	if left == right {
		return
	}
	leftTime, leftParsed := parseISO(left)
	rightTime, rightParsed := parseISO(right)
	if !leftParsed || !rightParsed {
		*out = append(*out, fmt.Sprintf("  ~ %s: omarchy=%q pshell=%q (unparseable)", path, left, right))
		return
	}
	drift := leftTime.Sub(rightTime)
	if drift < 0 {
		drift = -drift
	}
	if drift > resetsAtTolerance {
		*out = append(*out, fmt.Sprintf("  ~ %s: omarchy=%q pshell=%q (%s apart, tolerance %s)",
			path, left, right, drift, resetsAtTolerance))
	}
}

func brief(value any) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		return fmt.Sprint(value)
	}
	if len(encoded) > 160 {
		return string(encoded[:160]) + "..."
	}
	return string(encoded)
}

// ------------------------------------------------------------------ fixtures

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

// snapshot copies a real directory into the fixture. The originals read
// directories this program's own author is actively writing to, so comparing
// two sequential runs against the live tree would diff the drift rather than
// the port. cp preserves mtimes, which the Codex scan filters on.
func snapshot(t *testing.T, from, to string) bool {
	t.Helper()
	if _, err := os.Stat(from); err != nil {
		return false
	}
	if err := os.MkdirAll(filepath.Dir(to), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := exec.Command("cp", "-a", from, to).Run(); err != nil {
		t.Fatalf("snapshot %s: %v", from, err)
	}
	return true
}

const defaultPath = "/usr/bin:/bin:/usr/local/bin"

// --------------------------------------------------------------------- tests

func TestDifferentialAgainstOmarchy(t *testing.T) {
	if testing.Short() {
		t.Skip("SKIPPING DIFFERENTIAL: -short was given, so nothing was compared against the Omarchy collectors")
	}
	haveCollectors(t, "claude", "codex", "fireworks")
	t.Logf("excluded from comparison: updatedAt (both sides stamp \"now\"); "+
		"limits[].resetsAt compared within %s because Anthropic recomputes it per request", resetsAtTolerance)
	binary := buildBinary(t)

	t.Run("real transcripts", func(t *testing.T) {
		home := t.TempDir()
		copied := snapshot(t, filepath.Join(homeDir(), ".claude", "projects"), filepath.Join(home, ".claude", "projects"))
		snapshot(t, filepath.Join(homeDir(), ".pi", "agent", "sessions"), filepath.Join(home, ".pi", "agent", "sessions"))
		snapshot(t, filepath.Join(homeDir(), ".codex", "sessions"), filepath.Join(home, ".codex", "sessions"))
		snapshot(t, filepath.Join(homeDir(), ".codex", "archived_sessions"), filepath.Join(home, ".codex", "archived_sessions"))
		snapshot(t, filepath.Join(homeDir(), ".local", "share", "opencode", "opencode.db"),
			filepath.Join(home, ".local", "share", "opencode", "opencode.db"))
		if !copied {
			t.Skip("SKIPPING: no ~/.claude/projects on this machine to compare against")
		}

		// PATH deliberately excludes `codex`, so the Codex collector takes
		// its "not in PATH" branch on both sides and the comparison stays
		// deterministic. The app-server path is covered by "codex app-server"
		// below.
		probe := fixture{home: home, path: defaultPath, binary: binary, agents: []string{"claude", "codex"}}
		pshell := probe.pshellRecords(t)
		for _, agent := range probe.agents {
			compare(t, agent, probe.omarchyRecord(t, agent), pshell[agent])
		}
	})

	t.Run("claude stats-cache fallback", func(t *testing.T) {
		home := t.TempDir()
		today := time.Now().Format("2006-01-02")
		if err := os.MkdirAll(filepath.Join(home, ".claude", "projects"), 0o755); err != nil {
			t.Fatal(err)
		}

		activity := make([]string, 0, 9)
		for offset := 8; offset >= 0; offset-- {
			day := time.Now().AddDate(0, 0, -offset).Format("2006-01-02")
			count := offset * 11
			activity = append(activity, fmt.Sprintf(`{"date":%q,"messageCount":%d}`, day, count))
		}
		write(t, filepath.Join(home, ".claude", "stats-cache.json"), fmt.Sprintf(`{
  "totalMessages": 4211,
  "totalSessions": 87,
  "modelUsage": {"claude-opus-5": {"inputTokens": 11, "outputTokens": 22, "cacheReadInputTokens": 33, "cacheCreationInputTokens": 44}},
  "dailyModelTokens": [{"date": %q, "tokensByModel": {"claude-opus-5": 1234, "claude-haiku-4-5": 56}}],
  "dailyActivity": [%s]
}`, today, strings.Join(activity, ",")))

		nowMs := time.Now().UnixMilli()
		startOfDay := time.Now().Truncate(24 * time.Hour)
		write(t, filepath.Join(home, ".claude", "history.jsonl"), strings.Join([]string{
			fmt.Sprintf(`{"timestamp":%d,"sessionId":"old"}`, startOfDay.AddDate(0, 0, -2).UnixMilli()),
			fmt.Sprintf(`{"timestamp":%d,"sessionId":"a"}`, nowMs-40000),
			`not json at all`,
			``,
			fmt.Sprintf(`{"timestamp":%d,"sessionId":"a"}`, nowMs-20000),
			fmt.Sprintf(`{"timestamp":%d,"sessionId":"b"}`, nowMs-10000),
		}, "\n")+"\n")

		probe := fixture{home: home, path: defaultPath, binary: binary, agents: []string{"claude"}}
		compare(t, "claude", probe.omarchyRecord(t, "claude"), probe.pshellRecords(t)["claude"])
	})

	t.Run("claude pi sessions merged", func(t *testing.T) {
		home := t.TempDir()
		if err := os.MkdirAll(filepath.Join(home, ".claude", "projects"), 0o755); err != nil {
			t.Fatal(err)
		}
		now := time.Now()
		write(t, filepath.Join(home, ".pi", "agent", "sessions", "proj", "one.jsonl"), strings.Join([]string{
			// Counted: the four buckets, today.
			fmt.Sprintf(`{"type":"message","id":"m1","timestamp":%q,"message":{"role":"assistant","provider":"anthropic","model":"claude-opus-5","usage":{"input":100,"output":200,"cacheRead":300,"cacheWrite":400}}}`,
				now.Format(time.RFC3339)),
			// Counted: only a grand total, which is filed as input.
			fmt.Sprintf(`{"type":"message","id":"m2","timestamp":%q,"message":{"role":"assistant","provider":"anthropic","model":"claude-sonnet-5","usage":{"totalTokens":500}}}`,
				now.AddDate(0, 0, -3).Format(time.RFC3339)),
			// Ignored: another provider's spend is not this subscription's.
			`{"type":"message","id":"m3","message":{"role":"assistant","provider":"openai","usage":{"input":9999}}}`,
			// Ignored: malformed line mid-file.
			`{"type":"message","id":"m4","message":{"role":"assistant","provider":"anthropic","usage":{`,
			// Ignored: repeat of m1's id.
			fmt.Sprintf(`{"type":"message","id":"m1","timestamp":%q,"message":{"role":"assistant","provider":"anthropic","usage":{"input":7}}}`,
				now.Format(time.RFC3339)),
			// Ignored: zero usage.
			`{"type":"message","id":"m5","message":{"role":"assistant","provider":"anthropic","usage":{"input":0,"output":0}}}`,
		}, "\n")+"\n")

		probe := fixture{home: home, path: defaultPath, binary: binary, agents: []string{"claude"}}
		compare(t, "claude", probe.omarchyRecord(t, "claude"), probe.pshellRecords(t)["claude"])
	})

	t.Run("codex app-server", func(t *testing.T) {
		home := t.TempDir()
		bin := filepath.Join(home, "bin")
		// A stub app-server, so the RPC path -- the plan label and both limit
		// windows -- is compared rather than left to whatever the real Codex
		// reports today.
		//
		// One reply per request, deliberately. Omarchy's collector polls the
		// pipe with select() and then reads it with a buffered readline, so a
		// second line arriving in the same read lands in Python's buffer where
		// select() cannot see it and the request times out. That is a real bug
		// in the original -- it is why this machine's stored Codex record says
		// authHelpText "account/rateLimits/read" -- and this port does not
		// reproduce it; see TestCodexRPCReadsPastAnUnrelatedNotification.
		write(t, filepath.Join(bin, "codex"), `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
  *'"account/rateLimits/read"'*)
    printf '{"id":3,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":37.5,"windowDurationMins":300,"resetsAt":1788000000},"secondary":{"usedPercent":12,"windowDurationMins":10080,"resetsAt":1788500000}}}}\n'
    ;;
  *'"account/read"'*)
    printf '{"id":2,"result":{"account":{"planType":"pro","type":"chatgpt"}}}\n'
    ;;
  *'"initialize"'*)
    printf '{"id":1,"result":{"userAgent":"stub"}}\n'
    ;;
  esac
done
`)
		if err := os.Chmod(filepath.Join(bin, "codex"), 0o755); err != nil {
			t.Fatal(err)
		}

		probe := fixture{home: home, path: bin + ":" + defaultPath, binary: binary, agents: []string{"codex"}}
		compare(t, "codex", probe.omarchyRecord(t, "codex"), probe.pshellRecords(t)["codex"])
	})

	t.Run("fireworks billing api", func(t *testing.T) {
		home := t.TempDir()
		server := httptest.NewServer(http.HandlerFunc(fireworksStub(t)))
		defer server.Close()

		// The one field this port moves: the Fireworks config lived under
		// ~/.config/omarchy and now lives under ~/.config/pshell. Both are
		// written with the same content so the records can still be compared.
		config := `{"fundedAmount": "100", "fundedAt": "2026-07-01"}`
		write(t, filepath.Join(home, ".config", "omarchy", "agents", "fireworks.json"), config)
		write(t, filepath.Join(home, ".config", "pshell", "agents", "fireworks.json"), config)

		probe := fixture{
			home: home, path: defaultPath, binary: binary, agents: []string{"fireworks"},
			extra: []string{
				"FIREWORKS_API_KEY=test-key",
				"FIREWORKS_API_BASE_URL=" + server.URL,
				"FIREWORKS_AUTH_PATH=" + filepath.Join(home, "no-such-auth.ini"),
			},
		}
		compare(t, "fireworks", probe.omarchyRecord(t, "fireworks"), probe.pshellRecords(t)["fireworks"])
	})
}

// fireworksStub answers the billing calls with a fixed account, two pages of
// usage, a permission-denied balance and a cost subtotal -- everything the
// populated Fireworks path touches, which this machine's real account cannot
// exercise because it has no serverless spend.
func fireworksStub(t *testing.T) http.HandlerFunc {
	today := time.Now()
	day := func(offset int) string {
		return today.AddDate(0, 0, -offset).UTC().Format("2006-01-02T00:00:00Z")
	}
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch {
		case r.URL.Path == "/v1/accounts":
			fmt.Fprintf(w, `{"accounts":[{"name":"accounts/acme","createTime":"2026-07-01T00:00:00Z"}]}`)
		case strings.HasSuffix(r.URL.Path, "/billingUsage"):
			if r.URL.Query().Get("pageToken") == "" {
				fmt.Fprintf(w, `{"nextPageToken":"page-2","serverlessCosts":[
                  {"startTime":%q,"group":{"model_name":"accounts/fireworks/models/llama-v3p1-70b"},"promptTokens":1000,"cachedPromptTokens":250,"completionTokens":400},
                  {"startTime":%q,"group":{"model_name":"kimi-k2p5"},"promptTokens":10,"cachedPromptTokens":0,"uncachedPromptTokens":10,"completionTokens":0}
                ]}`, day(0), day(3))
				return
			}
			fmt.Fprintf(w, `{"serverlessCosts":[
              {"startTime":%q,"group":{"model_name":"llama-v3p1-70b"},"promptTokens":7,"cachedPromptTokens":99,"completionTokens":1},
              {"startTime":%q,"modelName":"deepseek-v3","promptTokens":0,"cachedPromptTokens":0,"completionTokens":0},
              {"startTime":%q,"group":{},"promptTokens":500,"completionTokens":250}
            ]}`, day(0), day(2), day(20))
		case strings.HasSuffix(r.URL.Path, ":getBalance"):
			http.Error(w, `{"error":"PERMISSION_DENIED"}`, http.StatusForbidden)
		case strings.HasSuffix(r.URL.Path, "/usageCosts:query"):
			fmt.Fprint(w, `{"subtotal":{"units":12,"nanos":500000000}}`)
		default:
			t.Logf("fireworks stub: unexpected %s %s", r.Method, r.URL.Path)
			http.NotFound(w, r)
		}
	}
}

// TestUpdatedAtMatchesPythonIsoformat pins the one field the differential
// excludes. The panel's parseTime() trims six fractional digits to three
// because ECMAScript only defines three, and that comment stays correct only
// while this program keeps writing six.
func TestUpdatedAtMatchesPythonIsoformat(t *testing.T) {
	when := time.Date(2026, 8, 31, 19, 25, 10, 600498000, time.UTC)
	if got, want := pyISOFormat(when), "2026-08-31T19:25:10.600498+00:00"; got != want {
		t.Errorf("pyISOFormat = %q, want %q", got, want)
	}
	// Python's isoformat drops the fraction entirely on an exact second.
	exact := time.Date(2026, 8, 31, 19, 25, 10, 0, time.UTC)
	if got, want := pyISOFormat(exact), "2026-08-31T19:25:10+00:00"; got != want {
		t.Errorf("pyISOFormat = %q, want %q", got, want)
	}
}
