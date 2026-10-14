import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { loadQmlJs } from "./load-qml-js.mjs";

const Weather = loadQmlJs("Services/Weather.js");

// The whole set Open-Meteo documents itself as emitting. Driven from a list on
// purpose: adding a case to the table without adding it here is fine, but
// dropping one from the table fails loudly rather than showing a question mark
// in the bar for a code that is perfectly ordinary.
const CODES = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99];

// A real reply from api.open-meteo.com, fetched once while this was written
// and saved rather than re-fetched: the point of the fixture is that the field
// names in the parser were checked against a payload the service actually
// sent, and a fixture that talks to the network is a test that fails on a
// train.
const PAYLOAD = {
    latitude: 12.970123,
    longitude: 77.56364,
    generationtime_ms: 0.19299983978271484,
    utc_offset_seconds: 19800,
    timezone: "Asia/Kolkata",
    timezone_abbreviation: "GMT+5:30",
    elevation: 914.0,
    current_units: { time: "iso8601", interval: "seconds", temperature_2m: "°C", weather_code: "wmo code", relative_humidity_2m: "%", apparent_temperature: "°C", wind_speed_10m: "km/h" },
    current: { time: "2026-08-31T21:15", interval: 900, temperature_2m: 23.8, weather_code: 3, relative_humidity_2m: 71, apparent_temperature: 25.1, wind_speed_10m: 12.2 },
    daily_units: { time: "iso8601", weather_code: "wmo code", temperature_2m_max: "°C", temperature_2m_min: "°C", sunrise: "iso8601", sunset: "iso8601" },
    daily: {
        time: ["2026-08-31", "2026-09-01", "2026-09-02"],
        weather_code: [51, 55, 80],
        temperature_2m_max: [28.6, 28.5, 28.8],
        temperature_2m_min: [19.3, 19.3, 19.9],
        sunrise: ["2026-08-31T06:08", "2026-09-01T06:08", "2026-09-02T06:08"],
        sunset: ["2026-08-31T18:31", "2026-09-01T18:30", "2026-09-02T18:30"]
    }
};

const NOW = Date.parse("2026-08-31T15:45:00Z");

// ------------------------------------------------------------- describe

test("every code Open-Meteo emits has a label and an icon", () => {
    for (const code of CODES) {
        const entry = Weather.describe(code);
        assert.notEqual(entry.label, "", `code ${code} has no label`);
        assert.notEqual(entry.icon, "", `code ${code} has no icon`);
        assert.notEqual(entry.night, "", `code ${code} has no night icon`);
        assert.notEqual(entry.label, "Unknown", `code ${code} fell through to the fallback`);
    }
});

test("every Material Symbol the shell names by hand is a ligature the shipped font has", () => {
    // The reason this is worth a test rather than a careful reading: a
    // Material Symbols name that is not in this cut of the font renders as the
    // literal word in the bar, which looks like a data bug and is not one.
    // `clear_night` is the specific one that bit -- the upstream alias exists,
    // the glyph in the file this repo ships does not.
    //
    // The font's name table separates a glyph's aliases with tabs and marks
    // the filled cut with a dot, so splitting on everything that is not a name
    // character is what turns "sunny.fill\tclear_day" into three usable names.
    const font = readFileSync(new URL("../assets/fonts/material-symbols/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf", import.meta.url));
    const names = new Set(font.toString("latin1").split(/[^A-Za-z0-9_]+/));

    const wanted = new Map();
    const want = (name, source) => wanted.set(name, source);

    want("question_mark", "Weather.js fallback");
    for (const code of CODES) {
        const entry = Weather.describe(code);
        want(entry.icon, `Weather.js code ${code}`);
        want(entry.night, `Weather.js code ${code} at night`);
    }

    // Glyphs.qml's fixed symbols are the shell's other hand-written names, and
    // they are swept here rather than only the five the weather panel added:
    // the trap is the name, not the widget, and the next one to be typed will
    // be somebody else's.
    const glyphs = readFileSync(new URL("../Services/Glyphs.qml", import.meta.url), "utf8");
    const fixed = [...glyphs.matchAll(/readonly\s+property\s+string\s+(\w+)\s*:\s*"([a-z0-9_]+)"/g)];
    // A refactor that renames or reshapes that block must not quietly turn
    // this sweep into an assertion about nothing.
    assert.ok(fixed.length >= 20, `only found ${fixed.length} fixed symbols in Glyphs.qml`);
    for (const [, property, name] of fixed)
        want(name, `Glyphs.${property}`);

    for (const [name, source] of wanted)
        assert.ok(names.has(name), `${name} (${source}) is not a ligature in the shipped font`);
});

