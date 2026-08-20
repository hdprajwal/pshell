pragma Singleton

import QtQuick
import Quickshell

// Material Symbols names, picked the way DMS picks them.
//
// The companion to Icons: that one asks the icon theme for a file, this one
// names a glyph in the font qsbar ships. Both answer the same questions --
// "which battery icon for 40% while charging?" -- so a call site swaps one
// for the other without restating the thresholds.
//
// The mapping is DMS's, thresholds included, so an icon means the same thing
// in both shells. Where Quickshell hands us a 0-1 fraction and DMS works in
// percent, the conversion happens here rather than at the call site.
Singleton {
    id: root

    // ------------------------------------------------------------- network

    // DMS bands wifi at 50% and 25%, and treats "on but not associated" as
    // the same picture as "off" -- there is no signal either way.
    function wifi(enabled, connected, strength) {
        if (!enabled || !connected)
            return "wifi_off";
        const percent = strength <= 1 ? strength * 100 : strength;
        if (percent >= 50)
            return "wifi";
        if (percent >= 25)
            return "wifi_2_bar";
        return "wifi_1_bar";
    }

    function wired(connected) {
        return connected ? "settings_ethernet" : "lan";
    }

    function vpn(connected) {
        return connected ? "vpn_key" : "vpn_key_off";
    }

    // ----------------------------------------------------------- bluetooth

    function bluetooth(enabled, connected) {
        if (!enabled)
            return "bluetooth_disabled";
        return connected ? "bluetooth_connected" : "bluetooth";
    }

    // What a paired device looks like. BlueZ reports a freedesktop icon name
    // that is close enough to sort on, and the device's own name covers the
    // ones that do not report one.
    function bluetoothDevice(deviceName, iconHint) {
        const name = String(deviceName || "").toLowerCase();
        const icon = String(iconHint || "").toLowerCase();
        const has = keys => keys.some(k => icon.indexOf(k) >= 0 || name.indexOf(k) >= 0);

        if (has(["headset", "audio", "headphone", "airpod", "arctis"]))
            return "headset";
        if (has(["mouse"]))
            return "mouse";
        if (has(["keyboard"]))
            return "keyboard";
        if (has(["phone", "iphone", "android", "samsung"]))
            return "smartphone";
        if (has(["watch"]))
            return "watch";
        if (has(["speaker"]))
            return "speaker";
        if (icon.indexOf("display") >= 0 || name.indexOf("tv") >= 0)
            return "tv";
        return "bluetooth";
    }

    // --------------------------------------------------------------- audio

    function volume(muted, level) {
        if (muted)
            return "volume_off";
        if (level <= 0)
            return "volume_mute";
        if (level <= 0.33)
            return "volume_down";
        return "volume_up";
    }

    function microphone(muted) {
        return muted ? "mic_off" : "mic";
    }

    // A sink's form factor is the only honest signal about what it is; the
    // node name is the fallback for the drivers that do not set one.
    function sink(node) {
        if (!node)
            return "speaker";

        const props = node.properties || {};
        const formFactor = String(props["device.form-factor"] || "").toLowerCase();
        switch (formFactor) {
        case "headphone":
        case "headset":
        case "hands-free":
        case "handset":
            return "headset";
        case "tv":
        case "monitor":
            return "tv";
        case "speaker":
        case "computer":
        case "hifi":
        case "portable":
        case "car":
            return "speaker";
        }

        const bus = String(props["device.bus"] || "").toLowerCase();
        if (bus === "bluetooth")
            return "headset";

        // A bluez sink carries its bus on the device, not the node, so the
        // node name is the only place the radio shows up.
        const name = String(node.name || "").toLowerCase();
        if (name.indexOf("bluez") >= 0)
            return "headset";
        if (name.indexOf("hdmi") >= 0)
            return "tv";
        if (name.indexOf("iec958") >= 0 || name.indexOf("spdif") >= 0)
            return "speaker";
        if (bus === "usb")
            return "headset";
        return "speaker";
    }

    function source(node) {
        const name = String((node && node.name) || "").toLowerCase();
        if (name.indexOf("bluez") >= 0 || name.indexOf("usb") >= 0)
            return "headset";
        return "mic";
    }

    // ------------------------------------------------------------- battery

    // DMS draws charging as one of the seven charging cuts and otherwise
    // steps a six-bar meter. The bands are theirs.
    function battery(percent, charging) {
        if (charging) {
            if (percent >= 90)
                return "battery_charging_full";
            if (percent >= 80)
                return "battery_charging_90";
            if (percent >= 60)
                return "battery_charging_80";
            if (percent >= 50)
                return "battery_charging_60";
            if (percent >= 30)
                return "battery_charging_50";
            if (percent >= 20)
                return "battery_charging_30";
            return "battery_charging_20";
        }
        if (percent >= 95)
            return "battery_full";
        if (percent >= 85)
            return "battery_6_bar";
        if (percent >= 70)
            return "battery_5_bar";
        if (percent >= 55)
            return "battery_4_bar";
        if (percent >= 40)
            return "battery_3_bar";
        if (percent >= 25)
            return "battery_2_bar";
        return "battery_1_bar";
    }

    // ---------------------------------------------------------- brightness

    function brightness(fraction) {
        const percent = fraction <= 1 ? fraction * 100 : fraction;
        if (percent <= 33)
            return "brightness_low";
        if (percent <= 66)
            return "brightness_medium";
        return "brightness_high";
    }

    // ------------------------------------------------------- fixed symbols
    //
    // Named rather than spelled out at the call site, so the shell has one
    // place to look when an icon needs changing.
    readonly property string nightMode: "nightlight"
    readonly property string darkMode: "contrast"
    readonly property string settings: "settings"
    readonly property string pin: "push_pin"
    readonly property string lock: "lock"
    readonly property string powerOff: "power_settings_new"
    readonly property string logout: "logout"
    readonly property string unknown: "help"
}
