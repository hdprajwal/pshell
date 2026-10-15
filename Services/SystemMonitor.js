.pragma library

// The system monitor's arithmetic: what /proc/stat, /proc/meminfo,
// /proc/net/dev, a hwmon directory listing and `df -P` say, and how to put it
// on a bar. Kept out of Services/SystemMonitor.qml so `node --test` can load
// it the way tests/load-qml-js.mjs loads the other libraries -- a CPU
// percentage is two samples subtracted, and an off-by-one column in that
// subtraction reads as a plausible number rather than an error.
//
// DMS gets the same numbers from its `dgop` binary. pshell reads the files
// itself: they are a few hundred bytes each and the kernel formats them for
// exactly this.

// What the bar can show, in the order it shows them. `metrics` on the widget
// picks a subset; the order stays this one, so two bars configured with the
// same set in a different order still agree.
var METRICS = ["cpu", "ram", "temp", "disk", "net"];
var DEFAULT_METRICS = ["cpu", "ram", "temp"];

// DMS's thresholds, so a pill turns the same colour at the same reading in
// both shells. Past `warn` the icon takes the accent, past `danger` the
// urgent colour.
var LEVELS = {
    cpu: { warn: 60, danger: 80 },
    ram: { warn: 75, danger: 90 },
    temp: { warn: 69, danger: 85 },
    disk: { warn: 75, danger: 90 }
};

// --------------------------------------------------------------- config

// `metrics` from config.json, as an array or a comma-separated string.
// Unknown names are dropped rather than refused -- a config file is not a
// place to report errors to -- and nothing left means the default.
function parseMetrics(value) {
    var wanted;
    if (Array.isArray(value))
        wanted = value;
    else if (typeof value === "string")
        wanted = value.split(",");
    else
        return DEFAULT_METRICS.slice();

    var names = wanted.map(function (v) {
        return String(v).trim().toLowerCase();
    });
    var picked = METRICS.filter(function (m) {
        return names.indexOf(m) >= 0;
    });
    return picked.length > 0 ? picked : DEFAULT_METRICS.slice();
}

// 0 normal, 1 warn, 2 danger. An unknown reading is normal: a pill that
// cannot read its sensor has nothing to be alarmed about.
function level(metric, value) {
    var l = LEVELS[metric];
    if (!l || value === null || value === undefined || !isFinite(value) || value < 0)
        return 0;
    if (value > l.danger)
        return 2;
    if (value > l.warn)
        return 1;
    return 0;
}

// ------------------------------------------------------------------ cpu

// Every `cpu` line of /proc/stat as { busy, total } in jiffies: the
// aggregate first, then one per core. Idle is idle plus iowait, as top and
// DMS count it -- a core waiting on the disk is not doing work.
function parseCpuStat(text) {
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].trim().split(/\s+/);
        if (f[0].indexOf("cpu") !== 0)
            continue;
        var n = f.slice(1, 9).map(Number);
        if (n.length < 4 || n.some(function (x) {
            return !isFinite(x);
        }))
            continue;
        var total = n.reduce(function (a, b) {
            return a + b;
        }, 0);
        var idle = n[3] + (n[4] || 0);
        out.push({ busy: total - idle, total: total });
    }
    return out;
}

// Percent busy between two parseCpuStat samples, one per entry, -1 where
// there is nothing to compare: no earlier sample, a core that came online
// in between, or no time passed.
function cpuUsage(prev, cur) {
    var out = [];
    for (var i = 0; i < (cur || []).length; i++) {
        var p = prev && prev[i];
        var dt = p ? cur[i].total - p.total : 0;
        if (!p || dt <= 0) {
            out.push(-1);
            continue;
        }
        var busy = (cur[i].busy - p.busy) / dt * 100;
        out.push(Math.max(0, Math.min(100, busy)));
    }
    return out;
}

// --------------------------------------------------------------- memory

// /proc/meminfo in bytes. Used is total minus available, which is what
// `free` calls used: page cache the kernel will hand back is not in use.
function parseMeminfo(text) {
    var kb = {};
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = /^(\w+):\s+(\d+)/.exec(lines[i]);
        if (m)
            kb[m[1]] = Number(m[2]);
    }
    if (!kb.MemTotal)
        return null;
    var available = kb.MemAvailable !== undefined ? kb.MemAvailable : (kb.MemFree || 0) + (kb.Buffers || 0) + (kb.Cached || 0);
    var used = Math.max(0, kb.MemTotal - available);
    var swapTotal = kb.SwapTotal || 0;
    var swapUsed = Math.max(0, swapTotal - (kb.SwapFree || 0));
    return {
        total: kb.MemTotal * 1024,
        used: used * 1024,
        percent: used / kb.MemTotal * 100,
        swapTotal: swapTotal * 1024,
        swapUsed: swapUsed * 1024,
        swapPercent: swapTotal > 0 ? swapUsed / swapTotal * 100 : 0
    };
}

// ------------------------------------------------------------------ net

// Interfaces whose traffic is already counted on a physical one, or never
// left the machine: loopback, container and VM bridges, and tunnels, whose
// packets go out again, encrypted, through the card underneath.
function isVirtualInterface(name) {
    return /^(lo|veth|docker|br-|virbr|vnet|tun|tap|tailscale|wg|zt)/.test(name);
}

// Total bytes received and sent across the physical interfaces.
function parseNetDev(text) {
    var rx = 0;
    var tx = 0;
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var cut = lines[i].indexOf(":");
        if (cut < 0)
            continue;
        var name = lines[i].substring(0, cut).trim();
        if (name === "" || isVirtualInterface(name))
            continue;
        var f = lines[i].substring(cut + 1).trim().split(/\s+/).map(Number);
        if (f.length < 9 || !isFinite(f[0]) || !isFinite(f[8]))
            continue;
        rx += f[0];
        tx += f[8];
    }
    return { rx: rx, tx: tx };
}

