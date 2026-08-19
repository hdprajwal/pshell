import QtQuick

Row {
    id: root

    property var entries: []

    spacing: Config.gap
    height: Config.size

    Repeater {
        model: root.entries

        Loader {
            required property var modelData

            sourceComponent: {
                switch (modelData.type) {
                case "clock":
                    return clockComponent;
                case "workspaces":
                    return workspacesComponent;
                default:
                    return procComponent;
                }
            }
            onLoaded: if (item)
                item.cfg = modelData
        }
    }

    Component {
        id: clockComponent
        Clock {}
    }
    Component {
        id: workspacesComponent
        Workspaces {}
    }
    Component {
        id: procComponent
        ProcWidget {}
    }
}