test("a code nobody has heard of degrades without throwing", () => {
    for (const junk of [42, 0.5, null, undefined, -1, NaN, {}, [], ""]) {
        const entry = Weather.describe(junk);
        assert.notEqual(entry.label, "", `${JSON.stringify(junk)} produced an empty label`);
        assert.notEqual(entry.icon, "");
    }
    // null must not become code 0. Number(null) is 0 and 0 is "Clear sky", so
    // the lenient coercion would answer a missing reading with a sunny day.
    assert.notEqual(Weather.describe(null).label, Weather.describe(0).label);
});

test("a quoted code is the same code", () => {
    // Nothing in the shell quotes these -- JSON gives numbers -- but the cache
    // is hand-editable and a string that looks like a code should not become a
    // question mark. Pinned as an equality against the number so the assertion
    // survives every wording change to the label itself.
    assert.deepEqual(Weather.describe("3"), Weather.describe(3));
});

test("clear and partly cloudy change after dark; rain does not", () => {
    for (const code of [0, 1, 2]) {
        const entry = Weather.describe(code);
        assert.equal(entry.varies, true, `code ${code} should differ by daylight`);
        assert.notEqual(entry.icon, entry.night);
        assert.notEqual(Weather.iconFor(code, true), Weather.iconFor(code, false));
    }
    for (const code of [3, 45, 61, 65, 71, 95]) {
        const entry = Weather.describe(code);
        assert.equal(entry.varies, false, `code ${code} should look the same after dark`);
        assert.equal(Weather.iconFor(code, true), Weather.iconFor(code, false));
    }
});

test("iconFor with nobody saying which half of the day it is draws the day cut", () => {
    assert.equal(Weather.iconFor(0), Weather.describe(0).icon);
    assert.equal(Weather.iconFor(0, undefined), Weather.describe(0).icon);
    assert.equal(Weather.iconFor(0, null), Weather.describe(0).icon);
});

test("the three drizzle intensities share one picture and say the difference in words", () => {
    const labels = new Set([51, 53, 55].map(c => Weather.describe(c).label));
    const icons = new Set([51, 53, 55].map(c => Weather.describe(c).icon));
    assert.equal(labels.size, 3);
    assert.equal(icons.size, 1);
});

// ------------------------------------------------------------ isDaytime

test("isDaytime against a real sunrise and sunset", () => {
    const up = "2026-08-31T06:08";
    const down = "2026-08-31T18:31";

    assert.equal(Weather.isDaytime("2026-08-31T05:00", up, down), false, "before sunrise");
    assert.equal(Weather.isDaytime("2026-08-31T12:00", up, down), true, "noon");
    assert.equal(Weather.isDaytime("2026-08-31T21:15", up, down), false, "after sunset");

    // The boundaries belong to the lit side going up and the dark side coming
    // down, which is how the sky reads at those two minutes.
    assert.equal(Weather.isDaytime(up, up, down), true, "exactly sunrise");
    assert.equal(Weather.isDaytime(down, up, down), false, "exactly sunset");
});

test("isDaytime is not fooled by a timezone", () => {
    // 21:15 in Asia/Kolkata is 15:45 UTC. Date.parse on a zone-free string
    // reads it as UTC, so anything that went through Date would call this
    // afternoon and put a sun in the bar at nine in the evening.
    assert.equal(Weather.isDaytime("2026-08-31T21:15", "2026-08-31T06:08", "2026-08-31T18:31"), false);
});

test("isDaytime with no usable sunrise falls back to the clock, not to a throw", () => {
    for (const bad of [undefined, null, "", "not a time", "18:31"]) {
        assert.equal(Weather.isDaytime("2026-08-31T12:00", bad, "2026-08-31T18:31"), true);
        assert.equal(Weather.isDaytime("2026-08-31T23:00", "2026-08-31T06:08", bad), false);
    }
    // Nothing usable at all: day, because a sun is the picture that reads as
    // "weather" and a moon is a claim.
    assert.equal(Weather.isDaytime(null, null, null), true);
});

// ----------------------------------------------------------- formatting

