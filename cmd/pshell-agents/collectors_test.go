package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func tempJSONL(t *testing.T, dir, name string, lines ...string) string {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	body := ""
	if len(lines) > 0 {
		body = strings.Join(lines, "\n") + "\n"
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

// A fixed clock, so "today" is a decision the test makes rather than one the
// calendar makes while the suite is running.
func at(hour, minute int) time.Time {
	return time.Date(2026, 8, 31, hour, minute, 0, 0, time.Local)
}

func iso(when time.Time) string { return when.Format(time.RFC3339) }

// ------------------------------------------------------- Claude transcripts

func TestClaudeProjectScanTokenArithmetic(t *testing.T) {
	now := at(10, 0)
	dir := t.TempDir()
	tempJSONL(t, dir, "proj/a.jsonl",
		// Four buckets, today, snake_case as Claude Code writes them.
		fmt.Sprintf(`{"type":"assistant","sessionId":"s1","timestamp":%q,"message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":30,"cache_creation_input_tokens":40}}}`, iso(now)),
		// camelCase spelling, same model, still today.
		fmt.Sprintf(`{"type":"assistant","sessionId":"s1","timestamp":%q,"message":{"id":"m2","model":"claude-opus-5","usage":{"inputTokens":1,"outputTokens":2,"cacheReadInputTokens":3,"cacheCreationInputTokens":4}}}`, iso(now)),
		// A second model and a second session, three days back.
		fmt.Sprintf(`{"type":"assistant","sessionId":"s2","timestamp":%q,"message":{"id":"m3","model":"claude-haiku-4-5","usage":{"input_tokens":5,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}`, iso(now.AddDate(0, 0, -3))),
		// Repeat of m1's id: one assistant message, however many transcripts
		// it appears in.
		fmt.Sprintf(`{"type":"assistant","sessionId":"s3","timestamp":%q,"message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":999}}}`, iso(now)),
		// Zero usage is not a prompt.
		fmt.Sprintf(`{"type":"assistant","sessionId":"s4","timestamp":%q,"message":{"id":"m4","model":"claude-opus-5","usage":{"input_tokens":0,"output_tokens":0}}}`, iso(now)),
		// Not an assistant turn.
		fmt.Sprintf(`{"type":"user","sessionId":"s5","timestamp":%q,"message":{"id":"m5","role":"user","usage":{"input_tokens":500}}}`, iso(now)),
	)

	stats := scanClaudeProjects(dir, now)

	if stats.TotalPrompts != 3 {
		t.Errorf("TotalPrompts = %d, want 3", stats.TotalPrompts)
	}
	if stats.TotalSessions != 2 {
		t.Errorf("TotalSessions = %d, want 2", stats.TotalSessions)
	}
	if stats.TodayPrompts != 2 {
		t.Errorf("TodayPrompts = %d, want 2", stats.TodayPrompts)
	}
	if stats.TodaySessions != 1 {
		t.Errorf("TodaySessions = %d, want 1", stats.TodaySessions)
	}
	if stats.TodayTotalTokens != 110 {
		t.Errorf("TodayTotalTokens = %d, want 110", stats.TodayTotalTokens)
	}

	want := &Bucket{InputTokens: 11, OutputTokens: 22, CacheReadInputTokens: 33, CacheCreationInputTokens: 44}
	if got := stats.ModelUsage["claude-opus-5"]; !reflect.DeepEqual(got, want) {
		t.Errorf("opus bucket = %+v, want %+v", got, want)
	}
	// The panel's modelTotal() sums exactly the four; nothing else may reach
	// the record and be counted.
	if total := want.InputTokens + want.OutputTokens + want.CacheReadInputTokens + want.CacheCreationInputTokens; total != 110 {
		t.Errorf("four buckets sum to %d, want 110", total)
	}
	if got := stats.TodayTokensByModel["claude-opus-5"]; got != 110 {
		t.Errorf("todayTokensByModel = %d, want 110", got)
	}

	if len(stats.RecentDays) != 7 {
		t.Fatalf("RecentDays has %d entries, want 7", len(stats.RecentDays))
	}
	if last := stats.RecentDays[6]; last.Date != "2026-08-31" || last.MessageCount != 110 {
		t.Errorf("last recent day = %+v, want 2026-08-31/110", last)
	}
	if third := stats.RecentDays[3]; third.Date != "2026-08-28" || third.MessageCount != 5 {
		t.Errorf("three days back = %+v, want 2026-08-28/5", third)
	}
	if !reflect.DeepEqual(stats.ActiveDates, []string{"2026-08-28", "2026-08-31"}) {
		t.Errorf("ActiveDates = %v", stats.ActiveDates)
	}
	if stats.ActiveDays != 2 {
		t.Errorf("ActiveDays = %d, want 2", stats.ActiveDays)
	}
}

func TestClaudeProjectScanDayBoundary(t *testing.T) {
	now := at(10, 0)
	midnight := time.Date(2026, 8, 31, 0, 0, 0, 0, time.Local)
	dir := t.TempDir()
	tempJSONL(t, dir, "proj/a.jsonl",
		fmt.Sprintf(`{"type":"assistant","sessionId":"s1","timestamp":%q,"message":{"id":"before","usage":{"input_tokens":7}}}`, iso(midnight.Add(-time.Second))),
		fmt.Sprintf(`{"type":"assistant","sessionId":"s1","timestamp":%q,"message":{"id":"after","usage":{"input_tokens":9}}}`, iso(midnight)),
		// A UTC-stamped message is filed by the local day it lands on, not by
		// the date in its own text.
		fmt.Sprintf(`{"type":"assistant","sessionId":"s1","timestamp":%q,"message":{"id":"utc","usage":{"input_tokens":1}}}`, midnight.Add(2*time.Hour).UTC().Format("2006-01-02T15:04:05Z")),
	)

	stats := scanClaudeProjects(dir, now)
	if stats.TodayTotalTokens != 10 {
		t.Errorf("TodayTotalTokens = %d, want 10 (9 after midnight plus 1 stamped in UTC)", stats.TodayTotalTokens)
	}
	if stats.RecentDays[5].Date != "2026-08-30" || stats.RecentDays[5].MessageCount != 7 {
		t.Errorf("yesterday = %+v, want 2026-08-30/7", stats.RecentDays[5])
	}
	if stats.TotalPrompts != 3 {
		t.Errorf("TotalPrompts = %d, want 3", stats.TotalPrompts)
	}
}

func TestClaudeProjectScanSurvivesBadInput(t *testing.T) {
	now := at(10, 0)

	t.Run("empty session directory", func(t *testing.T) {
		stats := scanClaudeProjects(t.TempDir(), now)
		if stats.TotalPrompts != 0 || stats.TodayTotalTokens != 0 {
			t.Errorf("empty directory produced %+v", stats)
		}
		if len(stats.RecentDays) != 7 {
			t.Errorf("RecentDays = %d entries, want 7 zeroed days", len(stats.RecentDays))
		}
	})

	t.Run("missing directory", func(t *testing.T) {
		stats := scanClaudeProjects(filepath.Join(t.TempDir(), "nope"), now)
		if stats.TotalPrompts != 0 {
			t.Errorf("missing directory produced %d prompts", stats.TotalPrompts)
		}
	})

	t.Run("malformed line mid-file", func(t *testing.T) {
		dir := t.TempDir()
		tempJSONL(t, dir, "proj/a.jsonl",
			fmt.Sprintf(`{"type":"assistant","sessionId":"s","timestamp":%q,"message":{"id":"good1","usage":{"input_tokens":5}}}`, iso(now)),
			`{"type":"assistant","message":{"usage":{"input_tokens":`,
			`{"usage": not even json}`,
			fmt.Sprintf(`{"type":"assistant","sessionId":"s","timestamp":%q,"message":{"id":"good2","usage":{"input_tokens":6}}}`, iso(now)),
		)
		stats := scanClaudeProjects(dir, now)
		if stats.TotalPrompts != 2 || stats.TodayTotalTokens != 11 {
			t.Errorf("got %d prompts / %d tokens, want 2 / 11", stats.TotalPrompts, stats.TodayTotalTokens)
		}
	})

	t.Run("session file that is not JSON at all", func(t *testing.T) {
		dir := t.TempDir()
		tempJSONL(t, dir, "proj/a.jsonl", "this is a log file", "\x00\x01binary\x02", `"usage": 3`)
		tempJSONL(t, dir, "proj/b.jsonl",
			fmt.Sprintf(`{"type":"assistant","sessionId":"s","timestamp":%q,"message":{"id":"ok","usage":{"input_tokens":4}}}`, iso(now)))
		stats := scanClaudeProjects(dir, now)
		if stats.TotalPrompts != 1 || stats.TodayTotalTokens != 4 {
			t.Errorf("got %d prompts / %d tokens, want 1 / 4", stats.TotalPrompts, stats.TodayTotalTokens)
		}
	})

	t.Run("a line with no id keys off the file and its line number", func(t *testing.T) {
		dir := t.TempDir()
		line := fmt.Sprintf(`{"type":"assistant","sessionId":"s","timestamp":%q,"message":{"usage":{"input_tokens":3}}}`, iso(now))
		tempJSONL(t, dir, "proj/a.jsonl", line, line)
		stats := scanClaudeProjects(dir, now)
		// Same text twice, but different line numbers, so both count. Two
		// identical lines really are two turns when neither names itself.
		if stats.TotalPrompts != 2 {
			t.Errorf("TotalPrompts = %d, want 2", stats.TotalPrompts)
		}
	})
}

// ------------------------------------------------------------------- limits

func TestProbeLimitShapes(t *testing.T) {
	payload := map[string]any{
		"five_hour":            map[string]any{"utilization": 26.0, "resets_at": "2026-08-31T20:50:00.422544+00:00"},
		"seven_day_oauth_apps": map[string]any{"utilization": 38.0, "resets_at": "2026-09-01T09:00:00+00:00"},
		"limits": []any{
			map[string]any{
				"kind": "weekly_scoped", "percent": 49.0, "resets_at": "2026-09-01T09:00:00+00:00",
				"scope": map[string]any{"model": map[string]any{"display_name": "Fable"}},
			},
			// Repeat of the same model and window: one gauge, not two.
			map[string]any{
				"kind": "weekly_scoped", "percent": 51.0,
				"scope": map[string]any{"model": map[string]any{"display_name": "Fable"}},
			},
			// Only an id, and a five-hour window.
			map[string]any{
				"kind": "five_hour_scoped", "percent": 3.0,
				"scope": map[string]any{"model": map[string]any{"id": "opus-5"}},
			},
			// A kind that names no window keeps the bare model name.
			map[string]any{
				"kind": "mystery", "percent": 1.0,
				"scope": map[string]any{"model": map[string]any{"display_name": "Sonnet"}},
			},
			// No model scope at all: a flat bucket in disguise, skipped here.
			map[string]any{"kind": "weekly", "percent": 90.0},
		},
	}

	limits := buildLimitsForTest(t, payload)
	want := []Limit{
		{Label: "Session (5-hour)", Percent: 0.26, ResetsAt: "2026-08-31T20:50:00.422544+00:00"},
		{Label: "Weekly (7-day)", Percent: 0.38, ResetsAt: "2026-09-01T09:00:00+00:00"},
		{Label: "Fable Weekly", Title: "Fable Weekly", Percent: 0.49, ResetsAt: "2026-09-01T09:00:00+00:00"},
		{Label: "opus-5 Session", Title: "opus-5 Session", Percent: 0.03, ResetsAt: ""},
		{Label: "Sonnet", Title: "Sonnet", Percent: 0.01, ResetsAt: ""},
	}
	if !reflect.DeepEqual(limits, want) {
		t.Errorf("limits =\n%+v\nwant\n%+v", limits, want)
	}

	// The panel's windowLabel() shortens the two flat labels and otherwise
	// prefers the title, which is what keeps "Fable Weekly" out of "weekly".
	for _, limit := range limits[2:] {
		if limit.Title == "" {
			t.Errorf("scoped limit %q has no title; windowLabel() would fall back to the label", limit.Label)
		}
	}
}

// buildLimitsForTest runs the same assembly probeClaudeLimits does, without
// the HTTP round trip.
func buildLimitsForTest(t *testing.T, payload map[string]any) []Limit {
	t.Helper()
	encoded, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(encoded, &decoded); err != nil {
		t.Fatal(err)
	}

	weekly, _ := firstTruthy(decoded["seven_day_oauth_apps"], decoded["seven_day"]).(map[string]any)
	session, _ := decoded["five_hour"].(map[string]any)
	raw := []any{session["utilization"], weekly["utilization"]}
	entries, _ := decoded["limits"].([]any)
	for _, item := range entries {
		if entry, ok := item.(map[string]any); ok {
			raw = append(raw, entry["percent"])
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
	if percent := normalizeUtilization(session["utilization"], percentScale); percent >= 0 {
		limits = append(limits, Limit{Label: "Session (5-hour)", Percent: percent, ResetsAt: normalizeResetAt(session["resets_at"])})
	}
	if percent := normalizeUtilization(weekly["utilization"], percentScale); percent >= 0 {
		limits = append(limits, Limit{Label: "Weekly (7-day)", Percent: percent, ResetsAt: normalizeResetAt(weekly["resets_at"])})
	}
	return append(limits, scopedLimits(decoded, percentScale)...)
}

func TestNormalizeUtilizationScale(t *testing.T) {
	cases := []struct {
		name         string
		value        any
		percentScale bool
		want         float64
	}{
		// A payload carrying any value at or above 1 is percent-scaled, so a
		// bare 1.0 is one percent and not the whole allowance.
		{"one percent in a percent payload", 1.0, true, 0.01},
		{"a fraction in a fraction payload", 0.37, false, 0.37},
		{"above one is always a percentage", 37.0, false, 0.37},
		{"clamped at the top", 260.0, true, 1},
		{"a percent sign is tolerated", "42%", true, 0.42},
		{"nothing parseable", "n/a", true, -1},
		{"missing", nil, true, -1},
		{"negative", -3.0, true, -1},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if got := normalizeUtilization(test.value, test.percentScale); got != test.want {
				t.Errorf("normalizeUtilization(%v, %v) = %v, want %v", test.value, test.percentScale, got, test.want)
			}
		})
	}
}

func TestNormalizeResetAt(t *testing.T) {
	tests := []struct {
		name  string
		value any
		want  string
	}{
		{"epoch seconds", "1788000000", "2026-08-29T10:40:00+00:00"},
		{"epoch milliseconds", "1788000000000", "2026-08-29T10:40:00+00:00"},
		{"an ISO string round-trips", "2026-09-01T09:00:00.422933+00:00", "2026-09-01T09:00:00.422933+00:00"},
		{"a Z suffix becomes an offset", "2026-09-01T09:00:00Z", "2026-09-01T09:00:00+00:00"},
		{"junk is passed through", "soon", "soon"},
		{"empty", "", ""},
		{"absent", nil, ""},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if got := normalizeResetAt(test.value); got != test.want {
				t.Errorf("normalizeResetAt(%v) = %q, want %q", test.value, got, test.want)
			}
		})
	}
}