// Bytes per second between two samples taken `ms` apart. A counter that
// went backwards -- an interface that went down and came back -- is a
// reset, not negative traffic.
function rate(prev, cur, ms) {
    if (prev === null || prev === undefined || !(ms > 0))
        return 0;
    return Math.max(0, cur - prev) * 1000 / ms;
}

// ----------------------------------------------------------------- temp

// The sensor listing Services/SystemMonitor.qml collects once: one line per
// temperature input, `chip<TAB>label<TAB>path`. A thermal zone is listed as
// chip `zone:<type>` with no label.
function parseSensorList(text) {
    var out = [];
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var f = lines[i].split("\t");
        if (f.length < 3 || f[2].trim() === "")
            continue;
        out.push({ chip: f[0].trim(), label: f[1].trim(), path: f[2].trim() });
    }
    return out;
}

// Which sensor is "the CPU". The package sensor where the chip has one --
// Intel's `Package id 0`, AMD's `Tctl` -- since a single core's reading
// jumps around with whatever ran on it last. Then the ARM SoC zones, then
// the ACPI zone, which is the board's guess and better than nothing.
// Returns the sensor, or null when there is none to read.
function pickCpuSensor(sensors) {
    var rules = [
        ["coretemp", /^package id/i],
        ["k10temp", /^tctl$/i],
        ["k10temp", /^tdie$/i],
        ["zenpower", /^tdie$/i],
        ["zenpower", /^tctl$/i],
        ["coretemp", null],
        ["k10temp", null],
        ["zenpower", null],
        ["cpu_thermal", null],
        ["soc_thermal", null],
        ["zone:x86_pkg_temp", null],
        ["zone:cpu-thermal", null],
        ["zone:cpu_thermal", null],
        ["acpitz", null],
        ["zone:acpitz", null]
    ];
    var list = sensors || [];
    for (var r = 0; r < rules.length; r++) {
        for (var i = 0; i < list.length; i++) {
            if (list[i].chip !== rules[r][0])
                continue;
            if (rules[r][1] === null || rules[r][1].test(list[i].label))
                return list[i];
        }
    }
    return null;
}

// A temp*_input or thermal_zone*/temp: millidegrees Celsius. Null for
// anything else, rather than a zero that reads as a cold room.
function parseTemperature(text) {
    var s = String(text === undefined || text === null ? "" : text).trim();
    if (!/^-?\d+$/.test(s))
        return null;
    return Number(s) / 1000;
}

// ----------------------------------------------------------------- disk

// One data line of `df -P -B1 <path>`: size, used and available in bytes,
// and the mount point, which may have spaces in it. Percent is used over
// used plus available, as df's own Capacity column counts it, so the
// reserved blocks only root can write do not read as free.
function parseDfLine(line) {
    var f = String(line || "").trim().split(/\s+/);
    if (f.length < 6)
        return null;
    var size = Number(f[1]);
    var used = Number(f[2]);
    var avail = Number(f[3]);
    if (!isFinite(size) || !isFinite(used) || !isFinite(avail) || used + avail <= 0)
        return null;
    return {
        mount: f.slice(5).join(" "),
        size: size,
        used: used,
        avail: avail,
        percent: used / (used + avail) * 100
    };
}

// ---------------------------------------------------------------- words

// "15.5 GiB". Binary units, which is what /proc and df count in.
function formatSize(bytes) {
    var units = ["B", "KiB", "MiB", "GiB", "TiB"];
    var v = Math.max(0, Number(bytes) || 0);
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
        v /= 1024;
        u++;
    }
    return (u === 0 || v >= 100 ? Math.round(v) : v.toFixed(1)) + " " + units[u];
}

// A network rate. Compact for the bar -- "820K", "1.2M", never wider than
// four characters, so the pill does not breathe with every packet -- and
// spelled out for the panel and scripts: "820 KiB/s".
function formatRate(bytesPerSecond, compact) {
    var units = compact ? ["B", "K", "M", "G"] : ["B/s", "KiB/s", "MiB/s", "GiB/s"];
    var v = Math.max(0, Number(bytesPerSecond) || 0);
    var u = 0;
    while (v >= 1000 && u < units.length - 1) {
        v /= 1024;
        u++;
    }
    var n = u === 0 || v >= 10 ? String(Math.round(v)) : v.toFixed(1);
    return compact ? n + units[u] : n + " " + units[u];
}

function formatPercent(value) {
    return value === null || value === undefined || !isFinite(value) || value < 0 ? "--%" : Math.round(value) + "%";
}

function formatTemperature(value) {
    return value === null || value === undefined || !isFinite(value) ? "--°" : Math.round(value) + "°";
}

// The `pshell sysmon status` line. Fixed order, one field per metric, and
// a dash where there is no reading, so `cut` and `awk` can find each one.
function statusLine(s) {
    var mem = s.memory;
    var disk = s.disk;
    return [
        "cpu " + formatPercent(s.cpu),
        "ram " + (mem ? formatPercent(mem.percent) + " " + formatSize(mem.used) + "/" + formatSize(mem.total) : "--%"),
        "temp " + (s.temperature === null || s.temperature === undefined ? "--" : Math.round(s.temperature) + "C"),
        "disk " + (disk ? formatPercent(disk.percent) + " " + disk.mount : "--%"),
        "net down " + formatRate(s.rx, false) + " up " + formatRate(s.tx, false)
    ].join(", ");
}