test("formatTemp rounds, keeps negatives, and never invents a zero", () => {
    assert.equal(Weather.formatTemp(23.8, "metric"), "24°C");
    assert.equal(Weather.formatTemp(23.4, "metric"), "23°C");
    assert.equal(Weather.formatTemp(0, "metric"), "0°C");
    assert.equal(Weather.formatTemp(-4.6, "metric"), "-5°C");
    // Math.round(-0.4) is -0; the reading is freezing point, not minus zero.
    assert.equal(Weather.formatTemp(-0.4, "metric"), "0°C");
    assert.equal(Weather.formatTemp(74.6, "imperial"), "75°F");

    // The whole point of the strict coercion: null is what a NaN becomes on
    // the way through JSON.stringify into the persisted cache, and Number(null)
    // is 0. A reading that was never taken must not read as freezing.
    for (const missing of [null, undefined, "", NaN, "warm"])
        assert.equal(Weather.formatTemp(missing, "metric"), "—");
});

test("formatSpeed and formatPercent carry their units and their dash", () => {
    assert.equal(Weather.formatSpeed(12.2, "metric"), "12 km/h");
    assert.equal(Weather.formatSpeed(12.2, "imperial"), "12 mph");
    assert.equal(Weather.formatSpeed(null, "metric"), "—");
    assert.equal(Weather.formatPercent(71), "71%");
    assert.equal(Weather.formatPercent(null), "—");
});

// -------------------------------------------------------------- requests

test("the forecast URL asks for the unit rather than converting after the fact", () => {
    const metric = Weather.forecastUrl(12.97, 77.59, "metric");
    assert.ok(metric.includes("temperature_unit=celsius"));
    assert.ok(metric.includes("wind_speed_unit=kmh"));

    const imperial = Weather.forecastUrl(12.97, 77.59, "imperial");
    assert.ok(imperial.includes("temperature_unit=fahrenheit"));
    assert.ok(imperial.includes("wind_speed_unit=mph"));

    // Every field the parser reads has to be asked for. Pinned as a list
    // because a request that quietly drops one shows a dash forever and looks
    // like a network problem.
    for (const field of ["temperature_2m", "weather_code", "relative_humidity_2m", "apparent_temperature", "wind_speed_10m", "temperature_2m_max", "temperature_2m_min", "sunrise", "sunset", "precipitation_probability", "is_day"])
        assert.ok(metric.includes(field), `${field} is not in the request`);
    assert.ok(metric.includes("timezone=auto"));
    assert.ok(metric.includes("forecast_days=3"));

    assert.equal(Weather.forecastUrl(null, 77.59, "metric"), "");
    assert.equal(Weather.forecastUrl("nowhere", "nowhere", "metric"), "");
});

test("the geocoding URL escapes the name and refuses an empty one", () => {
    assert.ok(Weather.geocodeUrl("San José").includes("name=San%20Jos%C3%A9"));
    assert.equal(Weather.geocodeUrl(""), "");
    assert.equal(Weather.geocodeUrl("   "), "");
    assert.equal(Weather.geocodeUrl(null), "");
});

// --------------------------------------------------------------- parsing

test("a geocoding hit yields coordinates and a label that disambiguates", () => {
    const hit = Weather.parseGeocode({
        results: [{ id: 1277333, name: "Bengaluru", latitude: 12.97194, longitude: 77.59369, timezone: "Asia/Kolkata", country: "India", admin1: "Karnataka" }]
    });
    assert.equal(hit.latitude, 12.97194);
    assert.equal(hit.longitude, 77.59369);
    assert.equal(hit.name, "Bengaluru");
    // One pinned string, because "which of the two Springfields" is the whole
    // reason admin1 is in there and an assertion on the parts alone would not
    // notice them being joined in the wrong order.
    assert.equal(hit.label, "Bengaluru, Karnataka, India");
    assert.equal(hit.timezone, "Asia/Kolkata");
});

test("a name that matches nothing comes back with no results key at all", () => {
    // Verified against the live endpoint: a miss is `{generationtime_ms: ...}`
    // and not `{results: []}`, so anything reaching for `[0]` gets a
    // TypeError instead of a miss.
    assert.equal(Weather.parseGeocode({ generationtime_ms: 0.1 }), null);
    assert.equal(Weather.parseGeocode({ results: [] }), null);
    assert.equal(Weather.parseGeocode({ results: [{ name: "nowhere" }] }), null);
    assert.equal(Weather.parseGeocode(null), null);
    assert.equal(Weather.parseGeocode("not json"), null);
});

