# jira-tray

A lightweight Jira task monitor that lives in your KDE Plasma system tray. It polls your Jira instance for assigned tasks and displays them as a badge widget with a popup list.

## Architecture

```
┌──────────────┐  HTTP/JSON   ┌────────────────┐  REST API   ┌──────────┐
│ Plasma Widget│ ◄──────────► │ jira-tray (Go) │ ◄─────────► │ Jira     │
│ (QML)        │  :17842      │ local server   │             │ Instance │
└──────────────┘              └────────────────┘              └──────────┘
```

- **Go backend** — polls Jira, caches results, sends desktop notifications on new issues
- **QML widget** — connects to the local server, shows a colored badge (green/yellow/red) and a task list popup

## Requirements

- Go 1.22+
- KDE Plasma 6

## Quick Start

```bash
git clone https://github.com/Aladex/jira-tray.git
cd jira-tray
make install
```

Set the required environment variables (e.g. in `~/.config/environment.d/jira-tray.conf`):

```bash
JIRA_URL=https://jira.example.com
JIRA_TOKEN=your-personal-access-token
```

Then add the **Jira Tasks** widget to your panel or system tray.

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `JIRA_URL` | Yes | — | Base URL of your Jira instance |
| `JIRA_TOKEN` | Yes | — | Jira personal access token (Bearer) |
| `JIRA_JQL` | No | `assignee = currentUser() AND status not in (Done, Closed, Resolved)` | JQL filter for tasks |
| `JIRA_POLL_INTERVAL` | No | `5m` | Poll interval (Go duration: `30s`, `2m`, `10m`, etc.) |

## Autostart

`make install` places a `.desktop` file in `~/.config/autostart/`, so the backend starts automatically on login. Make sure your environment variables are set before the session starts (e.g. via `environment.d`).

## Uninstall

```bash
make uninstall
```

## License

MIT
