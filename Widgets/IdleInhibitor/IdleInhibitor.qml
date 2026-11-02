import QtQuick
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The bar's keep-awake button. Only the view lives here: the state, the
// timer and the overlay surface that holds the actual inhibitor are in
// Services/IdleInhibit.qml, because this widget exists once per monitor and
// per-monitor copies of a whole-session toggle could disagree with each
// other. Every instance reads and drives the same singleton, so the
// indicators on every bar agree, and so does `pshell idle remaining`.
//
// A click opens a panel of durations rather than toggling, the layout of
// vorssaint's Keep Awake: a switch for no limit, then a grid of times. It
// stays a BarIndicator rather than becoming a Panel so it keeps hiding
// itself while off, as the other indicators do; the open/close state a Panel
// would own is the handful of lines below instead.
BarIndicator {
    id: root

    property var cfg: ({})

    // What Panel gives its widgets, kept to what KeyboardPanel calls back.
    property bool opened: false
    property bool popoutSwitchClosing: false
    function open() {
        opened = true;
    }
    function close() {
        opened = false;
        untilOpen = false;
    }
    function toggle() {
        if (opened)
            close();
        else
            open();
    }

    // The clock picker under the grid, shown by the Until chip.
    property bool untilOpen: false

    // Minutes, as IdleInhibit.forMinutes takes them; 0 is no limit and -1
    // the clock picker, matching IdleInhibit.preset.
    readonly property var chips: [
        { label: "15m", minutes: 15 },
        { label: "30m", minutes: 30 },
        { label: "1h", minutes: 60 },
        { label: "2h", minutes: 120 },
        { label: "4h", minutes: 240 },
        { label: "8h", minutes: 480 },
        { label: "∞", minutes: 0 },
        { label: "Until…", minutes: -1 }
    ]

    readonly property string statusText: {
        if (!IdleInhibit.inhibited)
            return "Screen sleeps normally";
        if (!IdleInhibit.timed)
            return "Awake until you turn it off";
        return "Awake until " + IdleInhibit.endsAtText + ", " + IdleInhibit.leftText + " left";
    }

    function chipLit(minutes) {
        if (minutes === -1)
            return root.untilOpen || (IdleInhibit.inhibited && IdleInhibit.preset === -1);
        return IdleInhibit.inhibited && IdleInhibit.preset === minutes;
    }

    function pickChip(minutes) {
        if (minutes === -1) {
            if (IdleInhibit.inhibited && IdleInhibit.preset === -1) {
                IdleInhibit.off();
                return;
            }
            root.untilOpen = !root.untilOpen;
            if (root.untilOpen)
                root.seedClock();
            return;
        }
        root.untilOpen = false;
        if (root.chipLit(minutes))
            IdleInhibit.off();
        else
            IdleInhibit.forMinutes(minutes);
    }

    // The picker opens on an hour from now, rounded up to the quarter, so
    // the common answer is one click on Start.
    function seedClock() {
        const at = new Date(Date.now() + 60 * 60000);
        const minutes = Math.ceil(at.getMinutes() / 15) * 15;
        at.setMinutes(minutes, 0, 0);
        hourField.value = at.getHours();
        minuteField.value = at.getMinutes();
    }

    function startClock() {
        const hh = String(hourField.value).padStart(2, "0");
        const mm = String(minuteField.value).padStart(2, "0");
        IdleInhibit.untilClock(hh + ":" + mm);
        root.untilOpen = false;
    }

    active: IdleInhibit.inhibited
    // Held lit while its own panel is open, or the icon the panel hangs from
    // would fade out from under it the moment the pointer left the bar.
    activeOverride: root.opened ? true : null
    activeTooltipText: IdleInhibit.timed ? "Awake until " + IdleInhibit.endsAtText + ", " + IdleInhibit.leftText + " left" : "Keeping the screen awake"
    inactiveTooltipText: "Keep the screen awake"

    iconSource: Icons.first(IdleInhibit.inhibited ? ["my-caffeine-on-symbolic", "caffeine-cup-full", "preferences-desktop-screensaver-symbolic"] : ["my-caffeine-off-symbolic", "caffeine-cup-empty", "preferences-desktop-screensaver-symbolic"])
    iconColor: IdleInhibit.inhibited ? Commons.Color.accent : Commons.Color.foreground

    onPressed: b => {
        if (b === Qt.LeftButton)
            root.toggle();
    }

    KeyboardPanel {
        id: panel
        anchorItem: root
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(300))
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()

            Column {
                id: column
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.xxl

                Row {
                    spacing: Style.spacing.md

                    PanelSectionHeader {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "KEEP AWAKE"
                    }

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: Glyphs.info
                        size: Math.round(Style.font.caption * 1.2)
                        color: infoHover.hovered ? Commons.Color.popups.text : Commons.Color.muted

                        HoverHandler {
                            id: infoHover
                        }

                        PanelToolTip {
                            visible: infoHover.hovered
                            text: "Click a time to start. Click it again to stop."
                        }
                    }
                }

                // Status and the no-limit switch, on one line.
                Item {
                    width: parent.width
                    implicitHeight: Math.max(status.implicitHeight, noLimitSwitch.implicitHeight)

                    Text {
                        id: status
                        anchors.left: parent.left
                        anchors.right: noLimitSwitch.left
                        anchors.rightMargin: Style.spacing.lg
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.statusText
                        color: Commons.Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        elide: Text.ElideRight
                    }

                    ToggleSwitch {
                        id: noLimitSwitch
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        checked: IdleInhibit.inhibited
                        onToggled: {
                            root.untilOpen = false;
                            IdleInhibit.toggle();
                        }
                    }
                }

                Grid {
                    id: grid
                    width: parent.width
                    columns: 4
                    spacing: Style.spacing.md

                    readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

                    Repeater {
                        model: root.chips

                        Button {
                            required property var modelData

                            width: grid.cellWidth
                            text: modelData.label
                            fontSize: Style.font.bodySmall
                            bordered: true
                            active: root.chipLit(modelData.minutes)
                            onClicked: root.pickChip(modelData.minutes)
                        }
                    }
                }

                // The Until chip's clock: hour, minute, Start. A time already
                // past today means tomorrow, which the service works out.
                Row {
                    id: clockRow
                    visible: root.untilOpen
                    spacing: Style.spacing.md

                    // The two fields share what the colon and Start leave.
                    readonly property real fieldWidth: (column.width - colon.implicitWidth - startButton.implicitWidth - spacing * 3) / 2

                    NumberField {
                        id: hourField
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: 23
                        fieldWidth: clockRow.fieldWidth
                        fontSize: Style.font.bodySmall
                        onModified: v => value = v
                        field.textFromValue: (v, locale) => String(v).padStart(2, "0")
                    }

                    Text {
                        id: colon
                        anchors.verticalCenter: parent.verticalCenter
                        text: ":"
                        color: Commons.Color.popups.text
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }

                    NumberField {
                        id: minuteField
                        anchors.verticalCenter: parent.verticalCenter
                        from: 0
                        to: 59
                        fieldWidth: clockRow.fieldWidth
                        fontSize: Style.font.bodySmall
                        onModified: v => value = v
                        field.textFromValue: (v, locale) => String(v).padStart(2, "0")
                    }

                    Button {
                        id: startButton
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Start"
                        fontSize: Style.font.bodySmall
                        bordered: true
                        onClicked: root.startClock()
                    }
                }
            }
        }
    }
}
