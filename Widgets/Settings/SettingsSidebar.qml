import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

// The page list. One level and no filter field: both existed to hold the four
// network pages, and neither earns its keep over a single row.
//
// The model is a plain array literal rather than anything cleverer: it is the
// same list SettingsApp.tabIds holds, and a JS array is the one shape a
// Repeater already understands.
Item {
    id: sidebar

    implicitWidth: Style.space(220)

    readonly property var pages: [
        {
            id: "about",
            label: "About",
            icon: Glyphs.info
        }
    ]

    Rectangle {
        anchors.fill: parent
        color: Style.normalFill
    }

    Flickable {
        anchors.top: parent.top
        anchors.topMargin: Style.spacing.lg
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.spacing.sm
        anchors.rightMargin: Style.spacing.sm
        anchors.bottomMargin: Style.spacing.lg
        contentWidth: width
        contentHeight: tree.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: tree
            width: parent.width
            spacing: Style.spacing.xxs

            Repeater {
                model: sidebar.pages

                SidebarRow {
                    required property var modelData

                    width: tree.width
                    tabId: modelData.id
                    label: modelData.label
                    icon: modelData.icon
                }
            }
        }
    }

    component SidebarRow: BorderSurface {
        id: row

        property string tabId: ""
        property string label: ""
        property string icon: ""

        readonly property bool current: SettingsApp.currentTab === row.tabId
        readonly property bool hot: hover.containsMouse

        implicitHeight: Math.round(Style.font.body * 2.2)
        radius: Style.cornerRadius
        color: row.current ? Style.selectedFill : (row.hot ? Style.hoverFill : "transparent")
        borderSpec: Border.none()

        Row {
            anchors.left: parent.left
            anchors.leftMargin: Style.spacing.md
            anchors.right: parent.right
            anchors.rightMargin: Style.spacing.md
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.spacing.md

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: row.icon
                filled: row.current
                size: Math.round(Style.font.body * 1.1)
                color: row.current ? Color.accent : Color.foreground
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: row.label
                color: row.current ? Color.accent : Color.foreground
                elide: Text.ElideRight
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
        }

        MouseArea {
            id: hover
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: SettingsApp.setTab(row.tabId)
        }
    }
}