func TestLimitWindowOpen(t *testing.T) {
	now := at(10, 0)
	cases := []struct {
		name string
		at   string
		want bool
	}{
		{"a window that has not reset is still worth showing", iso(now.Add(time.Hour)), true},
		{"a window that has reset describes a period that is over", iso(now.Add(-time.Hour)), false},
		{"no reset time at all", "", true},
		{"an unreadable timestamp is no reason to drop a real number", "whenever", true},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if got := limitWindowOpen(Limit{ResetsAt: test.at}, now); got != test.want {
				t.Errorf("limitWindowOpen(%q) = %v, want %v", test.at, got, test.want)
			}
		})
	}
}

func TestClaudePlanLabel(t *testing.T) {
	cases := []struct{ tier, subscription, want string }{
		{"max_5x_something", "", "Max 5x"},
		{"MAX_20X", "", "Max 20X"},
		{"", "pro", "Pro"},
		{"unrecognised", "team", "Team"},
		{"", "", ""},
	}
	for _, test := range cases {
		if got := claudePlanLabel(test.tier, test.subscription); got != test.want {
			t.Errorf("claudePlanLabel(%q, %q) = %q, want %q", test.tier, test.subscription, got, test.want)
		}
	}
}

// -------------------------------------------------------------------- Codex

