package main

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"
)

// The Claude usage caches are keyed on age, but what they hold is dated: the
// today* fields belong to the day of the scan. These tests scan at 23:55 and
// read back at 00:05, well inside the cache's maximum age, so only the date
// check stands between yesterday's tokens and today's count.

var (
	lateNight   = at(23, 55)
	sameNight   = at(23, 58)
	nextMorning = time.Date(2026, 9, 1, 0, 5, 0, 0, time.Local)
)

const cacheAge = time.Hour

func isolateCaches(t *testing.T) string {
	t.Helper()
	home := t.TempDir()
	t.Setenv("HOME", home)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("XDG_DATA_HOME", filepath.Join(home, ".local", "share"))
	return home
}

// checkMidnight runs one cache through the 23:55 / 23:58 / 00:05 sequence.
// The 23:58 read happens after the source data is gone, which proves the
// cache really is being served on the same day; restore puts the data back
// so the 00:05 rescan has something to file under yesterday.
func checkMidnight(t *testing.T, read func(time.Time) *Stats, remove, restore func()) {
	t.Helper()
	first := read(lateNight)
	if first == nil || first.TodayTotalTokens != 100 {
		t.Fatalf("23:55 scan = %+v, want 100 tokens today", first)
	}

	remove()
	if cached := read(sameNight); cached == nil || cached.TodayTotalTokens != 100 {
		t.Fatalf("23:58 read = %+v, want the cached 100 tokens", cached)
	}
	restore()

	after := read(nextMorning)
	if after == nil {
		t.Fatal("00:05 read returned no stats, want a rescan that still sees yesterday")
	}
	if after.TodayTotalTokens != 0 {
		t.Errorf("00:05 TodayTotalTokens = %d, want 0: yesterday's scan was served as today", after.TodayTotalTokens)
	}
	if len(after.ActiveDates) != 1 || after.ActiveDates[0] != "2026-08-31" {
		t.Errorf("00:05 ActiveDates = %v, want [2026-08-31]", after.ActiveDates)
	}
}

func TestClaudeTranscriptCacheMissesAfterMidnight(t *testing.T) {
	isolateCaches(t)
	projects := t.TempDir()
	line := fmt.Sprintf(`{"type":"assistant","sessionId":"s1","timestamp":%q,"message":{"id":"m1","model":"claude-opus-5","usage":{"input_tokens":100}}}`, iso(lateNight))
	path := tempJSONL(t, projects, "proj/a.jsonl", line)

	checkMidnight(t,
		func(now time.Time) *Stats {
			stats := cachedClaudeScan(projects, cacheAge, now)
			return &stats
		},
		func() { os.Remove(path) },
		func() { tempJSONL(t, projects, "proj/a.jsonl", line) },
	)
}

func TestClaudePiCacheMissesAfterMidnight(t *testing.T) {
	home := isolateCaches(t)
	sessions := filepath.Join(home, ".pi", "agent", "sessions")
	line := fmt.Sprintf(`{"type":"message","id":"e1","timestamp":%q,"message":{"role":"assistant","provider":"anthropic","model":"claude-opus-5","usage":{"input":100}}}`, iso(lateNight))
	path := tempJSONL(t, sessions, "s1.jsonl", line)

	checkMidnight(t,
		func(now time.Time) *Stats { return scanClaudePiUsage(cacheAge, now) },
		func() { os.Remove(path) },
		func() { tempJSONL(t, sessions, "s1.jsonl", line) },
	)
}

func TestClaudeOpencodeCacheMissesAfterMidnight(t *testing.T) {
	if _, err := exec.LookPath(sqliteCommand); err != nil {
		t.Skipf("%s is not installed", sqliteCommand)
	}
	isolateCaches(t)
	db := opencodeDBPath()
	if err := os.MkdirAll(filepath.Dir(db), 0o755); err != nil {
		t.Fatal(err)
	}
	row := fmt.Sprintf(`{"role":"assistant","providerID":"anthropic","modelID":"claude-opus-5","tokens":{"input":100,"output":0,"reasoning":0,"cache":{"read":0,"write":0}},"time":{"created":%d}}`, lateNight.UnixMilli())
	sqlite := func(statement string) {
		t.Helper()
		if output, err := exec.Command(sqliteCommand, db, statement).CombinedOutput(); err != nil {
			t.Fatalf("sqlite3: %v: %s", err, output)
		}
	}
	sqlite("CREATE TABLE message (session_id TEXT, data TEXT)")
	insert := fmt.Sprintf("INSERT INTO message VALUES ('s1', '%s')", row)
	sqlite(insert)

	checkMidnight(t,
		func(now time.Time) *Stats { return scanClaudeOpencodeUsage(cacheAge, now) },
		func() { sqlite("DELETE FROM message") },
		func() { sqlite(insert) },
	)
}
