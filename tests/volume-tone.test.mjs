import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const T = loadQmlJs("Services/VolumeTone.js");

const SOUND = "/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga";
const ON = { enabled: true, keys: true, own: false };

function seen(volume, extra = {}) {
  return { key: "speakers#51", sink: "alsa_output.speakers", volume, muted: false, ...extra };
}

// A sink that has been the default for longer than the quiet window, at
// `volume`, so the next reading is judged as a change.
function settledAt(volume) {
  const first = T.observe(null, seen(volume), 0).state;
  return T.observe(first, seen(volume), 5000).state;
}

// Feeds readings one after another and says whether any of them armed the
// wait, and what the state ended as.
function feed(state, readings, now = 10000) {
  let armed = false;
  for (const r of readings) {
    const out = T.observe(state, r, now);
    state = out.state;
    armed = armed || out.arm;
    now += 20;
  }
  return { state, armed };
}

// ------------------------------------------------------------- watching

test("the first reading at start is the baseline, not a change", () => {
  const out = T.observe(null, seen(0.4), 1000);
  assert.equal(out.arm, false);
  assert.equal(out.state.settled, 0.4);
});

// The sink reports its stored level a moment after it is known; with
// Quickshell the volume reads 0 until then.
test("a level that arrives just after the sink appears is not a change", () => {
  const first = T.observe(null, seen(0), 1000).state;
  const out = T.observe(first, seen(0.4), 1300);
  assert.equal(out.arm, false);
  assert.equal(out.state.settled, 0.4);
});

test("a level that moves after the quiet window arms the wait", () => {
  const out = T.observe(settledAt(0.4), seen(0.45), 10000);
  assert.equal(out.arm, true);
  assert.equal(out.state.settled, 0.4, "settled stays where the burst started");
  assert.equal(out.state.last, 0.45);
});

test("no sink, or one not ready, is no state and no tone", () => {
  for (const s of [null, undefined, { key: "", volume: 0.5 }]) {
    const out = T.observe(settledAt(0.4), s, 10000);
    assert.equal(out.arm, false);
    assert.equal(out.state, null);
  }
});

test("the default switching to another device is not a change", () => {
  const out = T.observe(settledAt(0.4), seen(0.8, { key: "headset#77", sink: "bluez_output.headset" }), 10000);
  assert.equal(out.arm, false);
  assert.equal(out.state.key, "headset#77");
  assert.equal(out.state.settled, 0.8);
});

test("a mute toggle does not arm, because the level did not move", () => {
  const out = T.observe(settledAt(0.4), seen(0.4, { muted: true }), 10000);
  assert.equal(out.arm, false);
  assert.equal(out.state.muted, true);
});

test("the same level reported twice is one change", () => {
  const s = settledAt(0.4);
  const a = T.observe(s, seen(0.45), 10000);
  const b = T.observe(a.state, seen(0.4501), 10010);
  assert.equal(a.arm, true);
  assert.equal(b.arm, false);
});

// ------------------------------------------------------------- deciding

test("a held key or a drag is one tone at the end, at the level it landed on", () => {
  const { state, armed } = feed(settledAt(0.3), [0.31, 0.32, 0.33, 0.34, 0.35].map(v => seen(v)));
  assert.equal(armed, true);
  assert.equal(T.verdict(state, seen(0.35), ON), "");
});

test("a level that went somewhere and came back does not sound", () => {
  const { state } = feed(settledAt(0.3), [seen(0.35), seen(0.3)]);
  assert.equal(T.verdict(state, seen(0.3), ON), "unchanged");
});

test("muted, nothing sounds", () => {
  const { state } = feed(settledAt(0.3), [seen(0.35, { muted: true })]);
  assert.equal(T.verdict(state, seen(0.35, { muted: true }), ON), "muted");
});

test("at 0% nothing sounds", () => {
  const { state } = feed(settledAt(0.3), [seen(0)]);
  assert.equal(T.verdict(state, seen(0), ON), "silent");
});

test("a sink that changed while the wait ran does not get the tone", () => {
  const { state } = feed(settledAt(0.3), [seen(0.35)]);
  assert.equal(T.verdict(state, seen(0.35, { key: "headset#77" }), ON), "sink changed");
  assert.equal(T.verdict(state, { key: "", volume: 0.35 }, ON), "sink changed");
});

