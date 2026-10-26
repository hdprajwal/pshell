import QtQuick
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../Services/NotificationHistory.js" as History

// Notification behaviour: toast lifetimes, how many stack up, which corner,
// how much history is kept, and which apps are muted. Everything writes
// through Config.set() into the `notifications` group, so the server and the
// toast stacks pick a change up on the next notification with no restart.
SettingsPage {
    id: page

    title: "Notifications"

    // One write per edit, and always the whole timeout object: the three
    // urgencies live under one `timeout` key, and writing "the low value"
    // alone would need a third path level that ConfigPath deliberately does
    // not have.
    function setTimeout(key, seconds) {
        const next = {
            low: Config.notifications.timeoutLow,
            normal: Config.notifications.timeoutNormal,
            critical: Config.notifications.timeoutCritical
        };
        next[key] = seconds;
        Config.set("notifications.timeout", next);
    }

    // The mute list is keys, the page shows apps: everything seen in
    // history, plus anything already muted even when its notifications have
    // aged out -- an app you cannot see cannot be unmuted.
    readonly property var muteRows: {
        const rows = [];
        const seen = {};
        const groups = History.groupByApp(Notifications.history);
        for (var i = 0; i < groups.length; i++) {
            rows.push({
                key: groups[i].key,
                label: groups[i].appName
            });
            seen[groups[i].key] = true;
        }
        const muted = Config.notifications.muted;
        for (var j = 0; j < muted.length; j++) {
            const key = String(muted[j] || "").toLowerCase();
            if (key !== "" && !seen[key]) {
                rows.push({
                    key: key,
                    label: String(muted[j])
                });
                seen[key] = true;
            }
        }
        return rows;
    }

    function toggleMute(key) {
        const list = Config.notifications.muted.slice();
        var at = -1;
        for (var i = 0; i < list.length; i++) {
            if (String(list[i] || "").toLowerCase() === key)
                at = i;
        }
        if (at >= 0)
            list.splice(at, 1);
        else
            list.push(key);
        Config.set("notifications.muted", list);
    }

    FormSection {
        title: "Toasts"
        // Zero is the default for critical: a critical notification that quietly
        // vanishes defeats the urgency.
        help: "Seconds on screen per urgency; 0 stays until dismissed."

        Row {
            spacing: Style.spacing.xl

            NumberField {
                label: "Low"
                from: 0
                to: 3600
                value: Math.round(Config.notifications.timeoutLow)
                onModified: v => page.setTimeout("low", v)
            }

            NumberField {
                label: "Normal"
                from: 0
                to: 3600
                value: Math.round(Config.notifications.timeoutNormal)
                onModified: v => page.setTimeout("normal", v)
            }

            NumberField {
                label: "Critical"
                from: 0
                to: 3600
                value: Math.round(Config.notifications.timeoutCritical)
                onModified: v => page.setTimeout("critical", v)
            }
        }

        // Spaced off the timeouts by hand: the card's column has no spacing
        // of its own, and these rows would otherwise sit on the fields'
        // bottom edge.
        Item {
            width: 1
            height: Style.spacing.md
        }

        // More than this waits behind a "+N more" row, which says so itself.
        FormRow {
            label: "Visible at once"

            NumberField {
                from: 1
                to: 20
                value: Config.notifications.maxVisible
                onModified: v => Config.set("notifications.maxVisible", v)
            }
        }

        FormRow {
            label: "Position"

            Dropdown {
                showLabel: false
                options: [
                    {
                        value: "auto",
                        label: "Opposite the bar"
                    },
                    {
                        value: "top",
                        label: "Top"
                    },
                    {
                        value: "bottom",
                        label: "Bottom"
                    }
                ]
                value: Config.notifications.position
                onChanged: v => Config.set("notifications.position", v)
            }
        }

        FormRow {
            label: "History kept"

            NumberField {
                from: 0
                to: 1000
                value: Config.notifications.historyDepth
                onModified: v => Config.set("notifications.historyDepth", v)
            }
        }
    }

    // Not a notification, but the nearest thing to one: something the shell
    // tells you on its own, by sound rather than a toast. Too small for a
    // page of its own. Writes the `volumeTone` group.
    FormSection {
        title: "Volume tone"
        // It plays at the new level, so you hear how loud it is and which
        // device will play; silent when muted, at 0%, and when the output
        // switches.
        help: "A short click once the volume stops changing."

        Toggle {
            width: parent.width
            label: "Tone after a volume change"
            checked: Config.volumeTone.enabled
            onClicked: Config.set("volumeTone.enabled", !Config.volumeTone.enabled)
        }

        Toggle {
            width: parent.width
            label: "Volume keys and other apps too"
            description: "Off: only the control centre and pshell audio."
            // Inert, not hidden, while the tone is off; see ThemePage.
            enabled: Config.volumeTone.enabled
            opacity: Config.volumeTone.enabled ? 1 : 0.4
            checked: Config.volumeTone.keys
            onClicked: Config.set("volumeTone.keys", !Config.volumeTone.keys)
        }
    }

    FormSection {
        title: "Muted apps"
        help: "Muted apps still reach history, they just never toast."

        Text {
            width: parent.width
            visible: page.muteRows.length === 0
            text: "No apps yet."
            color: Commons.Color.muted
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }

        Repeater {
            model: page.muteRows

            Toggle {
                required property var modelData

                width: parent.width
                label: modelData.label
                checked: History.isMuted({
                    desktopEntry: modelData.key
                }, Config.notifications.muted)
                onClicked: page.toggleMute(modelData.key)
            }
        }
    }
}
