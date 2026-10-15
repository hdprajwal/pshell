import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const M = loadQmlJs("Services/SystemMonitor.js");

// --------------------------------------------------------------- config

test("parseMetrics defaults to cpu, ram and temp", () => {
  for (const v of [undefined, null, 3, {}, [], "", "gpu,fan"])
    assert.deepEqual(M.parseMetrics(v), ["cpu", "ram", "temp"], JSON.stringify(v));
});

test("parseMetrics takes an array or a comma list, in the bar's own order", () => {
  assert.deepEqual(M.parseMetrics(["net", "cpu"]), ["cpu", "net"]);
  assert.deepEqual(M.parseMetrics(" Disk , ram,bogus"), ["ram", "disk"]);
});

test("level uses DMS's thresholds, strictly above each", () => {
  assert.equal(M.level("cpu", 60), 0);
  assert.equal(M.level("cpu", 61), 1);
  assert.equal(M.level("cpu", 81), 2);
  assert.equal(M.level("temp", 70), 1);
  assert.equal(M.level("temp", 86), 2);
  assert.equal(M.level("ram", 91), 2);
});

test("level calls an unknown reading normal", () => {
  for (const v of [null, undefined, NaN, -1])
    assert.equal(M.level("temp", v), 0, String(v));
  assert.equal(M.level("net", 99), 0);
});

// ------------------------------------------------------------------ cpu

const STAT_A = `cpu  100 0 100 700 100 0 0 0 0 0
cpu0 50 0 50 350 50 0 0 0 0 0
cpu1 50 0 50 350 50 0 0 0 0 0
intr 12345 0 0
ctxt 999`;

const STAT_B = `cpu  200 0 200 900 100 0 0 0 0 0
cpu0 150 0 50 400 50 0 0 0 0 0
cpu1 50 0 150 500 50 0 0 0 0 0
intr 12999 0 0`;

test("parseCpuStat reads the aggregate and every core, counting iowait as idle", () => {
  const s = M.parseCpuStat(STAT_A);
  assert.equal(s.length, 3);
  assert.deepEqual(s[0], { busy: 200, total: 1000 });
});

test("cpuUsage is busy over elapsed, per entry", () => {
  const u = M.cpuUsage(M.parseCpuStat(STAT_A), M.parseCpuStat(STAT_B));
  // aggregate: busy +200 of +400
  assert.equal(u[0], 50);
  // cpu0: busy +100 of +150; cpu1: busy +100 of +250
  assert.ok(Math.abs(u[1] - 66.666) < 0.01);
  assert.equal(u[2], 40);
});

test("cpuUsage answers -1 with nothing to compare against", () => {
  const b = M.parseCpuStat(STAT_B);
  assert.deepEqual(M.cpuUsage(null, b), [-1, -1, -1]);
  assert.deepEqual(M.cpuUsage(b, b), [-1, -1, -1]);
  // A core that came online since the last sample.
  assert.deepEqual(M.cpuUsage(M.parseCpuStat(STAT_A).slice(0, 2), M.parseCpuStat(STAT_B)).slice(2), [-1]);
});

// --------------------------------------------------------------- memory

test("parseMeminfo counts used as total minus available, like free", () => {
  const m = M.parseMeminfo(`MemTotal:       1000 kB
MemFree:         100 kB
MemAvailable:    750 kB
Buffers:          50 kB
Cached:          200 kB
SwapTotal:       400 kB
SwapFree:        300 kB`);
  assert.equal(m.total, 1000 * 1024);
  assert.equal(m.used, 250 * 1024);
  assert.equal(m.percent, 25);
  assert.equal(m.swapUsed, 100 * 1024);
  assert.equal(m.swapPercent, 25);
});

test("parseMeminfo falls back to free + buffers + cached on old kernels", () => {
  const m = M.parseMeminfo("MemTotal: 1000 kB\nMemFree: 100 kB\nBuffers: 100 kB\nCached: 300 kB\n");
  assert.equal(m.percent, 50);
  assert.equal(m.swapPercent, 0);
});

test("parseMeminfo answers null without a total", () => {
  assert.equal(M.parseMeminfo(""), null);
  assert.equal(M.parseMeminfo(undefined), null);
});

// ------------------------------------------------------------------ net

const NETDEV = `Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:   30691     469    0    0    0     0          0         0    30691     469    0    0    0     0       0          0
enp2s0:     500       5    0    0    0     0          0         0      70       1    0    0    0     0       0          0
 wlan0: 1000       7    0    0    0     0          0         0 200  157373    0    0    0     0       0          0
tailscale0:      86       1    0    0    0     0          0         0     3260      26    0    0    0     0       0          0
docker0:       9       0    0    0    0     0          0         0        9       0    0   11    0     0       0          0
br-85b01f1b74d7:  9       0    0    0    0     0          0         0        9       0    0   11    0     0       0          0
veth12ab:  9       0    0    0    0     0          0         0        9       0    0   11    0     0       0          0`;

test("parseNetDev sums the physical interfaces and skips loopback, bridges and tunnels", () => {
  assert.deepEqual(M.parseNetDev(NETDEV), { rx: 1500, tx: 270 });
});

test("parseNetDev reads a counter glued to the colon", () => {
  assert.deepEqual(M.parseNetDev("eth0:123 0 0 0 0 0 0 0 456 0 0 0 0 0 0 0"), { rx: 123, tx: 456 });
});