test("the real payload parses into the reading the widget draws", () => {
    const reading = Weather.parseForecast(PAYLOAD, NOW, "metric");
    assert.equal(reading.fetchedAt, NOW);
    assert.equal(reading.units, "metric");
    assert.equal(reading.timezone, "Asia/Kolkata");
    assert.equal(reading.time, "2026-08-31T21:15");
    assert.equal(reading.code, 3);
    assert.equal(reading.temperature, 23.8);
    assert.equal(reading.apparent, 25.1);
    assert.equal(reading.humidity, 71);
    assert.equal(reading.wind, 12.2);
    assert.equal(reading.sunrise, "2026-08-31T06:08");
    assert.equal(reading.sunset, "2026-08-31T18:31");
    assert.equal(reading.days.length, 3);
    assert.equal(reading.days[0].max, 28.6);
    assert.equal(reading.days[2].code, 80);
});

test("a payload missing whole blocks yields holes, not an exception", () => {
    assert.equal(Weather.parseForecast(null, NOW, "metric"), null);
    assert.equal(Weather.parseForecast("<html>rate limited</html>", NOW, "metric"), null);

    const bare = Weather.parseForecast({}, NOW, "metric");
    assert.equal(bare.days.length, 0);
    assert.ok(!isFinite(bare.temperature));
    assert.equal(bare.sunrise, "");

    // A current block with only some of what was asked for.
    const partial = Weather.parseForecast({ current: { time: "2026-08-31T21:15", temperature_2m: 23.8 } }, NOW, "metric");
    assert.equal(partial.temperature, 23.8);
    assert.ok(!isFinite(partial.humidity));
    assert.ok(!isFinite(partial.apparent));
});

test("a four-day payload is cut to the three the strip draws", () => {
    const four = JSON.parse(JSON.stringify(PAYLOAD));
    four.daily.time.push("2026-09-03");
    four.daily.temperature_2m_max.push(30.0);
    assert.equal(Weather.parseForecast(four, NOW, "metric").days.length, 3);
});

// ---------------------------------------------------------- presentation

test("weekdayName does not shift a day west of Greenwich", () => {
    // new Date("2026-09-01").getDay() parses as UTC midnight and reads back in
    // the machine's zone, so in America/New_York it answers Monday for a
    // Tuesday. This is the assertion that would catch that, and it holds
    // whatever TZ the test runs under.
    assert.equal(Weather.weekdayName("2026-08-31"), "Mon");
    assert.equal(Weather.weekdayName("2026-09-01"), "Tue");
    assert.equal(Weather.weekdayName("2026-09-02"), "Wed");
    assert.equal(Weather.weekdayName("2026-01-01"), "Thu");
    assert.equal(Weather.weekdayName(""), "");
    assert.equal(Weather.weekdayName(null), "");
    assert.equal(Weather.weekdayName("tomorrow"), "");
});

test("the strip names today by the reading's own date, not by index", () => {
    const reading = Weather.parseForecast(PAYLOAD, NOW, "metric");
    const strip = Weather.dailyStrip(reading);
    assert.equal(strip.length, 3);
    assert.equal(strip[0].name, "Today");
    assert.equal(strip[1].name, "Tue");
    assert.equal(strip[2].name, "Wed");
    assert.equal(strip[0].high, "29°C");
    assert.equal(strip[0].low, "19°C");
    assert.notEqual(strip[0].icon, "");

    // A cache served after midnight: days[0] is yesterday and must not be
    // called Today.
    const stale = JSON.parse(JSON.stringify(reading));
    stale.time = "2026-09-01T00:30";
    assert.equal(Weather.dailyStrip(stale)[0].name, "Mon");
    assert.equal(Weather.dailyStrip(stale)[1].name, "Today");

    assert.deepEqual(Weather.dailyStrip(null), []);
    assert.deepEqual(Weather.dailyStrip({}), []);
});

test("summarise on a well-formed reading", () => {
    const shaped = Weather.summarise(Weather.parseForecast(PAYLOAD, NOW, "metric"));
    assert.equal(shaped.valid, true);
    assert.equal(shaped.day, false, "21:15 in Bengaluru is after sunset");
    assert.equal(shaped.temp, "24°C");
    assert.equal(shaped.feels, "25°C");
    assert.equal(shaped.humidity, "71%");
    assert.equal(shaped.wind, "12 km/h");
    assert.notEqual(shaped.label, "");
    assert.notEqual(shaped.icon, "");
});

