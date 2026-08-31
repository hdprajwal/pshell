.pragma library

// Everything the weather widget decides, kept away from Quickshell so
// `node --test` can reach it -- the same split ConfigPath.js, Backlight.js and
// NotificationHistory.js are on. Services/Weather.qml is left with an
// XMLHttpRequest, two timers and a cache; every judgement call is here.
//
// That line is drawn deliberately wide. A WMO table with twenty-eight entries,
// a day/night cut, a string-compared sunrise boundary and a weekday name that
// must not shift timezone are all arithmetic that breaks quietly, and QML is
// where arithmetic goes to stop being tested.

// ------------------------------------------------------------- WMO 4677
//
// The codes Open-Meteo actually emits, from its own documentation: 0-3, 45,
// 48, 51-57, 61-67, 71-77, 80-86, 95-99. Anything outside the table is a code
// they added after this was written, and it gets a question mark rather than a
// blank widget.
//
// `night` is the same picture after dark for everything that looks the same
// after dark. That is stated per entry rather than left to whether someone
// remembered to add a second name: fog at midnight is fog, and an entry that
// names one icon is saying so, not forgetting.
//
// Icon names are checked against the cut of Material Symbols Rounded this repo
// ships in assets/fonts. Note `moon_stars` and not `clear_night`: the upstream
// alias exists, the glyph in this font file does not, and a missing ligature
// renders as the literal word in the bar.
var TABLE = {
    0: { label: "Clear sky", icon: "clear_day", night: "moon_stars" },
    1: { label: "Mainly clear", icon: "partly_cloudy_day", night: "partly_cloudy_night" },
    2: { label: "Partly cloudy", icon: "partly_cloudy_day", night: "partly_cloudy_night" },
    3: { label: "Overcast", icon: "cloud" },

    45: { label: "Fog", icon: "foggy" },
    48: { label: "Freezing fog", icon: "foggy" },

    // Three intensities of the same weather. One picture, three labels: the
    // bar cannot show the difference between light and dense drizzle at
    // sixteen pixels, and the panel says it in words anyway.
    51: { label: "Light drizzle", icon: "rainy_light" },
    53: { label: "Drizzle", icon: "rainy_light" },
    55: { label: "Dense drizzle", icon: "rainy_light" },

    // Freezing drizzle and freezing rain share the sleet glyph. What matters
    // about them is that it is landing as ice, which is what `rainy_snow`
    // draws; the water/ice distinction the codes make is in the label.
    56: { label: "Light freezing drizzle", icon: "rainy_snow" },
    57: { label: "Freezing drizzle", icon: "rainy_snow" },

    61: { label: "Light rain", icon: "rainy" },
    63: { label: "Rain", icon: "rainy" },
    // Heavy rain gets its own glyph where heavy drizzle does not. Drizzle at
    // its worst is still drizzle; heavy rain is a different plan for the
    // afternoon, and the bar is the place that says so without being opened.
    65: { label: "Heavy rain", icon: "rainy_heavy" },

    66: { label: "Light freezing rain", icon: "rainy_snow" },
    67: { label: "Freezing rain", icon: "rainy_snow" },

    71: { label: "Light snow", icon: "weather_snowy" },
    73: { label: "Snow", icon: "weather_snowy" },
    75: { label: "Heavy snow", icon: "snowing_heavy" },
    77: { label: "Snow grains", icon: "grain" },

    80: { label: "Light showers", icon: "rainy" },
    81: { label: "Showers", icon: "rainy" },
    82: { label: "Violent showers", icon: "rainy_heavy" },

    85: { label: "Light snow showers", icon: "snowing" },
    86: { label: "Snow showers", icon: "snowing_heavy" },

    95: { label: "Thunderstorm", icon: "thunderstorm" },
    96: { label: "Thunderstorm with hail", icon: "weather_hail" },
    99: { label: "Thunderstorm with heavy hail", icon: "weather_hail" }
};

var UNKNOWN = { label: "Unknown", icon: "question_mark" };

// A code is a number in the payload and a number in the table. It is coerced
// from a string because a hand-written cache or a future payload may quote it,
// but `null` must not become `0`: Number(null) is 0, and 0 is "Clear sky",
// which would turn a missing reading into a confident sunny day. Non-integers
// are out for the same reason -- 0.5 is not a code, and rounding it would
// invent one.
function _codeKey(code) {
    var value;
    if (typeof code === "number")
        value = code;
    else if (typeof code === "string" && code.trim() !== "")
        value = Number(code);
    else
        return NaN;
    if (!isFinite(value) || Math.floor(value) !== value)
        return NaN;
    return value;
}

