import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

// The category tree. Two levels, because two is what this shell needs and a
// third would make it a tree view rather than a sidebar.
//
// The model is a plain array literal rather than anything cleverer: it is the
// same list SettingsApp.tabIds flattens, and a JS array is the one shape both
// a Repeater and a filter function already understand.
Item {
    id: sidebar

    implicitWidth: Style.space(220)

    readonly property var categories: [
        {
            id: "network",
            label: "Network",
            icon: "wifi",
            children: [
                {
                    id: "network.status",
                    label: "Status",
                    icon: Glyphs.lan
                },
                {
                    id: "network.wifi",
                    label: "Wi-Fi",
                    icon: "wifi"
                },
                {
                    id: "network.ethernet",
                    label: "Ethernet",
                    icon: Glyphs.ethernet
                },
                {
                    id: "network.vpn",
                    label: "VPN",
                    icon: Glyphs.vpn(true)
                }
            ]
        },
        {
            id: "sep",
            separator: true,
            children: []
        },
        {
            id: "about",
            label: "About",
            icon: Glyphs.info,
            children: []
        }
    ]

    property string filter: ""

    // A leaf matches on its own label or on its category's, so typing
    // "network" keeps all four network pages rather than none of them.
    function matches(category, leaf) {
        if (sidebar.filter === "")
            return true;
        const needle = sidebar.filter.toLowerCase();
        if (String(category.label || "").toLowerCase().indexOf(needle) >= 0)
            return true;
        return String(leaf.label || "").toLowerCase().indexOf(needle) >= 0;
    }

    function categoryVisible(category) {
        if (category.separator === true)
            return sidebar.filter === "";
        if (category.children.length === 0)
            return sidebar.filter === "" || String(category.label || "").toLowerCase().indexOf(sidebar.filter.toLowerCase()) >= 0;
        for (var i = 0; i < category.children.length; i++) {
            if (sidebar.matches(category, category.children[i]))
                return true;
        }
        return false;
    }

    Rectangle {
        anchors.fill: parent
        color: Style.normalFill
    }

    TextField {
        id: filterField
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.spacing.lg
        placeholderText: "Filter"
        onTextChanged: sidebar.filter = text.trim()
    }

    Flickable {
        anchors.top: filterField.bottom
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
                model: sidebar.categories

                Column {
                    id: group

                    required property var modelData

                    width: tree.width
                    spacing: Style.spacing.xxs
                    // Height from state, never from a child's `visible`. See
                    // the trap note in SettingsPage.qml.
                    height: sidebar.categoryVisible(modelData) ? implicitHeight : 0
                    visible: height > 0

                    PanelSeparator {
                        width: parent.width
                        visible: group.modelData.separator === true
                    }

                    // A category with children is a heading you cannot click:
                    // "Network" is not a page, and offering it as one would
                    // mean inventing an overview nobody asked for.
                    PanelSectionHeader {
                        visible: group.modelData.separator !== true && group.modelData.children.length > 0
                        leftPadding: Style.spacing.md
                        topPadding: Style.spacing.md
                        text: group.modelData.label || ""
                    }

                    // A category with no children is itself a leaf. About is
                    // the only one today, and it exists so the shell is
                    // exercised by more than one category rather than being
                    // quietly shaped around Network.
                    SidebarRow {
                        width: parent.width
                        visible: group.modelData.separator !== true && group.modelData.children.length === 0
                        tabId: group.modelData.id || ""
                        label: group.modelData.label || ""
                        icon: group.modelData.icon || ""
                        indented: false
                    }

                    Repeater {
                        model: group.modelData.children

                        SidebarRow {
                            required property var modelData

                            width: tree.width
                            visible: sidebar.matches(group.modelData, modelData)
                            height: visible ? implicitHeight : 0
                            tabId: modelData.id
                            label: modelData.label
                            icon: modelData.icon
                            indented: true
                        }
                    }
                }
            }
        }
    }

    component SidebarRow: BorderSurface {
        id: row

        property string tabId: ""
        property string label: ""
        property string icon: ""
        property bool indented: true

        readonly property bool current: SettingsApp.currentTab === row.tabId
        readonly property bool hot: hover.containsMouse

        implicitHeight: Math.round(Style.font.body * 2.2)
        radius: Style.cornerRadius
        color: row.current ? Style.selectedFill : (row.hot ? Style.hoverFill : "transparent")
        borderSpec: Border.none()

        Row {
            anchors.left: parent.left
            anchors.leftMargin: row.indented ? Style.spacing.xxl : Style.spacing.md
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
