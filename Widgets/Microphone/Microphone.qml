import QtQuick
import Quickshell
import qs.Services
import qs.Components
import qs.Commons
import qs.Ui

// Mute state for the default source, and the volume on the wheel.
//
// No panel of its own. Picking an input device already lives in the control
// centre, and a second copy of that list is a second thing to keep right.
//
// BarIconButton's icon canvas is a fixed square centred in its slot, with no
// room for a second element beside it once the slot widens for the
// percentage text. A plain WidgetButton with its own icon+text Row gets the
// same interactive chrome — hover, press, wheel, tooltip — without that
// constraint.
BarWidget {
    id: root
    moduleName: "qsbar.microphone"

    property var cfg: ({})

    readonly property bool showVolume: cfg.showVolume === true
    readonly property string volumeText: root.showVolume && !Audio.micMuted ? Math.round(Audio.micVolume * 100) + "%" : ""

    visible: Audio.source !== null
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        labelVisible: false
        hasVisualContent: true
        // Muted reads as urgent rather than dimmed. A hot mic you believe is
        // off is the expensive mistake here, not the other way round.
        active: Audio.micMuted
        tooltipText: Audio.micMuted ? "Microphone muted" : "Microphone live"
        implicitWidth: content.implicitWidth + Style.spacing.lg * 2

        onPressed: b => {
            if (b === Qt.RightButton) {
                if (cfg.onRightClick && root.bar)
                    root.bar.run(cfg.onRightClick);
                return;
            }
            Audio.toggleMicMute();
        }

        onWheelMoved: delta => {
            const step = delta > 0 ? 0.05 : -0.05;
            Audio.setMicVolume(Audio.micVolume + step);
        }

        Row {
            id: content
            anchors.centerIn: parent
            spacing: 4

            BarIcon {
                anchors.verticalCenter: parent.verticalCenter
                iconSource: Icons.microphone(Audio.micMuted)
                size: Style.bar.iconCanvas
                color: button.active ? button.activeColor : button.foreground
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.volumeText !== ""
                text: root.volumeText
                color: button.active ? button.activeColor : button.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
            }
        }
    }
}