test("summarise on a reading with nothing in it is honest rather than zero", () => {
    for (const nothing of [null, undefined, "", 0]) {
        const shaped = Weather.summarise(nothing);
        assert.equal(shaped.valid, false);
        assert.equal(shaped.temp, "—");
        assert.notEqual(shaped.label, "");
    }

    const holes = Weather.summarise(Weather.parseForecast({ current: { time: "2026-08-31T12:00" } }, NOW, "metric"));
    assert.equal(holes.valid, false);
    assert.equal(holes.temp, "—");
    assert.equal(holes.feels, "—");
    assert.equal(holes.humidity, "—");
    assert.equal(holes.wind, "—");

    // The cache round-trip: NaN goes out as null and must come back as a dash.
    const revived = JSON.parse(JSON.stringify(Weather.parseForecast({}, NOW, "metric")));
    assert.equal(revived.temperature, null);
    assert.equal(Weather.summarise(revived).temp, "—");
    assert.equal(Weather.summarise(revived).valid, false);
});

test("summarise picks the night cut of an icon that has one", () => {
    const night = Weather.parseForecast({ current: { time: "2026-08-31T21:15", weather_code: 0, temperature_2m: 20 }, daily: { time: ["2026-08-31"], sunrise: ["2026-08-31T06:08"], sunset: ["2026-08-31T18:31"] } }, NOW, "metric");
    const day = JSON.parse(JSON.stringify(night));
    day.time = "2026-08-31T12:00";

    assert.equal(Weather.summarise(night).icon, Weather.describe(0).night);
    assert.equal(Weather.summarise(day).icon, Weather.describe(0).icon);
    assert.equal(Weather.summarise(night).label, Weather.summarise(day).label);
});

test("ageText counts up and says so", () => {
    const now = 1_000_000_000_000;
    assert.equal(Weather.ageText(now, now), "just now");
    assert.equal(Weather.ageText(now - 60_000, now), "just now");
    assert.equal(Weather.ageText(now - 12 * 60_000, now), "12m ago");
    assert.equal(Weather.ageText(now - 3 * 3_600_000, now), "3h ago");
    assert.equal(Weather.ageText(now - 2 * 86_400_000, now), "2d ago");
    // A clock that went backwards -- an NTP step, a suspend -- is not a
    // reading from the future.
    assert.equal(Weather.ageText(now + 5000, now), "just now");
    assert.equal(Weather.ageText(0, now), "never");
    assert.equal(Weather.ageText(null, now), "never");
});

test("stale is two missed refreshes, not one late one", () => {
    const now = 1_000_000_000_000;
    const minutes = m => now - m * 60_000;
    assert.equal(Weather.isStale(minutes(15), now, 15), false, "one interval is a refresh landing late");
    assert.equal(Weather.isStale(minutes(29), now, 15), false);
    assert.equal(Weather.isStale(minutes(31), now, 15), true);
    assert.equal(Weather.isStale(minutes(11), now, 5), true);
    // Never fetched is stale by definition; a nonsense interval falls back to
    // the default rather than dividing the widget by zero.
    assert.equal(Weather.isStale(0, now, 15), true);
    assert.equal(Weather.isStale(minutes(5), now, 0), false);
    assert.equal(Weather.isStale(minutes(60), now, NaN), true);
});

test("the IPC line is one line with every column present", () => {
    const reading = Weather.parseForecast(PAYLOAD, NOW, "metric");
    reading.place = "Bengaluru, Karnataka, India";
    const line = Weather.oneLine(reading, NOW + 12 * 60_000);
    assert.equal(line.indexOf("\n"), -1);
    assert.equal(line.indexOf("\t"), -1);
    assert.ok(line.startsWith("24°C"));
    assert.ok(line.includes("Bengaluru, Karnataka, India"));
    assert.ok(line.endsWith("12m ago"));

    // Nothing fetched yet still prints four columns rather than a blank line.
    const empty = Weather.oneLine(null, NOW);
    assert.equal(empty.indexOf("\n"), -1);
    assert.ok(empty.includes("—"));
    assert.ok(empty.endsWith("never"));
});

