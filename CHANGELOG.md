# Changelog

This file tracks user-visible changes to `termux-dashboard`.

## Unreleased

### Added
- Optional `Aliveness Window` startup flow for fresh session creation.
- Direct-write aliveness journaling to a configurable note directory.
- Dedicated `Codex Alerts Window` with exact `codex-alert` command resolution, actions, and JSON status rendering.
- `--codex-alerts-window` direct entry point and help documentation.

### Changed
- Startup behavior now uses 6 windows when `Aliveness Window` is enabled and 5 when it is disabled.
- The dashboard remains a thin control surface; `crosshost-utils` retains watcher and notification ownership.
- README and canonical docs now reflect shipped Aliveness behavior.

### Fixed
- Fresh startup now lands on the correct initial tmux window.
- Aliveness note output now matches the canonical Markdown format.
