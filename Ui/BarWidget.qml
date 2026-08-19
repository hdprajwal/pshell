import QtQuick
import qs.Commons

// Base type every QML widget extends. Property names match Omarchy's
// qs.Ui.BarWidget, so a widget written for Omarchy works here unchanged.
//
// The host injects three things:
//   bar         the Bar instance (colors, run(), tooltips)
//   moduleName  the widget's id, used to look up settings
//   settings    this widget's inline options from config.json
Item {
    id: root

    property QtObject bar: null
    property string moduleName: ""
    property var settings: ({})

    readonly property bool vertical: bar ? bar.vertical : false
    readonly property int barSize: bar ? bar.barSize : Style.bar.sizeHorizontal

    // Call `method` on every copy of this widget. One bar exists per monitor,
    // so a refresh triggered on one screen has to reach the others.
    function broadcast(method) {
        const items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root];
        for (var i = 0; i < items.length; i++) {
            if (items[i] && typeof items[i][method] === "function")
                items[i][method]();
        }
    }

    // Read one option from this widget's config entry.
    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }
}
