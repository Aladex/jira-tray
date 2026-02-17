import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    property alias cfg_jiraUrl: jiraUrlField.text
    property alias cfg_jiraToken: jiraTokenField.text
    property alias cfg_jiraJql: jqlField.text
    property alias cfg_pollInterval: pollIntervalField.text

    QQC2.TextField {
        id: jiraUrlField
        Kirigami.FormData.label: "Jira URL:"
        placeholderText: "https://jira.example.com"
    }

    QQC2.TextField {
        id: jiraTokenField
        Kirigami.FormData.label: "API Token:"
        echoMode: TextInput.Password
        placeholderText: "Personal access token"
    }

    QQC2.TextField {
        id: jqlField
        Kirigami.FormData.label: "JQL Filter:"
        placeholderText: "assignee = currentUser() AND status not in (Done, Closed, Resolved)"
    }

    QQC2.TextField {
        id: pollIntervalField
        Kirigami.FormData.label: "Poll Interval:"
        placeholderText: "5m"
    }

    QQC2.Label {
        text: "Examples: 30s, 2m, 10m"
        opacity: 0.6
        font: Kirigami.Theme.smallFont
    }
}
