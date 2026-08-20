import QtQuick
import Quickshell
import qs.Services
import qs.Components
import qs.Commons

// Mute state for the default source, and the volume on the wheel.
//
// No panel of its own. Picking an input device already lives in the control
// centre, and a second copy of that list is a second thing to keep right.
BarButton {
    id: root

    property var cfg: ({})
    property var bar: null

    readonly property bool showVolume: cfg.showVolume === true

    shown: Audio.source !== null
    iconSource: Icons.microphone(Audio.micMuted)
    // Muted reads as urgent rather than dimmed. A hot mic you believe is off is
    // the expensive mistake here, not the other way round.
    iconColor: Audio.micMuted ? Color.urgent : Color.foreground
    text: root.showVolume && !Audio.micMuted ? Math.round(Audio.micVolume * 100) + "%" : ""

    onClicked: button => {
        if (button === Qt.RightButton) {
            if (cfg.onRightClick && root.bar)
                root.bar.run(cfg.onRightClick);
            return;
        }
        Audio.toggleMicMute();
    }

    onWheel: delta => {
        const step = delta > 0 ? 0.05 : -0.05;
        Audio.setMicVolume(Audio.micVolume + step);
    }
}
