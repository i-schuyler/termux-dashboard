# Termux Dashboard

_A tmux-based mobile developer workspace launcher for Termux._

## What it is

`termux-dashboard` is a shell-based launcher that starts and reattaches a structured tmux workspace for day-to-day development on Android in Termux. It focuses on fast project selection, script launching, and safe repo-aware workflows.

This repository is the source-of-truth for dashboard behavior, tests, and documentation.

## Who it is for

- Termux users who want a repeatable mobile development workspace.
- Developers managing multiple local repos under `~/projects`.
- Users who want lightweight shell tooling instead of heavyweight IDE startup.

## Repo layout

- `scripts/termux-dashboard` — dashboard launcher and window flows.
- `tests/lint-shell.sh` — shell syntax + shellcheck lint path.
- `tests/termux-dashboard-smoke.sh` — tmux behavior smoke tests.
- `docs/termux-dashboard.md` — dashboard behavior spec.
- `docs/DECISIONS.md` — dashboard-only architecture/behavior decisions.
- `docs/INDEX.md` — docs entrypoint for this repo.
- `.github/workflows/dashboard-pr-ci.yml` — PR CI for lint + smoke tests.

## Local testing

```sh
bash tests/lint-shell.sh
bash tests/termux-dashboard-smoke.sh
```

## Downstream integration note

`termux-shortcuts` currently owns downstream installer/integration concerns. This repo stays focused on `termux-dashboard` behavior and source-of-truth documentation.
