import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

// The shell every settings page sits in: a title, an error banner and a
// scrolling column. A page declares its sections as children and never thinks
// about the Flickable.
//
// The banner's height comes from `error !== ""` and never from the banner
// child's `visible`. QML inherits `visible` down the tree, so a container
// sized from a child's visibility drives its own input -- the same trap
// Components/Section.qml records for bar slots, and it bites the same way
// here.
Item {
    id: page

    property string title: ""
    property string subtitle: ""
    property string error: ""

    default property alias content: column.children

    Column {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.xs

        Text {
            text: page.title
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
        }

        Text {
            width: parent.width
            visible: page.subtitle !== ""
            text: page.subtitle
            color: Color.muted
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }
    }

    // nmcli's own words, verbatim, on the surface that caused them. Never a
    // modal: a failed save is information, not an interruption, and a dialog
    // over the field you were editing hides the thing you need to fix.
    BorderSurface {
        id: banner
        anchors.top: header.bottom
        anchors.topMargin: page.error !== "" ? Style.spacing.md : 0
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.panelPadding
        anchors.rightMargin: Style.spacing.panelPadding
        height: page.error !== "" ? errorText.implicitHeight + Style.spacing.xxl : 0
        clip: true
        radius: Style.cornerRadius
        color: Util.alpha(Color.urgent, 0.12)
        borderSpec: Border.none()

        Text {
            id: errorText
            anchors.fill: parent
            anchors.margins: Style.spacing.lg
            text: page.error
            color: Color.urgent
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
        }
    }

    Flickable {
        anchors.top: banner.bottom
        anchors.topMargin: Style.spacing.xxl
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.spacing.panelPadding
        anchors.rightMargin: Style.spacing.panelPadding
        anchors.bottomMargin: Style.spacing.panelPadding
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: column
            width: parent.width
            spacing: Style.spacing.xxl
        }
    }
}
