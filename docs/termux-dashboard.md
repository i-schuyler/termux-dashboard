# termux-dashboard (Canonical Anchor)

Status: docs anchor only for later implementation slices.

## Shortcut identity

- Exact shortcut name: `termux-dashboard`
- Source-of-truth repo: `termux-dashboard`
- Downstream installer/integration repo: `termux-shortcuts`
- Installer requirement (later slice): install to `~/.shortcuts/termux-dashboard`
- Product role: `termux-dashboard` is the primary entry point.

## tmux window contract

When `Aliveness Window` is enabled, the dashboard session uses exactly 5 windows in this exact order:

1. `Aliveness Window`
2. `Current Project Window`
3. `Projects Window`
4. `New Window`
5. `Scripts Window`

When `Aliveness Window` is disabled, the dashboard session uses exactly 4 windows in this exact order:

1. `Current Project Window`
2. `Projects Window`
3. `New Window`
4. `Scripts Window`

`Aliveness Window` is shown first on fresh session creation only when enabled.

- On reattach, preserve the current tmux state instead of forcing `Aliveness Window` or `Current Project Window`.
- Help is exposed as a command (for example, a menu option or CLI flag), not as a dedicated tmux window.

## Prompt contract (approved copy)

- First prompt: `Run 'pkg update && pkg upgrade -y' Y/n (default no)`
- Project menu must show `Pinned` and `Recent` blocks first, then provide a selectable `Show full list` option.
- Project prompt should be self-describing and mirror the clarity of the pkg-update question.
- Second prompt flow: choose project from available directories under the configured projects path; default view shows only `Pinned` and `Recent` blocks with a selectable full-list reveal; full-list view is alphabetical across all available directories; default selection remains the last-selected project when valid; `Exit` opens the configured projects path (default `~/projects`)
- If there is no valid remembered last project, UI must explicitly say so and explain that pressing Enter opens the configured projects path (default `~/projects`).
- Third prompt (conditional): `Do you want to git pull? Y/n (default no)` is shown only when the local default branch is behind its remote and repo state is otherwise eligible; otherwise, print a brief reason pull was skipped.
- Scripts menu must show `Pinned` and `Recent` blocks first, then provide a selectable `Show full list` option.
- Scripts prompt should be self-describing and mirror the clarity of the pkg-update question.
- Script selection flow mirrors project selection flow: default view shows only `Pinned` and `Recent` blocks with a selectable full-list reveal, full-list view includes all executable scripts in scope, and default selection remains the last-selected script when valid.

## Aliveness Window contract

`Aliveness Window` runs only on fresh session creation, not on reattach.

Prompt flow (asked one after another in this exact order):

1. `What made me feel most alive today ?`
2. `Aliveness score (1–10):`
3. `What drained my aliveness today?`
4. `Drain score (1–10):`
5. `Save note y/n (default: yes)?`

Rules:

- Each prompt is optional; pressing Enter skips that answer.
- The `Save note` prompt defaults to `yes`.
- A single timestamp is recorded once per entry, not once per question.
- New entries are prepended to the journal file.
- If all journal-answer fields are blank/skipped, no new entry is written.
- The journal is written directly to the configured aliveness-note directory; no mirror/copy flow is used.
- The default aliveness-note directory is `/storage/emulated/0/Documents`.
- The default note filename is `termux-dashboard-aliveness.md`.
- On first path setup, the directory prompt should be prefilled with `/storage/emulated/0/Documents` so the user can edit the tail of the path instead of retyping the whole prefix.
- Directory setup should be asked only when an entry exists, the user chose to save it, and no custom aliveness-note directory has been set yet.
- At first-time directory setup, pressing Enter accepts `/storage/emulated/0/Documents` as-is.
- After the final prompt, focus must move to `Current Project Window`.
- `Aliveness Window` should not remain the active working window after the prompt flow completes.
- Print `Aliveness captured.` only when an entry was written.

## Window behavior

