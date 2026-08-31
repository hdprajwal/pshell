import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
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

test("every icon the table names is a ligature the shipped font actually has", () => {
    // The reason this is worth a test rather than a careful reading: a
    // Material Symbols name that is not in this cut of the font renders as the
    // literal word in the bar, which looks like a data bug and is not one.
    // `clear_night` is the specific one that bit -- the upstream alias exists,
    // the glyph in the file this repo ships does not.
    const font = readFileSync(new URL("../assets/fonts/material-symbols/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf", import.meta.url));
    const names = new Set(font.toString("latin1").split(/[^A-Za-z0-9_]+/));

    const wanted = new Set(["question_mark"]);
    for (const code of CODES) {
        const entry = Weather.describe(code);
        wanted.add(entry.icon);
        wanted.add(entry.night);
    }
    for (const name of wanted)
        assert.ok(names.has(name), `${name} is not a ligature in the shipped font`);
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
    for (const field of ["temperature_2m", "weather_code", "relative_humidity_2m", "apparent_temperature", "wind_speed_10m", "temperature_2m_max", "temperature_2m_min", "sunrise", "sunset"])
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