test("switched off, nothing sounds", () => {
  const { state } = feed(settledAt(0.3), [seen(0.35)]);
  assert.equal(T.verdict(state, seen(0.35), { ...ON, enabled: false }), "off");
  assert.equal(T.verdict(state, seen(0.35), undefined), "off");
});

// Raising the volume while muted unmutes it with swayosd; the new level is
// exactly what the tone is for.
test("a key that unmutes and raises sounds", () => {
  const start = T.observe(settledAt(0.3), seen(0.3, { muted: true }), 9000).state;
  const { state } = feed(start, [seen(0.3), seen(0.35)]);
  assert.equal(T.verdict(state, seen(0.35), ON), "");
});

test("with keys off, only pshell's own changes sound", () => {
  const { state } = feed(settledAt(0.3), [seen(0.35)]);
  const keysOff = { enabled: true, keys: false };
  assert.equal(T.verdict(state, seen(0.35), { ...keysOff, own: false }), "not pshell's");
  assert.equal(T.verdict(state, seen(0.35), { ...keysOff, own: true }), "");
});

test("settle makes the current level the one the next change is measured from", () => {
  const { state } = feed(settledAt(0.3), [seen(0.35)]);
  const after = T.settle(state, seen(0.35));
  assert.equal(after.settled, 0.35);
  assert.equal(T.verdict(after, seen(0.35), ON), "unchanged");
});

test("a level moved while muted is settled, so unmuting at it is quiet", () => {
  const { state } = feed(settledAt(0.3), [seen(0.5, { muted: true })]);
  const after = T.settle(state, seen(0.5, { muted: true }));
  const out = T.observe(after, seen(0.5), 20000);
  assert.equal(out.arm, false);
  assert.equal(T.verdict(out.state, seen(0.5), ON), "unchanged");
});

test("settle leaves a state alone when the sink moved under it", () => {
  const s = settledAt(0.3);
  assert.equal(T.settle(s, seen(0.5, { key: "other#1" })), s);
  assert.equal(T.settle(null, seen(0.5)), null);
});

test("isOwnChange counts a change that lands just after pshell set the level", () => {
  assert.equal(T.isOwnChange(0, 10000), false, "pshell never set it");
  assert.equal(T.isOwnChange(9990, 0), false, "nothing has moved");
  assert.equal(T.isOwnChange(10000, 10000), true);
  assert.equal(T.isOwnChange(10000, 10150), true);
  assert.equal(T.isOwnChange(10000, 10151), false);
  assert.equal(T.isOwnChange(10000, 9990), false, "a change from before pshell set it");
});

// keys: false. A scroll in the control centre, then a volume key 400 ms
// later, before the wait for the scroll's tone has run out: the level that
// lands is the key's, so it is not pshell's to sound for.
test("a key press just after pshell's own change is not pshell's", () => {
  let state = settledAt(0.4);
  const scrollAt = 10000;
  state = T.observe(state, seen(0.45), scrollAt + 5).state;
  assert.equal(T.isOwnChange(scrollAt, state.changedAt), true, "the scroll alone is pshell's");
  state = T.observe(state, seen(0.5), scrollAt + 400).state;
  const own = T.isOwnChange(scrollAt, state.changedAt);
  assert.equal(own, false);
  assert.equal(T.verdict(state, seen(0.5), { enabled: true, keys: false, own }), "not pshell's");
});

test("observe keeps when the level last moved, and settle carries it", () => {
  let state = settledAt(0.4);
  state = T.observe(state, seen(0.45), 10000).state;
  assert.equal(state.changedAt, 10000);
  state = T.observe(state, seen(0.45, { muted: true }), 10300).state;
  assert.equal(state.changedAt, 10000, "a mute toggle is not a change of level");
  assert.equal(T.settle(state, seen(0.45)).changedAt, 10000);
});

test("clampDelay defaults and bounds the wait", () => {
  for (const v of [undefined, null, "", "soon", NaN])
    assert.equal(T.clampDelay(v), 180, String(v));
  assert.equal(T.clampDelay(250), 250);
  assert.equal(T.clampDelay("250"), 250);
  assert.equal(T.clampDelay(0), 50);
  assert.equal(T.clampDelay(99999), 2000);
});

// -------------------------------------------------------------- playing

