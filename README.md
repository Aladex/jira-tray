# jira-tray

A lightweight Jira task monitor that lives in your KDE Plasma system tray. It polls one or more Jira instances for assigned tasks and displays them as a badge widget with a popup list.

## Architecture

```
┌──────────────┐  HTTP/JSON   ┌────────────────┐  REST API   ┌──────────────┐
│ Plasma Widget│ ◄──────────► │ jira-tray (Go) │ ◄─────────► │ Jira Server  │
│ (QML)        │  :17842      │ local server   │             │ Jira Cloud   │
└──────────────┘              └────────────────┘              └──────────────┘
```

- **Go backend** — polls multiple Jira instances, caches results, sends desktop notifications on new issues
- **QML widget** — connects to the local server, shows a colored badge (green/yellow/red) and a task list popup grouped by instance

## Requirements

- Go 1.22+
- KDE Plasma 6

## Quick Start

```bash
git clone https://github.com/Aladex/jira-tray.git
cd jira-tray
make install
```

Add the **Jira Tasks** widget to your panel or system tray, then right-click it and choose **Configure...** to add your Jira instances.

## Configuration

The widget has a built-in settings page (right-click the widget > Configure) that supports multiple Jira instances. For each instance you can set:

- **Name** — display name for the instance
- **Jira URL** — base URL of your Jira instance
- **Email (Cloud)** — your Atlassian account email; leave empty for Server/DC
- **API Token** — personal access token
- **JQL Filter** — custom JQL query
- **Poll Interval** — how often to check for updates (`30s`, `2m`, `10m`, etc.)

### Authentication

Auth type is auto-detected per instance:

| Email field | Auth method | Use case |
|---|---|---|
| Filled | Basic (`email:token`) | Jira Cloud |
| Empty | Bearer (`token`) | Jira Server / Data Center |

### Environment variables (optional override)

Environment variables create a synthetic "Environment" instance that runs alongside widget-configured instances.

| Variable | Default | Description |
|---|---|---|
| `JIRA_URL` | — | Base URL of your Jira instance |
| `JIRA_TOKEN` | — | Jira personal access token |
| `JIRA_EMAIL` | — | Email for Basic auth (Cloud) |
| `JIRA_JQL` | `assignee = currentUser() AND status not in (Done, Closed, Resolved)` | JQL filter |
| `JIRA_POLL_INTERVAL` | `5m` | Poll interval (Go duration) |

### Migration from single-instance config

Old `config.json` files (flat format) are auto-migrated to the new multi-instance format on first load.

## Autostart

`make install` places a `.desktop` file in `~/.config/autostart/`, so the backend starts automatically on login. Make sure your environment variables are set before the session starts (e.g. via `environment.d`).

## Uninstall

```bash
make uninstall
```

## License

MIT
