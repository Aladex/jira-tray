import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property string cfg_instances

    property var instanceList: []

    Component.onCompleted: {
        try {
            instanceList = JSON.parse(cfg_instances)
        } catch(e) {
            instanceList = []
        }
        if (instanceList.length > 0) {
            loadInstance(0)
        }
    }

    onCfg_instancesChanged: {
        try {
            instanceList = JSON.parse(cfg_instances)
        } catch(e) {
            instanceList = []
        }
    }

    property int selectedIndex: -1

    function generateId() {
        var chars = "0123456789abcdef"
        var id = ""
        for (var i = 0; i < 8; i++) {
            id += chars.charAt(Math.floor(Math.random() * chars.length))
        }
        return id
    }

    function saveList() {
        cfg_instances = JSON.stringify(instanceList)
    }

    function loadInstance(index) {
        if (index < 0 || index >= instanceList.length) {
            selectedIndex = -1
            nameField.text = ""
            urlField.text = ""
            emailField.text = ""
            tokenField.text = ""
            jqlField.text = ""
            pollField.text = ""
            return
        }
        selectedIndex = index
        var inst = instanceList[index]
        nameField.text = inst.name || ""
        urlField.text = inst.jiraUrl || ""
        emailField.text = inst.jiraEmail || ""
        tokenField.text = inst.jiraToken || ""
        jqlField.text = inst.jql || ""
        pollField.text = inst.pollInterval || "5m"
    }

    function saveCurrentInstance() {
        if (selectedIndex < 0 || selectedIndex >= instanceList.length) return
        var inst = instanceList[selectedIndex]
        inst.name = nameField.text
        inst.jiraUrl = urlField.text
        inst.jiraEmail = emailField.text
        inst.jiraToken = tokenField.text
        inst.jql = jqlField.text
        inst.pollInterval = pollField.text
        instanceList[selectedIndex] = inst
        saveList()
    }

    // --- Instance list ---
    QQC2.Label {
        text: "Instances"
        font.bold: true
        Kirigami.FormData.isSection: true
    }

    ColumnLayout {
        Kirigami.FormData.label: " "
        spacing: Kirigami.Units.smallSpacing

        Repeater {
            id: listRepeater
            model: instanceList.length

            QQC2.ItemDelegate {
                Layout.fillWidth: true
                highlighted: page.selectedIndex === index
                contentItem: QQC2.Label {
                    text: (instanceList[index].name || "(unnamed)") + (instanceList[index].jiraUrl ? ("  —  " + instanceList[index].jiraUrl) : "")
                    elide: Text.ElideRight
                }
                onClicked: {
                    saveCurrentInstance()
                    page.selectedIndex = index
                    loadInstance(index)
                }
            }
        }

        RowLayout {
            spacing: Kirigami.Units.smallSpacing

            QQC2.Button {
                text: "Add"
                icon.name: "list-add"
                onClicked: {
                    saveCurrentInstance()
                    var newInst = {
                        id: generateId(),
                        name: "New Instance",
                        jiraUrl: "",
                        jiraToken: "",
                        jiraEmail: "",
                        jql: "assignee = currentUser() AND status not in (Done, Closed, Resolved)",
                        pollInterval: "5m"
                    }
                    instanceList.push(newInst)
                    saveList()
                    loadInstance(instanceList.length - 1)
                }
            }

            QQC2.Button {
                text: "Remove"
                icon.name: "list-remove"
                enabled: selectedIndex >= 0
                onClicked: {
                    if (selectedIndex < 0) return
                    instanceList.splice(selectedIndex, 1)
                    saveList()
                    if (instanceList.length > 0) {
                        var newIdx = Math.min(selectedIndex, instanceList.length - 1)
                        loadInstance(newIdx)
                    } else {
                        loadInstance(-1)
                    }
                }
            }
        }
    }

    // --- Edit form ---
    Kirigami.Separator {
        Kirigami.FormData.isSection: true
        Kirigami.FormData.label: selectedIndex >= 0 ? "Edit Instance" : "Select an instance"
    }

    QQC2.TextField {
        id: nameField
        Kirigami.FormData.label: "Name:"
        placeholderText: "My Jira"
        enabled: selectedIndex >= 0
        onTextEdited: saveCurrentInstance()
    }

    QQC2.TextField {
        id: urlField
        Kirigami.FormData.label: "Jira URL:"
        placeholderText: "https://jira.example.com"
        enabled: selectedIndex >= 0
        onTextEdited: saveCurrentInstance()
    }

    QQC2.TextField {
        id: emailField
        Kirigami.FormData.label: "Email (Cloud):"
        placeholderText: "user@example.com (leave empty for Server/DC)"
        enabled: selectedIndex >= 0
        onTextEdited: saveCurrentInstance()
    }

    QQC2.Label {
        visible: selectedIndex >= 0
        text: emailField.text ? "Auth: Basic (Cloud)" : "Auth: Bearer (Server/DC)"
        opacity: 0.7
        font: Kirigami.Theme.smallFont
    }

    QQC2.TextField {
        id: tokenField
        Kirigami.FormData.label: "API Token:"
        echoMode: TextInput.Password
        placeholderText: "Personal access token"
        enabled: selectedIndex >= 0
        onTextEdited: saveCurrentInstance()
    }

    QQC2.TextField {
        id: jqlField
        Kirigami.FormData.label: "JQL Filter:"
        placeholderText: "assignee = currentUser() AND status not in (Done, Closed, Resolved)"
        enabled: selectedIndex >= 0
        onTextEdited: saveCurrentInstance()
    }

    QQC2.TextField {
        id: pollField
        Kirigami.FormData.label: "Poll Interval:"
        placeholderText: "5m"
        enabled: selectedIndex >= 0
        onTextEdited: saveCurrentInstance()
    }

    QQC2.Label {
        text: "Examples: 30s, 2m, 10m"
        opacity: 0.6
        font: Kirigami.Theme.smallFont
    }
}