// ----------------------------------------------------------------- hourly

// An hourly block the way Open-Meteo writes one: naive local strings for
// `days` days from local midnight, every one of them UTC plus the single
// `offset` the reply reports -- including across a DST change, which the live
// API was checked for (Sydney's 2026-10-04T02:00 is in the reply although the
// clocks skipped it). Temperatures count up from 10 so a slot's position is
// readable off its value.
function hourly(firstDate, offsetSeconds, days = 3, extra = {}) {
    const [y, m, d] = firstDate.split("-").map(Number);
    const time = [];
    const temperature_2m = [];
    const weather_code = [];
    const precipitation_probability = [];
    const is_day = [];
    for (let i = 0; i < days * 24; i++) {
        time.push(new Date(Date.UTC(y, m - 1, d, i)).toISOString().slice(0, 16));
        temperature_2m.push(10 + i);
        weather_code.push(i % 2 === 0 ? 0 : 61);
        precipitation_probability.push((i * 5) % 100);
        is_day.push(i % 24 >= 6 && i % 24 < 18 ? 1 : 0);
    }
    return { utc_offset_seconds: offsetSeconds, hourly: { time, temperature_2m, weather_code, precipitation_probability, is_day }, ...extra };
}

test("the hourly row is asked for in the same request, not a second one", () => {
    const url = Weather.forecastUrl(12.97, 77.59, "metric");
    assert.equal(url.split("?").length, 2);
    assert.ok(/[?&]hourly=[^&]*temperature_2m/.test(url));
    assert.ok(/[?&]hourly=[^&]*precipitation_probability/.test(url));
    assert.ok(/[?&]hourly=[^&]*is_day/.test(url));
});

test("localToEpoch reads the payload's string against the payload's offset", () => {
    assert.equal(Weather.localToEpoch("2026-08-31T21:00", 19800), Date.parse("2026-08-31T15:30:00Z"));
    assert.equal(Weather.localToEpoch("2026-08-31T21:00", -14400), Date.parse("2026-09-01T01:00:00Z"));
    assert.equal(Weather.localToEpoch("2026-08-31T21:00", 0), Date.parse("2026-08-31T21:00:00Z"));
    assert.ok(Number.isNaN(Weather.localToEpoch("2026-08-31T21:00", null)), "no offset is no instant, not UTC");
    assert.ok(Number.isNaN(Weather.localToEpoch("tonight", 19800)));
});

test("the hourly row starts at the location's current hour, not at midnight", () => {
    // NOW is 15:45Z, which is 21:15 in Bengaluru.
    const reading = Weather.parseForecast({ ...PAYLOAD, ...hourly("2026-08-31", 19800) }, NOW, "metric");
    // The 21 hours already over when the reply landed are not cached.
    assert.equal(reading.hours[0].time, "2026-08-31T21:00");
    assert.equal(reading.hours.length, 72 - 21);

    const strip = Weather.hourlyStrip(reading, NOW, 12, false);
    assert.equal(strip.length, 12);
    assert.equal(strip[0].name, "Now");
    assert.equal(strip[0].hour, "21:00");
    assert.equal(strip[0].temp, "31°C");
    assert.equal(strip[1].name, "22:00");
    assert.equal(strip[3].name, "00:00", "the row carries on past midnight");
    assert.equal(strip[3].time, "2026-09-01T00:00");

    // Forty minutes on, still the 21:00 hour; an hour on, the row moves.
    assert.equal(Weather.hourlyStrip(reading, NOW + 40 * 60_000, 12, false)[0].time, "2026-08-31T21:00");
    assert.equal(Weather.hourlyStrip(reading, NOW + 60 * 60_000, 12, false)[0].time, "2026-08-31T22:00");
    assert.equal(Weather.hourlyStrip(reading, NOW + 60 * 60_000, 12, false)[0].name, "Now");
});

test("a location west of the machine starts at its own hour", () => {
    // New York at -4h. 15:45Z is 11:45 there and 21:15 in Bengaluru; the
    // same instant must start the two rows at different wall-clock hours.
    const reading = Weather.parseForecast(hourly("2026-08-31", -14400), NOW, "metric");
    const strip = Weather.hourlyStrip(reading, NOW, 3, false);
    assert.deepEqual(strip.map(s => s.time), ["2026-08-31T11:00", "2026-08-31T12:00", "2026-08-31T13:00"]);
});

