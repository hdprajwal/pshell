import QtQuick
import qs.Services
// Qualified for the collision this file is one half of: qs.Services exports a
// Weather too -- the singleton -- and a directory's own types win the
// unqualified name, so `Weather` here would mean this widget. The same answer
// Widgets/Notifications gives, for the same reason.
import qs.Services as Services
import qs.Commons
import qs.Ui

// The bar's weather: an icon and a temperature, with the detail behind them.
//
// The view half only. Every fetch, the cache, the refresh timer and the panel's
// wanted-open state live in Services/Weather.qml, because this widget exists
// once per monitor and neither the requests nor the panel may.
//
// No ipcTarget and manageIpc off: pshell.weather is registered by the service,
// which is where refresh/current/setLocation have to live anyway. A second
// handler here would fight it over the same name, once per monitor. The
// lifecycle functions route through the service instead, so the panel opens on
// whichever monitor's widget was clicked and IPC opens it on the focused one.
Panel {
    id: root

    moduleName: "pshell.weather"
    manageIpc: false

    property var cfg: ({})

    // Off by default. A condition in words is four to twelve characters of bar
    // for something the icon already says, and the tooltip says it for free.
    readonly property bool showLabel: cfg.showLabel === true
    readonly property int panelWidth: cfg.panelWidth || Style.space(300)

    readonly property string screenName: bar && bar.screen ? bar.screen.name : ""
    readonly property bool hostsPanel: Services.Weather.panelOpen && Services.Weather.panelScreen === root.screenName

    function open() {
        Services.Weather.openPanel(root.screenName);
    }

    function close() {
        Services.Weather.closePanel();
    }

    function toggle() {
        Services.Weather.togglePanel(root.screenName);
    }

    readonly property var summary: Services.Weather.summary
    readonly property bool waiting: Services.Weather.reading === null

    readonly property string tooltipText: {
        const lines = [];
        if (root.waiting)
            lines.push(Services.Weather.configured ? "Waiting for the first reading" : "No location set");
        else
            lines.push(root.summary.temp + "  " + root.summary.label);
        if (Services.Weather.place !== "")
            lines.push(Services.Weather.place);
        if (!root.waiting)
            lines.push("Updated " + Services.Weather.age);
        if (Services.Weather.lastError !== "")
            lines.push(Services.Weather.lastError);
        return lines.join("\n");
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    BarIconButton {
        id: button

        anchors.fill: parent
        bar: root.bar
        iconName: root.summary.icon
        // A dash, never a zero. Before the first fetch lands there is no
        // temperature, and 0° is a reading somebody could dress for.
        // summarise() answers "—" for that, and the icon beside it is the
        // question mark rather than a sun.
        label: button.vertical ? "" : (root.showLabel ? root.summary.temp + "  " + root.summary.label : root.summary.temp)
        // Two refresh intervals with nothing new. The number on screen is
        // still the truth as of some point in the past, so it stays up and
        // goes quiet rather than being replaced by an error.
        dimmed: Services.Weather.stale
        tooltipText: root.tooltipText

        onPressed: b => {
            if (b === Qt.LeftButton)
                root.toggle();
        }
    }

    KeyboardPanel {
        id: panel

        anchorItem: button
        owner: root
        bar: root.bar
        open: root.hostsPanel
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(root.panelWidth + panel.horizontalContentInset)
        contentHeight: panel.fittedContentHeight(column.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher

            anchors.fill: parent
            onCloseRequested: root.close()
            onTabRequested: direction => root.switchPanel(direction)

            Column {
                id: column

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Style.spacing.xxl

                PanelHero {
                    foreground: Color.popups.text
                    iconComponent: Component {
                        MaterialIcon {
                            name: root.summary.icon
                            size: Style.font.display
                            color: Color.popups.text
                        }
                    }
                    title: root.summary.temp
                    meta: root.summary.label
                    // The pill only appears when the reading has aged out, so
                    // it is a state and not a permanent label.
                    detail: Services.Weather.stale ? "STALE" : ""

                    trailingControl: Component {
                        PanelActionButton {
                            foreground: Color.popups.text
                            tooltipText: "Refresh"
                            onClicked: Services.Weather.refresh()

                            MaterialIcon {
                                anchors.centerIn: parent
                                name: Glyphs.refresh
                                size: Style.font.icon
                                color: Services.Weather.busy ? Color.accent : Color.muted
                            }
                        }
                    }
                }

                // Where and when, on one line under the hero. The age is the
                // half that matters on a dropped network: a temperature with
                // no age on it is a claim about right now.
                Row {
                    width: parent.width
                    spacing: Style.spacing.sm

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: Glyphs.place
                        size: Style.font.caption
                        color: Color.muted
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: column.width - Style.font.caption - Style.spacing.sm
                        elide: Text.ElideRight
                        text: {
                            const where = Services.Weather.place !== "" ? Services.Weather.place : "Nowhere in particular";
                            return root.waiting ? where : where + " · updated " + Services.Weather.age;
                        }
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }

                PanelSeparator {
                    foreground: Color.popups.text
                }

                // Feels like, humidity, wind. Three rows rather than three
                // columns: the values are short but the labels are not, and a
                // three-column layout would either elide them or set the panel
                // width from the longest word in it.
                Column {
                    width: parent.width
                    spacing: Style.spacing.md

                    Repeater {
                        model: [
                            {
                                icon: Glyphs.thermostat,
                                label: "Feels like",
                                value: root.summary.feels
                            },
                            {
                                icon: Glyphs.humidity,
                                label: "Humidity",
                                value: root.summary.humidity
                            },
                            {
                                icon: Glyphs.wind,
                                label: "Wind",
                                value: root.summary.wind
                            }
                        ]

                        Row {
                            id: statRow

                            required property var modelData

                            width: column.width
                            spacing: Style.spacing.md

                            MaterialIcon {
                                id: statIcon

                                anchors.verticalCenter: parent.verticalCenter
                                name: statRow.modelData.icon
                                size: Style.font.icon
                                color: Color.muted
                            }

                            Text {
                                id: statLabel

                                anchors.verticalCenter: parent.verticalCenter
                                text: statRow.modelData.label
                                color: Color.popups.text
                                opacity: 0.75
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                            }

                            // The value is pushed to the trailing edge, so
                            // three rows of different label lengths still line
                            // their numbers up.
                            Item {
                                height: 1
                                width: Math.max(0, statRow.width - statRow.spacing * 3 - statIcon.width - statLabel.width - statValue.width)
                            }

                            Text {
                                id: statValue

                                anchors.verticalCenter: parent.verticalCenter
                                text: statRow.modelData.value
                                color: Color.popups.text
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                                font.bold: true
                            }
                        }
                    }
                }

                PanelSeparator {
                    foreground: Color.popups.text
                }

                // The three days Open-Meteo was asked for. Today is one of
                // them and is named "Today" by its date rather than by its
                // index, so a cache served after midnight does not call
                // yesterday today.
                Column {
                    width: parent.width
                    spacing: Style.spacing.lg
                    visible: Services.Weather.strip.length > 0

                    PanelSectionHeader {
                        text: "Next days"
                        foreground: Color.popups.text
                    }

                    Row {
                        width: parent.width

                        Repeater {
                            model: Services.Weather.strip

                            Column {
                                required property var modelData

                                width: column.width / Math.max(1, Services.Weather.strip.length)
                                spacing: Style.spacing.sm

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.name
                                    color: Color.popups.text
                                    opacity: 0.75
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.caption
                                    font.bold: true
                                }

                                MaterialIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: modelData.icon
                                    size: Style.font.iconLarge
                                    color: Color.popups.text
                                }

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.high
                                    color: Color.popups.text
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.low
                                    color: Color.muted
                                    font.family: Style.font.family
                                    font.pixelSize: Style.font.bodySmall
                                }
                            }
                        }
                    }
                }

                // Whatever went wrong last, in front of the user rather than
                // in the shell's log. A geocoding miss names the string that
                // missed, so "No such place: “Bengalru”" is a typo you can
                // see rather than a network you go looking at.
                Text {
                    visible: Services.Weather.lastError !== ""
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: Services.Weather.lastError
                    color: Color.urgent
                    font.family: Style.font.family
                    font.pixelSize: Style.font.caption
                }
            }
        }
    }
}
