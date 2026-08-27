import QtQuick
import qs.Services
import qs.Commons
import qs.Ui
import "../../Services/NotificationHistory.js" as History

// Notification behaviour: toast lifetimes, how many stack up, which corner,
// how much history is kept, and which apps are muted. Everything writes
// through Config.set() into the `notifications` group, so the server and the
// toast stacks pick a change up on the next notification with no restart.
SettingsPage {
    id: page

    title: "Notifications"
    subtitle: "pshell is the notification daemon; nothing else needs to run."

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
        help: "How long a toast stays up, in seconds, per urgency. Zero means it never leaves on its own -- the default for critical, because a critical notification that quietly vanishes defeats the urgency."

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

        NumberField {
            label: "Visible at once -- more than this waits behind a +N more row"
            from: 1
            to: 20
            value: Config.notifications.maxVisible
            onModified: v => Config.set("notifications.maxVisible", v)
        }

        Dropdown {
            width: parent.width
            label: "Position"
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

    FormSection {
        title: "History"
        help: "How many notifications the panel remembers, across restarts."

        NumberField {
            label: "Depth"
            from: 0
            to: 1000
            value: Config.notifications.historyDepth
            onModified: v => Config.set("notifications.historyDepth", v)
        }
    }

    FormSection {
        title: "Muted apps"
        help: "A muted app's notifications still land in history; they just never toast. The list is every app history has seen."

        Text {
            width: parent.width
            visible: page.muteRows.length === 0
            text: "Nothing has notified yet. Apps appear here once they do."
            color: Color.muted
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