// { label, icon, night, varies }. `varies` is returned rather than left for
// the caller to work out from `icon !== night`, because "does this condition
// look different after dark" is a real question about the weather and not a
// coincidence of two strings.
function describe(code) {
    var entry = TABLE[_codeKey(code)] || UNKNOWN;
    var night = entry.night || entry.icon;
    return {
        label: entry.label,
        icon: entry.icon,
        night: night,
        varies: night !== entry.icon
    };
}

// Day is the default when nobody said. Everything that calls this knows
// whether the sun is up -- isDaytime() answers that from the payload -- but a
// caller that has not worked it out yet should get the picture that reads as
// "weather", not the one that reads as "night".
function iconFor(code, isDay) {
    var entry = describe(code);
    if (isDay === undefined || isDay === null)
        return entry.icon;
    return isDay ? entry.icon : entry.night;
}

var ISO_LOCAL = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/;

// Compared as strings, not as dates.
//
// With `timezone=auto` Open-Meteo returns local wall-clock ISO with no zone
// suffix: "2026-08-31T21:15" means 21:15 where the coordinates are, and
// Date.parse would read it as 21:15 UTC and put Bengaluru's evening five and a
// half hours out. Every one of the three strings comes from the same payload
// in the same zone, and "YYYY-MM-DDTHH:MM" sorts chronologically under plain
// lexicographic comparison, so comparing the text is both correct and the only
// form that cannot pick up a timezone on the way through.
//
// Sunrise counts as day and sunset counts as night: the boundary belongs to
// the lit side going up and the dark side coming down, which is the way the
// sky actually reads at those two minutes.
function isDaytime(nowIso, sunriseIso, sunsetIso) {
    var now = String(nowIso || "");
    var up = String(sunriseIso || "");
    var down = String(sunsetIso || "");

    if (ISO_LOCAL.test(now) && ISO_LOCAL.test(up) && ISO_LOCAL.test(down))
        return now >= up && now < down;

    // No usable sunrise or sunset -- a payload that dropped `daily`, or a
    // cache written by an older version. Six to six is wrong twice a year at
    // most latitudes and wrong all winter at high ones, but it is a picture
    // rather than a blank, and the temperature beside it is still true.
    if (ISO_LOCAL.test(now)) {
        var hour = Number(now.substr(11, 2));
        return hour >= 6 && hour < 18;
    }
    return true;
}

// ------------------------------------------------------------- formatting
//
// The value is already in the unit being displayed, so nothing here converts.
//
// That is the whole reason `units` reaches the request builder below as
// `temperature_unit` and `wind_speed_unit` rather than being applied on the
// way out: converting locally means two call sites -- the bar and the panel --
// each doing their own arithmetic on the same reading, and the first rounding
// difference between them is a bug nobody can reproduce. Open-Meteo does the
// conversion once, server side, for free, and `current_units` in the reply
// says which unit came back.
//
// Hence the parameter is `value` and not `celsius`: naming it for one of the
// two units it can hold would be a comment that lies.

// Number(), except that null, undefined and "" come back NaN rather than 0.
//
// This is the one coercion in the file that has to be stricter than the
// language's, and the reason is the persisted cache: a field the payload never
// carried is NaN in memory, JSON.stringify writes NaN out as `null`, and
// Number(null) is 0. Round-tripping the cache through state.json would
// therefore turn a missing temperature into a confident 0°, which is exactly
// the reading this widget must never show.
function _num(value) {
    if (value === null || value === undefined || value === "")
        return NaN;
    var n = Number(value);
    return isFinite(n) ? n : NaN;
}

function formatTemp(value, units) {
    var n = _num(value);
    if (!isFinite(n))
        return "—";
    // Math.round(-0.4) is -0, whose string form is "0" and not "-0", so
    // freezing point needs no special case.
    return String(Math.round(n)) + "°" + (String(units) === "imperial" ? "F" : "C");
}

function formatSpeed(value, units) {
    var n = _num(value);
    if (!isFinite(n))
        return "—";
    return String(Math.round(n)) + (String(units) === "imperial" ? " mph" : " km/h");
}

function formatPercent(value) {
    var n = _num(value);
    if (!isFinite(n))
        return "—";
    return String(Math.round(n)) + "%";
}

// -------------------------------------------------------------- requests

