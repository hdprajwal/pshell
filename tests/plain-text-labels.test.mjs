import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const repo = join(dirname(fileURLToPath(import.meta.url)), "..");

// A Text item defaults to AutoText, which renders anything that looks like
// HTML -- and RichText fetches an <img src> on sight. Window titles, SSIDs,
// Bluetooth and Tailscale names, tray menus and notification summaries are
// all chosen by someone else, so the items showing them must say
// Text.PlainText. These guard each one by the binding it displays.
const sites = [
    ["Widgets/ActiveWindow/ActiveWindow.qml", "text: root.appName"],
    ["Widgets/ActiveWindow/ActiveWindow.qml", "text: root.title"],
    ["Ui/BarIconButton.qml", "text: root.label"],
    ["Ui/Button.qml", "text: root.text"],
    ["Ui/PanelToolTip.qml", "text: root.text"],
    ["shell.qml", "text: tooltip.text"],
    ["Ui/PanelHero.qml", "text: root.meta.toUpperCase()"],
    ["Ui/SearchableDropdown.qml", "text: root.currentLabel()"],
    ["Ui/SearchableDropdown.qml", "text: root.optionLabel(modelData)"],
    ["Ui/SearchableDropdown.qml", "text: root.optionDescription(modelData)"],
    ["Widgets/Network/NetworkList.qml", "text: netRow.modelData.name"],
    ["Widgets/Network/PasswordPrompt.qml", "text: \"Connect to \" + root.ssid"],
    ["Widgets/Bluetooth/BluetoothList.qml", "text: devRow.label"],
    ["Widgets/Tray/TrayMenu.qml", "text: \"‹  \""],
    ["Widgets/Tray/TrayMenu.qml", "text: row.modelData ? (row.modelData.text"],
    ["Widgets/Tailscale/TailscaleDevice.qml", "text: root.hostName"],
    ["Widgets/Tailscale/TailscaleDevice.qml", "text: root.isSelf ? \"This device\" : root.owner"],
    ["Widgets/Tailscale/Tailscale.qml", "text: parent.modelData"],
    ["Widgets/Tailscale/Tailscale.qml", "text: root.lastError"],
    ["Widgets/Notifications/Toast.qml", "text: toast.notification ? toast.notification.appName"],
    ["Widgets/Notifications/Toast.qml", "text: toast.notification ? toast.notification.summary"],
    ["Widgets/Notifications/NotificationRow.qml", "text: row.record ? row.record.appName"],
    ["Widgets/Notifications/NotificationRow.qml", "text: row.record ? row.record.summary"],
    ["Widgets/Notifications/Notifications.qml", "text: group.modelData.appName"],
    // The title binding is a block; the width line is the same item's.
    ["Widgets/Lock/LockMedia.qml", "width: Math.min(implicitWidth, root.maxTitleWidth)"],
    ["Widgets/Lock/LockNotifications.qml", "text: chip.modelData.appName"],
    ["Widgets/ControlCenter/AudioDeviceList.qml", "text: devRow.modelData.description"],
    ["Widgets/ControlCenter/AudioDeviceList.qml", "text: parent.modelData.description"],
    ["Widgets/ControlCenter/ControlCenter.qml", "text: tile.title"],
    ["Widgets/ControlCenter/ControlCenter.qml", "text: tile.subtitle"],
];

// The body of the object whose own property line `at` is: walk back to the
// `{` that opens it, then forward to the `}` that closes it.
function enclosingObject(src, at) {
    let depth = 0;
    let open = -1;
    for (let i = at; i >= 0; i--) {
        if (src[i] === "}")
            depth++;
        else if (src[i] === "{") {
            if (depth === 0) {
                open = i;
                break;
            }
            depth--;
        }
    }
    assert.ok(open >= 0, "no enclosing object");
    depth = 0;
    for (let i = open; i < src.length; i++) {
        if (src[i] === "{")
            depth++;
        else if (src[i] === "}" && --depth === 0)
            return { head: src.slice(src.lastIndexOf("\n", open) + 1, open).trim(), body: src.slice(open, i + 1) };
    }
    assert.fail("unclosed object");
}

// Only the object's own lines, not those of a child (a Behavior, an
// animation) that happens to sit inside it.
function ownLines(body) {
    const out = [];
    let depth = 0;
    for (const line of body.split("\n")) {
        if (depth === 1)
            out.push(line.trim());
        for (const c of line)
            depth += c === "{" ? 1 : c === "}" ? -1 : 0;
    }
    return out;
}

for (const [file, binding] of sites) {
    test(`${file}: "${binding}" renders as plain text`, () => {
        const src = readFileSync(join(repo, file), "utf8");
        const at = src.indexOf(binding);
        assert.ok(at >= 0, `binding not found in ${file}`);
        const { head, body } = enclosingObject(src, at);
        assert.match(head, /\bText$/, `binding is not on a Text item (${head})`);
        assert.ok(ownLines(body).includes("textFormat: Text.PlainText"), "missing textFormat: Text.PlainText");
    });
}
