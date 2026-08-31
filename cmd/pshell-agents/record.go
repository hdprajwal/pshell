package main

import (
	"sort"
	"time"
)

// The record format Services/AgentUsage.qml parses. It is the contract
// between this program and the panel: a renamed field is a silently blank
// section, so nothing here is cosmetic.
const schemaVersion = 1

// Bucket is the four-way token split reported per model. AgentUsage.qml's
// modelTotal() sums exactly these four and nothing else, so a fifth bucket
// added here would be collected and then never counted.
type Bucket struct {
	InputTokens              int64 `json:"inputTokens"`
	OutputTokens             int64 `json:"outputTokens"`
	CacheReadInputTokens     int64 `json:"cacheReadInputTokens"`
	CacheCreationInputTokens int64 `json:"cacheCreationInputTokens"`
}

func (b *Bucket) add(input, output, cacheRead, cacheWrite int64) {
	b.InputTokens += input
	b.OutputTokens += output
	b.CacheReadInputTokens += cacheRead
	b.CacheCreationInputTokens += cacheWrite
}

// Day is one column of the panel's seven-day chart. `messageCount` counts
// tokens, not messages: the name is older than the meaning and the panel
// already reads it, so it stays wrong rather than becoming incompatible.
type Day struct {
	Date         string `json:"date"`
	MessageCount int64  `json:"messageCount"`
}

// Limit is one usage window. AgentUsage.qml's windowLabel() special-cases the
// two labels the collectors write themselves -- "Session (5-hour)" and
// "Weekly (7-day)" -- and otherwise prefers `title`, which is how a
// model-scoped window such as "Fable Weekly" keeps its own wording.
type Limit struct {
	Label    string  `json:"label"`
	Title    string  `json:"title,omitempty"`
	Percent  float64 `json:"percent"`
	ResetsAt string  `json:"resetsAt"`
}

// Balance is Fireworks' prepaid ledger, which has no window to burn and so
// no Limit to sit in.
type Balance struct {
	Remaining float64 `json:"remaining"`
	Funded    float64 `json:"funded"`
	Spent     float64 `json:"spent"`
	Currency  string  `json:"currency"`
	Estimated bool    `json:"estimated"`
}

// Stats is everything a provider knows about its own history. Every provider
// carries the whole shape even when it can only fill part of it, because the
// panel reads the fields unconditionally.
type Stats struct {
	TodayPrompts       int              `json:"todayPrompts"`
	TodaySessions      int              `json:"todaySessions"`
	TodayTotalTokens   int64            `json:"todayTotalTokens"`
	TodayTokensByModel map[string]int64 `json:"todayTokensByModel"`
	RecentDays         []Day            `json:"recentDays"`
	TotalPrompts       int              `json:"totalPrompts"`
	TotalSessions      int              `json:"totalSessions"`
	// Days with any recorded usage, for the all-time "N days" summary. The
	// dates travel too: merging snapshots from several sources needs their
	// union, which a count alone cannot give.
	ActiveDays  int                `json:"activeDays"`
	ActiveDates []string           `json:"activeDates"`
	ModelUsage  map[string]*Bucket `json:"modelUsage"`
}

// emptyStats is the zero record's stats: empty containers rather than nil, so
// the JSON carries `{}` and `[]` instead of `null`.
func emptyStats() Stats {
	return Stats{
		TodayTokensByModel: map[string]int64{},
		RecentDays:         []Day{},
		ActiveDates:        []string{},
		ModelUsage:         map[string]*Bucket{},
	}
}

// Record is one provider's file. Optional fields are pointers or carry
// omitempty because the Python collectors omitted them entirely and the
// panel distinguishes absent from false in at least one place.
type Record struct {
	SchemaVersion int    `json:"schemaVersion"`
	ID            string `json:"id"`
	Name          string `json:"name"`
	UpdatedAt     string `json:"updatedAt"`
	Ready         bool   `json:"ready"`
	HasLocalStats bool   `json:"hasLocalStats"`
	// Fireworks only: its billing numbers are account-global, not
	// machine-local, so aggregation across synced devices must not sum them.
	Scope string `json:"scope,omitempty"`
	// Fireworks only: the billing API reports tokens but never prompt or
	// session counts.
	HasPromptStats  *bool    `json:"hasPromptStats,omitempty"`
	TierLabel       string   `json:"tierLabel"`
	UsageStatusText string   `json:"usageStatusText"`
	AuthHelpText    string   `json:"authHelpText"`
	RetryAdvised    bool     `json:"retryAdvised,omitempty"`
	Limits          []Limit  `json:"limits"`
	Balance         *Balance `json:"balance,omitempty"`
	Stats
}

// ------------------------------------------------------------------- tally

// tally accumulates per-message usage into the shape Stats wants. Claude and
// Codex both walk several sources into one of these; keeping the arithmetic
// in one place is what makes "the four buckets" mean the same thing twice.
type tally struct {
	today       string
	recentDates []string
	recent      map[string]int64

	todayByModel  map[string]int64
	modelUsage    map[string]*Bucket
	sessions      map[string]struct{}
	todaySessions map[string]struct{}
	activeDays    map[string]struct{}

	prompts      int
	todayPrompts int
	todayTotal   int64
}

