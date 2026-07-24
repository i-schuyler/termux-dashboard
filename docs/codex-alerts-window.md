# Codex Alerts Window

Status: approved implementation contract.

## Purpose

Add a dedicated `Codex Alerts Window` to `termux-dashboard` as a thin control surface for the installed `codex-alert` command from `i-schuyler/crosshost-utils`.

The dashboard owns menu presentation and status summarization only. `crosshost-utils` remains authoritative for the VPS hook, SSH watcher, event schema, deduplication, notification delivery, wake-lock lifecycle, logs, configuration, and privacy behavior.

## Dependency contract

The dashboard must locate an executable `codex-alert` using this order:

1. `TERMUX_DASHBOARD_CODEX_ALERT_COMMAND`, when explicitly set to an executable path.
2. `$HOME/.local/bin/codex-alert`, the canonical `crosshost-utils` install target.
3. `codex-alert` resolved from `PATH`.

The dashboard must never source `codex-alert` configuration or import its implementation. It must execute the command as an argument-safe command path.

When the command is unavailable, the window must remain usable, report the missing dependency clearly, and identify the canonical install source without attempting installation automatically.

## tmux window contract

On fresh session creation, append `Codex Alerts Window` after `Scripts Window`.

When `Aliveness Window` is enabled, the dashboard uses exactly 6 windows in this order:

1. `Aliveness Window`
2. `Current Project Window`
3. `Projects Window`
4. `New Window`
5. `Scripts Window`
6. `Codex Alerts Window`

When `Aliveness Window` is disabled, the dashboard uses exactly 5 windows in this order:

1. `Current Project Window`
2. `Projects Window`
3. `New Window`
4. `Scripts Window`
5. `Codex Alerts Window`

Reattach behavior remains unchanged: preserve the current tmux window and pane state.

The dedicated CLI entry point is:

```text
termux-dashboard --codex-alerts-window
```

The window starts in `$HOME/.local/bin` when that directory exists; otherwise it uses the existing explicit dashboard startup fallback rather than silently falling back to plain `$HOME`.

## Menu contract

The menu loops until `Exit` is selected and exposes these actions in this exact order:

1. `Start`
2. `Start — reliable`
3. `Start for 4 hours`
4. `Stop`
5. `Status`
6. `Send test alert`
7. `Doctor`
8. `View logs`
9. `Exit`

Command mapping:

| Menu action | Command |
|---|---|
| Start | `codex-alert start` |
| Start — reliable | `codex-alert start --reliable` |
| Start for 4 hours | `codex-alert start --for 4h` |
| Stop | `codex-alert stop` |
| Status | dashboard-rendered summary from `codex-alert status --json` |
| Send test alert | `codex-alert test` |
| Doctor | `codex-alert doctor` |
| View logs | `codex-alert logs` |

The dashboard must not add boot startup, automatic watcher startup, widget discovery, charging-only behavior, quiet hours, Samsung edge lighting, or notification actions in this slice.

## Status JSON contract

The window must consume `codex-alert status --json` rather than scraping human-readable output.

Recognized stable fields:

- `state`
- `mode`
- `host`
- `tmux_session`
- `wake_lock`
- `started_at`
- `stop_at`
- `last_event_at`
- `last_notification_at`
- `reconnect_count`
- `last_error`

The compact dashboard summary must show at least:

- state
- mode
- host
- wake-lock state
- timed stop value when present
- last notification value
- reconnect count
- last error when present

Unknown additional JSON fields must be ignored. Missing optional values must render as a safe placeholder such as `never`, `none`, or `not scheduled`.

Malformed JSON, a nonzero status command, or an unavailable JSON parser must produce a concise error without terminating the dashboard session.

## Interaction and failure behavior

- Starting an already-running watcher must defer to `codex-alert` behavior and display its result.
- Stop must defer to `codex-alert` for watcher and wake-lock cleanup.
- Each action must preserve the command exit status long enough to print a concise success/failure result.
- After an action completes, the user must be able to read the output before the menu redraws.
- `View logs` is a bounded one-shot display using `codex-alert logs`; it must not start `logs --follow`.
- Invalid menu input must not exit the window.
- The dashboard must not handle or display prompts, full Codex responses, event spool contents, credentials, private keys, or environment dumps.

## Verification contract

Required repository checks:

```sh
bash tests/lint-shell.sh
bash tests/termux-dashboard-smoke.sh
```

Smoke coverage must include:

- help output includes `--codex-alerts-window` and the new window description;
- exact fresh-session window order with Aliveness enabled and disabled;
- reattach does not force-select the alerts window;
- command resolution precedence;
- all eight menu actions map to the exact approved `codex-alert` arguments;
- status rendering invokes `status --json` and parses stable fields;
- unknown JSON fields do not break rendering;
- malformed JSON and missing command fail safely;
- the control surface does not invoke boot, widget, watcher internals, or `logs --follow`.

Use a stub `codex-alert` executable in isolated test homes. Tests must not require a live VPS, Android notification permission, or the real `crosshost-utils` installation.

## Documentation and downstream boundary

This repo owns:

- dashboard window behavior;
- menu and status UX;
- runtime tests;
- canonical dashboard documentation and changelog.

`termux-shortcuts` owns copying the updated source-of-truth dashboard launcher into `~/.shortcuts/termux-dashboard`. The downstream update must happen only after this repository's implementation PR is validated and merged.
