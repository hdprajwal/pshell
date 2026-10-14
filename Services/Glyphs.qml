pragma Singleton

import QtQuick
import Quickshell

// Material Symbols names, picked the way DMS picks them.
//
// The companion to Icons: that one asks the icon theme for a file, this one
// names a glyph in the font pshell ships. Both answer the same questions --
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
    readonly property string edit: "edit"
    readonly property string pin: "push_pin"
    readonly property string lock: "lock"
    readonly property string powerOff: "power_settings_new"
    readonly property string logout: "logout"
    readonly property string keyboard: "keyboard"

    // The other two session actions, named here rather than spelled at the
    // power menu's call site so the five icons are picked in one place.
    // `bedtime` is the crescent DMS uses for suspend -- a moon reads as
    // "asleep, still there", which `power_settings_new` does not -- and
    // `restart_alt` is the circular arrow rather than `refresh`, which is
    // already this file's manual-refresh symbol and would say "fetch again"
    // on a button that restarts the machine.
    readonly property string suspend: "bedtime"
    readonly property string reboot: "restart_alt"

    // The keybind sheet's bar icon. The command key, not `keyboard`: that one
    // is the keyboard *backlight* slider's, and two panels wearing the same
    // glyph for unrelated things is how a bar stops being readable.
    readonly property string keybinds: "keyboard_command_key"

    // The update indicator's bar icon: an arrow coming down into a tray, the
    // symbol Material uses for "a system update is waiting". Not `refresh`,
    // which is this file's "fetch again" and is what right-clicking it does,
    // and not `download`, which reads as a file on its way to ~/Downloads.
    readonly property string updates: "system_update_alt"

    // The notification bell's three states: at rest, ringing (something
    // unread), and struck out for do-not-disturb. Named here rather than at
    // the call sites because the bar widget, the settings sidebar and the
    // panel header all draw the same bell and must keep agreeing on it.
    readonly property string notifications: "notifications"
    readonly property string notificationsActive: "notifications_active"
    readonly property string notificationsOff: "notifications_off"
    // The history panel's group-collapse chevron; rotation does "collapsed".
    readonly property string expandMore: "expand_more"

    // The weather panel's detail rows, and the manual refresh above them.
    //
    // Only these. The WMO code that decides which cloud the bar wears is not
    // here and should not be: that mapping is twenty-eight entries with a
    // label attached to each, and splitting the label from the icon across two
    // files is how they come to disagree. It lives in Services/Weather.js
    // beside its labels, and this block keeps its stated job -- the symbols
    // more than one part of the shell might reach for.
    readonly property string thermostat: "thermostat"
    readonly property string humidity: "humidity_mid"
    readonly property string wind: "air"
    readonly property string place: "place"
    readonly property string refresh: "refresh"

    // --------------------------------------------------- settings app
    //
    // One symbol per page in the sidebar. This said "one symbol, because the
    // settings app is one page" until the wallpaper and theme pages arrived;
    // the network pages' lan, ethernet, vpn and expander arrows are still
    // gone and stay gone until something draws them again.
    readonly property string wallpaper: "wallpaper"
    readonly property string palette: "palette"
    readonly property string info: "info"

    // The wallpaper page's toolbar and grid. `view_carousel` is the
    // three-cards-in-a-row picture, which is what the carousel overlay looks
    // like when it opens; `check` is the badge on the wallpaper that is up.
    readonly property string folder: "folder"
    readonly property string shuffle: "shuffle"
    readonly property string carousel: "view_carousel"
    readonly property string check: "check"
    readonly property string previous: "chevron_left"
    readonly property string next: "chevron_right"

    // The weather page's row. `partly_cloudy_day` and not `thermostat`, which
    // this file already has: that one is the panel's "feels like" symbol and
    // means temperature, so in a nav row it would name the one setting on the
    // page that is not about temperature at all. The same reasoning `keybinds`
    // records for not reusing `keyboard`.
    //
    // Not one of Weather.js's condition icons either, even though it shares a
    // name with the code-1 cut: the sidebar row is a fixed label for a page,
    // and a row that tracked the sky would look like a broken reading.
    readonly property string weather: "partly_cloudy_day"
}
