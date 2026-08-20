pragma Singleton

import QtQuick
import Quickshell

// Themed icon lookup. Everything here resolves a name to a real file up
// front, because the image provider answers a missing icon with a magenta
// placeholder at Ready status rather than an error, so there is nothing to
// react to after the fact.
Singleton {
    id: root

    function path(name) {
        if (!name)
            return "";
        const found = Quickshell.iconPath(String(name), true);
        if (found === "")
            return "";
        return found.charAt(0) === "/" ? "file://" + found : found;
    }

    // A desktop entry's icon is either a name to look up in the theme or an
    // absolute path to a file on disk, and nothing in the entry distinguishes
    // them. Zed ships the second kind, Helium the first.
    function fromEntry(icon) {
        const name = String(icon || "");
        if (name === "")
            return "";
        if (name.charAt(0) === "/")
            return "file://" + name;
        return root.path(name);
    }

    // First name that the current theme actually has.
    function first(names) {
        for (var i = 0; i < names.length; i++) {
            const found = root.path(names[i]);
            if (found !== "")
                return found;
        }
        return "";
    }

    // Freedesktop names every mainstream theme ships, so these keep working
    // if the user switches away from Papirus.
    function battery(percent, charging) {
        const suffix = charging ? "-charging-symbolic" : "-symbolic";
        var level = "full";
        if (percent <= 10)
            level = "empty";
        else if (percent <= 25)
            level = "caution";
        else if (percent <= 50)
            level = "low";
        else if (percent <= 80)
            level = "good";
        return root.first(["battery-" + level + suffix, "battery-" + level, charging ? "battery-charging-symbolic" : "battery-symbolic"]);
    }

    // Quickshell reports signal strength as a 0-1 double, not a percentage.
    function wifi(strength) {
        var level = "excellent";
        if (strength < 0.2)
            level = "none";
        else if (strength < 0.4)
            level = "weak";
        else if (strength < 0.6)
            level = "ok";
        else if (strength < 0.8)
            level = "good";
        return root.first(["network-wireless-signal-" + level + "-symbolic", "network-wireless-signal-" + level, "network-wireless-symbolic"]);
    }

    function wired(connected) {
        return root.first([connected ? "network-wired-symbolic" : "network-wired-disconnected-symbolic", "network-wired"]);
    }

    function wifiOff() {
        return root.first(["network-wireless-offline-symbolic", "network-wireless-disabled-symbolic", "network-offline-symbolic"]);
    }

    function microphone(muted) {
        if (muted)
            return root.first(["microphone-sensitivity-muted-symbolic", "audio-input-microphone-muted-symbolic"]);
        return root.first(["audio-input-microphone-symbolic", "audio-input-microphone"]);
    }

    function bluetooth(enabled, connected) {
        if (!enabled)
            return root.first(["bluetooth-disabled-symbolic", "bluetooth-inactive-symbolic", "bluetooth-symbolic"]);
        return root.first([connected ? "bluetooth-active-symbolic" : "bluetooth-symbolic", "bluetooth"]);
    }
}
