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

write_codex_alert_stub() {
  local target_path="$1"
  local label="$2"
  local log_file="$3"
  mkdir -p "$(dirname "$target_path")"
  cat > "$target_path" <<EOF
#!/usr/bin/env bash
printf '%s|%s\n' '$label' "\$*" >> '$log_file'
if [ "\${1:-}" = status ] && [ "\${2:-}" = --json ]; then
  printf '%s\n' "\${CODEX_ALERT_STUB_JSON:-}"
  exit "\${CODEX_ALERT_STUB_STATUS_EXIT:-0}"
fi
printf '%s\n' "stub output: \$*"
exit "\${CODEX_ALERT_STUB_ACTION_EXIT:-0}"
EOF
  chmod +x "$target_path"
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

wait_for_window_absent() {
  local tmux_tmpdir="$1"
  local session_name="$2"
  local window_name="$3"
  local attempt
  local windows_output

  for attempt in $(seq 1 80); do
    windows_output="$(tmux_exec "$tmux_tmpdir" list-windows -t "$session_name" -F '#{window_name}' 2>/dev/null || true)"
    if [[ "$windows_output" != *"$window_name"* ]]; then
      return 0
    fi
    sleep 0.2
  done

  fail "window was not removed from $session_name: $window_name\nObserved windows:\n$windows_output"
}

wait_for_selected_window() {
  local tmux_tmpdir="$1"
  local session_name="$2"
  local expected_window_name="$3"
  local attempt
  local selected_window

  for attempt in $(seq 1 80); do
    selected_window="$(tmux_exec "$tmux_tmpdir" display-message -p -t "$session_name" '#{window_name}' 2>/dev/null || true)"
    if [ "$selected_window" = "$expected_window_name" ]; then
      return 0
    fi
    sleep 0.2
  done

  fail "session did not select expected window (expected: $expected_window_name, actual: ${selected_window:-<empty>})"
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
  assert_contains "$output" "termux-dashboard --aliveness-window" "help output"
  assert_contains "$output" "termux-dashboard --codex-alerts-window" "help output"
  assert_contains "$output" "Codex Alerts Window     Control the installed crosshost-utils codex-alert watcher." "help output"
  assert_contains "$output" "Internal state files (extensionless):" "help output"
  assert_contains "$output" 'Recent projects:$HOME/.config/termux-dashboard/recent_projects' "help output"
  assert_contains "$output" 'Recent scripts: $HOME/.config/termux-dashboard/recent_scripts' "help output"
  assert_contains "$output" 'Last project:   $HOME/.config/termux-dashboard/last_project' "help output"
  assert_contains "$output" 'Aliveness enabled toggle: $HOME/.config/termux-dashboard/aliveness_enabled' "help output"
  assert_contains "$output" 'Aliveness note dir:       $HOME/.config/termux-dashboard/aliveness_note_dir' "help output"
  assert_contains "$output" 'Projects: $HOME/.config/termux-dashboard/pinned-projects.txt' "help output"
  assert_contains "$output" "Editable pin config files (.txt, user-local, not repo-canonical):" "help output"
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

  printf '0\n' > "$home_dir/.config/termux-dashboard/aliveness_enabled"

  printf '%s\n' "$project_name" > "$home_dir/.config/termux-dashboard/last_project"

  env -u TMUX HOME="$home_dir" TMUX_TMPDIR="$tmux_tmpdir" TERMUX_DASHBOARD_NO_ATTACH=1 bash "$DASHBOARD_SCRIPT"
  wait_for_tmux_session "$tmux_tmpdir" "termux-dashboard"
  local first_menu_heading="Run 'pkg update && pkg upgrade -y' Y/n (default no)"
  wait_for_pane_text "$tmux_tmpdir" "$pane_target" "$first_menu_heading"

  local initial_pane_output
  initial_pane_output="$(capture_pane_text "$tmux_tmpdir" "$pane_target")"

  local first_non_empty_line
  first_non_empty_line="$(printf '%s\n' "$initial_pane_output" | sed -n '/[^[:space:]]/{s/^[[:space:]]*//;s/[[:space:]]*$//;p;q;}')"
  if [ "$first_non_empty_line" != "$first_menu_heading" ]; then
    fail "pre-menu pane output noise detected (first non-empty line: ${first_non_empty_line:-<empty>})"
  fi

  assert_not_contains "$initial_pane_output" "__td_cwd_file=" "pane output cleanliness"
  assert_not_contains "$initial_pane_output" "TERMUX_DASHBOARD_FINAL_CWD_FILE=" "pane output cleanliness"
  assert_not_contains "$initial_pane_output" "--current-project-window" "pane output cleanliness"

  tmux_exec "$tmux_tmpdir" send-keys -t "$pane_target" C-m
  wait_for_pane_text "$tmux_tmpdir" "$pane_target" "Default project (Enter): $project_name"
  wait_for_pane_text "$tmux_tmpdir" "$pane_target" "Project selection (number or Enter for default):"

  tmux_exec "$tmux_tmpdir" send-keys -t "$pane_target" C-m

  wait_for_pane_cwd "$tmux_tmpdir" "$pane_target" "$expected_path"

  tmux_exec "$tmux_tmpdir" kill-session -t "termux-dashboard" >/dev/null 2>&1 || true
}

test_aliveness_write_flow() {
  local home_dir
  home_dir="$(new_test_home)"

  local note_dir="$home_dir/aliveness-notes"
  mkdir -p "$note_dir"
  printf '%s\n' "$note_dir" > "$home_dir/.config/termux-dashboard/aliveness_note_dir"

  local output
  output="$(printf 'Shipped real work\n8\nLong context switching\n4\ny\n' | HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --aliveness-window 2>&1)"

  local note_file="$note_dir/termux-dashboard-aliveness.md"
  if [ ! -f "$note_file" ]; then
    fail "aliveness write flow did not create note file"
  fi

  local note_contents
  note_contents="$(cat "$note_file")"

  local first_line
  first_line="$(sed -n '1p' "$note_file")"
  if [[ ! "$first_line" =~ ^##\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
    fail "aliveness write flow timestamp format mismatch: $first_line"
  fi

  assert_contains "$note_contents" $'### What made me feel most alive today?\nShipped real work' "aliveness write flow"
  assert_contains "$note_contents" "Aliveness score (1–10): 8" "aliveness write flow"
  assert_contains "$note_contents" $'### What drained my aliveness today?\nLong context switching' "aliveness write flow"
  assert_contains "$note_contents" "Drain score (1–10): 4" "aliveness write flow"
  assert_not_contains "$note_contents" "What made me feel most alive today ?:" "aliveness write flow"

  local trailing_hex
  trailing_hex="$(tail -c 2 "$note_file" | od -An -t x1 | tr -d '[:space:]')"
  if [ "$trailing_hex" != "0a0a" ]; then
    fail "aliveness write flow missing final blank line"
  fi

  assert_contains "$output" "Aliveness captured." "aliveness write flow"
}

test_aliveness_all_skipped_no_write() {
  local home_dir
  home_dir="$(new_test_home)"

  local note_dir="$home_dir/aliveness-notes"
  mkdir -p "$note_dir"
  printf '%s\n' "$note_dir" > "$home_dir/.config/termux-dashboard/aliveness_note_dir"

  local output
  output="$(printf '\n\n\n\n\n' | HOME="$home_dir" bash "$DASHBOARD_SCRIPT" --aliveness-window 2>&1)"

  local note_file="$note_dir/termux-dashboard-aliveness.md"
  if [ -f "$note_file" ]; then
    fail "all-skipped aliveness flow unexpectedly wrote a note file"
  fi

  assert_not_contains "$output" "Aliveness captured." "all-skipped aliveness flow"
}

test_aliveness_window_handoff_cleanup() {
  local root
  root="$(new_temp_root)"

  local home_dir="$root/home"
  mkdir -p "$home_dir/projects/demo" "$home_dir/bin" "$home_dir/.config/termux-dashboard"

  local tmux_tmpdir="$root/tmux"
  local aliveness_pane_target="termux-dashboard:Aliveness Window"
  mkdir -p "$tmux_tmpdir"

  env -u TMUX HOME="$home_dir" TMUX_TMPDIR="$tmux_tmpdir" TERMUX_DASHBOARD_NO_ATTACH=1 bash "$DASHBOARD_SCRIPT"
  wait_for_tmux_session "$tmux_tmpdir" "termux-dashboard"
  wait_for_pane_text "$tmux_tmpdir" "$aliveness_pane_target" "What made me feel most alive today ?"
  wait_for_selected_window "$tmux_tmpdir" "termux-dashboard" "Aliveness Window"

  local enter_count
  for enter_count in 1 2 3 4 5; do
    tmux_exec "$tmux_tmpdir" send-keys -t "$aliveness_pane_target" C-m
    sleep 0.1
  done

  wait_for_window_absent "$tmux_tmpdir" "termux-dashboard" "Aliveness Window"
  wait_for_selected_window "$tmux_tmpdir" "termux-dashboard" "Current Project Window"

  local windows_output
  windows_output="$(tmux_exec "$tmux_tmpdir" list-windows -t "termux-dashboard" -F '#{window_name}')"
  assert_not_contains "$windows_output" "Aliveness Window" "aliveness window handoff cleanup"

  tmux_exec "$tmux_tmpdir" kill-session -t "termux-dashboard" >/dev/null 2>&1 || true
}

test_aliveness_window_disabled_omits_window() {
  local root
  root="$(new_temp_root)"

  local home_dir="$root/home"
  mkdir -p "$home_dir/projects" "$home_dir/bin" "$home_dir/.config/termux-dashboard"

  printf '0\n' > "$home_dir/.config/termux-dashboard/aliveness_enabled"

  local tmux_tmpdir="$root/tmux"
  mkdir -p "$tmux_tmpdir"

  env -u TMUX HOME="$home_dir" TMUX_TMPDIR="$tmux_tmpdir" TERMUX_DASHBOARD_NO_ATTACH=1 bash "$DASHBOARD_SCRIPT"
  wait_for_tmux_session "$tmux_tmpdir" "termux-dashboard"
  wait_for_selected_window "$tmux_tmpdir" "termux-dashboard" "Current Project Window"

  local windows_output
  windows_output="$(tmux_exec "$tmux_tmpdir" list-windows -t "termux-dashboard" -F '#{window_name}')"

  assert_not_contains "$windows_output" "Aliveness Window" "aliveness window disabled contract"

  tmux_exec "$tmux_tmpdir" kill-session -t "termux-dashboard" >/dev/null 2>&1 || true
}

test_codex_alert_command_resolution() {
  local home_dir
  home_dir="$(new_test_home)"
  local root="${home_dir%/home}"
  local log_file="$root/codex-alert.log"
  local override="$root/override/codex-alert"
  local canonical="$home_dir/.local/bin/codex-alert"
  local path_dir="$root/path-bin"
  local path_command="$path_dir/codex-alert"

  write_codex_alert_stub "$override" override "$log_file"
  write_codex_alert_stub "$canonical" canonical "$log_file"
  write_codex_alert_stub "$path_command" path "$log_file"

  printf '1\n\n9\n' | HOME="$home_dir" PATH="$path_dir:$PATH" TERMUX_DASHBOARD_CODEX_ALERT_COMMAND="$override" bash "$DASHBOARD_SCRIPT" --codex-alerts-window >/dev/null
  assert_contains "$(cat "$log_file")" "override|start" "codex-alert override precedence"
  assert_not_contains "$(cat "$log_file")" "canonical|" "codex-alert override precedence"
  : > "$log_file"

  printf '1\n\n9\n' | HOME="$home_dir" PATH="$path_dir:$PATH" bash "$DASHBOARD_SCRIPT" --codex-alerts-window >/dev/null
  assert_contains "$(cat "$log_file")" "canonical|start" "codex-alert canonical precedence"
  assert_not_contains "$(cat "$log_file")" "path|" "codex-alert canonical precedence"
  : > "$log_file"

  chmod -x "$canonical"
  printf '1\n\n9\n' | HOME="$home_dir" PATH="$path_dir:$PATH" bash "$DASHBOARD_SCRIPT" --codex-alerts-window >/dev/null
  assert_contains "$(cat "$log_file")" "path|start" "codex-alert PATH fallback"
}

test_codex_alert_actions_and_status() {
  local home_dir
  home_dir="$(new_test_home)"
  local root="${home_dir%/home}"
  local log_file="$root/codex-alert.log"
  local stub="$root/stub/codex-alert"
  write_codex_alert_stub "$stub" stub "$log_file"

  local status_json='{"state":"running","mode":"reliable","host":"vps.example","wake_lock":true,"stop_at":"2026-07-24T15:00:00Z","last_notification_at":"2026-07-24T11:00:00Z","reconnect_count":7,"last_error":"none recorded","unknown_future_field":{"ignored":true}}'
  local output
  output="$(printf '0\n1\n\n2\n\n3\n\n4\n\n5\n\n6\n\n7\n\n8\n\n9\n' | HOME="$home_dir" TERMUX_DASHBOARD_CODEX_ALERT_COMMAND="$stub" CODEX_ALERT_STUB_JSON="$status_json" bash "$DASHBOARD_SCRIPT" --codex-alerts-window 2>&1)"

  local calls
  calls="$(cat "$log_file")"
  assert_contains "$output" "Invalid choice. Enter a listed number." "codex-alert invalid input"
  local expected_menu=$'1) Start\n2) Start — reliable\n3) Start for 4 hours\n4) Stop\n5) Status\n6) Send test alert\n7) Doctor\n8) View logs\n9) Exit'
  assert_contains "$output" "$expected_menu" "codex-alert menu order"
  assert_contains "$calls" "stub|start" "codex-alert start mapping"
  assert_contains "$calls" "stub|start --reliable" "codex-alert reliable mapping"
  assert_contains "$calls" "stub|start --for 4h" "codex-alert timed mapping"
  assert_contains "$calls" "stub|stop" "codex-alert stop mapping"
  assert_contains "$calls" "stub|status --json" "codex-alert JSON status mapping"
  assert_contains "$calls" "stub|test" "codex-alert test mapping"
  assert_contains "$calls" "stub|doctor" "codex-alert doctor mapping"
  assert_contains "$calls" "stub|logs" "codex-alert logs mapping"
  assert_not_contains "$calls" "logs --follow" "codex-alert bounded logs"
  assert_not_contains "$calls" "boot" "codex-alert scope boundary"
  assert_not_contains "$calls" "widget" "codex-alert scope boundary"
  assert_contains "$output" "State:              running" "codex-alert status rendering"
  assert_contains "$output" "Mode:               reliable" "codex-alert status rendering"
  assert_contains "$output" "Host:               vps.example" "codex-alert status rendering"
  assert_contains "$output" "Wake lock:          enabled" "codex-alert status rendering"
  assert_contains "$output" "Timed stop:         2026-07-24T15:00:00Z" "codex-alert status rendering"
  assert_contains "$output" "Last notification:  2026-07-24T11:00:00Z" "codex-alert status rendering"
  assert_contains "$output" "Reconnect count:    7" "codex-alert status rendering"
  assert_contains "$output" "Last error:         none recorded" "codex-alert status rendering"
  assert_not_contains "$output" "unknown_future_field" "codex-alert unknown JSON field"
}

test_codex_alert_safe_failures() {
  local home_dir
  home_dir="$(new_test_home)"
  local root="${home_dir%/home}"
  local log_file="$root/codex-alert.log"
  local stub="$root/stub/codex-alert"
  write_codex_alert_stub "$stub" stub "$log_file"

  local malformed_output
  malformed_output="$(printf '5\n\n9\n' | HOME="$home_dir" TERMUX_DASHBOARD_CODEX_ALERT_COMMAND="$stub" CODEX_ALERT_STUB_JSON='not-json' bash "$DASHBOARD_SCRIPT" --codex-alerts-window 2>&1)"
  assert_contains "$malformed_output" "Status unavailable: codex-alert returned malformed JSON." "malformed status JSON"

  local nonzero_output
  nonzero_output="$(printf '5\n\n9\n' | HOME="$home_dir" TERMUX_DASHBOARD_CODEX_ALERT_COMMAND="$stub" CODEX_ALERT_STUB_JSON='{}' CODEX_ALERT_STUB_STATUS_EXIT=23 bash "$DASHBOARD_SCRIPT" --codex-alerts-window 2>&1)"
  assert_contains "$nonzero_output" "Status failed (exit 23)." "nonzero status command"

  local action_failure_output
  action_failure_output="$(printf '1\n\n9\n' | HOME="$home_dir" TERMUX_DASHBOARD_CODEX_ALERT_COMMAND="$stub" CODEX_ALERT_STUB_ACTION_EXIT=17 bash "$DASHBOARD_SCRIPT" --codex-alerts-window 2>&1)"
  assert_contains "$action_failure_output" "Start failed (exit 17)." "nonzero action command"

  local missing_home
  missing_home="$(new_test_home)"
  local missing_output
  missing_output="$(printf '1\n\n9\n' | HOME="$missing_home" PATH="${PATH//:$root\/stub/}" bash "$DASHBOARD_SCRIPT" --codex-alerts-window 2>&1)"
  assert_contains "$missing_output" "codex-alert is unavailable." "missing codex-alert"
  assert_contains "$missing_output" "https://github.com/i-schuyler/crosshost-utils" "missing codex-alert install source"
}

test_codex_alert_tmux_layout_and_reattach() {
  local root
  root="$(new_temp_root)"
  local home_dir="$root/home"
  mkdir -p "$home_dir/projects" "$home_dir/bin" "$home_dir/.local/bin" "$home_dir/.config/termux-dashboard"
  local tmux_tmpdir="$root/tmux"
  mkdir -p "$tmux_tmpdir"

  env -u TMUX HOME="$home_dir" TMUX_TMPDIR="$tmux_tmpdir" TERMUX_DASHBOARD_NO_ATTACH=1 bash "$DASHBOARD_SCRIPT"
  wait_for_tmux_session "$tmux_tmpdir" "termux-dashboard"
  local enabled_windows
  enabled_windows="$(tmux_exec "$tmux_tmpdir" list-windows -t termux-dashboard -F '#{window_name}')"
  local expected_enabled=$'Aliveness Window\nCurrent Project Window\nProjects Window\nNew Window\nScripts Window\nCodex Alerts Window'
  if [ "$enabled_windows" != "$expected_enabled" ]; then
    fail "enabled alerts window order mismatch (observed: $enabled_windows)"
  fi
  wait_for_pane_cwd "$tmux_tmpdir" "termux-dashboard:Codex Alerts Window" "$home_dir/.local/bin"

  tmux_exec "$tmux_tmpdir" select-window -t "termux-dashboard:Scripts Window"
  env -u TMUX HOME="$home_dir" TMUX_TMPDIR="$tmux_tmpdir" TERMUX_DASHBOARD_NO_ATTACH=1 bash "$DASHBOARD_SCRIPT"
  wait_for_selected_window "$tmux_tmpdir" "termux-dashboard" "Scripts Window"
  local reattach_windows
  reattach_windows="$(tmux_exec "$tmux_tmpdir" list-windows -t termux-dashboard -F '#{window_name}')"
  if [ "$reattach_windows" != "$expected_enabled" ]; then
    fail "reattach changed alerts window layout"
  fi
  tmux_exec "$tmux_tmpdir" kill-session -t termux-dashboard >/dev/null 2>&1 || true

  printf '0\n' > "$home_dir/.config/termux-dashboard/aliveness_enabled"
  env -u TMUX HOME="$home_dir" TMUX_TMPDIR="$tmux_tmpdir" TERMUX_DASHBOARD_NO_ATTACH=1 bash "$DASHBOARD_SCRIPT"
  wait_for_tmux_session "$tmux_tmpdir" "termux-dashboard"
  local disabled_windows
  disabled_windows="$(tmux_exec "$tmux_tmpdir" list-windows -t termux-dashboard -F '#{window_name}')"
  local expected_disabled=$'Current Project Window\nProjects Window\nNew Window\nScripts Window\nCodex Alerts Window'
  if [ "$disabled_windows" != "$expected_disabled" ]; then
    fail "disabled alerts window order mismatch (observed: $disabled_windows)"
  fi
  wait_for_pane_cwd "$tmux_tmpdir" "termux-dashboard:Codex Alerts Window" "$home_dir/.local/bin"
  tmux_exec "$tmux_tmpdir" kill-session -t termux-dashboard >/dev/null 2>&1 || true

  rmdir "$home_dir/.local/bin" "$home_dir/.local"
  env -u TMUX HOME="$home_dir" TMUX_TMPDIR="$tmux_tmpdir" TERMUX_DASHBOARD_NO_ATTACH=1 bash "$DASHBOARD_SCRIPT"
  wait_for_tmux_session "$tmux_tmpdir" "termux-dashboard"
  wait_for_pane_cwd "$tmux_tmpdir" "termux-dashboard:Codex Alerts Window" "$REPO_ROOT/scripts"
  tmux_exec "$tmux_tmpdir" kill-session -t termux-dashboard >/dev/null 2>&1 || true
}

main() {
  require_commands bash git tmux mktemp

  if [ ! -f "$DASHBOARD_SCRIPT" ]; then
    fail "Missing script under test: $DASHBOARD_SCRIPT"
  fi

  run_test "help output" test_help_output
  run_test "codex-alert command resolution" test_codex_alert_command_resolution
  run_test "codex-alert actions and status" test_codex_alert_actions_and_status
  run_test "codex-alert safe failures" test_codex_alert_safe_failures
  run_test "codex-alert tmux layout and reattach" test_codex_alert_tmux_layout_and_reattach
  run_test "pin files absent" test_pins_absent
  run_test "pin file filtering" test_pin_filtering
  run_test "behind-only pull gating" test_behind_only_pull_gating
  run_test "zero eligible stale branches" test_zero_eligible_stale_branches
  run_test "tmux pane cwd handoff" test_tmux_pane_cwd_handoff
  run_test "aliveness direct write flow" test_aliveness_write_flow
  run_test "aliveness all-skipped no-write" test_aliveness_all_skipped_no_write
  run_test "aliveness window handoff cleanup" test_aliveness_window_handoff_cleanup
  run_test "aliveness window disabled omits window" test_aliveness_window_disabled_omits_window

  log "Completed $PASS_COUNT smoke checks"
}

main "$@"
