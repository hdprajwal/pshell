import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.Services
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "qsbar.tray"

    property var cfg: ({})

    // Follows the shared barIconSize unless this widget overrides it, either
    // with an exact iconSize or a scale against the bar height.
    readonly property int iconSize: cfg.iconSize || (cfg.iconScale !== undefined ? Math.round(Style.bar.sizeHorizontal * cfg.iconScale) : Style.bar.iconCanvas)

    // Comma-separated ids to leave out, matched case-insensitively.
    readonly property var hidden: String(cfg.hide || "").split(",").map(s => s.trim().toLowerCase()).filter(s => s !== "")

    readonly property var items: {
        const all = SystemTray.items.values;
        if (root.hidden.length === 0)
            return all;
        return all.filter(item => root.hidden.indexOf(String((item && item.id) || "").toLowerCase()) < 0);
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

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: cfg.spacing !== undefined ? cfg.spacing : 6

        Repeater {
            model: root.items

            BarIconButton {
                id: entry

                required property var modelData

                readonly property string label: modelData.tooltipTitle || modelData.title || modelData.id || ""

                bar: root.bar
                slotSize: root.iconSize
                opticalSize: root.iconSize
                tooltipText: entry.label
                iconComponent: Component {
                    Item {
                        anchors.fill: parent

                        readonly property string source: root.iconSource(entry.modelData)

                        BarIcon {
                            anchors.fill: parent
                            visible: parent.source !== ""
                            iconSource: parent.source
                            size: root.iconSize
                            color: Color.foreground
                        }

                        // An icon that fails to resolve still needs to be
                        // clickable, so fall back to the first letter of the
                        // item id.
                        Text {
                            anchors.centerIn: parent
                            visible: parent.source === ""
                            text: {
                                const id = entry.modelData.id || "";
                                return id === "" ? "?" : id.charAt(0).toUpperCase();
                            }
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Math.round(root.iconSize * 0.7)
                        }
                    }
                }

                onPressed: button => {
                    if (button === Qt.RightButton) {
                        if (entry.modelData.hasMenu)
                            trayMenu.openFor(entry.modelData, entry);
                        return;
                    }

                    if (button === Qt.MiddleButton) {
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

                onWheelMoved: delta => entry.modelData.scroll(delta, false)
            }
        }
    }

    // One menu instance shown for whichever icon was clicked, rather than one
    // per icon sitting idle.
    TrayMenu {
        id: trayMenu
        bar: root.bar
        owner: root
    }
}
