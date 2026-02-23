import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.plasma.extras 2.0 as PlasmaExtras
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasma5support as P5Support

PlasmoidItem {
    id: root

    property int taskCount: 0
    property string lastUpdate: ""
    property string errorText: ""
    property var taskModel: []
    property int currentTab: 0
    property var instanceNames: []
    property var instanceCounts: ({})

    // Per-instance state: { id: { issues: [], lastKeys: {}, lastError: "", lastUpdate: "" } }
    property var instanceStates: ({})
    // Per-instance last poll timestamp (ms): { id: number }
    property var instanceLastPoll: ({})

    // Notification support via notify-send
    P5Support.DataSource {
        id: notifier
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            disconnectSource(source)
        }
    }

    function sendNotification(title, body) {
        var cmd = "notify-send '" + title.replace(/'/g, "'\\''") + "' '" + body.replace(/'/g, "'\\''") + "'"
        notifier.connectSource(cmd)
    }

    function parsePollInterval(str) {
        if (!str) return 300000
        var match = str.match(/^(\d+)(s|m|h)$/)
        if (!match) return 300000
        var val = parseInt(match[1])
        switch (match[2]) {
            case "s": return val * 1000
            case "m": return val * 60000
            case "h": return val * 3600000
        }
        return 300000
    }

    function getInstances() {
        var raw = Plasmoid.configuration.instances
        try {
            var list = JSON.parse(raw)
            if (Array.isArray(list)) return list
        } catch(e) {}
        return []
    }

    function fetchInstanceIssues(inst, callback) {
        var isCloud = (inst.jiraEmail || "") !== ""
        var apiPath, authHeader

        if (isCloud) {
            apiPath = "/rest/api/3/search/jql?jql=" + encodeURIComponent(inst.jql || "") + "&fields=summary,status&maxResults=50"
            authHeader = "Basic " + Qt.btoa(inst.jiraEmail + ":" + inst.jiraToken)
        } else {
            apiPath = "/rest/api/2/search?jql=" + encodeURIComponent(inst.jql || "") + "&fields=summary,status&maxResults=50"
            authHeader = "Bearer " + inst.jiraToken
        }

        var url = inst.jiraUrl.replace(/\/+$/, "") + apiPath

        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        callback(null, data.issues || [])
                    } catch(e) {
                        callback("Failed to parse response", [])
                    }
                } else {
                    var errMsg = "HTTP " + xhr.status
                    try {
                        var errData = JSON.parse(xhr.responseText)
                        if (errData.errorMessages && errData.errorMessages.length > 0)
                            errMsg = errData.errorMessages[0]
                    } catch(e) {}
                    callback(errMsg, [])
                }
            }
        }
        xhr.open("GET", url)
        xhr.setRequestHeader("Authorization", authHeader)
        xhr.setRequestHeader("Accept", "application/json")
        xhr.send()
    }

    Timer {
        id: pollTimer
        interval: 10000
        running: true
        repeat: true
        onTriggered: pollAllInstances()
    }

    function pollAllInstances() {
        var list = getInstances()
        var now = Date.now()
        for (var i = 0; i < list.length; i++) {
            var inst = list[i]
            if (!inst.jiraUrl || !inst.jiraToken) continue
            var interval = parsePollInterval(inst.pollInterval)
            var lastPoll = instanceLastPoll[inst.id] || 0
            if (now - lastPoll >= interval) {
                pollInstance(inst)
            }
        }
    }

    function pollInstance(inst) {
        var lp = instanceLastPoll
        lp[inst.id] = Date.now()
        instanceLastPoll = lp

        fetchInstanceIssues(inst, function(err, issues) {
            var states = instanceStates
            var state = states[inst.id] || { issues: [], lastKeys: {}, lastError: "", lastUpdate: "" }

            if (err) {
                state.lastError = err
                state.lastUpdate = Qt.formatTime(new Date(), "HH:mm:ss")
                states[inst.id] = state
                instanceStates = states
                rebuildTaskModel()
                return
            }

            state.lastError = ""
            state.lastUpdate = Qt.formatTime(new Date(), "HH:mm:ss")

            // Detect new issues for notifications
            var currentKeys = {}
            var newIssues = []
            for (var j = 0; j < issues.length; j++) {
                var key = issues[j].key
                currentKeys[key] = true
                if (!state.lastKeys[key] && Object.keys(state.lastKeys).length > 0) {
                    newIssues.push(issues[j])
                }
            }

            state.lastKeys = currentKeys
            state.issues = issues
            states[inst.id] = state
            instanceStates = states

            // Send notifications for new issues
            for (var k = 0; k < newIssues.length; k++) {
                var iss = newIssues[k]
                sendNotification(
                    "[" + (inst.name || "Jira") + "] New: " + iss.key,
                    iss.fields.summary
                )
            }

            rebuildTaskModel()
        })
    }

    function rebuildTaskModel() {
        var list = getInstances()
        var tasks = []
        var names = []
        var counts = {}
        var latestUpdate = ""
        var anyError = ""

        for (var i = 0; i < list.length; i++) {
            var inst = list[i]
            var state = instanceStates[inst.id]
            if (!state) continue

            var instName = inst.name || inst.id
            names.push(instName)
            var instIssues = state.issues || []
            counts[instName] = instIssues.length

            for (var j = 0; j < instIssues.length; j++) {
                var iss = instIssues[j]
                tasks.push({
                    key: iss.key,
                    summary: iss.fields.summary,
                    status: iss.fields.status.name,
                    url: inst.jiraUrl.replace(/\/+$/, "") + "/browse/" + iss.key,
                    instanceName: instName
                })
            }

            if (state.lastUpdate) latestUpdate = state.lastUpdate
            if (state.lastError) anyError = state.lastError
        }

        taskModel = tasks
        taskCount = tasks.length
        instanceNames = names
        instanceCounts = counts
        lastUpdate = latestUpdate
        errorText = anyError
    }

    function triggerRefresh() {
        instanceLastPoll = {}
        pollAllInstances()
    }

    // Clean up stale instances when config changes
    Connections {
        target: Plasmoid.configuration
        function onInstancesChanged() {
            configChangeTimer.restart()
        }
    }

    Timer {
        id: configChangeTimer
        interval: 500
        onTriggered: {
            var list = getInstances()
            var activeIds = {}
            for (var i = 0; i < list.length; i++) {
                activeIds[list[i].id] = true
            }

            // Remove stale instance states
            var states = instanceStates
            var lp = instanceLastPoll
            var changed = false
            for (var id in states) {
                if (!activeIds[id]) {
                    delete states[id]
                    delete lp[id]
                    changed = true
                }
            }
            if (changed) {
                instanceStates = states
                instanceLastPoll = lp
                rebuildTaskModel()
            }

            // Trigger immediate poll for any new/changed instances
            pollAllInstances()
        }
    }

    function filteredTasks() {
        if (currentTab === 0) return taskModel
        var name = instanceNames[currentTab - 1]
        return taskModel.filter(function(t) { return t.instanceName === name })
    }

    function instanceTaskCount(name) {
        return instanceCounts[name] || 0
    }

    function badgeColor() {
        if (taskCount === 0) return "#4CAF50"
        if (taskCount <= 5) return "#FFC107"
        return "#F44336"
    }

    Plasmoid.status: taskCount > 0 ? PlasmaCore.Types.ActiveStatus : PlasmaCore.Types.PassiveStatus

    toolTipMainText: "Jira: " + taskCount + " tasks"
    toolTipSubText: lastUpdate ? "Updated " + lastUpdate : "Loading..."

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

            // "No instances configured" placeholder
            PlasmaComponents.Label {
                visible: root.getInstances().length === 0
                text: "No instances configured.\nRight-click \u2192 Configure to add Jira instances."
                opacity: 0.6
                Layout.fillWidth: true
                Layout.fillHeight: true
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
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
                visible: root.getInstances().length > 0 && root.filteredTasks().length === 0 && root.errorText === ""
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
                            text: modelData.key + " \u2014 " + modelData.summary
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
                                text: modelData.instanceName ? ("\u00b7 " + modelData.instanceName) : ""
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
            root.pollAllInstances()
        }
    }

    onExpandedChanged: {
        if (expanded) {
            triggerRefresh()
        }
    }
}