func TestCodexNativeSessionTokenSplit(t *testing.T) {
	now := at(10, 0)
	home := t.TempDir()
	t.Setenv("CODEX_HOME", home)

	tempJSONL(t, filepath.Join(home, "sessions"), "s.jsonl",
		`{"type":"turn_context","payload":{"model":"gpt-5.5"}}`,
		// Cached tokens are inside input_tokens and reasoning inside output,
		// so the split must not double-count either.
		fmt.Sprintf(`{"type":"response_item","timestamp":%q,"payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":700,"cache_write_input_tokens":100,"output_tokens":50}}}}`, iso(now)),
		// total_token_usage is cumulative and must be ignored.
		fmt.Sprintf(`{"type":"response_item","timestamp":%q,"payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":999999},"last_token_usage":{"input_tokens":10,"output_tokens":5}}}}`, iso(now)),
		// A model switch mid-session applies from here on.
		`{"type":"turn_context","payload":{"model_slug":"gpt-5.6-sol"}}`,
		fmt.Sprintf(`{"type":"response_item","timestamp":%q,"payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":8,"output_tokens":2}}}}`, iso(now.AddDate(0, 0, -1))),
		// Malformed line mid-file.
		`{"type":"response_item","payload":{"type":"token_count",`,
		// An all-zero turn is not a turn.
		fmt.Sprintf(`{"type":"response_item","timestamp":%q,"payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":0,"output_tokens":0}}}}`, iso(now)),
	)

	counts := newTally(now)
	scanNativeCodexSessions(counts, now)
	stats := counts.stats()

	want := &Bucket{InputTokens: 210, OutputTokens: 55, CacheReadInputTokens: 700, CacheCreationInputTokens: 100}
	if got := stats.ModelUsage["gpt-5.5"]; !reflect.DeepEqual(got, want) {
		t.Errorf("gpt-5.5 bucket = %+v, want %+v", got, want)
	}
	if got := stats.ModelUsage["gpt-5.6-sol"]; got == nil || got.InputTokens != 8 || got.OutputTokens != 2 {
		t.Errorf("gpt-5.6-sol bucket = %+v, want 8 in / 2 out", got)
	}
	if stats.TodayTotalTokens != 1065 {
		t.Errorf("TodayTotalTokens = %d, want 1065", stats.TodayTotalTokens)
	}
	if stats.TotalPrompts != 3 {
		t.Errorf("TotalPrompts = %d, want 3", stats.TotalPrompts)
	}
	if stats.TotalSessions != 1 {
		t.Errorf("TotalSessions = %d, want 1", stats.TotalSessions)
	}
}