// The forecast URL, built in one place so the field list and the unit
// parameters cannot drift apart from the parser below.
//
// Units are asked for rather than converted, per the note above. Metric is
// Open-Meteo's default and is still spelled out, so the URL says what it wants
// instead of relying on a default that is theirs to change.
//
// `forecast_days=3` because the strip is three days. Asking for the week and
// showing three would be a bigger reply every fifteen minutes for nothing.
function forecastUrl(latitude, longitude, units) {
    var lat = _num(latitude);
    var lon = _num(longitude);
    if (!isFinite(lat) || !isFinite(lon))
        return "";
    var imperial = String(units) === "imperial";
    return "https://api.open-meteo.com/v1/forecast" + "?latitude=" + lat + "&longitude=" + lon + "&current=temperature_2m,weather_code,relative_humidity_2m,apparent_temperature,wind_speed_10m" + "&daily=weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset" + "&timezone=auto&forecast_days=3" + "&temperature_unit=" + (imperial ? "fahrenheit" : "celsius") + "&wind_speed_unit=" + (imperial ? "mph" : "kmh");
}

// A different host from the forecast, and also keyless. `count=1` because the
// answer is fed straight into coordinates -- offering a chooser would be a
// second panel for a setting that is typed once.
function geocodeUrl(name) {
    var text = String(name || "").trim();
    if (text === "")
        return "";
    return "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(text) + "&count=1&language=en&format=json";
}

// ---------------------------------------------------------------- parsing

// A name that matches nothing comes back as `{"generationtime_ms": 0.1}` --
// an object with no `results` key at all, not an empty array. Both shapes are
// treated the same here, because the difference is not something a caller
// should have to know, and getting it wrong is a TypeError on `[0]` rather
// than a miss.
function parseGeocode(payload) {
    if (!payload || typeof payload !== "object")
        return null;
    var results = payload.results;
    if (!Array.isArray(results) || results.length === 0)
        return null;
    var hit = results[0] || {};
    var lat = _num(hit.latitude);
    var lon = _num(hit.longitude);
    if (!isFinite(lat) || !isFinite(lon))
        return null;

    // "Bengaluru, Karnataka, India" -- the parts that exist, in that order.
    // admin1 is what tells the two Springfields apart, and plenty of places
    // have no admin1 at all.
    var parts = [];
    if (hit.name)
        parts.push(String(hit.name));
    if (hit.admin1)
        parts.push(String(hit.admin1));
    if (hit.country)
        parts.push(String(hit.country));

    return {
        latitude: lat,
        longitude: lon,
        name: String(hit.name || ""),
        label: parts.join(", "),
        timezone: String(hit.timezone || "")
    };
}

function _dayAt(daily, index, key) {
    var column = daily ? daily[key] : null;
    if (!Array.isArray(column) || index >= column.length)
        return undefined;
    return column[index];
}

// The forecast payload reduced to the object the widget draws and the cache
// stores. Every field is coerced here so nothing downstream has to guess, and
// a payload missing a block yields a reading with holes rather than throwing
// on the way in -- a half-answer that says "—" beats an exception that leaves
// the last good reading unreplaced but the widget mid-update.
//
// `fetchedAt` is epoch milliseconds and not the payload's own `current.time`.
// That one is local wall-clock in the forecast's zone, which is the wrong
// clock for "how old is this" when the machine is somewhere else, and it moves
// in fifteen-minute steps because that is Open-Meteo's model resolution.
function parseForecast(payload, nowMs, units) {
    if (!payload || typeof payload !== "object")
        return null;

    var current = payload.current && typeof payload.current === "object" ? payload.current : {};
    var daily = payload.daily && typeof payload.daily === "object" ? payload.daily : {};

    var days = [];
    var dates = Array.isArray(daily.time) ? daily.time : [];
    for (var i = 0; i < dates.length && i < 3; i++) {
        days.push({
            date: String(dates[i]),
            code: _dayAt(daily, i, "weather_code"),
            max: _num(_dayAt(daily, i, "temperature_2m_max")),
            min: _num(_dayAt(daily, i, "temperature_2m_min"))
        });
    }

    var when = Number(nowMs);
    return {
        fetchedAt: isFinite(when) ? when : 0,
        units: String(units) === "imperial" ? "imperial" : "metric",
        latitude: _num(payload.latitude),
        longitude: _num(payload.longitude),
        timezone: String(payload.timezone || ""),
        time: String(current.time || ""),
        code: current.weather_code,
        temperature: _num(current.temperature_2m),
        apparent: _num(current.apparent_temperature),
        humidity: _num(current.relative_humidity_2m),
        wind: _num(current.wind_speed_10m),
        // Today's, which is the pair the current condition's day/night cut is
        // decided against. The other two days' are dropped: the strip draws
        // daytime icons for days that have not started.
        sunrise: String(_dayAt(daily, 0, "sunrise") || ""),
        sunset: String(_dayAt(daily, 0, "sunset") || ""),
        days: days
    };
}

// ---------------------------------------------------------- presentation

var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

