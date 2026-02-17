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

    readonly property string baseUrl: "http://127.0.0.1:17842"

    Plasmoid.status: taskCount > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    toolTipMainText: "Jira: " + taskCount + " tasks"
    toolTipSubText: lastUpdate ? "Updated " + lastUpdate : "Loading..."

    // Poll status every 30s
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
                    } catch(e) {}
                }
                fetchTasks();
            }
        };
        xhr.open("POST", baseUrl + "/api/refresh");
        xhr.send();
    }

    function badgeColor() {
        if (taskCount === 0) return "#4CAF50";  // green
        if (taskCount <= 5) return "#FFC107";    // yellow
        return "#F44336";                         // red
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

            PlasmaComponents.Label {
                visible: root.taskModel.length === 0 && root.errorText === ""
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
                visible: root.taskModel.length > 0
                model: root.taskModel
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

                        PlasmaComponents.Label {
                            text: modelData.status
                            Layout.fillWidth: true
                            opacity: 0.6
                            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                        }
                    }

                    onClicked: Qt.openUrlExternally(modelData.url)
                }
            }
        }

        Component.onCompleted: root.fetchTasks()
    }

    onExpandedChanged: {
        if (expanded) {
            fetchTasks();
        }
    }
}