func TestCodexNativeSessionsIgnoreStaleFiles(t *testing.T) {
	now := time.Now()
	home := t.TempDir()
	t.Setenv("CODEX_HOME", home)
	path := tempJSONL(t, filepath.Join(home, "sessions"), "old.jsonl",
		`{"type":"response_item","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":42}}}}`)
	stale := now.Add(-40 * 24 * time.Hour)
	if err := os.Chtimes(path, stale, stale); err != nil {
		t.Fatal(err)
	}

	counts := newTally(now)
	scanNativeCodexSessions(counts, now)
	if counts.stats().TotalPrompts != 0 {
		t.Errorf("a session older than the retention window was counted")
	}
}

func TestCodexLimitWindowLabels(t *testing.T) {
	cases := []struct {
		name string
		raw  any
		want *Limit
	}{
		{"the weekly window has its own wording", map[string]any{"usedPercent": 12.0, "windowDurationMins": 10080.0, "resetsAt": 1788500000.0},
			&Limit{Label: "Weekly (7-day)", Percent: 0.12, ResetsAt: "2026-09-04T05:33:20+00:00"}},
		{"whole hours", map[string]any{"usedPercent": 37.5, "windowDurationMins": 300.0},
			&Limit{Label: "5h window", Percent: 0.375}},
		{"anything else stays in minutes", map[string]any{"usedPercent": 5.0, "windowDurationMins": 90.0},
			&Limit{Label: "90m window", Percent: 0.05}},
		{"no duration", map[string]any{"usedPercent": 5.0},
			&Limit{Label: "Limit", Percent: 0.05}},
		{"a window with no usage figure is not a gauge", map[string]any{"windowDurationMins": 300.0}, nil},
		{"not a window at all", "primary", nil},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			got := codexLimitWindow(test.raw)
			if !reflect.DeepEqual(got, test.want) {
				t.Errorf("codexLimitWindow = %+v, want %+v", got, test.want)
			}
		})
	}
}

