import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami

PlasmoidItem {
    id: root

    property int taskCount: 0
    property string lastUpdate: ""
    property string errorText: ""
    property var taskModel: []
    property int currentTab: 0  // 0 = All
    property var instanceNames: []

    function filteredTasks() {
        if (currentTab === 0) return taskModel
        var name = instanceNames[currentTab - 1]
        return taskModel.filter(function(t) { return t.instanceName === name })
    }

    function instanceTaskCount(name) {
        return instanceCounts[name] || 0
    }

    property var instanceCounts: ({})

    function updateInstancesFromStatus(data) {
        if (!data.instances) return
        var names = []
        var counts = {}
        for (var i = 0; i < data.instances.length; i++) {
            var inst = data.instances[i]
            names.push(inst.name)
            counts[inst.name] = inst.count
        }
        instanceNames = names
        instanceCounts = counts
    }

    readonly property string baseUrl: "http://127.0.0.1:17842"

    Plasmoid.status: taskCount > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    Connections {
        target: Plasmoid.configuration
        function onInstancesChanged() { pushConfigTimer.restart() }
    }

    Timer {
        id: pushConfigTimer
        interval: 500
        onTriggered: pushConfig()
    }

    function pushConfig() {
        var raw = Plasmoid.configuration.instances
        var list
        try {
            list = JSON.parse(raw)
        } catch(e) {
            return
        }
        if (!Array.isArray(list) || list.length === 0) return

        var xhr = new XMLHttpRequest()
        xhr.open("POST", baseUrl + "/api/instances/sync")
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(list))
    }

    toolTipMainText: "Jira: " + taskCount + " tasks"
    toolTipSubText: lastUpdate ? "Updated " + lastUpdate : "Loading..."

    Timer {
        id: statusTimer
        interval: 30000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: fetchStatus()
    }

    function fetchStatus() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        taskCount = data.count;
                        lastUpdate = data.lastUpdate || "";
                        errorText = data.error || "";
                        updateInstancesFromStatus(data);
                    } catch(e) {}
                }
            }
        };
        xhr.open("GET", baseUrl + "/api/status");
        xhr.send();
    }

    function fetchTasks() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        taskModel = data;
                    } catch(e) {}
                }
            }
        };
        xhr.open("GET", baseUrl + "/api/tasks");
        xhr.send();
    }

    function triggerRefresh() {
        var xhr = new XMLHttpRequest();
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText);
                        taskCount = data.count;
                        lastUpdate = data.lastUpdate || "";
                        errorText = data.error || "";
                        updateInstancesFromStatus(data);
                    } catch(e) {}
                }
                fetchTasks();
            }
        };
        xhr.open("POST", baseUrl + "/api/refresh");
        xhr.send();
    }

    function badgeColor() {
        if (taskCount === 0) return "#4CAF50";
        if (taskCount <= 5) return "#FFC107";
        return "#F44336";
    }

    compactRepresentation: MouseArea {
        id: compactRoot

        Layout.minimumWidth: Kirigami.Units.iconSizes.small
        Layout.minimumHeight: Kirigami.Units.iconSizes.small
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium

        onClicked: root.expanded = !root.expanded

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            radius: width / 2
            color: root.badgeColor()

            PlasmaComponents.Label {
                anchors.centerIn: parent
                text: root.taskCount > 99 ? "99" : root.taskCount.toString()
                font.pixelSize: parent.height * 0.5
                font.bold: true
                color: root.taskCount <= 5 && root.taskCount > 0 ? "#333333" : "white"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 20

        header: PlasmaExtras.PlasmoidHeading {
            RowLayout {
                anchors.fill: parent
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents.Label {
                    text: "Jira: " + root.taskCount + " tasks"
                    font.bold: true
                    Layout.fillWidth: true
                }

                PlasmaComponents.Label {
                    text: root.lastUpdate ? root.lastUpdate : ""
                    opacity: 0.6
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                }

                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    onClicked: root.triggerRefresh()
                    PlasmaComponents.ToolTip { text: "Refresh" }
                }
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            PlasmaComponents.Label {
                visible: root.errorText !== ""
                text: "Error: " + root.errorText
                color: Kirigami.Theme.negativeTextColor
                Layout.fillWidth: true
                Layout.margins: Kirigami.Units.smallSpacing
                wrapMode: Text.Wrap
            }

            PlasmaComponents.TabBar {
                id: tabBar
                visible: root.instanceNames.length > 1
                Layout.fillWidth: true

                PlasmaComponents.TabButton {
                    text: "All (" + root.taskModel.length + ")"
                    checked: root.currentTab === 0
                    onClicked: root.currentTab = 0
                }

                Repeater {
                    model: root.instanceNames
                    PlasmaComponents.TabButton {
                        required property string modelData
                        required property int index
                        text: modelData + " (" + root.instanceTaskCount(modelData) + ")"
                        checked: root.currentTab === index + 1
                        onClicked: root.currentTab = index + 1
                    }
                }
            }

            PlasmaComponents.Label {
                visible: root.filteredTasks().length === 0 && root.errorText === ""
                text: "No tasks"
                opacity: 0.6
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            ListView {
                id: taskList
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.filteredTasks().length > 0
                model: root.filteredTasks()
                clip: true

                delegate: PlasmaComponents.ItemDelegate {
                    width: taskList.width

                    contentItem: ColumnLayout {
                        spacing: 2

                        PlasmaComponents.Label {
                            text: modelData.key + " — " + modelData.summary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }

                        RowLayout {
                            spacing: Kirigami.Units.smallSpacing
                            PlasmaComponents.Label {
                                text: modelData.status
                                opacity: 0.6
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                            PlasmaComponents.Label {
                                visible: root.currentTab === 0 && modelData.instanceName !== undefined
                                text: modelData.instanceName ? ("· " + modelData.instanceName) : ""
                                opacity: 0.4
                                font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                            }
                        }
                    }

                    onClicked: Qt.openUrlExternally(modelData.url)
                }
            }
        }

        Component.onCompleted: {
            root.pushConfig()
            root.fetchTasks()
        }
    }

    onExpandedChanged: {
        if (expanded) {
            fetchTasks();
        }
    }
}
