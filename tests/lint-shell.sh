#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

log() {
  printf '[lint-shell] %s\n' "$*"
}

mapfile -t shell_targets < <(
  {
    find scripts -maxdepth 1 -type f ! -name "*.conf" -print
    find tests -maxdepth 1 -type f -name "*.sh" -print
  } | LC_ALL=C sort -u
)

log "Running bash -n syntax checks"
for target in "${shell_targets[@]}"; do
  bash -n "$target"
done

if command -v shellcheck >/dev/null 2>&1; then
  log "Running shellcheck error-level checks"
  shellcheck -S error "${shell_targets[@]}"
else
  log "shellcheck not found; skipping shellcheck stage"
fi

log "All shell lint checks passed"
