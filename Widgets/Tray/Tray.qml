import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Services

Row {
    id: root

    property var cfg: ({})
    property var bar: null

    // Follows the shared barIconSize unless this widget overrides it, either
    // with an exact iconSize or a scale against the bar height.
    readonly property int iconSize: cfg.iconSize || (cfg.iconScale !== undefined ? Math.round(Config.size * cfg.iconScale) : Config.barIconSize)

    // Icon themes only ship a few fixed sizes, and a request that falls
    // between them misses. Status icons in particular are commonly 22 and 24
    // only, with no 16 at all: breeze ships flameshot-tray at 22 and 24, so
    // asking for 16 loses an icon that is sitting right there. Request the
    // next real size up, starting at 22, and let the scene graph scale it
    // down to whatever the bar actually needs.
    readonly property int requestSize: {
        const sizes = [22, 24, 32, 48, 64];
        for (var i = 0; i < sizes.length; i++) {
            if (sizes[i] >= root.iconSize)
                return sizes[i];
        }
        return sizes[sizes.length - 1];
    }
    // Comma-separated ids to leave out, matched case-insensitively.
    readonly property var hidden: String(cfg.hide || "").split(",").map(s => s.trim().toLowerCase()).filter(s => s !== "")

    readonly property var items: {
        const all = SystemTray.items.values;
        if (root.hidden.length === 0)
            return all;
        return all.filter(item => root.hidden.indexOf(String(item?.id || "").toLowerCase()) < 0);
    }

    // Status Notifier icons arrive in three shapes: a bare theme name, an
    // absolute path, or a name with the search directory bolted on as a
    // "?path=" query. Only the last one needs unpicking.
    // Apps advertise an icon name their own theme ships but yours may not.
    // Flameshot asks for "flameshot-tray", which only breeze has, so fall
    // back to the plain app id and pick up Papirus's "flameshot.svg".
    function byId(item) {
        return Icons.path(String((item && item.id) || ""));
    }

    function iconSource(item) {
        const icon = item && item.icon;
        if (typeof icon !== "string" || icon === "")
            return root.byId(item);

        const marker = icon.indexOf("?path=");
        if (marker >= 0) {
            const name = icon.substring(0, marker);
            const dir = icon.substring(marker + 6);
            var file = name.substring(name.lastIndexOf("/") + 1);
            // Dropbox hands over a bare name but files it under a theme path.
            if (file.indexOf("dropboxstatus") === 0)
                file = "hicolor/16x16/status/" + file;
            return "file://" + dir + "/" + file;
        }

        if (icon.charAt(0) === "/")
            return "file://" + icon;

        const resolved = Icons.path(icon);
        return resolved !== "" ? resolved : root.byId(item);
    }

    // Menus drop away from whichever screen edge the bar sits on.
    readonly property int menuEdge: {
        switch (Config.position) {
        case "bottom":
            return Edges.Top;
        case "left":
            return Edges.Right;
        case "right":
            return Edges.Left;
        default:
            return Edges.Bottom;
        }
    }

    spacing: cfg.spacing !== undefined ? cfg.spacing : 6
    height: Config.size

    Repeater {
        model: root.items

        Item {
            id: entry

            required property var modelData

            readonly property string label: modelData.tooltipTitle || modelData.title || modelData.id || ""


            anchors.verticalCenter: parent.verticalCenter
            width: root.iconSize
            height: root.iconSize

            // Hover backing, so an icon has a visible hit target.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: 4
                color: pointer.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : "transparent"
            }

            IconImage {
                id: image
                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize
                source: root.iconSource(entry.modelData)
                asynchronous: true
                visible: source !== "" && status === Image.Ready

                // IconImage normally asks the theme for exactly the size it
                // draws at, which for a small bar is a size no theme ships.
                // Ask for a real size instead and let the image downscale,
                // which is sharper than scaling the drawn result.
                backer.sourceSize.width: root.requestSize
                backer.sourceSize.height: root.requestSize
                backer.smooth: true
            }

            // An icon that fails to resolve still needs to be clickable, so
            // fall back to the first letter of the item id.
            Text {
                anchors.centerIn: parent
                visible: !image.visible
                text: {
                    const id = entry.modelData.id || "";
                    return id === "" ? "?" : id.charAt(0).toUpperCase();
                }
                color: Config.fg
                font.family: Config.fontFamily
                font.pixelSize: Math.round(root.iconSize * 0.7)
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor

                onEntered: if (root.bar)
                    root.bar.showTooltip(entry, entry.label)
                onExited: if (root.bar)
                    root.bar.hideTooltip(entry)

                onClicked: mouse => {
                    if (root.bar)
                        root.bar.hideTooltip(entry);

                    if (mouse.button === Qt.RightButton) {
                        if (entry.modelData.hasMenu)
                            trayMenu.openFor(entry.modelData, entry);
                        return;
                    }

                    if (mouse.button === Qt.MiddleButton) {
                        entry.modelData.secondaryActivate();
                        return;
                    }

                    // Some apps expose no activate action at all and expect
                    // the menu to be the whole interface.
                    if (entry.modelData.onlyMenu) {
                        if (entry.modelData.hasMenu)
                            trayMenu.openFor(entry.modelData, entry);
                    } else {
                        entry.modelData.activate();
                    }
                }

                onWheel: wheel => {
                    const dy = wheel.angleDelta.y;
                    const dx = wheel.angleDelta.x;
                    if (dy !== 0)
                        entry.modelData.scroll(dy, false);
                    if (dx !== 0)
                        entry.modelData.scroll(dx, true);
                }
            }
        }
    }

    // One menu instance shown for whichever icon was clicked, rather than one
    // per icon sitting idle.
    TrayMenu {
        id: trayMenu
        bar: root.bar
    }
}
