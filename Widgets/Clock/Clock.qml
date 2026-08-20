import QtQuick
import Quickshell
import qs.Services
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "qsbar.clock"

    property var cfg: ({})
    readonly property string format: cfg.format || "ddd dd MMM  HH:mm"

    implicitWidth: label.implicitWidth
    implicitHeight: root.barSize

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: Qt.formatDateTime(clock.date, root.format)
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
    }
}
