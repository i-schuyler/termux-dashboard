# AGENTS.md

## Purpose

This file defines repo-local guidance for Codex and contributors working in `termux-dashboard`.

`termux-dashboard` is the source-of-truth repository for dashboard behavior, tests, and docs.

## Authority ladder

1. System/developer/user prompt instructions
2. Repo `AGENTS.md` (this file)
3. Existing repo code/docs behavior as source of truth

## Workflow defaults

- Codex-prompt-first: follow the current user prompt contract before adding assumptions.
- PR-first: do slice work on a feature branch, then open a PR.
- Suggested branch bootstrap before edits:

```sh
git fetch origin
git checkout -b <branch-name>
```

- After successful slice work:

```sh
git push -u origin <branch-name>
gh pr create --title "<PR title>" --body "<PR body>"
```

- After merge cleanup:

```sh
git checkout main
git pull --ff-only
git branch -d <branch-name>
git push origin --delete <branch-name>
```

## Slice preflight (run exactly)

```sh
git fetch origin
git status --porcelain
git branch --show-current
git rev-list --left-right --count origin/main...HEAD
```

## Required verification defaults

- Default verification path is the repo tests under `tests/*.sh`.
- If a slice touches dashboard runtime behavior (including `scripts/termux-dashboard`), run:
  - `bash tests/lint-shell.sh`
  - `bash tests/termux-dashboard-smoke.sh`
- For pane/cwd/handoff behavior, actual tmux pane outcomes are authoritative (`#{pane_current_path}` and pane content), not internal script cwd assumptions.
- Do not claim pane/cwd verification based only on internal script cwd.
- If CI fails on a branch, patch the same branch with the smallest targeted fix.

## Repo boundaries

- Keep this repo focused on dashboard source-of-truth behavior.
- Downstream installer and integration work belongs in `termux-shortcuts`, not this repo.

## Stop rules

Stop before editing if any of the following is true:

- Current branch is `main`
- Working tree is dirty (except explicitly allowed bootstrap seeding states)
- `origin/main...HEAD` is both ahead and behind non-zero
- Required evidence cannot be found in repo
- A requested doc change would silently redefine source-layer meaning instead of local repo behavior

## Evidence-before-edit

- Verify exact repo file:line evidence before editing.
- Cite those file:line references in final summaries when required.

## Source-layer guardrail

- Do not redefine source-layer meaning in docs.
- Document repo-local behavior and clearly mark tentative vs locked decisions.

## Output contract

- Match the prompt-defined output contract exactly.
- Keep summaries concise, factual, and scoped to the slice.

## Clipboard requirement

- When requested, copy the final summary payload exactly via Termux API:

```sh
termux-clipboard-set
```

- If Termux API is unavailable, report that explicitly.
