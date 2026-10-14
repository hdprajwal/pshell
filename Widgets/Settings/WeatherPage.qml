import QtQuick
import qs.Services
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Where the forecast comes from, in what units, and how often. Everything on
// this page is the `weather` block of config.json, which the service reads
// through Config.weather -- so a change here reaches the widget on the next
// binding evaluation and the next fetch, with no restart.
//
// The writes that carry a rule go through Services/Weather.qml's own functions
// rather than Config.set(): `pshell weather setLocation` and this page are two
// ways of asking for the same thing, and the rule that a name clears explicit
// coordinates has to live in one place or the two surfaces will eventually
// disagree about it.
//
// Each section wraps its rows in a Column of its own. FormSection's card sets
// spacing 0, which is right for the kit's controls -- they carry their own
// padding -- and leaves plain Text, TextField and Row flush against each
// other, so those bring their own.
SettingsPage {
    id: page

    title: "Weather"
    subtitle: "Open-Meteo: no API key and no account. Only a bar with the weather widget in it polls on its own; the button below fetches on any bar."

    // The service's own words, on the page that caused them. A geocoding miss
    // names the string that missed, so a name that resolved to nothing says so
    // here rather than only in the bar's panel, which the settings window is
    // probably covering.
    error: Weather.lastError

    readonly property bool fixed: Config.weather.hasCoordinates

    FormSection {
        title: "Place"
        help: "A name, resolved through Open-Meteo's geocoder once and then remembered. Only the name is sent, and only when it changes."

        Column {
            width: parent.width
            spacing: Style.spacing.md

            TextField {
                id: locationField

                width: parent.width
                text: Config.weather.location
                placeholderText: "Bengaluru"

                // editingFinished fires on every focus loss, changed or not,
                // and an unchanged write would cost a config rewrite and a
                // refetch for nothing -- the same guard the wallpaper page's
                // directory field carries. It matters more here: setLocation
                // clears explicit coordinates, so tabbing through this field
                // must not throw away coordinates nobody was editing.
                onEditingFinished: {
                    const next = locationField.text.trim();
                    if (next === Config.weather.location)
                        return;
                    if (next === "") {
                        // Not setLocation(""), which refuses an empty name.
                        // Erasing the label asks for nowhere in particular,
                        // and coordinates already set are then the only thing
                        // left saying where you are -- clearing those too
                        // would leave the widget with no location at all.
                        Config.set("weather.location", "");
                        return;
                    }
                    Weather.setLocation(next);
                }
            }

            // The precedence rule, said on the surface where it bites: with
            // coordinates set, typing a new name here moves the label and not
            // the forecast, and a page that stayed quiet about that would look
            // broken rather than obeyed.
            Text {
                width: parent.width
                visible: page.fixed
                text: "Coordinates below are set, so they decide where the forecast is for. This name is only the label the panel shows."
                color: Commons.Color.muted
                wrapMode: Text.WordWrap
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
            }
        }
    }

    FormSection {
        title: "Exact coordinates"
        help: "Set these and they beat the name above, and the geocoder is never contacted at all. There is more than one Springfield and the geocoder hands back the biggest; this is how you say which one you meant. Round them off if you would rather not hand over your street."

        Column {
            width: parent.width
            spacing: Style.spacing.lg

            Row {
                spacing: Style.spacing.xl

                Column {
                    spacing: Style.spacing.md

                    Text {
                        text: "Latitude"
                        color: Qt.darker(Commons.Color.foreground, 1.4)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }

                    TextField {
                        id: latitudeField

                        width: Style.spacing.numberFieldWidth
                        // Empty, not 0, when there are none: 0 is a real
                        // coordinate in the Gulf of Guinea, which is why
                        // Config's _coord() checks for null before it coerces
                        // rather than after.
                        text: page.fixed ? String(Config.weather.latitude) : ""
                        placeholderText: "12.97"

                        // The validator is this field saying what it will
                        // take, not a second copy of the rule --
                        // Weather.setCoordinates refuses the same range for
                        // the CLI, which never sees this. What it buys is
                        // `acceptableInput` below, so the button is dead until
                        // both halves are a place.
                        validator: DoubleValidator {
                            bottom: -90
                            top: 90
                            decimals: 6
                            notation: DoubleValidator.StandardNotation
                        }
                    }
                }

                Column {
                    spacing: Style.spacing.md

                    Text {
                        text: "Longitude"
                        color: Qt.darker(Commons.Color.foreground, 1.4)
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                    }

                    TextField {
                        id: longitudeField

                        width: Style.spacing.numberFieldWidth
                        text: page.fixed ? String(Config.weather.longitude) : ""
                        placeholderText: "77.59"

                        validator: DoubleValidator {
                            bottom: -180
                            top: 180
                            decimals: 6
                            notation: DoubleValidator.StandardNotation
                        }
                    }
                }
            }

            Row {
                spacing: Style.spacing.md

                Button {
                    id: applyButton

                    text: "Use these coordinates"
                    bordered: true
                    // Both halves or neither, because one of them is not a
                    // place: a latitude on its own leaves hasCoordinates false
                    // and the write would change nothing on screen.
                    enabled: latitudeField.acceptableInput && longitudeField.acceptableInput
                    opacity: applyButton.enabled ? 1 : 0.4
                    onClicked: Weather.setCoordinates(latitudeField.text, longitudeField.text)
                }

                Button {
                    id: clearButton

                    text: "Use the place name"
                    bordered: true
                    enabled: page.fixed
                    opacity: clearButton.enabled ? 1 : 0.4
                    onClicked: {
                        Weather.clearCoordinates();
                        // Emptied by hand, not left to the bindings above:
                        // typing into a TextField breaks its binding, so the
                        // fields would otherwise go on showing the coordinates
                        // that were just thrown away.
                        latitudeField.text = "";
                        longitudeField.text = "";
                    }
                }
            }
        }
    }

    FormSection {
        title: "Units"
        help: "Metric is °C and km/h, imperial is °F and mph. Open-Meteo converts at its end, so changing this refetches rather than rounding what is already on screen."

        ButtonGroup {
            options: [
                {
                    value: "metric",
                    label: "Metric"
                },
                {
                    value: "imperial",
                    label: "Imperial"
                }
            ]
            value: Config.weather.units
            onChanged: v => Config.set("weather.units", v)
        }
    }

    FormSection {
        title: "Refresh"
        help: "Minutes between fetches. Five is the floor -- Open-Meteo is free and unauthenticated, and pointing tight loops at a service like that is how it stops being either. Fifteen is also as fine as the data gets: the forecast model itself moves in fifteen-minute steps."

        // The spinbox range is the config's own clamp, so the page cannot
        // offer a number Config.weather.intervalMin would quietly rewrite. A
        // field that accepted 1 and then behaved like 5 reads as the setting
        // being ignored.
        NumberField {
            label: "Minutes"
            from: 5
            to: 1440
            value: Config.weather.intervalMin
            onModified: v => Config.set("weather.intervalMin", v)
        }
    }

    FormSection {
        title: "Right now"
        help: "What the last fetch came back with. This is where a place you just typed is confirmed -- the settings window is usually sitting on top of the bar that would otherwise show it."

        Column {
            width: parent.width
            spacing: Style.spacing.lg

            Row {
                width: parent.width
                spacing: Style.spacing.md

                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: Weather.summary.icon
                    size: Style.font.iconLarge
                    color: Commons.Color.foreground
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.spacing.xs

                    Text {
                        text: Weather.reading !== null ? Weather.summary.temp + "  " + Weather.summary.label : (Weather.configured ? "Waiting for the first reading" : "No location set")
                        color: Commons.Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                    }

                    // The place the fetch answered for, with the age beside
                    // it. The place is what confirms a setting took --
                    // "Cambridge" against the Cambridge you meant -- and the
                    // age is what says so when the answer has not changed.
                    Text {
                        visible: Weather.reading !== null
                        text: (Weather.place !== "" ? Weather.place : "Nowhere in particular") + " · updated " + Weather.age
                        color: Commons.Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                    }
                }
            }

            Button {
                id: refreshNow

                text: Weather.busy ? "Fetching…" : "Refresh now"
                bordered: true
                // Disabled rather than hidden while a fetch is in flight: the
                // service queues a second request and honours it when the
                // first lands, so clicking again is not free -- and a button
                // that vanished mid-fetch would read as a failure.
                enabled: Weather.configured && !Weather.busy
                opacity: refreshNow.enabled ? 1 : 0.4
                onClicked: Weather.refresh()
            }
        }
    }
}