func TestCodexRPCReadsPastAnUnrelatedNotification(t *testing.T) {
	home := t.TempDir()
	bin := filepath.Join(home, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	// Omarchy's collector cannot do this: it polls the pipe with select() and
	// reads it with a buffered readline, so a notification arriving in the
	// same read as the reply hides the reply in Python's own buffer and the
	// request times out. That is why this machine's stored Codex record says
	// authHelpText "account/rateLimits/read" rather than carrying limits.
	script := `#!/bin/sh
while IFS= read -r line; do
  case "$line" in
  *'"account/rateLimits/read"'*)
    printf '{"method":"session/notification","params":{}}\n'
    printf '{"id":3,"result":{"rateLimits":{"planType":"plus","primary":{"usedPercent":50,"windowDurationMins":300,"resetsAt":0}}}}\n'
    ;;
  *'"account/read"'*) printf '{"id":2,"result":{"account":{}}}\n' ;;
  *'"initialize"'*) printf '{"id":1,"result":{}}\n' ;;
  esac
done
`
	if err := os.WriteFile(filepath.Join(bin, "codex"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HOME", home)
	t.Setenv("PATH", bin+":"+os.Getenv("PATH"))

	rpc := fetchCodexRPC()
	if rpc.usageStatusText != "" {
		t.Fatalf("usageStatusText = %q (%s), want the RPC to have succeeded", rpc.usageStatusText, rpc.authHelpText)
	}
	if rpc.tierLabel != "plus" {
		t.Errorf("tierLabel = %q, want %q", rpc.tierLabel, "plus")
	}
	if len(rpc.limits) != 1 || rpc.limits[0].Label != "5h window" || rpc.limits[0].Percent != 0.5 {
		t.Errorf("limits = %+v, want one 5h window at 0.5", rpc.limits)
	}
	if rpc.limits[0].ResetsAt != "" {
		t.Errorf("resetsAt = %q, want empty for a zero reset", rpc.limits[0].ResetsAt)
	}
}

// ---------------------------------------------------------------- Fireworks

func TestSummarizeFireworksUsage(t *testing.T) {
	today := at(10, 0)
	day := func(offset int) string {
		return today.AddDate(0, 0, -offset).UTC().Format("2006-01-02T15:04:05Z")
	}
	payload := map[string]any{"serverlessCosts": []any{
		// promptTokens splits into cached and uncached when the API reports
		// only the total.
		map[string]any{"startTime": day(0), "group": map[string]any{"model_name": "accounts/fireworks/models/llama-v3p1-70b"},
			"promptTokens": 1000.0, "cachedPromptTokens": 250.0, "completionTokens": 400.0},
		// An explicit uncached figure is taken as given.
		map[string]any{"startTime": day(2), "group": map[string]any{"model_name": "kimi-k2p5"},
			"promptTokens": 10.0, "cachedPromptTokens": 0.0, "uncachedPromptTokens": 10.0, "completionTokens": 5.0},
		// A cache figure larger than the prompt is clamped to it.
		map[string]any{"startTime": day(0), "group": map[string]any{"model_name": "llama-v3p1-70b"},
			"promptTokens": 7.0, "cachedPromptTokens": 99.0, "completionTokens": 1.0},
		// Nothing spent, no row.
		map[string]any{"startTime": day(1), "modelName": "deepseek-v3",
			"promptTokens": 0.0, "completionTokens": 0.0},
		// Older than the chart, but still an active day.
		map[string]any{"startTime": day(20), "group": map[string]any{},
			"promptTokens": 500.0, "completionTokens": 250.0},
	}}

	stats := summarizeFireworksUsage(payload, today)

	// "v3p1" is how Fireworks spells "v3.1" in a model id.
	llama := stats.ModelUsage["llama-v3.1-70b"]
	if llama == nil {
		t.Fatalf("model names = %v, want a llama-v3.1-70b entry", stats.ModelUsage)
	}
	// Row one: 1000 prompt tokens of which 250 were cache hits, so 750 are
	// uncached input. Row three: 7 prompt tokens against a cache figure of 99,
	// clamped to 7, which leaves nothing uncached.
	want := &Bucket{InputTokens: 750, OutputTokens: 401, CacheReadInputTokens: 257, CacheCreationInputTokens: 0}
	if !reflect.DeepEqual(llama, want) {
		t.Errorf("llama bucket = %+v, want %+v", llama, want)
	}
	if got := stats.TodayTotalTokens; got != 1408 {
		t.Errorf("TodayTotalTokens = %d, want 1408", got)
	}
	if got := stats.TodayTokensByModel["llama-v3.1-70b"]; got != 1408 {
		t.Errorf("todayTokensByModel = %d, want 1408", got)
	}
	if got := stats.ModelUsage["unknown"]; got == nil || got.InputTokens != 500 {
		t.Errorf("a row with no model name = %+v, want 500 input under \"unknown\"", got)
	}
	if stats.RecentDays[6].MessageCount != 1408 || stats.RecentDays[4].MessageCount != 15 {
		t.Errorf("recentDays = %+v", stats.RecentDays)
	}
	// The 20-day-old row is off the chart but on the calendar.
	if stats.ActiveDays != 3 {
		t.Errorf("ActiveDays = %d (%v), want 3", stats.ActiveDays, stats.ActiveDates)
	}
	// The billing API never reports prompts or sessions.
	if stats.TotalPrompts != 0 || stats.TotalSessions != 0 {
		t.Errorf("Fireworks reported prompt or session counts it cannot know")
	}
}

func TestFireworksMoneyIsExact(t *testing.T) {
	funded, ok := parseDecimalNanos("100.10")
	if !ok || funded != 100_100_000_000 {
		t.Fatalf("parseDecimalNanos(100.10) = %d, %v", funded, ok)
	}
	spent := moneyNanos(map[string]any{"units": 12.0, "nanos": 500000000.0})
	if spent != 12_500_000_000 {
		t.Fatalf("moneyNanos = %d", spent)
	}
	if got := nanosToFloat(funded - spent); got != 87.6 {
		t.Errorf("remaining = %v, want 87.6 exactly", got)
	}
	if _, ok := parseDecimalNanos("not a number"); ok {
		t.Errorf("parseDecimalNanos accepted junk")
	}
}

func TestUnspellDecimalPoint(t *testing.T) {
	cases := map[string]string{
		"llama-v3p1-70b": "llama-v3.1-70b",
		"kimi-k2p5":      "kimi-k2.5",
		"pythia-1b":      "pythia-1b",
		"gpt-oss-120b":   "gpt-oss-120b",
		"p1":             "p1",
	}
	for in, want := range cases {
		if got := unspellDecimalPoint(in); got != want {
			t.Errorf("unspellDecimalPoint(%q) = %q, want %q", in, got, want)
		}
	}
}

// -------------------------------------------------------------- coercions

func TestNumberCoercionsFollowTheirOriginals(t *testing.T) {
	cases := []struct {
		name                     string
		value                    any
		claude, codex, fireworks int64
	}{
		{"a plain count", 42.0, 42, 42, 42},
		{"a float rounds one way and truncates the other", 3.7, 4, 3, 4},
		{"a tie goes to the even neighbour", 2.5, 2, 2, 2},
		{"a numeric string", "17", 17, 17, 17},
		{"a decimal string is not an integer literal", "17.5", 18, 0, 18},
		{"junk", "many", 0, 0, 0},
		{"missing", nil, 0, 0, 0},
		{"negative", -5.0, -5, -5, 0},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if got := claudeNumber(test.value); got != test.claude {
				t.Errorf("claudeNumber(%v) = %d, want %d", test.value, got, test.claude)
			}
			if got := codexNumber(test.value); got != test.codex {
				t.Errorf("codexNumber(%v) = %d, want %d", test.value, got, test.codex)
			}
			if got := fireworksNumber(test.value); got != test.fireworks {
				t.Errorf("fireworksNumber(%v) = %d, want %d", test.value, got, test.fireworks)
			}
		})
	}
}

func TestUsageTokenPrefersSnakeCase(t *testing.T) {
	usage := map[string]any{"input_tokens": 5.0, "inputTokens": 900.0}
	if got := usageToken(usage, "input_tokens", "inputTokens"); got != 5 {
		t.Errorf("usageToken = %d, want the snake_case 5", got)
	}
	if got := usageToken(map[string]any{"inputTokens": 7.0}, "input_tokens", "inputTokens"); got != 7 {
		t.Errorf("usageToken = %d, want the camelCase 7", got)
	}
	// Present but null is zero, not a fall-through to the other spelling.
	if got := usageToken(map[string]any{"input_tokens": nil, "inputTokens": 9.0}, "input_tokens", "inputTokens"); got != 0 {
		t.Errorf("usageToken = %d, want 0", got)
	}
}

func TestLocalDay(t *testing.T) {
	now := at(10, 0)
	midnight := time.Date(2026, 8, 31, 0, 0, 0, 0, time.Local)
	cases := []struct {
		name  string
		value any
		want  string
	}{
		{"milliseconds", float64(midnight.UnixMilli()), "2026-08-31"},
		{"seconds", float64(midnight.Add(-time.Second).Unix()), "2026-08-30"},
		{"an ISO string with an offset", iso(midnight.Add(-time.Second)), "2026-08-30"},
		{"a Z-suffixed instant lands on its local day", midnight.Add(time.Hour).UTC().Format("2006-01-02T15:04:05Z"), "2026-08-31"},
		{"a bare date", "2026-07-04", "2026-07-04"},
		{"junk falls back to today", "sometime", "2026-08-31"},
		{"absent falls back to today", nil, "2026-08-31"},
	}
	for _, test := range cases {
		t.Run(test.name, func(t *testing.T) {
			if got := localDay(test.value, now); got != test.want {
				t.Errorf("localDay(%v) = %q, want %q", test.value, got, test.want)
			}
		})
	}
}

func TestRecentDateStringsSpanSevenDaysOldestFirst(t *testing.T) {
	got := recentDateStrings(at(23, 59))
	want := []string{"2026-08-25", "2026-08-26", "2026-08-27", "2026-08-28", "2026-08-29", "2026-08-30", "2026-08-31"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("recentDateStrings = %v, want %v", got, want)
	}
}

// ------------------------------------------------------------------- merge

func TestMergeStats(t *testing.T) {
	base := Stats{
		TodayPrompts: 2, TodaySessions: 1, TodayTotalTokens: 100,
		TodayTokensByModel: map[string]int64{"opus": 100},
		RecentDays:         []Day{{Date: "2026-08-30", MessageCount: 5}, {Date: "2026-08-31", MessageCount: 100}},
		TotalPrompts:       10, TotalSessions: 3, ActiveDays: 2,
		ActiveDates: []string{"2026-08-30", "2026-08-31"},
		ModelUsage:  map[string]*Bucket{"opus": {InputTokens: 1, OutputTokens: 2, CacheReadInputTokens: 3, CacheCreationInputTokens: 4}},
	}
	extra := Stats{
		TodayPrompts: 1, TodaySessions: 1, TodayTotalTokens: 7,
		TodayTokensByModel: map[string]int64{"opus": 7, "sonnet": 0},
		RecentDays:         []Day{{Date: "2026-08-31", MessageCount: 7}},
		TotalPrompts:       4, TotalSessions: 1, ActiveDays: 9,
		ActiveDates: []string{"2026-08-31"},
		ModelUsage:  map[string]*Bucket{"opus": {InputTokens: 10}, "sonnet": {OutputTokens: 5}},
	}

	merged := mergeStats(base, extra)
	if merged.TotalPrompts != 14 || merged.TodayTotalTokens != 107 || merged.TotalSessions != 4 {
		t.Errorf("counts = %+v", merged)
	}
	if got := merged.ModelUsage["opus"]; got.InputTokens != 11 || got.CacheCreationInputTokens != 4 {
		t.Errorf("opus bucket = %+v", got)
	}
	if got := merged.RecentDays; len(got) != 2 || got[1].MessageCount != 107 {
		t.Errorf("recentDays = %+v", got)
	}
	// Sources overlap in time, so dates are unioned, not summed -- but a
	// source that only knows a count still bounds the answer from below.
	if !reflect.DeepEqual(merged.ActiveDates, []string{"2026-08-30", "2026-08-31"}) {
		t.Errorf("activeDates = %v", merged.ActiveDates)
	}
	if merged.ActiveDays != 9 {
		t.Errorf("activeDays = %d, want 9", merged.ActiveDays)
	}
}

// ------------------------------------------------------------------ records

// TestRecordCarriesEveryFieldThePanelReads is the contract with
// Services/AgentUsage.qml. Every key here is read by the service or by
// Widgets/AiUsage; a rename would be a silently blank section rather than an
// error anyone would see.
func TestRecordCarriesEveryFieldThePanelReads(t *testing.T) {
	now := at(10, 0)
	records := map[string]Record{
		"fireworks": fireworksBaseRecord(now),
		"claude": {
			SchemaVersion: schemaVersion, ID: claudeID, Name: claudeName,
			UpdatedAt: pyISOFormat(now.UTC()), Ready: true, HasLocalStats: true,
			Limits: []Limit{}, Stats: emptyStats(),
		},
	}
	required := []string{
		"id", "name", "schemaVersion", "ready", "tierLabel", "usageStatusText", "authHelpText",
		"hasLocalStats", "updatedAt", "limits", "modelUsage", "todayTokensByModel",
		"todayTotalTokens", "todayPrompts", "todaySessions", "totalPrompts", "totalSessions",
		"activeDates", "activeDays", "recentDays",
	}

	for name, record := range records {
		encoded, err := json.Marshal(record)
		if err != nil {
			t.Fatal(err)
		}
		var decoded map[string]any
		if err := json.Unmarshal(encoded, &decoded); err != nil {
			t.Fatal(err)
		}
		for _, key := range required {
			value, present := decoded[key]
			if !present {
				t.Errorf("%s record is missing %q", name, key)
				continue
			}
			// null would reach the panel as undefined and quietly disable a
			// section; the containers have to be empty, not absent.
			if value == nil {
				t.Errorf("%s record has %q as null", name, key)
			}
		}
	}

	// Fireworks alone carries these two, and the panel keeps prompt counts
	// out of its tooltip because of the second.
	encoded, _ := json.Marshal(fireworksBaseRecord(now))
	var fireworks map[string]any
	json.Unmarshal(encoded, &fireworks)
	if fireworks["scope"] != "account" {
		t.Errorf("fireworks scope = %v", fireworks["scope"])
	}
	if hasPrompts, present := fireworks["hasPromptStats"]; !present || hasPrompts != false {
		t.Errorf("fireworks hasPromptStats = %v (present %v)", hasPrompts, present)
	}
	// retryAdvised is absent unless Claude asks for it, which is how the
	// original wrote it.
	if _, present := fireworks["retryAdvised"]; present {
		t.Errorf("retryAdvised leaked into a record that did not set it")
	}
}

func TestWriteJSONAtomicLeavesNoPartialFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "claude.json")
	if err := writeJSONAtomic(path, map[string]any{"first": true}, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := writeJSONAtomic(path, map[string]any{"second": true}, 0o600); err != nil {
		t.Fatal(err)
	}

	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(content) != "{\"second\":true}\n" {
		t.Errorf("content = %q", content)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("mode = %v, want 0600", info.Mode().Perm())
	}
	// The temp file is renamed, never left behind: FileView watches this
	// directory and a stray .json would become a phantom provider.
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 {
		t.Errorf("directory holds %d entries, want only the record", len(entries))
	}
}