// The weekday for a "YYYY-MM-DD" with no timezone anywhere in it.
//
// `new Date("2026-09-01").getDay()` is the trap: the string parses as UTC
// midnight and getDay() reads it back in the machine's zone, so anywhere west
// of Greenwich the strip labels every day as the one before. Date.UTC in and
// getUTCDay out keeps both ends in the same zone, and the zone cancels.
function weekdayName(dateIso) {
    var text = String(dateIso || "");
    if (!/^\d{4}-\d{2}-\d{2}/.test(text))
        return "";
    var year = Number(text.substr(0, 4));
    var month = Number(text.substr(5, 2));
    var day = Number(text.substr(8, 2));
    var at = new Date(Date.UTC(year, month - 1, day));
    if (isNaN(at.getTime()))
        return "";
    return WEEKDAYS[at.getUTCDay()];
}

// The three-day strip: one row per day, already worded. The first day of an
// Open-Meteo forecast is always today, but that is asserted against the
// reading's own clock rather than assumed from the index -- a cache served
// after midnight has a `days[0]` that is yesterday, and calling it "Today"
// would be the widget lying about the one thing it is for.
function dailyStrip(reading) {
    if (!reading || !Array.isArray(reading.days))
        return [];
    var today = String(reading.time || "").substr(0, 10);
    var units = reading.units;
    var out = [];
    for (var i = 0; i < reading.days.length; i++) {
        var day = reading.days[i];
        var described = describe(day.code);
        out.push({
            date: day.date,
            // Daytime icons throughout. A day is not a moment, and the sun is
            // up for the part of it anyone is planning around.
            icon: described.icon,
            label: described.label,
            name: day.date === today && today !== "" ? "Today" : weekdayName(day.date),
            high: formatTemp(day.max, units),
            low: formatTemp(day.min, units)
        });
    }
    return out;
}

// Everything the bar and the panel draw, shaped once so the two cannot
// disagree about rounding or about which icon the hour calls for.
function summarise(reading) {
    if (!reading || typeof reading !== "object") {
        return {
            valid: false,
            day: true,
            icon: "question_mark",
            label: "…",
            temp: "—",
            feels: "—",
            humidity: "—",
            wind: "—",
            place: ""
        };
    }
    var units = reading.units;
    var day = isDaytime(reading.time, reading.sunrise, reading.sunset);
    var described = describe(reading.code);
    return {
        valid: isFinite(_num(reading.temperature)),
        day: day,
        icon: day ? described.icon : described.night,
        label: described.label,
        temp: formatTemp(reading.temperature, units),
        feels: formatTemp(reading.apparent, units),
        humidity: formatPercent(reading.humidity),
        wind: formatSpeed(reading.wind, units),
        place: String(reading.place || "")
    };
}

// How old the reading on screen is, worded for a panel line. Deliberately not
// NotificationHistory.relativeTime: that one answers "3m" for a list where the
// column header carries the meaning, and this one is a sentence fragment that
// has to stand alone next to a temperature. Two wordings, two functions, and
// neither one bent to serve the other's caller.
function ageText(fetchedAt, nowMs) {
    var then = Number(fetchedAt);
    var now = Number(nowMs);
    if (!isFinite(then) || !isFinite(now) || then <= 0)
        return "never";
    var seconds = Math.floor((now - then) / 1000);
    if (seconds < 0)
        return "just now";
    if (seconds < 90)
        return "just now";
    if (seconds < 3600)
        return Math.floor(seconds / 60) + "m ago";
    if (seconds < 86400)
        return Math.floor(seconds / 3600) + "h ago";
    return Math.floor(seconds / 86400) + "d ago";
}

// Older than two refresh intervals means at least one fetch was missed and
// nobody said so. One interval would flicker: a refresh that lands a second
// late would mark the reading stale between the timer firing and the reply
// arriving, every single time.
function isStale(fetchedAt, nowMs, intervalMin) {
    var then = Number(fetchedAt);
    var now = Number(nowMs);
    if (!isFinite(then) || then <= 0)
        return true;
    if (!isFinite(now))
        return false;
    var minutes = Number(intervalMin);
    if (!isFinite(minutes) || minutes <= 0)
        minutes = 15;
    return now - then > minutes * 2 * 60000;
}

// The one line `pshell weather current` prints. Machine-readable means one
// line, tab-free, with the fields in a fixed order and no field silently
// missing: a place that failed to resolve prints "—" and keeps its column.
function oneLine(reading, nowMs) {
    var shaped = summarise(reading);
    var age = reading ? ageText(reading.fetchedAt, nowMs) : "never";
    var place = shaped.place !== "" ? shaped.place : "—";
    return [shaped.temp, shaped.label, place, age].join("  ");
}
