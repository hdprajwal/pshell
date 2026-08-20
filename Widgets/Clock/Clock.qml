import QtQuick
import Quickshell
import qs.Services

Item {
    id: root

    property var cfg: ({})
    readonly property string format: cfg.format || "ddd dd MMM  HH:mm"

    implicitWidth: label.implicitWidth
    implicitHeight: Config.size

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, root.format)
        color: Config.fg
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
    }
}