test("rate is bytes per second, and a counter reset is zero", () => {
  assert.equal(M.rate(1000, 3000, 2000), 1000);
  assert.equal(M.rate(5000, 100, 2000), 0);
  assert.equal(M.rate(null, 100, 2000), 0);
  assert.equal(M.rate(0, 100, 0), 0);
});

// ----------------------------------------------------------------- temp

test("parseSensorList reads chip, label and path, and skips blank lines", () => {
  const s = M.parseSensorList("coretemp\tPackage id 0\t/sys/class/hwmon/hwmon6/temp1_input\n\nacpitz\t\t/sys/x\nbroken\n");
  assert.equal(s.length, 2);
  assert.deepEqual(s[0], { chip: "coretemp", label: "Package id 0", path: "/sys/class/hwmon/hwmon6/temp1_input" });
  assert.equal(s[1].label, "");
});

test("pickCpuSensor prefers the package sensor over any one core", () => {
  const s = [
    { chip: "acpitz", label: "", path: "a" },
    { chip: "nvme", label: "Composite", path: "n" },
    { chip: "coretemp", label: "Core 0", path: "c0" },
    { chip: "coretemp", label: "Package id 0", path: "pkg" }
  ];
  assert.equal(M.pickCpuSensor(s).path, "pkg");
});

test("pickCpuSensor takes Tctl on AMD, and falls back to the ACPI zone", () => {
  assert.equal(M.pickCpuSensor([
    { chip: "k10temp", label: "Tccd1", path: "ccd" },
    { chip: "k10temp", label: "Tctl", path: "tctl" }
  ]).path, "tctl");
  assert.equal(M.pickCpuSensor([
    { chip: "nvme", label: "Composite", path: "n" },
    { chip: "zone:acpitz", label: "", path: "z" }
  ]).path, "z");
});

test("pickCpuSensor answers null rather than reading a disk as the CPU", () => {
  assert.equal(M.pickCpuSensor([{ chip: "nvme", label: "Composite", path: "n" }]), null);
  assert.equal(M.pickCpuSensor([]), null);
});

test("parseTemperature reads millidegrees and refuses anything else", () => {
  assert.equal(M.parseTemperature("52000\n"), 52);
  assert.equal(M.parseTemperature("-5000"), -5);
  for (const v of ["", undefined, null, "N/A", "52.0"])
    assert.equal(M.parseTemperature(v), null, String(v));
});

// ----------------------------------------------------------------- disk

test("parseDfLine reads bytes and a mount point with spaces in it", () => {
  const d = M.parseDfLine("/dev/sdb1  1000  300  600  34% /run/media/me/My Disk");
  assert.equal(d.mount, "/run/media/me/My Disk");
  assert.equal(d.size, 1000);
  assert.equal(d.avail, 600);
  // used / (used + avail), as df counts it, not used / size.
  assert.equal(Math.round(d.percent), 33);
});

test("parseDfLine answers null for the blank line a failed df leaves", () => {
  for (const v of ["", undefined, "Filesystem 1-blocks Used Available Capacity Mounted on", "x 0 0 0 0% /"])
    assert.equal(M.parseDfLine(v), null, String(v));
});

// ---------------------------------------------------------------- words

test("formatSize uses binary units with one decimal below 100", () => {
  assert.equal(M.formatSize(512), "512 B");
  assert.equal(M.formatSize(1536), "1.5 KiB");
  assert.equal(M.formatSize(16.6 * 1024 ** 3), "16.6 GiB");
  assert.equal(M.formatSize(500 * 1024 ** 3), "500 GiB");
});

test("formatRate stays at four characters or fewer on the bar", () => {
  for (const v of [0, 999, 1000, 9.9 * 1024, 999 * 1024, 1023 * 1024, 5.5 * 1024 ** 2, 900 * 1024 ** 2, 3 * 1024 ** 3])
    assert.ok(M.formatRate(v, true).length <= 4, M.formatRate(v, true));
  assert.equal(M.formatRate(1.25 * 1024 ** 2, true), "1.3M");
  assert.equal(M.formatRate(820 * 1024, false), "820 KiB/s");
});

test("formatPercent and formatTemperature dash an unknown reading", () => {
  assert.equal(M.formatPercent(-1), "--%");
  assert.equal(M.formatPercent(42.4), "42%");
  assert.equal(M.formatTemperature(null), "--°");
  assert.equal(M.formatTemperature(51.6), "52°");
});

test("statusLine keeps one field per metric in a fixed order", () => {
  const line = M.statusLine({
    cpu: 12.2,
    memory: { percent: 43, used: 6.8 * 1024 ** 3, total: 31.2 * 1024 ** 3 },
    temperature: 52.4,
    disk: { percent: 33, mount: "/" },
    rx: 2048,
    tx: 0
  });
  assert.equal(line, "cpu 12%, ram 43% 6.8 GiB/31.2 GiB, temp 52C, disk 33% /, net down 2.0 KiB/s up 0 B/s");
});

test("statusLine dashes what it has not read yet", () => {
  assert.equal(M.statusLine({ cpu: -1, memory: null, temperature: null, disk: null, rx: 0, tx: 0 }),
    "cpu --%, ram --%, temp --, disk --%, net down 0 B/s up 0 B/s");
});
