package main

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// opencode keeps every message it has ever sent in a SQLite database, with
// the provider, model and token split on each one. A subscription burned
// entirely through opencode writes no native transcript anywhere else, so
// skipping this database means reporting zero for a machine that spent
// millions of tokens.
//
// This is the one place the program shells out. Go's standard library has no
// SQLite reader, the alternatives are a cgo build or a third-party pure-Go
// engine, and neither is worth carrying for one read-only query -- so the
// `sqlite3` command does it. A machine without `sqlite3` loses opencode's
// contribution and keeps everything else, which is the same degradation the
// original had when the database was absent.
const sqliteCommand = "sqlite3"

// opencodeQueryTimeout bounds the shell-out. The query is indexed by nothing
// and scans the message table, but the JSON filters run inside SQLite and a
// 100 MB database answers in well under a second; a minute is the runaway
// stop, not the expected cost.
const opencodeQueryTimeout = 60 * time.Second

type opencodeRow struct {
	SessionID  string `json:"sessionId"`
	Input      any    `json:"input"`
	Output     any    `json:"output"`
	Reasoning  any    `json:"reasoning"`
	CacheRead  any    `json:"cacheRead"`
	CacheWrite any    `json:"cacheWrite"`
	Created    any    `json:"created"`
	ModelID    any    `json:"modelId"`
}

func opencodeDBPath() string {
	return filepath.Join(xdgDir("XDG_DATA_HOME", ".local/share"), "opencode", "opencode.db")
}

// opencodeQuery pulls out the six scalars this program needs rather than the
// whole message blob. The originals parsed every row in Python and one of
// them wasted hundreds of megabytes of memory doing it; letting SQLite do the
// extraction keeps multi-megabyte transcripts from ever crossing the pipe.
//
// The two LIKE terms are acceleration, not the filter: they skip rows whose
// raw text cannot contain the pairs, so the json_extract comparisons below
// them stay the authority. json_valid guards those, because json_extract
// raises on malformed JSON rather than returning NULL and one bad row would
// otherwise abort the scan.
func opencodeQuery(provider string) string {
	return fmt.Sprintf(`SELECT session_id AS sessionId,
       json_extract(data,'$.tokens.input')       AS input,
       json_extract(data,'$.tokens.output')      AS output,
       json_extract(data,'$.tokens.reasoning')   AS reasoning,
       json_extract(data,'$.tokens.cache.read')  AS cacheRead,
       json_extract(data,'$.tokens.cache.write') AS cacheWrite,
       json_extract(data,'$.time.created')       AS created,
       json_extract(data,'$.modelID')            AS modelId
FROM message
WHERE data LIKE '%%"role"%%:%%"assistant"%%'
  AND data LIKE '%%"providerID"%%:%%"%s"%%'
  AND CASE WHEN json_valid(data) THEN json_extract(data,'$.role') END = 'assistant'
  AND CASE WHEN json_valid(data) THEN json_extract(data,'$.providerID') END = '%s'`, provider, provider)
}

// readOpencodeRows returns opencode's assistant messages for one provider.
// The second value says whether the read ran to completion: a scan cut short
// by a missing binary or a locked database still leaves the other sources
// intact, but must not be cached as if it were the whole story.
func readOpencodeRows(provider string) ([]opencodeRow, bool) {
	// Exact match on the provider id. opencode's ids are free-form and a
	// custom "anthropic-proxy" gateway is not this subscription.
	if provider != "anthropic" && provider != "openai" {
		return nil, false
	}
	db := opencodeDBPath()
	if info, err := os.Stat(db); err != nil || !info.Mode().IsRegular() {
		// No database is not a failure. Nothing was missed.
		return nil, true
	}
	if _, err := exec.LookPath(sqliteCommand); err != nil {
		warnf("opencode usage skipped: %s is not installed", sqliteCommand)
		return nil, false
	}

	ctx, cancel := context.WithTimeout(context.Background(), opencodeQueryTimeout)
	defer cancel()

	// -readonly rather than a plain open: opencode may be writing right now,
	// and this program has no business touching its journal.
	cmd := exec.CommandContext(ctx, sqliteCommand,
		"-readonly", "-json", "-cmd", ".timeout 2000",
		db, opencodeQuery(provider))
	output, err := cmd.Output()
	if err != nil {
		warnf("opencode usage unavailable: %v", err)
		return nil, false
	}

	trimmed := strings.TrimSpace(string(output))
	if trimmed == "" {
		return nil, true
	}
	var rows []opencodeRow
	if err := json.Unmarshal([]byte(trimmed), &rows); err != nil {
		warnf("opencode usage unreadable: %v", err)
		return nil, false
	}
	return rows, true
}

// lastPathSegment is the originals' `str(id).rstrip("/").split("/")[-1]`:
// opencode model ids are sometimes "provider/model" and only the model half
// is worth a row in the panel's ranking.
func lastPathSegment(value string) string {
	trimmed := strings.TrimRight(value, "/")
	if index := strings.LastIndex(trimmed, "/"); index >= 0 {
		return trimmed[index+1:]
	}
	return trimmed
}
