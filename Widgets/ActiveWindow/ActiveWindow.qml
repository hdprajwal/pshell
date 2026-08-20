import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Services
import qs.Commons

// The focused window: its icon, its application name, and its title.
//
// The source is ToplevelManager, which is the wlr foreign-toplevel protocol
// rather than Hyprland's IPC, so unlike `workspaces` this is not tied to one
// compositor. Hyprland's own activeToplevel reads null here whether or not a
// window is focused, so it would not have worked anyway.
Item {
    id: root

    property var cfg: ({})
    property var bar: null

    readonly property var toplevel: ToplevelManager.activeToplevel
    readonly property string appId: toplevel ? String(toplevel.appId || "") : ""
    readonly property string title: toplevel ? String(toplevel.title || "") : ""

    // Reading the model's length is what makes this re-run. heuristicLookup is
    // a plain function call, so without touching a property the binding would
    // never notice that the desktop entry scan finished and would sit on the
    // appId fallback for the life of the bar.
    readonly property var entry: {
        const scanned = DesktopEntries.applications.values.length;
        if (root.appId === "" || scanned === 0)
            return null;
        return DesktopEntries.heuristicLookup(root.appId);
    }

    // The entry's name where there is a .desktop file, otherwise the last
    // segment of a reverse-DNS appId, which is the part "dev.zed.Zed" means.
    readonly property string appName: {
        if (root.entry && root.entry.name)
            return String(root.entry.name);
        if (root.appId === "")
            return "";
        const parts = root.appId.split(".");
        return parts[parts.length - 1];
    }

    readonly property string iconSource: {
        if (root.appId === "")
            return "";
        const themed = root.entry ? Icons.fromEntry(root.entry.icon) : "";
        return themed !== "" ? themed : Icons.path(root.appId);
    }

    readonly property bool showIcon: cfg.showIcon !== false
    readonly property bool showAppName: cfg.showAppName !== false
    readonly property int maxWidth: cfg.maxWidth || 400

    // Nothing focused collapses the slot, and Section.qml hides a slot with no
    // width, so the bar closes the gap on an empty workspace.
    implicitWidth: root.toplevel ? content.implicitWidth : 0
    implicitHeight: Style.bar.sizeHorizontal
    visible: root.toplevel !== null

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        // A plain Image rather than BarIcon. BarIcon runs a ColorOverlay to
        // tint symbolic icons to the foreground colour, which is right for the
        // tray and the battery and wrong for an application logo.
        Image {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showIcon && root.iconSource !== ""
            source: root.iconSource
            width: Style.bar.iconCanvas
            height: Style.bar.iconCanvas
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 64
            sourceSize.height: 64
            smooth: true
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showAppName && root.appName !== ""
            text: root.appName
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showAppName && root.appName !== "" && root.title !== ""
            text: "·"
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.title !== ""
            // A browser tab puts the whole page title in here, so this needs a
            // ceiling or one window pushes every other widget off the bar.
            width: Math.min(implicitWidth, root.maxWidth)
            elide: Text.ElideRight
            text: root.title
            color: Color.foreground
            opacity: 0.75
            font.family: Style.font.family
            font.pixelSize: Style.font.body
        }
    }
}