func newTally(now time.Time) *tally {
	dates := recentDateStrings(now)
	t := &tally{
		today:         dateString(now),
		recentDates:   dates,
		recent:        make(map[string]int64, len(dates)),
		todayByModel:  map[string]int64{},
		modelUsage:    map[string]*Bucket{},
		sessions:      map[string]struct{}{},
		todaySessions: map[string]struct{}{},
		activeDays:    map[string]struct{}{},
	}
	for _, day := range dates {
		t.recent[day] = 0
	}
	return t
}

func (t *tally) add(day, sessionKey, model string, input, output, cacheRead, cacheWrite int64) {
	total := input + output + cacheRead + cacheWrite

	t.prompts++
	t.sessions[sessionKey] = struct{}{}
	t.activeDays[day] = struct{}{}

	bucket := t.modelUsage[model]
	if bucket == nil {
		bucket = &Bucket{}
		t.modelUsage[model] = bucket
	}
	bucket.add(input, output, cacheRead, cacheWrite)

	if _, ok := t.recent[day]; ok {
		t.recent[day] += total
	}

	if day == t.today {
		t.todayPrompts++
		t.todaySessions[sessionKey] = struct{}{}
		t.todayTotal += total
		t.todayByModel[model] += total
	}
}

func (t *tally) stats() Stats {
	days := make([]Day, 0, len(t.recentDates))
	for _, day := range t.recentDates {
		days = append(days, Day{Date: day, MessageCount: t.recent[day]})
	}
	return Stats{
		TodayPrompts:       t.todayPrompts,
		TodaySessions:      len(t.todaySessions),
		TodayTotalTokens:   t.todayTotal,
		TodayTokensByModel: t.todayByModel,
		RecentDays:         days,
		TotalPrompts:       t.prompts,
		TotalSessions:      len(t.sessions),
		ActiveDays:         len(t.activeDays),
		ActiveDates:        sortedKeys(t.activeDays),
		ModelUsage:         t.modelUsage,
	}
}

func sortedKeys(set map[string]struct{}) []string {
	out := make([]string, 0, len(set))
	for key := range set {
		out = append(out, key)
	}
	sort.Strings(out)
	return out
}

// ------------------------------------------------------------------- merge

// mergeStats folds a second source's stats into the first. Sources overlap in
// time, so dates are unioned rather than summed: a machine that ran Claude
// through two front ends on the same day had one active day, not two.
func mergeStats(base, extra Stats) Stats {
	merged := Stats{
		TodayPrompts:     base.TodayPrompts + extra.TodayPrompts,
		TodaySessions:    base.TodaySessions + extra.TodaySessions,
		TodayTotalTokens: base.TodayTotalTokens + extra.TodayTotalTokens,
		TotalPrompts:     base.TotalPrompts + extra.TotalPrompts,
		TotalSessions:    base.TotalSessions + extra.TotalSessions,
	}

	byModel := map[string]int64{}
	for model, count := range base.TodayTokensByModel {
		byModel[model] += count
	}
	for model, count := range extra.TodayTokensByModel {
		byModel[model] += count
	}
	merged.TodayTokensByModel = byModel

	usage := map[string]*Bucket{}
	for _, source := range []map[string]*Bucket{base.ModelUsage, extra.ModelUsage} {
		for model, bucket := range source {
			if bucket == nil {
				continue
			}
			target := usage[model]
			if target == nil {
				target = &Bucket{}
				usage[model] = target
			}
			target.add(bucket.InputTokens, bucket.OutputTokens, bucket.CacheReadInputTokens, bucket.CacheCreationInputTokens)
		}
	}
	merged.ModelUsage = usage

	byDate := map[string]int64{}
	for _, source := range [][]Day{base.RecentDays, extra.RecentDays} {
		for _, day := range source {
			if day.Date == "" {
				continue
			}
			byDate[day.Date] += day.MessageCount
		}
	}
	dates := make([]string, 0, len(byDate))
	for date := range byDate {
		dates = append(dates, date)
	}
	sort.Strings(dates)
	merged.RecentDays = make([]Day, 0, len(dates))
	for _, date := range dates {
		merged.RecentDays = append(merged.RecentDays, Day{Date: date, MessageCount: byDate[date]})
	}

	active := map[string]struct{}{}
	for _, date := range base.ActiveDates {
		active[date] = struct{}{}
	}
	for _, date := range extra.ActiveDates {
		active[date] = struct{}{}
	}
	merged.ActiveDates = sortedKeys(active)
	// A source that only knows a count still bounds the answer from below.
	merged.ActiveDays = len(active)
	if base.ActiveDays > merged.ActiveDays {
		merged.ActiveDays = base.ActiveDays
	}
	if extra.ActiveDays > merged.ActiveDays {
		merged.ActiveDays = extra.ActiveDays
	}
	return merged
}
