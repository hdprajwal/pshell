package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// The brief's requirement was that one provider failing must not take the
// others down. The bash driver got that from process boundaries; goroutines do
// not, so these are the tests that say it is actually true here.

func TestRunSurvivesAPanickingCollector(t *testing.T) {
	state := t.TempDir()
	t.Setenv("XDG_STATE_HOME", state)
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("HOME", t.TempDir())

	usage := filepath.Join(state, "pshell", "agents", "usage")
	if err := os.MkdirAll(usage, 0o755); err != nil {
		t.Fatal(err)
	}
	// A record from the last good run of the provider that is about to blow
	// up. It has to still be there afterwards.
	previous := filepath.Join(usage, "boom.json")
	if err := os.WriteFile(previous, []byte("{\"id\":\"boom\",\"todayTotalTokens\":99}"), 0o600); err != nil {
		t.Fatal(err)
	}

	saved := providerTable
	t.Cleanup(func() { providerTable = saved })
	fine := func(id string) func(options) (Record, error) {
		return func(options) (Record, error) {
			return Record{SchemaVersion: schemaVersion, ID: id, Limits: []Limit{}, Stats: emptyStats()}, nil
		}
	}
	providerTable = []provider{
		{"first", fine("first")},
		{"boom", func(options) (Record, error) {
			// The shape of failure this really guards against: a provider
			// answers in a form nobody expected and the walk over it asserts
			// on something that is not there.
			var payload map[string]any
			return Record{}, fmt.Errorf("%v", payload["missing"].(map[string]any)["deeper"])
		}},
		{"second", fine("second")},
	}

	// Two of three succeeded, so this is a success with a warning rather than
	// a failure -- and above all the process is still here to say so.
	if code := run(nil); code != 0 {
		t.Fatalf("run exited %d, want 0: a panicking collector took the others down", code)
	}

	for _, id := range []string{"first", "second"} {
		if _, err := os.Stat(filepath.Join(usage, id+".json")); err != nil {
			t.Errorf("%s wrote no record: %v", id, err)
		}
	}
	content, err := os.ReadFile(previous)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(content), "\"todayTotalTokens\":99") {
		t.Errorf("the panicking provider's previous record was clobbered: %s", content)
	}
}

func TestRunFailsOnlyWhenEveryProviderDoes(t *testing.T) {
	t.Setenv("XDG_STATE_HOME", t.TempDir())
	t.Setenv("XDG_CACHE_HOME", t.TempDir())
	t.Setenv("HOME", t.TempDir())

	saved := providerTable
	t.Cleanup(func() { providerTable = saved })
	providerTable = []provider{
		{"one", func(options) (Record, error) { panic("down") }},
		{"two", func(options) (Record, error) { return Record{}, fmt.Errorf("no route to host") }},
	}
	if code := run(nil); code == 0 {
		t.Error("run reported success with every provider failed")
	}
}

func TestCollectSafelyReportsThePanicWithItsStack(t *testing.T) {
	entry := provider{id: "boom", collect: func(options) (Record, error) {
		panic("a nil map, say")
	}}
	err := collectSafely(t.TempDir(), entry, options{now: time.Now()})
	if err == nil {
		t.Fatal("collectSafely swallowed a panic")
	}
	if !strings.Contains(err.Error(), "a nil map, say") {
		t.Errorf("error does not name the panic: %v", err)
	}
	// A panic here is a bug in this program, and the line number is the whole
	// report.
	if !strings.Contains(err.Error(), "collectSafely") {
		t.Errorf("error carries no stack: %v", err)
	}
}