test("the hourly row is the same whatever zone the machine is in", () => {
    // Nothing in the code reads the machine's zone, and this is what holds it
    // to that: the same reading and the same instant, sliced under three
    // TZs, one of which is on the other side of the date line from the
    // forecast.
    const script = `
        import { loadQmlJs } from ${JSON.stringify(new URL("./load-qml-js.mjs", import.meta.url).href)};
        const W = loadQmlJs("Services/Weather.js");
        const reading = JSON.parse(process.argv[1]);
        console.log(JSON.stringify(W.hourlyStrip(reading, Number(process.argv[2]), 6, true)));
    `;
    const reading = JSON.stringify(Weather.parseForecast({ ...PAYLOAD, ...hourly("2026-08-31", 19800) }, NOW, "metric"));
    const run = tz => execFileSync(process.execPath, ["--input-type=module", "-e", script, reading, String(NOW)], { env: { ...process.env, TZ: tz } }).toString();
    const utc = run("UTC");
    assert.equal(run("America/Los_Angeles"), utc);
    assert.equal(run("Pacific/Kiritimati"), utc);
    assert.equal(JSON.parse(utc)[0].hour, "9 PM");
});

test("a cache read after the clocks went forward still finds the right hour", () => {
    // Fetched in Sydney at 22:00 on 3 October, still +10. The reply's
    // strings are all +10, including 02:00 on the 4th, which never happened
    // on a Sydney wall clock.
    const fetchedAt = Date.parse("2026-10-03T12:00:00Z");
    const reading = Weather.parseForecast(hourly("2026-10-03", 36000), fetchedAt, "metric");

    // Read back at 05:00 AEDT (+11) on the 4th, i.e. 18:00Z on the 3rd.
    const later = Date.parse("2026-10-03T18:00:00Z");
    const strip = Weather.hourlyStrip(reading, later, 6, false);
    assert.equal(strip[0].at, later);
    assert.equal(strip[0].time, "2026-10-04T04:00", "labelled in the offset the reply was written in");

    // One real hour between every slot, straight through the change: no gap
    // and no repeat, because the series never had either.
    for (let i = 1; i < reading.hours.length; i++)
        assert.equal(reading.hours[i].at - reading.hours[i - 1].at, 3_600_000);
});

test("the night the clocks go back keeps one slot per hour", () => {
    // Berlin, fetched at 23:00 on 24 October at +2. At 03:30Z on the 25th the
    // clocks have gone back to +1, so the wall says 04:30; the reply, written
    // at +2, calls that hour 05:00.
    const fetchedAt = Date.parse("2026-10-24T21:00:00Z");
    const reading = Weather.parseForecast(hourly("2026-10-24", 7200), fetchedAt, "metric");
    const strip = Weather.hourlyStrip(reading, Date.parse("2026-10-25T03:30:00Z"), 4, false);
    assert.deepEqual(strip.map(s => s.hour), ["05:00", "06:00", "07:00", "08:00"]);
    assert.equal(strip[0].name, "Now");

    // The next fetch reports +1 and the same instant reads 04:00.
    const refetched = Weather.parseForecast(hourly("2026-10-24", 3600), Date.parse("2026-10-25T03:30:00Z"), "metric");
    assert.equal(Weather.hourlyStrip(refetched, Date.parse("2026-10-25T03:30:00Z"), 1, false)[0].hour, "04:00");
});

test("each hour draws its own day or night icon, and its rain chance only when it is worth reading", () => {
    const reading = Weather.parseForecast({ ...PAYLOAD, ...hourly("2026-08-31", 19800) }, NOW, "metric");
    const strip = Weather.hourlyStrip(reading, NOW, 24, false);
    // 21:00 is code 61 (odd hour) and night; 22:00 is code 0 at night.
    assert.equal(strip[0].icon, Weather.iconFor(61, false));
    assert.equal(strip[1].icon, Weather.describe(0).night);
    // 06:00 the next morning is code 0 by day.
    const six = strip.find(s => s.time === "2026-09-01T06:00");
    assert.equal(six.icon, Weather.describe(0).icon);

    // 21:00 is hour 21 of the fixture: 105 % 100 = 5% -- left blank in the
    // panel, printed for scripts.
    assert.equal(strip[0].wet, "");
    assert.equal(strip[0].precipitation, "5%");
    const wet = strip.find(s => s.time === "2026-09-01T04:00");
    assert.equal(wet.wet, "40%");

    // No is_day at all draws the day picture, the same default iconFor has.
    const noDay = hourly("2026-08-31", 19800);
    delete noDay.hourly.is_day;
    const dayless = Weather.hourlyStrip(Weather.parseForecast(noDay, NOW, "metric"), NOW, 2, false);
    assert.equal(dayless[1].icon, Weather.describe(0).icon);
});

