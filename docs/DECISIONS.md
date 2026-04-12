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
