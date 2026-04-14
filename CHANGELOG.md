# Changelog

This file tracks user-visible changes to `termux-dashboard`.

## Unreleased

### Added
- Optional `Aliveness Window` startup flow for fresh session creation.
- Direct-write aliveness journaling to a configurable note directory.

### Changed
- Startup behavior now uses 5 windows when `Aliveness Window` is enabled and 4 when it is disabled.
- README and canonical docs now reflect shipped Aliveness behavior.

### Fixed
- Fresh startup now lands on the correct initial tmux window.
- Aliveness note output now matches the canonical Markdown format.
