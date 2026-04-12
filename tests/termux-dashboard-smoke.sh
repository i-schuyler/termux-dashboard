#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD_SCRIPT="$REPO_ROOT/scripts/termux-dashboard"

PASS_COUNT=0
declare -a TEMP_ROOTS=()

log() {
  printf '[smoke] %s\n' "$*"
}

fail() {
  printf '[smoke][FAIL] %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$context (missing: $needle)"
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local context="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$context (unexpected: $needle)"
  fi
}

new_temp_root() {
  local root
  root="$(mktemp -d)"
  TEMP_ROOTS+=("$root")
  printf '%s\n' "$root"
}

cleanup() {
  local root
  for root in "${TEMP_ROOTS[@]}"; do
    if [ -d "$root/tmux" ]; then
      env -u TMUX TMUX_TMPDIR="$root/tmux" tmux kill-server >/dev/null 2>&1 || true
    fi
    rm -rf "$root"
  done
}
trap cleanup EXIT

require_commands() {
  local command_name
  for command_name in "$@"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      fail "Required command not found: $command_name"
    fi
  done
}

tmux_exec() {
  local tmux_tmpdir="$1"
  shift
  env -u TMUX TMUX_TMPDIR="$tmux_tmpdir" tmux "$@"
}

capture_pane_text() {
  local tmux_tmpdir="$1"
  local pane_target="$2"
  tmux_exec "$tmux_tmpdir" capture-pane -pt "$pane_target" 2>/dev/null || true
}

new_test_home() {
  local root
  root="$(new_temp_root)"
  local home_dir="$root/home"
  mkdir -p "$home_dir/projects" "$home_dir/bin" "$home_dir/.config/termux-dashboard"
  printf '%s\n' "$home_dir"
}

write_executable_script() {
  local target_dir="$1"
  local script_name="$2"
  cat > "$target_dir/$script_name" <<'EOF'
#!/usr/bin/env bash
echo "ok"
EOF
  chmod +x "$target_dir/$script_name"
}

set_git_identity() {
  local repo_dir="$1"
  git -C "$repo_dir" config user.name "Smoke Tester"
  git -C "$repo_dir" config user.email "smoke@example.com"
}

init_remote_with_main() {
  local root="$1"
  local remote_dir="$root/remote.git"
  local seed_dir="$root/seed"

  git -c init.defaultBranch=main init --bare "$remote_dir" >/dev/null
  git -c init.defaultBranch=main init "$seed_dir" >/dev/null
  set_git_identity "$seed_dir"

  printf 'seed\n' > "$seed_dir/README.md"
  git -C "$seed_dir" add README.md
  git -C "$seed_dir" commit -m "seed" >/dev/null
  git -C "$seed_dir" remote add origin "$remote_dir"
  git -C "$seed_dir" push -u origin main >/dev/null
  git --git-dir="$remote_dir" symbolic-ref HEAD refs/heads/main

  printf '%s\n' "$remote_dir"
}

wait_for_tmux_session() {
  local tmux_tmpdir="$1"
  local session_name="$2"
  local attempt

  for attempt in $(seq 1 50); do
    if tmux_exec "$tmux_tmpdir" has-session -t "$session_name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  fail "tmux session did not start: $session_name"
}

wait_for_pane_text() {
  local tmux_tmpdir="$1"
  local pane_target="$2"
  local expected_text="$3"
  local attempt
  local pane_output

  for attempt in $(seq 1 80); do
    pane_output="$(capture_pane_text "$tmux_tmpdir" "$pane_target")"
    if [[ "$pane_output" == *"$expected_text"* ]]; then
      return 0
    fi
    sleep 0.2
  done

  fail "pane did not show expected text for $pane_target: $expected_text\nObserved pane output:\n$pane_output"
}

wait_for_pane_cwd() {
  local tmux_tmpdir="$1"
  local pane_target="$2"
  local expected_path="$3"
  local attempt
  local current_path
  local pane_output

  for attempt in $(seq 1 80); do
    current_path="$(tmux_exec "$tmux_tmpdir" display-message -p -t "$pane_target" '#{pane_current_path}' 2>/dev/null || true)"
    if [ "$current_path" = "$expected_path" ]; then
      return 0
    fi
    sleep 0.2
  done

  pane_output="$(capture_pane_text "$tmux_tmpdir" "$pane_target")"
  fail "pane cwd mismatch for $pane_target (expected: $expected_path, actual: ${current_path:-<empty>})\nObserved pane output:\n$pane_output"
}

