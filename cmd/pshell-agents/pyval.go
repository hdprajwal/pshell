package main

import (
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
)

// Coercions that mirror what the collectors this program replaces did in
// Python. The session logs on disk are written by half a dozen different
// tools and none of them promise a type, so the old collectors leaned hard on
// Python's `or`, `float()` and `int()` to turn whatever they found into a
// number. Reproducing those rules exactly is the difference between the same
// token count and a plausible one.

// truthy is Python's notion of it: everything is true except None, False,
// zero, and the empty string, list, map and object. It is here because
// `usage.get("input") or 0` appears all over the originals and a Go `!= nil`
// is not the same test.
func truthy(value any) bool {
	switch v := value.(type) {
	case nil:
		return false
	case bool:
		return v
	case float64:
		return v != 0
	case string:
		return v != ""
	case []any:
		return len(v) > 0
	case map[string]any:
		return len(v) > 0
	default:
		return true
	}
}

// firstTruthy is the `a or b or c` chain.
func firstTruthy(values ...any) any {
	for _, value := range values {
		if truthy(value) {
			return value
		}
	}
	if len(values) == 0 {
		return nil
	}
	return values[len(values)-1]
}

// pyFloat is `float(value)`, reporting the TypeError/ValueError the callers
// all catch rather than raising it.
func pyFloat(value any) (float64, bool) {
	switch v := value.(type) {
	case nil:
		return 0, false
	case bool:
		if v {
			return 1, true
		}
		return 0, true
	case float64:
		return v, true
	case int64:
		return float64(v), true
	case string:
		n, err := strconv.ParseFloat(strings.TrimSpace(v), 64)
		if err != nil {
			return 0, false
		}
		return n, true
	default:
		return 0, false
	}
}

// roundHalfEven is Python's built-in round() on a float: ties go to the even
// neighbour, not away from zero. Token counts are integral in practice, so
// this almost never bites -- but "almost never" is the kind of drift a
// differential run is supposed to rule out, not tolerate.
func roundHalfEven(n float64) int64 {
	if math.IsNaN(n) || math.IsInf(n, 0) {
		return 0
	}
	rounded := math.RoundToEven(n)
	if rounded > math.MaxInt64 {
		return math.MaxInt64
	}
	if rounded < math.MinInt64 {
		return math.MinInt64
	}
	return int64(rounded)
}

// claudeNumber is the Claude collector's number(): round(float(value or 0)),
// with NaN and any conversion failure landing on zero.
func claudeNumber(value any) int64 {
	if !truthy(value) {
		return 0
	}
	n, ok := pyFloat(value)
	if !ok || math.IsNaN(n) {
		return 0
	}
	return roundHalfEven(n)
}

// codexNumber is the Codex collector's number(): int(value or 0). int()
// truncates a float toward zero rather than rounding it, and refuses a
// string that is not an integer literal, so this is deliberately not
// claudeNumber.
func codexNumber(value any) int64 {
	if !truthy(value) {
		return 0
	}
	switch v := value.(type) {
	case bool:
		return 1
	case float64:
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return 0
		}
		return int64(math.Trunc(v))
	case string:
		n, err := strconv.ParseInt(strings.TrimSpace(v), 10, 64)
		if err != nil {
			return 0
		}
		return n
	default:
		return 0
	}
}

// fireworksNumber is the Fireworks collector's number():
// max(0, round(float(value or 0))). The clamp matters -- the billing API can
// report a negative correction row and a negative token count would subtract
// from a model's lifetime total.
func fireworksNumber(value any) int64 {
	n := claudeNumber(value)
	if n < 0 {
		return 0
	}
	return n
}

// usageToken is the Claude collector's usage_token(): prefer the snake_case
// key, fall back to the camelCase one, and only then to zero. Which spelling
// a line uses depends on which tool wrote it.
func usageToken(usage map[string]any, snakeKey, camelKey string) int64 {
	value, ok := usage[snakeKey]
	if !ok {
		value = usage[camelKey]
	}
	return claudeNumber(value)
}

// pyStr is str(). Only ever applied to values that are strings in practice --
// session ids, model names -- but a session id that arrived as a number still
// has to key a set consistently rather than vanish.
func pyStr(value any) string {
	switch v := value.(type) {
	case nil:
		return "None"
	case string:
		return v
	case bool:
		if v {
			return "True"
		}
		return "False"
	case float64:
		if v == math.Trunc(v) && math.Abs(v) < 1e16 {
			return strconv.FormatInt(int64(v), 10)
		}
		return strconv.FormatFloat(v, 'g', -1, 64)
	default:
		return fmt.Sprint(v)
	}
}

// --------------------------------------------------------------------- time

func dateString(when time.Time) string {
	return when.Format("2006-01-02")
}

// recentDateStrings is the seven-day window the chart draws, oldest first.
// Built by calendar arithmetic rather than by subtracting 24-hour spans, so
// the day a clock change lands on is not counted twice or skipped.
func recentDateStrings(now time.Time) []string {
	year, month, day := now.Date()
	midnight := time.Date(year, month, day, 0, 0, 0, 0, now.Location())
	out := make([]string, 0, 7)
	for offset := 6; offset >= 0; offset-- {
		out = append(out, dateString(midnight.AddDate(0, 0, -offset)))
	}
	return out
}

// isoLayouts covers what Python's datetime.fromisoformat() accepts in the
// shapes these logs actually contain: a date, a date and time, either with or
// without fractional seconds, either with or without an offset.
var isoLayouts = []string{
	"2006-01-02T15:04:05.999999999-07:00",
	"2006-01-02T15:04:05-07:00",
	"2006-01-02T15:04-07:00",
	"2006-01-02T15:04:05.999999999",
	"2006-01-02T15:04:05",
	"2006-01-02T15:04",
	"2006-01-02",
}

// parseISO is fromisoformat() with the trailing "Z" normalised first, the way
// every caller in the originals did it. The second return says whether the
// text carried an offset, because a naive timestamp is read as local wall
// clock and an aware one is converted to it.
func parseISO(raw string) (time.Time, bool) {
	text := strings.TrimSpace(raw)
	if text == "" {
		return time.Time{}, false
	}
	text = strings.ReplaceAll(text, "Z", "+00:00")
	// fromisoformat() takes any single character as the date/time separator.
	if len(text) > 10 && text[10] != 'T' {
		text = text[:10] + "T" + text[11:]
	}
	for _, layout := range isoLayouts {
		if when, err := time.ParseInLocation(layout, text, time.Local); err == nil {
			return when, true
		}
	}
	return time.Time{}, false
}

// localDay is the collectors' local_day()/local_date_from_timestamp(): the
// local calendar date a log entry belongs to, whatever shape its timestamp
// arrived in, falling back to today rather than dropping the entry.
func localDay(value any, now time.Time) string {
	today := dateString(now)
	switch v := value.(type) {
	case nil:
		return today
	case float64:
		seconds := v
		// pi and Claude Code write milliseconds; Codex writes seconds. Ten
		// billion seconds is the year 2286, so anything above it is the
		// former.
		if seconds > 10_000_000_000 {
			seconds /= 1000
		}
		if math.IsNaN(seconds) || math.IsInf(seconds, 0) {
			return today
		}
		whole, frac := math.Modf(seconds)
		return dateString(time.Unix(int64(whole), int64(frac*1e9)).In(time.Local))
	}

	when, ok := parseISO(pyStr(value))
	if !ok {
		return today
	}
	return dateString(when.In(time.Local))
}