test("parseProbe reads players and readable files, and nothing else", () => {
  const out = T.parseProbe(`paplay\npw-play\nfile ${SOUND}\nfile /home/me/tick.wav\nsh: noise\nmpv\n\n`);
  assert.deepEqual(out.players, ["paplay", "pw-play"]);
  assert.deepEqual(out.files, [SOUND, "/home/me/tick.wav"]);
  assert.deepEqual(T.parseProbe(undefined), { players: [], files: [] });
});

test("choosePlayer prefers pw-play, then paplay, then canberra-gtk-play", () => {
  assert.equal(T.choosePlayer(["canberra-gtk-play", "paplay", "pw-play"]), "pw-play");
  assert.equal(T.choosePlayer(["canberra-gtk-play", "paplay"]), "paplay");
  assert.equal(T.choosePlayer(["canberra-gtk-play"]), "canberra-gtk-play");
  assert.equal(T.choosePlayer([]), "");
  assert.equal(T.choosePlayer(undefined), "");
});

test("chooseSound takes a readable custom sound, else the freedesktop one", () => {
  assert.equal(T.chooseSound("/home/me/tick.wav", ["/home/me/tick.wav", SOUND]), "/home/me/tick.wav");
  assert.equal(T.chooseSound("/home/me/typo.wav", [SOUND]), SOUND);
  assert.equal(T.chooseSound("", [SOUND]), SOUND);
  assert.equal(T.chooseSound("/home/me/typo.wav", []), "");
});

test("pw-play is aimed at the sink by name, with no gain of its own", () => {
  const argv = T.playerArgv("pw-play", SOUND, "alsa_output.speakers");
  assert.deepEqual(argv.slice(0, 3), ["pw-play", "--target", "alsa_output.speakers"]);
  assert.equal(argv[argv.length - 1], SOUND);
  assert.ok(!argv.includes("--volume"));
  assert.ok(!argv.includes("--media-role"), "a Notification role would share WirePlumber's notification volume");
  const props = JSON.parse(argv[argv.indexOf("-P") + 1]);
  assert.equal(props["node.name"], "pshell.volume-tone");
});

test("paplay is aimed at the sink too, and canberra-gtk-play cannot be", () => {
  assert.deepEqual(T.playerArgv("paplay", SOUND, "alsa_output.speakers"),
    ["paplay", "--device=alsa_output.speakers", "--client-name=pshell", "--stream-name=Volume tone", "--property=node.name=pshell.volume-tone", SOUND]);
  assert.deepEqual(T.playerArgv("canberra-gtk-play", SOUND, "alsa_output.speakers"),
    ["canberra-gtk-play", "-f", SOUND, "-d", "Volume tone"]);
});

test("without a sink name the player falls back to the default output", () => {
  assert.ok(!T.playerArgv("pw-play", SOUND, "").includes("--target"));
  assert.deepEqual(T.playerArgv("paplay", SOUND, ""), ["paplay", "--client-name=pshell", "--stream-name=Volume tone", "--property=node.name=pshell.volume-tone", SOUND]);
});

test("no player or no file is no command", () => {
  assert.deepEqual(T.playerArgv("", SOUND, "x"), []);
  assert.deepEqual(T.playerArgv("mpv", SOUND, "x"), []);
  assert.deepEqual(T.playerArgv("pw-play", "", "x"), []);
});

// What each player's stream looks like to Pipewire, seen live: pw-play and
// paplay carry the name they are given, canberra-gtk-play its own name.
test("isToneStream hides the tone from every player, and nothing else", () => {
  for (const player of ["pw-play", "paplay", "canberra-gtk-play"])
    assert.equal(T.isToneStream("pshell.volume-tone", player, false), true, player);
  assert.equal(T.isToneStream("canberra-gtk-play", "canberra-gtk-play", true), true);
  assert.equal(T.isToneStream("canberra-gtk-play", "canberra-gtk-play", false), false, "someone else's sound between tones");
  assert.equal(T.isToneStream("canberra-gtk-play", "pw-play", true), false, "pshell is not playing with canberra");
  assert.equal(T.isToneStream("pshell", "paplay", true), false, "a paplay stream without the property is not assumed");
  assert.equal(T.isToneStream("Firefox", "canberra-gtk-play", true), false);
});