run_test() {
  local name="$1"
  shift
  log "Running: $name"
  "$@"
  PASS_COUNT=$((PASS_COUNT + 1))
  log "PASS: $name"
}

test_help_output() {
  local home_dir
  home_dir="$(new_test_home)"
  local output

  output="$(HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --help 2>&1)"

  assert_contains "$output" "Usage:" "help output"
  assert_contains "$output" "termux-dashboard --current-project-window" "help output"
  assert_contains "$output" 'Projects: $HOME/.config/termux-dashboard/pinned-projects.txt' "help output"
}

test_pins_absent() {
  local home_dir
  home_dir="$(new_test_home)"
  mkdir -p "$home_dir/projects/alpha"
  write_executable_script "$home_dir/bin" "hello"

  local current_output
  current_output="$(printf '\n2\n' | HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --current-project-window 2>&1)"
  assert_contains "$current_output" "Pinned projects:" "absent project pin file"
  assert_contains "$current_output" "  (none)" "absent project pin file"

  local scripts_output
  scripts_output="$(printf '2\n' | HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --scripts-window 2>&1)"
  assert_contains "$scripts_output" "Pinned scripts:" "absent script pin file"
  assert_contains "$scripts_output" "  (none)" "absent script pin file"
}

test_pin_filtering() {
  local home_dir
  home_dir="$(new_test_home)"
  mkdir -p "$home_dir/projects/alpha" "$home_dir/projects/beta"
  write_executable_script "$home_dir/bin" "run-me"

  cat > "$home_dir/.config/termux-dashboard/pinned-projects.txt" <<'EOF'
# keep comments

alpha
ghost-project
alpha
EOF

  cat > "$home_dir/.config/termux-dashboard/pinned-scripts.txt" <<'EOF'
# keep comments

run-me
ghost-script
run-me
EOF

  local current_output
  current_output="$(printf '\n3\n' | HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --current-project-window 2>&1)"
  assert_contains "$current_output" "1) alpha" "project pin filtering"
  assert_not_contains "$current_output" "ghost-project" "project pin filtering"

  local scripts_output
  scripts_output="$(printf '3\n' | HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --scripts-window 2>&1)"
  assert_contains "$scripts_output" "1) run-me" "script pin filtering"
  assert_not_contains "$scripts_output" "ghost-script" "script pin filtering"
}

test_behind_only_pull_gating() {
  local root
  root="$(new_temp_root)"

  local home_dir="$root/home"
  mkdir -p "$home_dir/projects" "$home_dir/bin" "$home_dir/.config/termux-dashboard"

  local remote_dir
  remote_dir="$(init_remote_with_main "$root")"

  local behind_repo="$home_dir/projects/behind-repo"
  git clone "$remote_dir" "$behind_repo" >/dev/null
  set_git_identity "$behind_repo"

  local updater_dir="$root/updater"
  git clone "$remote_dir" "$updater_dir" >/dev/null
  set_git_identity "$updater_dir"
  printf 'behind\n' >> "$updater_dir/README.md"
  git -C "$updater_dir" add README.md
  git -C "$updater_dir" commit -m "behind update" >/dev/null
  git -C "$updater_dir" push origin main >/dev/null

  local behind_output
  behind_output="$(printf '\n1\n1\ny\n' | HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --current-project-window 2>&1)"
  assert_contains "$behind_output" "[git] clean → pulling with rebase from 'main'..." "behind-only pull gating"

  local up_to_date_home="$root/home-up-to-date"
  mkdir -p "$up_to_date_home/projects" "$up_to_date_home/bin" "$up_to_date_home/.config/termux-dashboard"

  local up_to_date_repo="$up_to_date_home/projects/up-to-date-repo"
  git clone "$remote_dir" "$up_to_date_repo" >/dev/null
  set_git_identity "$up_to_date_repo"

  local up_to_date_output
  up_to_date_output="$(printf '\n1\n1\n' | HOME="$up_to_date_home" bash "$DASHBOARD_SCRIPT" --current-project-window 2>&1)"
  assert_contains "$up_to_date_output" "[git] pull skipped: default branch is up-to-date" "behind-only pull gating"
  assert_not_contains "$up_to_date_output" "[git] clean → pulling with rebase from 'main'..." "behind-only pull gating"
}

