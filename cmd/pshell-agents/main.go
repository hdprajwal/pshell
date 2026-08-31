// Command pshell-agents writes one JSON usage record per coding agent into
// pshell's state directory, where Services/AgentUsage.qml watches them.
//
// It replaces Omarchy's omarchy-agent-usage-update and the three Python
// collectors behind it, which were the last piece of Omarchy pshell needed at
// runtime. The record format is unchanged: the panel already reads that
// shape, and a renamed field would be a silently blank section rather than an
// error anyone would see.
//
// Nothing here is a daemon. It runs, writes, and exits; the shell schedules
// it and the files are the only interface between the two.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const usage = `pshell-agents - collect coding-agent usage into pshell's state directory

usage: pshell-agents [--force] [--limits-only] [--except <agent>] [agent...]

  --force           rescan everything and re-probe limits, ignoring caches
  --limits-only     reuse any recent local scan; only the limits must be fresh
  --except <agent>  skip one agent; may be repeated
  agent...          collect only the named agents

Records are written to $XDG_STATE_HOME/pshell/agents/usage/<agent>.json.
`

// A provider is a name and the function that produces its record. Adding one
// is adding an entry here: the panel draws whatever records it finds.
type provider struct {
	id      string
	collect func(options) (Record, error)
}

func providers() []provider {
	return []provider{
		{claudeID, collectClaude},
		{codexID, collectCodex},
		{fireworksID, collectFireworks},
	}
}

type options struct {
	force      bool
	limitsOnly bool
	now        time.Time
}

// scanAge is how old a cached local scan may be and still be used. --force is
// a person asking for fresh numbers and reuses nothing; --limits-only
// promises only that the limits are fresh, so it may reuse a scan for far
// longer than an ordinary run, whose short window exists purely to dedup the
// concurrent collectors this program starts.
func (o options) scanAge() time.Duration {
	switch {
	case o.force:
		return 0
	case o.limitsOnly:
		return codexLimitsOnlyReuse
	default:
		return codexScanReuse
	}
}

func warnf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "pshell-agents: "+format+"\n", args...)
}

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(args []string) int {
	opts := options{now: time.Now()}
	only := map[string]bool{}
	excluded := map[string]bool{}

	// Hand-rolled rather than flag.Parse, because the driver this replaces
	// accepted flags and agent names in any order and the shell's saved
	// invocations should keep working.
	for index := 0; index < len(args); index++ {
		switch arg := args[index]; arg {
		case "--force":
			opts.force = true
		case "--limits-only":
			opts.limitsOnly = true
		case "--except":
			if index+1 < len(args) {
				index++
				excluded[args[index]] = true
			}
		case "-h", "--help":
			fmt.Print(usage)
			return 0
		default:
			only[arg] = true
		}
	}

	dir := stateDir()
	if err := os.MkdirAll(dir, 0o755); err != nil {
		warnf("cannot create %s: %v", dir, err)
		return 1
	}

	// A goroutine per provider. They share nothing: each reads its own files,
	// talks to its own endpoint and writes its own record, so one failing --
	// a dead network, a locked database -- must not take the others with it.
	var wait sync.WaitGroup
	var mutex sync.Mutex
	attempted, failed := 0, 0

	for _, entry := range providers() {
		if excluded[entry.id] {
			continue
		}
		if len(only) > 0 && !only[entry.id] {
			continue
		}
		attempted++

		wait.Add(1)
		go func(entry provider) {
			defer wait.Done()
			if err := collectInto(dir, entry, opts); err != nil {
				warnf("%s collector failed: %v", entry.id, err)
				mutex.Lock()
				failed++
				mutex.Unlock()
			}
		}(entry)
	}
	wait.Wait()

	if attempted == 0 {
		warnf("no agents selected")
		return 1
	}
	// A partial success is a success. One provider that could not answer
	// leaves its previous record in place and says so on stderr; the shell
	// has no use for an exit code that means "some of the numbers moved".
	if failed == attempted {
		return 1
	}
	return 0
}

// collectInto writes one provider's record. On any failure it writes nothing
// at all, which leaves the last good record in place: a panel showing numbers
// from fifteen minutes ago is worth more than one showing none.
func collectInto(dir string, entry provider, opts options) error {
	record, err := entry.collect(opts)
	if err != nil {
		return err
	}
	if record.ID == "" {
		return fmt.Errorf("collector produced a record with no id")
	}
	// 0600 because these are the user's own records and nobody else has any
	// business reading how much they spent today.
	return writeJSONAtomic(filepath.Join(dir, record.ID+".json"), record, 0o600)
}
