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
    property int currentTab: 0  // 0 = All
    property var instanceNames: []

    // Backend auto-install state
    // States: "checking", "connected", "not_running", "not_installed",
    //         "installing", "starting", "error"
    property string backendState: "checking"
    property string backendError: ""
    property string detectedArch: ""
    property string latestVersion: ""
    property int startPollCount: 0

    readonly property string backendBin: "~/.local/bin/jira-tray"
    readonly property string githubRepo: "Aladex/jira-tray"

    P5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            var stdout = data["stdout"] || ""
            var stderr = data["stderr"] || ""
            var exitCode = data["exit code"] || 0
            disconnectSource(source)
            if (source.indexOf("#__checkbin__") !== -1) {
                handleCheckBinResult(exitCode)
            } else if (source.indexOf("#__uname__") !== -1) {
                handleUnameResult(stdout.trim())
            } else if (source.indexOf("#__install__") !== -1) {
                handleInstallResult(exitCode, stderr)
            } else if (source.indexOf("#__start__") !== -1) {
                handleStartResult(exitCode, stderr)
            }
        }
    }

    function execCmd(tag, cmd) {
        var source = cmd + " #" + tag + "_" + Date.now()
        executable.connectSource(source)
    }

    // --- State machine transitions ---

    function beginBackendCheck() {
        backendState = "checking"
        backendError = ""
        fetchStatusForCheck()
    }

    function fetchStatusForCheck() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    backendState = "connected"
                    try {
                        var data = JSON.parse(xhr.responseText)
                        taskCount = data.count
                        lastUpdate = data.lastUpdate || ""
                        errorText = data.error || ""
                        updateInstancesFromStatus(data)
                    } catch(e) {}
                } else {
                    checkBackendInstalled()
                }
            }
        }
        xhr.open("GET", baseUrl + "/api/status")
        xhr.send()
    }

    function checkBackendInstalled() {
        execCmd("__checkbin__", "test -x " + backendBin.replace("~", "$HOME"))
    }

    function handleCheckBinResult(exitCode) {
        if (exitCode === 0) {
            backendState = "not_running"
            startBackend()
        } else {
            backendState = "not_installed"
            detectArch()
        }
    }

    function detectArch() {
        execCmd("__uname__", "uname -m")
    }

    function handleUnameResult(arch) {
        if (arch === "x86_64") {
            detectedArch = "amd64"
        } else if (arch === "aarch64" || arch === "arm64") {
            detectedArch = "arm64"
        } else {
            detectedArch = arch
        }
        fetchLatestVersion()
    }

    function fetchLatestVersion() {
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        latestVersion = data.tag_name || ""
                    } catch(e) {
                        backendState = "error"
                        backendError = "Failed to parse GitHub response"
                    }
                } else {
                    backendState = "error"
                    backendError = "Failed to fetch latest version (HTTP " + xhr.status + ")"
                }
            }
        }
        xhr.open("GET", "https://api.github.com/repos/" + githubRepo + "/releases/latest")
        xhr.send()
    }

    function downloadAndInstall() {
        backendState = "installing"
        backendError = ""
        var ver = latestVersion
        var tarball = "jira-tray-" + ver + "-linux-" + detectedArch + ".tar.gz"
        var url = "https://github.com/" + githubRepo + "/releases/download/" + ver + "/" + tarball
        var cmd = "set -e && " +
            "mkdir -p ~/.local/bin && " +
            "cd $(mktemp -d) && " +
            "curl -fsSL -o release.tar.gz '" + url + "' && " +
            "tar xzf release.tar.gz --strip-components=1 && " +
            "chmod +x jira-tray && " +
            "mv jira-tray ~/.local/bin/jira-tray && " +
            "mkdir -p ~/.config/autostart && " +
            "printf '[Desktop Entry]\\nType=Application\\nName=Jira Tray\\nComment=Jira task monitor for KDE Plasma system tray\\nExec=%s/.local/bin/jira-tray\\nTerminal=false\\nCategories=Utility;\\nX-KDE-autostart-phase=2\\n' \"$HOME\" > ~/.config/autostart/jira-tray.desktop"
        execCmd("__install__", cmd)
    }

    function handleInstallResult(exitCode, stderr) {
        if (exitCode === 0) {
            startBackend()
        } else {
            backendState = "error"
            backendError = "Install failed: " + stderr.split("\n")[0]
        }
    }

    function startBackend() {
        backendState = "starting"
        startPollCount = 0
        execCmd("__start__", "nohup ~/.local/bin/jira-tray > /dev/null 2>&1 & echo $!")
    }

    function handleStartResult(exitCode, stderr) {
        if (exitCode !== 0) {
            backendState = "error"
            backendError = "Failed to start backend"
            return
        }
        startPollTimer.start()
    }

    Timer {
        id: startPollTimer
        interval: 2000
        repeat: true
        onTriggered: {
            startPollCount++
            if (startPollCount > 15) {
                startPollTimer.stop()
                backendState = "error"
                backendError = "Backend started but not responding after 30s"
                return
            }
            var xhr = new XMLHttpRequest()
            xhr.onreadystatechange = function() {
                if (xhr.readyState === XMLHttpRequest.DONE) {
                    if (xhr.status === 200) {
                        startPollTimer.stop()
                        backendState = "connected"
                        try {
                            var data = JSON.parse(xhr.responseText)
                            taskCount = data.count
                            lastUpdate = data.lastUpdate || ""
                            errorText = data.error || ""
                            updateInstancesFromStatus(data)
                        } catch(e) {}
                        fetchTasks()
                    }
                }
            }
            xhr.open("GET", baseUrl + "/api/status")
            xhr.send()
        }
    }

    // --- End auto-install ---

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
        running: backendState === "connected"
        repeat: true
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
                } else {
                    beginBackendCheck()
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
        if (backendState !== "connected") return "#9E9E9E"
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
                text: root.backendState !== "connected" ? "?" : (root.taskCount > 99 ? "99" : root.taskCount.toString())
                font.pixelSize: parent.height * 0.5
                font.bold: true
                color: root.backendState !== "connected" ? "white" : (root.taskCount <= 5 && root.taskCount > 0 ? "#333333" : "white")
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
            visible: root.backendState === "connected"
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

        // --- Install / setup UI ---
        ColumnLayout {
            anchors.centerIn: parent
            visible: root.backendState !== "connected"
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                source: root.backendState === "error" ? "dialog-error" : "download"
                Layout.preferredWidth: Kirigami.Units.iconSizes.huge
                Layout.preferredHeight: Kirigami.Units.iconSizes.huge
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents.Label {
                text: {
                    switch (root.backendState) {
                        case "checking": return "Checking backend..."
                        case "not_running": return "Starting backend..."
                        case "not_installed": return "Backend not installed"
                        case "installing": return "Installing backend..."
                        case "starting": return "Starting backend..."
                        case "error": return "Error"
                        default: return ""
                    }
                }
                font.bold: true
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents.Label {
                visible: root.backendState === "not_installed" && root.latestVersion !== ""
                text: root.latestVersion + " / linux-" + root.detectedArch
                opacity: 0.6
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents.Label {
                visible: root.backendState === "error" && root.backendError !== ""
                text: root.backendError
                color: Kirigami.Theme.negativeTextColor
                wrapMode: Text.Wrap
                Layout.maximumWidth: Kirigami.Units.gridUnit * 16
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
            }

            PlasmaComponents.BusyIndicator {
                visible: root.backendState === "checking" || root.backendState === "installing" || root.backendState === "starting"
                running: visible
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents.Button {
                visible: root.backendState === "not_installed" && root.latestVersion !== ""
                text: "Install Backend"
                icon.name: "download"
                Layout.alignment: Qt.AlignHCenter
                onClicked: root.downloadAndInstall()
            }

            PlasmaComponents.Button {
                visible: root.backendState === "error"
                text: "Retry"
                icon.name: "view-refresh"
                Layout.alignment: Qt.AlignHCenter
                onClicked: root.beginBackendCheck()
            }
        }

        // --- Normal task UI ---
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            visible: root.backendState === "connected"

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
            root.beginBackendCheck()
        }
    }

    onExpandedChanged: {
        if (expanded) {
            if (backendState === "connected") {
                fetchTasks()
            }
        }
    }
}