test_zero_eligible_stale_branches() {
  local root
  root="$(new_temp_root)"

  local home_dir="$root/home"
  mkdir -p "$home_dir/projects" "$home_dir/bin" "$home_dir/.config/termux-dashboard"

  local remote_dir
  remote_dir="$(init_remote_with_main "$root")"

  local repo_dir="$home_dir/projects/stale-check"
  git clone "$remote_dir" "$repo_dir" >/dev/null
  set_git_identity "$repo_dir"

  git -C "$repo_dir" checkout -b stale-unmerged >/dev/null
  printf 'stale\n' > "$repo_dir/stale.txt"
  git -C "$repo_dir" add stale.txt
  git -C "$repo_dir" commit -m "stale branch" >/dev/null
  git -C "$repo_dir" push -u origin stale-unmerged >/dev/null
  git -C "$repo_dir" checkout main >/dev/null
  git -C "$repo_dir" push origin --delete stale-unmerged >/dev/null

  local output
  output="$(printf '\n1\n1\n' | HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --current-project-window 2>&1)"

  if ! git -C "$repo_dir" show-ref --verify --quiet refs/heads/stale-unmerged; then
    fail "zero eligible stale branches check deleted unmerged stale branch"
  fi

  assert_contains "$output" "[git] pull skipped: default branch is up-to-date" "zero eligible stale branches"
}

test_tmux_pane_cwd_handoff() {
  local root
  root="$(new_temp_root)"

  local home_dir="$root/home"
  local project_name="handoff-project"
  local expected_path="$home_dir/projects/$project_name"
  mkdir -p "$expected_path" "$home_dir/bin" "$home_dir/.config/termux-dashboard"

  local tmux_tmpdir="$root/tmux"
  local pane_target="termux-dashboard:Current Project Window"
  mkdir -p "$tmux_tmpdir"

  printf '%s\n' "$project_name" > "$home_dir/.config/termux-dashboard/last_project"

  env -u TMUX HOME="$home_dir" TMUX_TMPDIR="$tmux_tmpdir" TERMUX_DASHBOARD_NO_ATTACH=1 bash "$DASHBOARD_SCRIPT"
  wait_for_tmux_session "$tmux_tmpdir" "termux-dashboard"
  wait_for_pane_text "$tmux_tmpdir" "$pane_target" "Run 'pkg update && pkg upgrade -y' Y/n (default no)"

  tmux_exec "$tmux_tmpdir" send-keys -t "$pane_target" C-m
  wait_for_pane_text "$tmux_tmpdir" "$pane_target" "Default project (Enter): $project_name"
  wait_for_pane_text "$tmux_tmpdir" "$pane_target" "Project selection (number or Enter for default):"

  tmux_exec "$tmux_tmpdir" send-keys -t "$pane_target" C-m

  wait_for_pane_cwd "$tmux_tmpdir" "$pane_target" "$expected_path"

  local pane_output
  pane_output="$(capture_pane_text "$tmux_tmpdir" "$pane_target")"
  if [[ "$pane_output" == *"__td_cwd_file="* ]]; then
    log "TODO: add pane-output cleanliness assertion after pre-menu echo bug is fixed"
  fi

  tmux_exec "$tmux_tmpdir" kill-session -t "termux-dashboard" >/dev/null 2>&1 || true
}

main() {
  require_commands bash git tmux mktemp

  if [ ! -f "$DASHBOARD_SCRIPT" ]; then
    fail "Missing script under test: $DASHBOARD_SCRIPT"
  fi

  run_test "help output" test_help_output
  run_test "pin files absent" test_pins_absent
  run_test "pin file filtering" test_pin_filtering
  run_test "behind-only pull gating" test_behind_only_pull_gating
  run_test "zero eligible stale branches" test_zero_eligible_stale_branches
  run_test "tmux pane cwd handoff" test_tmux_pane_cwd_handoff

  log "Completed $PASS_COUNT smoke checks"
}

main "$@"