// ------------------------------------------------------------------- driver

func TestCollectIntoLeavesThePreviousRecordOnFailure(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "claude.json")
	if err := os.WriteFile(path, []byte(`{"id":"claude","todayTotalTokens":99}`), 0o600); err != nil {
		t.Fatal(err)
	}

	broken := provider{id: claudeID, collect: func(options) (Record, error) {
		return Record{}, fmt.Errorf("no route to host")
	}}
	if err := collectInto(dir, broken, options{now: time.Now()}); err == nil {
		t.Fatal("collectInto reported success for a failing collector")
	}
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(content), `"todayTotalTokens":99`) {
		t.Errorf("a failed collector truncated the previous record: %s", content)
	}
}

func TestRunSelectsProviders(t *testing.T) {
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("HOME", t.TempDir())
	// No codex on PATH and no network: every collector still produces a
	// record, because "cannot report" is a state the panel draws.
	t.Setenv("PATH", "/nonexistent")

	if code := run([]string{"--except", "claude", "--except", "fireworks", "codex"}); code != 0 {
		t.Fatalf("run exited %d", code)
	}
	usage := filepath.Join(state, "pshell", "agents", "usage")
	entries, err := os.ReadDir(usage)
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 1 || entries[0].Name() != "codex.json" {
		names := []string{}
		for _, entry := range entries {
			names = append(names, entry.Name())
		}
		t.Errorf("wrote %v, want only codex.json", names)
	}
}

func TestRunRejectsAnEmptySelection(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("HOME", t.TempDir())
	if code := run([]string{"nosuchagent"}); code == 0 {
		t.Error("run reported success having collected nothing")
	}
}