test("the hour follows the clock widget's twelve- or twenty-four-hour dial", () => {
    assert.equal(Weather.uses12Hour("HH:mm"), false);
    assert.equal(Weather.uses12Hour("ddd dd MMM  HH:mm"), false);
    assert.equal(Weather.uses12Hour("h:mm"), false, "h without a marker is still 0..23 in Qt");
    assert.equal(Weather.uses12Hour("h:mm AP"), true);
    assert.equal(Weather.uses12Hour("hh:mm ap"), true);
    assert.equal(Weather.uses12Hour("'at' HH:mm"), false, "quoted text is literal");
    assert.equal(Weather.uses12Hour(""), false);
    assert.equal(Weather.uses12Hour(null), false);

    assert.equal(Weather.hourLabel("2026-08-31T00:00", true), "12 AM");
    assert.equal(Weather.hourLabel("2026-08-31T09:00", true), "9 AM");
    assert.equal(Weather.hourLabel("2026-08-31T12:00", true), "12 PM");
    assert.equal(Weather.hourLabel("2026-08-31T21:00", true), "9 PM");
    assert.equal(Weather.hourLabel("2026-08-31T21:00", false), "21:00");
    assert.equal(Weather.hourLabel("", false), "");
});

test("a cache from before the hourly row, or one too old to have a future, draws no row", () => {
    // Exactly what an older pshell wrote to weather.json: no `hours` key.
    const old = Weather.parseForecast(PAYLOAD, NOW, "metric");
    delete old.hours;
    assert.deepEqual(Weather.hourlyStrip(old, NOW, 12, false), []);
    assert.equal(Weather.hourlyLines(old, NOW, 12), "");
    // And the rest of the panel still reads it.
    assert.equal(Weather.summarise(old).temp, "24°C");
    assert.equal(Weather.dailyStrip(old).length, 3);

    const reading = Weather.parseForecast({ ...PAYLOAD, ...hourly("2026-08-31", 19800) }, NOW, "metric");
    assert.deepEqual(Weather.hourlyStrip(reading, NOW + 4 * 86_400_000, 12, false), []);
    assert.deepEqual(Weather.hourlyStrip(reading, NOW, 0, false), [], "0 is the setting that hides it");
    assert.deepEqual(Weather.hourlyStrip(null, NOW, 12, false), []);

    // A reply with no hourly block parses to an empty list, not a throw.
    assert.deepEqual(Weather.parseForecast(PAYLOAD, NOW, "metric").hours, []);
    // Hours with no offset to read them against are dropped rather than
    // guessed at as UTC.
    assert.deepEqual(Weather.parseForecast({ hourly: hourly("2026-08-31", 0).hourly }, NOW, "metric").hours, []);
});

test("the hourly row survives the cache round trip", () => {
    const payload = { ...PAYLOAD, ...hourly("2026-08-31", 19800) };
    payload.hourly.temperature_2m[22] = null;
    const reading = Weather.parseForecast(payload, NOW, "metric");
    const revived = JSON.parse(JSON.stringify(reading));
    const strip = Weather.hourlyStrip(revived, NOW, 3, false);
    assert.deepEqual(strip, Weather.hourlyStrip(reading, NOW, 3, false));
    assert.equal(strip[1].temp, "—", "a missing reading is a dash after the round trip, not 0°");
});

test("the hourly IPC output is one fixed-column line per hour", () => {
    const reading = Weather.parseForecast({ ...PAYLOAD, ...hourly("2026-08-31", 19800) }, NOW, "metric");
    const lines = Weather.hourlyLines(reading, NOW, 24).split("\n");
    assert.equal(lines.length, 24);
    assert.equal(lines[0], "21:00  31°C  5%  Light rain");
    assert.equal(lines[1], "22:00  32°C  10%  Clear sky");
    for (const line of lines)
        assert.equal(line.indexOf("\t"), -1);
});
