# termux-dashboard (Canonical Anchor)

Status: docs anchor only for later implementation slices.

## Shortcut identity

- Exact shortcut name: `termux-dashboard`
- Source-of-truth repo: `termux-dashboard`
- Downstream installer/integration repo: `termux-shortcuts`
- Installer requirement (later slice): install to `~/.shortcuts/termux-dashboard`
- Product role: `termux-dashboard` is the primary entry point.

## tmux window contract

The dashboard session uses exactly 4 windows in this exact order:

1. `Current Project Window`
2. `Projects Window`
3. `New Window`
4. `Scripts Window`

`Current Project Window` is shown first.

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
