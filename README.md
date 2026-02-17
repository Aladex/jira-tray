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

Add the **Jira Tasks** widget to your panel or system tray, then right-click it and choose **Configure...** to enter your Jira URL and token.

## Configuration

The widget has a built-in settings page (right-click the widget > Configure). You can set:

- **Jira URL** — base URL of your Jira instance
- **API Token** — personal access token (Bearer)
- **JQL Filter** — custom JQL query
- **Poll Interval** — how often to check for updates (`30s`, `2m`, `10m`, etc.)

Settings are saved to `~/.config/jira-tray/config.json`.

### Environment variables (optional override)

Environment variables take priority over the widget settings. Useful for headless or scripted setups.

| Variable | Default | Description |
|---|---|---|
| `JIRA_URL` | — | Base URL of your Jira instance |
| `JIRA_TOKEN` | — | Jira personal access token (Bearer) |
| `JIRA_JQL` | `assignee = currentUser() AND status not in (Done, Closed, Resolved)` | JQL filter |
| `JIRA_POLL_INTERVAL` | `5m` | Poll interval (Go duration) |

## Autostart

`make install` places a `.desktop` file in `~/.config/autostart/`, so the backend starts automatically on login. Make sure your environment variables are set before the session starts (e.g. via `environment.d`).

## Uninstall

```bash
make uninstall
```

## License

MIT
