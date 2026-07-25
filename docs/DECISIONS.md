# Dashboard Decisions

This file tracks curated, dashboard-only decisions for this repo.

## Locked decisions

### D-001 — Source of truth lives here

- Status: Locked
- Decision: `termux-dashboard` is the source-of-truth repo for dashboard runtime behavior, tests, and docs.
- Consequence: Changes to dashboard behavior should be designed and validated here first.

### D-002 — Verification defaults use repo tests

- Status: Locked
- Decision: `tests/*.sh` are the default verification path.
- Required commands:
  - `bash tests/lint-shell.sh`
  - `bash tests/termux-dashboard-smoke.sh`
- Consequence: Avoid ad hoc verification claims when these tests apply.

### D-003 — Tmux pane outcomes are authoritative

- Status: Locked
- Decision: Pane/cwd behavior is verified by tmux-observed outcomes (`#{pane_current_path}` and pane content).
- Consequence: Internal script cwd assumptions are not sufficient evidence for pane/cwd correctness.

### D-004 — Script path remains stable

- Status: Locked
- Decision: Dashboard entrypoint path remains `scripts/termux-dashboard`.
- Consequence: Docs, tests, and CI should continue referencing this path.

### D-005 — Downstream integration boundary

- Status: Locked
- Decision: Installer and downstream integration belong in `termux-shortcuts`, not in this repo.
- Consequence: This repo stays scoped to dashboard product behavior and validation.

### D-006 — State/config file naming convention

- Status: Locked
- Decision: Only pinned user-editable config files use `.txt` (`pinned-projects.txt`, `pinned-scripts.txt`).
- Decision: Recent and last-selected internal state files are extensionless (`recent_projects`, `recent_scripts`, `last_project`, `last_script`).
- Decision: Pinned files are user-editable config; recent/last files are internal runtime state.
- Consequence: Docs and help output should preserve this distinction and avoid implying `.txt` on recent state files.
- Follow-up note: if legacy `recent_projects.txt` or `recent_scripts.txt` files are encountered in user environments, runtime compatibility handling should be addressed in a later runtime slice.

### D-007 — Codex alerts remain a thin external control surface

- Status: Locked
- Decision: `termux-dashboard` may present a dedicated Codex alerts window, but it must invoke the installed `codex-alert` command and consume `codex-alert status --json` rather than copying watcher, SSH, notification, deduplication, wake-lock, configuration, or privacy logic.
- Decision: The canonical `codex-alert` implementation remains owned by `i-schuyler/crosshost-utils`.
- Consequence: Dashboard tests use a stub command and do not require a live VPS or Android notification transport.
- Consequence: Installation and shortcut propagation remain downstream responsibilities of `termux-shortcuts`.

### D-008 — Heartloom Site window remains a thin external control surface

- Status: Locked direction; runtime implementation pending
- Decision: `termux-dashboard` should provide a dedicated **Heartloom Site** window for Schuyler's website authoring and publishing workflow.
- Decision: The dashboard must invoke the installed external `heartloom-site` command rather than copying repository sync, Obsidian reconciliation, preview, Git, pull-request, CI, merge, deployment, rollback, or smoke-check logic.
- Decision: The canonical `heartloom-site` implementation and its content/status contracts remain owned by `i-schuyler/heartloom-website`.
- Decision: The dashboard should consume a stable machine-readable status and progress-event interface while rendering friendly human-facing progress.
- Decision: Installation and shortcut propagation remain downstream responsibilities of `i-schuyler/termux-shortcuts`.
- Required initial actions:
  - Sync current website copy
  - Preview changes
  - Publish changes
  - Show status
  - Exit or return to the dashboard
- Required progress behavior:
  - show each active phase, such as syncing, validating, building, preparing a pull request, waiting for CI, merging, deploying, smoke-checking, and syncing the merged copy back to Obsidian;
  - provide heartbeat or elapsed-time feedback during long-running phases;
  - show failure phase, production-modification state, rollback state, and next safe action;
  - show final live links after success.
- Consequence: Dashboard tests should use a stub `heartloom-site` command and synthetic event/status output; they must not require a live vault, GitHub mutation, VPS, production deployment, or network service.
- Consequence: The Heartloom Site window should not be implemented until the external command contract is documented and stable enough to test against.
