package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

// ------------------------------------------------------------------- paths

func homeDir() string {
	if home, err := os.UserHomeDir(); err == nil && home != "" {
		return home
	}
	return "."
}

// xdgDir resolves one of the base directories, honouring its variable and
// falling back to the specification's default. Only ever called with an
// absolute-or-empty variable value, since a relative XDG path is undefined.
func xdgDir(variable, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(variable)); value != "" && filepath.IsAbs(value) {
		return value
	}
	return filepath.Join(homeDir(), fallback)
}

func stateDir() string {
	return filepath.Join(xdgDir("XDG_STATE_HOME", ".local/state"), "pshell", "agents", "usage")
}

// cacheRoot holds the scan caches. They are an optimisation and nothing else:
// every path that touches them degrades to a direct scan rather than failing,
// because the record is the contract and the cache is not.
func cacheRoot() (string, error) {
	root := filepath.Join(xdgDir("XDG_CACHE_HOME", ".cache"), "pshell", "agent-usage")
	if err := os.MkdirAll(root, 0o755); err != nil {
		return "", err
	}
	return root, nil
}

// ------------------------------------------------------------------ atomic

// writeJSONAtomic writes through a uniquely named temp file in the target's
// own directory and renames it into place. Two things need this. The state
// files are watched by FileView with watchChanges, so a half-written file is
// a parse error in the user's face; and the temp name is unique to this
// writer rather than derived from the target, because collectors run
// concurrently and a shared temp path means the second rename finds the
// first one's file already moved away.
func writeJSONAtomic(path string, payload any, mode fs.FileMode) error {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, "."+filepath.Base(path)+".*.tmp")
	if err != nil {
		return err
	}
	name := tmp.Name()
	defer os.Remove(name)

	if _, err := tmp.Write(encoded); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Chmod(mode); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(name, path)
}

// ------------------------------------------------------------------- cache

// readFreshJSON decodes path into target when it is younger than maxAge. A
// negative age means the mtime is in the future -- the clock moved backwards
// since the write -- and then the file's freshness cannot be trusted at all.
func readFreshJSON(path string, maxAge time.Duration, target any) bool {
	if maxAge <= 0 {
		return false
	}
	info, err := os.Stat(path)
	if err != nil {
		return false
	}
	age := time.Since(info.ModTime())
	if age < 0 || age > maxAge {
		return false
	}
	content, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return json.Unmarshal(content, target) == nil
}

// readJSONAnyAge is the same read without the freshness test, for the limits
// cache: a measured percentage outlives the probe that took it, and how long
// it stays usable is decided by the window it describes, not by an mtime.
func readJSONAnyAge(path string, target any) bool {
	content, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	return json.Unmarshal(content, target) == nil
}

// withLock serialises a rescan across concurrent runs. The lock is advisory
// and best-effort: if it cannot be taken the work still happens, because a
// missing lock should cost a duplicated scan and not a missing record.
func withLock(path string, fn func()) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		fn()
		return
	}
	defer file.Close()
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX); err != nil {
		fn()
		return
	}
	defer syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
	fn()
}

// ------------------------------------------------------------------- jsonl

// eachLine streams a file a line at a time. bufio.Scanner is the obvious tool
// and the wrong one: session transcripts routinely carry lines of several
// megabytes and Scanner gives up at its buffer limit, silently truncating a
// day's usage rather than reporting anything.
func eachLine(path string, fn func(lineNumber int, line string) error) error {
	file, err := os.Open(path)
	if err != nil {
		return err
	}
	defer file.Close()

	reader := bufio.NewReaderSize(file, 1<<16)
	for lineNumber := 1; ; lineNumber++ {
		line, err := reader.ReadString('\n')
		if line != "" {
			if callbackErr := fn(lineNumber, line); callbackErr != nil {
				return callbackErr
			}
		}
		if err != nil {
			if errors.Is(err, io.EOF) {
				return nil
			}
			return err
		}
	}
}

// walkFiles visits every regular file under root, quietly. A root that does
// not exist is not an error: a machine with no pi sessions is the normal
// case, not a broken one.
func walkFiles(root string, fn func(path string, info fs.FileInfo)) {
	info, err := os.Stat(root)
	if err != nil || !info.IsDir() {
		return
	}
	filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if entry.IsDir() {
			return nil
		}
		stat, err := entry.Info()
		if err != nil || !stat.Mode().IsRegular() {
			return nil
		}
		fn(path, stat)
		return nil
	})
}

// walkJSONL is walkFiles narrowed to the *.jsonl transcripts, matching the
// rglob("*.jsonl") the originals used.
func walkJSONL(root string, fn func(path string, info fs.FileInfo)) {
	walkFiles(root, func(path string, info fs.FileInfo) {
		if strings.HasSuffix(path, ".jsonl") {
			fn(path, info)
		}
	})
}
