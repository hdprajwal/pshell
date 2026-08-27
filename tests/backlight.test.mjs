import test from "node:test";
import assert from "node:assert/strict";
import { loadQmlJs } from "./load-qml-js.mjs";

const Backlight = loadQmlJs("Services/Backlight.js");

// `brightnessctl -lm` on the machine this was written on, pasted verbatim,
// not invented. The point of the fixture is every trap at once: a dozen LEDs
// that are not the keyboard, capslock names that contain "lock" but not the
// suffix, and `asus-wireless::airplane` reporting a nonsense 25500% -- real
// output is allowed to be that strange, and the parser has to shrug at it.
const REAL_OUTPUT = `intel_backlight,backlight,4328,61%,7142
enp2s0-0::lan,leds,0,0%,255
input10::capslock,leds,0,0%,1
input4::capslock,leds,0,0%,1
phy0-led,leds,1,100%,1
asus-wireless::airplane,leds,255,25500%,1
input4::scrolllock,leds,0,0%,1
input10::numlock,leds,1,100%,1
input10::kana,leds,0,0%,1
input10::scrolllock,leds,0,0%,1
input4::numlock,leds,1,100%,1
asus::kbd_backlight,leds,0,0%,3
enp2s0-2::lan,leds,0,0%,255
input10::compose,leds,0,0%,1
enp2s0-1::lan,leds,0,0%,255
`;

test("the real device list yields the screen and the keyboard, numbers as numbers", () => {
  const devices = Backlight.parseDevices(REAL_OUTPUT);
  assert.equal(devices.length, 15);

  const screen = Backlight.pickScreen(devices);
  assert.equal(screen.name, "intel_backlight");
  assert.equal(screen.class, "backlight");
  assert.equal(screen.current, 4328);
  assert.equal(screen.percent, 61);
  assert.equal(screen.max, 7142);

  const keyboard = Backlight.pickKeyboard(devices);
  assert.equal(keyboard.name, "asus::kbd_backlight");
  assert.equal(keyboard.class, "leds");
  assert.equal(keyboard.max, 3);
});

test("no other LED passes for the keyboard, however lock-ish its name", () => {
  // The names that share a directory with the keyboard on this machine.
  // Each would be picked by a substring match or a "first leds device"
  // heuristic, which is exactly why the picker matches the suffix.
  const impostors = [
    "input10::capslock,leds,0,0%,1",
    "phy0-led,leds,1,100%,1",
    "enp2s0-0::lan,leds,0,0%,255",
    "asus-wireless::airplane,leds,255,25500%,1"
  ].join("\n");
  assert.equal(Backlight.pickKeyboard(Backlight.parseDevices(impostors)), null);
});

test("a bare kbd_backlight with no vendor prefix is still the keyboard", () => {
  const devices = Backlight.parseDevices("kbd_backlight,leds,1,50%,2\n");
  assert.equal(Backlight.pickKeyboard(devices).name, "kbd_backlight");
});

test("a machine with no lit keyboard still finds its screen", () => {
  const devices = Backlight.parseDevices("amdgpu_bl0,backlight,120,47%,255\nphy0-led,leds,1,100%,1\n");
  assert.equal(Backlight.pickKeyboard(devices), null);
  assert.equal(Backlight.pickScreen(devices).name, "amdgpu_bl0");
});

test("a machine with no backlight-class device has no screen", () => {
  const devices = Backlight.parseDevices("tpacpi::kbd_backlight,leds,1,50%,2\n");
  assert.equal(Backlight.pickScreen(devices), null);
  assert.equal(Backlight.pickKeyboard(devices).name, "tpacpi::kbd_backlight");
});

test("max 0 makes a device absent for both pickers", () => {
  // A zero-range device has nowhere to move; a slider over it would divide
  // by zero to draw its handle. Same judgement as Brightness.qml's
  // `available: max > 0`.
  const devices = Backlight.parseDevices("intel_backlight,backlight,0,0%,0\nasus::kbd_backlight,leds,0,0%,0\n");
  assert.equal(devices.length, 2);
  assert.equal(Backlight.pickScreen(devices), null);
  assert.equal(Backlight.pickKeyboard(devices), null);
});

test("garbage, short lines, empty input and trailing newlines never throw", () => {
  assert.deepEqual(Backlight.parseDevices(""), []);
  assert.deepEqual(Backlight.parseDevices("\n\n"), []);
  assert.deepEqual(Backlight.parseDevices(undefined), []);
  assert.deepEqual(Backlight.parseDevices("brightnessctl: some warning\n"), []);
  assert.deepEqual(Backlight.parseDevices("a,b,c\n"), []);
  // Five fields but non-numeric where numbers belong: skipped, not thrown.
  assert.deepEqual(Backlight.parseDevices("dev,leds,x,y%,z\n"), []);
  // One bad line must not take the good one with it.
  const devices = Backlight.parseDevices("junk\nintel_backlight,backlight,4328,61%,7142\na,b,c,d\n");
  assert.equal(devices.length, 1);
  assert.equal(Backlight.pickScreen(devices).name, "intel_backlight");
});