- No dashboard window may silently fall back to plain `~`; every flow must land in an explicit target directory.
- `Current Project Window` fallback/`Exit` opens the configured projects path (default `~/projects`).
- `Current Project Window` must end in the selected repo directory after selection, including after stale-branch cleanup handling and optional git-pull handling.
- In `Current Project Window`, when repo context is available, print a concise repo status summary before stale-branch cleanup and pull-gating decisions.
- Repo status summary should include, when available: current branch, clean/dirty state, and relation of the local default branch to its remote default branch (`behind`, `ahead`, `diverged`, or `up-to-date`).
- In `Current Project Window`, after repo selection and before any pull prompt, run stale local branch cleanup evaluation.
- Stale-branch cleanup evaluation must run `git fetch --prune` first.
- The repo default branch must be detected dynamically; do not assume `main`.
- The default branch is never eligible for deletion.
- A local branch is eligible for cleanup only when its upstream is gone and it is fully merged into the detected default branch.
- No force-delete behavior is allowed for stale-branch cleanup.
- If the current branch is stale, deletion is allowed only after a successful switch to the default branch.
- If the selected repo is dirty, or switching to the default branch fails, print a brief notice, skip cleanup, skip auto-switching branches, leave the repo as-is, and do not ask the pull question.
- Pull prompt is behind-only: ask only when the local default branch is behind its remote default branch.
- If the repo is up-to-date, ahead, diverged, dirty, not on the default branch, or default-branch detection is unavailable, print a brief skip note and do not ask the pull question.
- `Projects Window` opens the configured projects path (default `~/projects`), never plain `~`.
- `New Window` is repeatable and mirrors the `Current Project Window` flow, including the same repo-status summary behavior, stale-branch cleanup, pull-gating, and working-directory guarantees.
- `Scripts Window` lists scripts from `~/bin`; default runs last-used script; startup/fallback/`Exit` path is the configured scripts path (default `~/bin`), never plain `~`.
- `Aliveness Window` is a startup prompt window, not a persistent workspace window.
- After the aliveness prompt flow completes, dashboard focus moves to `Current Project Window`.
- `Aliveness Window` must not interrupt normal reattach behavior.
- When `Aliveness Window` is disabled, dashboard startup must use the 4-window layout and must not create a hidden or inert aliveness window.

## Safety and state

- State persistence path: `$HOME/.config/termux-dashboard/`
- Git behavior: behind-only pull prompt, default `no`
- User-editable pinned config files:
  - `$HOME/.config/termux-dashboard/pinned-projects.txt`
  - `$HOME/.config/termux-dashboard/pinned-scripts.txt`
- Internal recent state files:
  - `$HOME/.config/termux-dashboard/recent_projects`
  - `$HOME/.config/termux-dashboard/recent_scripts`
- Internal last-selected state files:
  - `$HOME/.config/termux-dashboard/last_project`
  - `$HOME/.config/termux-dashboard/last_script`
- Pinned file format: plain text, one item per line.
- Blank lines in pinned files are allowed.
- Lines beginning with `#` in pinned files are comments.
- Missing/nonexistent pinned entries are skipped.
- Help command output should print the exact pinned-file paths so users can edit them quickly.
- Naming convention: only pinned config files use `.txt`; recent/last internal state files are extensionless.
- User-local config may include an enabled/disabled toggle for `Aliveness Window`.
- When `Aliveness Window` is disabled, the tmux session must omit that window entirely.
- User-local config may include an editable aliveness-note directory.
- Default aliveness-note directory: `/storage/emulated/0/Documents`
- Default aliveness note filename: `termux-dashboard-aliveness.md`
- The aliveness-note directory is user-local config/state and should persist across reinstalls when the user config directory is preserved.

## Runtime discovery guidance

- Runtime discovery is in scope for dashboard menus.
- Project choices are discovered from all available directories under the configured projects path, with no exclusions.
- Script choices are discovered from executable files under `~/bin`.
- [TENTATIVE] Default menu block sizes are 5 pinned items and 5 recent items unless later locked otherwise.

## Reattach behavior

- On reattach, preserve the current tmux state instead of forcibly selecting `Current Project Window`.

## Downstream integration boundary

- Installer behavior and downstream integration are out of scope for this repository.
- Integration implementation belongs in `termux-shortcuts`.
- This repository remains focused on dashboard runtime behavior and validation.
