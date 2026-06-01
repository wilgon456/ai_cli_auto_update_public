#!/usr/bin/env bash
set -Eeuo pipefail

# Auto-update local AI coding CLIs.
# Targets:
#   - Codex CLI: Homebrew cask/formula when present; npm global only if it is the active command
#   - Antigravity CLI: agy built-in updater when present
#
# Safe behavior:
#   - serializes with flock
#   - logs before/after versions
#   - continues per-tool if one updater fails
#   - never prints secrets/env values

LOCK_DIR="${LOCK_DIR:-/tmp/ai-cli-auto-update.lockdir}"
LOG_DIR="${LOG_DIR:-${HOME:-/tmp}/.ai-cli-auto-update/logs}"
BREW="${BREW:-$(command -v brew 2>/dev/null || echo /usr/local/bin/brew)}"
NPM="${NPM:-$(command -v npm 2>/dev/null || echo /usr/local/bin/npm)}"
PATH="/usr/local/bin:/opt/homebrew/bin:${HOME:-}/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"
DRY_RUN=false
VERSION_TIMEOUT_SECONDS="${VERSION_TIMEOUT_SECONDS:-10}"
if [[ ! "$VERSION_TIMEOUT_SECONDS" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ "$VERSION_TIMEOUT_SECONDS" == 0 || "$VERSION_TIMEOUT_SECONDS" == 0.0 ]]; then
  VERSION_TIMEOUT_SECONDS=10
fi
case "${1:-}" in
  --dry-run|--check) DRY_RUN=true ;;
  -h|--help)
    echo "Usage: $0 [--dry-run|--check]"
    exit 0
    ;;
esac

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

command_with_timeout() {
  local timeout_seconds="$1"; shift
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$timeout_seconds" "$@" <<'PY'
import subprocess
import sys

timeout = float(sys.argv[1])
argv = sys.argv[2:]
try:
    completed = subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=timeout,
    )
    if completed.stdout:
        sys.stdout.write(completed.stdout)
    sys.exit(completed.returncode)
except subprocess.TimeoutExpired as exc:
    output = exc.stdout or ""
    if isinstance(output, bytes):
        output = output.decode(errors="replace")
    if output:
        sys.stdout.write(output)
    sys.stderr.write(f"TIMEOUT after {timeout:g}s\n")
    sys.exit(124)
PY
  else
    "$@" &
    local cmd_pid=$! watchdog_pid rc
    (
      sleep "$timeout_seconds"
      if kill -0 "$cmd_pid" 2>/dev/null; then
        echo "TIMEOUT after ${timeout_seconds}s" >&2
        kill -TERM "$cmd_pid" 2>/dev/null || true
        sleep 1
        kill -KILL "$cmd_pid" 2>/dev/null || true
      fi
    ) &
    watchdog_pid=$!
    rc=0
    wait "$cmd_pid" || rc=$?
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
    if ((rc == 143 || rc == 137)); then
      return 124
    fi
    return "$rc"
  fi
}

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/update-$(date +%Y%m%d-%H%M%S).log"
LATEST_LOG="$LOG_DIR/latest.log"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [[ -f "$LOCK_DIR/pid" ]] && kill -0 "$(cat "$LOCK_DIR/pid" 2>/dev/null)" 2>/dev/null; then
    echo "[$(ts)] another update run is already active" | tee -a "$LOG_FILE"
    exit 0
  fi
  echo "[$(ts)] removing stale lock: $LOCK_DIR" | tee -a "$LOG_FILE"
  rm -f "$LOCK_DIR/pid" 2>/dev/null || true
  rmdir "$LOCK_DIR" 2>/dev/null || true
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "[$(ts)] another update run is already active" | tee -a "$LOG_FILE"
    exit 0
  fi
fi
printf '%s\n' "$$" > "$LOCK_DIR/pid"
trap 'rm -f "$LOCK_DIR/pid" 2>/dev/null || true; rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# Mirror all output to a timestamped log and latest.log.
: > "$LATEST_LOG"
exec > >(tee -a "$LOG_FILE" "$LATEST_LOG") 2>&1

failures=()
version_failures=()

run_step() {
  local name="$1"; shift
  echo
  echo "== $name =="
  echo "+ $*"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "dry-run: skipped $name"
    return 0
  fi
  if "$@"; then
    echo "✓ $name ok"
  else
    local rc=$?
    echo "✗ $name failed rc=$rc"
    failures+=("$name rc=$rc")
  fi
}

run_optional_step() {
  local name="$1"; shift
  echo
  echo "== $name =="
  echo "+ $*"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "dry-run: skipped $name"
    return 0
  fi
  if "$@"; then
    echo "✓ $name ok"
  else
    local rc=$?
    echo "warn: optional $name failed rc=$rc"
  fi
}

pass_missing() {
  local tool="$1" reason="$2"
  echo "pass: $tool not installed or not managed here ($reason)"
}

record_version_failure() {
  local item="$1" existing
  if ((${#version_failures[@]})); then
    for existing in "${version_failures[@]}"; do
      [[ "$existing" == "$item" ]] && return 0
    done
  fi
  version_failures+=("$item")
}

version_of() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%s: ' "$cmd"
    local version_output version_rc first_line
    version_rc=0
    version_output="$(command_with_timeout "$VERSION_TIMEOUT_SECONDS" "$cmd" --version 2>&1)" || version_rc=$?
    first_line="${version_output%%$'\n'*}"
    if ((version_rc == 124)); then
      echo "TIMEOUT after ${VERSION_TIMEOUT_SECONDS}s"
      echo "warn: $cmd --version timed out; continuing updater"
      record_version_failure "$cmd version timeout"
    elif ((version_rc != 0)); then
      echo "ERROR rc=$version_rc${first_line:+: $first_line}"
      echo "warn: $cmd --version failed rc=$version_rc; continuing updater"
      record_version_failure "$cmd version rc=$version_rc"
    else
      echo "${first_line:-unknown}"
    fi
    printf '  path: '
    command -v "$cmd" || true
  else
    echo "$cmd: not installed"
  fi
}

is_brew_cask_installed() {
  command -v "$BREW" >/dev/null 2>&1 && "$BREW" list --cask "$1" >/dev/null 2>&1
}

is_brew_formula_installed() {
  command -v "$BREW" >/dev/null 2>&1 && "$BREW" list --formula "$1" >/dev/null 2>&1
}

is_npm_global_installed() {
  command -v "$NPM" >/dev/null 2>&1 && "$NPM" list -g --depth=0 "$1" >/dev/null 2>&1
}

npm_global_package_path() {
  local pkg="$1" root
  root="$($NPM root -g 2>/dev/null || true)"
  [[ -n "$root" ]] || return 1
  printf '%s/%s\n' "$root" "$pkg"
}

is_npm_global_package_writable() {
  local pkg="$1" pkg_path pkg_parent
  pkg_path="$(npm_global_package_path "$pkg")" || return 1
  pkg_parent="$(dirname "$pkg_path")"
  [[ -w "$pkg_path" && -w "$pkg_parent" ]]
}

active_path_contains() {
  local cmd="$1" needle="$2"
  local p
  p="$(command -v "$cmd" 2>/dev/null || true)"
  [[ "$p" == *"$needle"* ]]
}

update_brew_package() {
  local name="$1"
  local outdated rc
  if is_brew_cask_installed "$name"; then
    outdated="$($BREW outdated --cask "$name" 2>&1)"
    rc=$?
    if ((rc != 0)) && [[ "$outdated" != *"$name"* ]]; then
      echo "$outdated"
      return "$rc"
    fi
    if [[ -n "$outdated" ]]; then
      "$BREW" upgrade --cask "$name"
    else
      echo "brew cask already up-to-date: $name"
    fi
  elif is_brew_formula_installed "$name"; then
    outdated="$($BREW outdated --formula "$name" 2>&1)"
    rc=$?
    if ((rc != 0)) && [[ "$outdated" != *"$name"* ]]; then
      echo "$outdated"
      return "$rc"
    fi
    if [[ -n "$outdated" ]]; then
      "$BREW" upgrade --formula "$name"
    else
      echo "brew formula already up-to-date: $name"
    fi
  else
    echo "brew package not installed: $name"
  fi
}

update_npm_package() {
  local pkg="$1"
  if is_npm_global_installed "$pkg"; then
    "$NPM" install -g "$pkg@latest"
  else
    echo "npm global package not installed: $pkg"
  fi
}

update_agy_cli() {
  if command -v agy >/dev/null 2>&1; then
    command_with_timeout 300 agy update
  else
    echo "agy command not installed"
  fi
}

echo "[$(ts)] AI CLI update started"
echo "host=$(hostname) user=$(id -un) dry_run=$DRY_RUN"

echo
echo "== before versions =="
version_of codex
version_of agy

if command -v "$BREW" >/dev/null 2>&1; then
  if is_brew_cask_installed codex || is_brew_formula_installed codex; then
    run_step "brew update" "$BREW" update
  else
    echo "pass: no target Homebrew-managed CLIs installed; skipping brew update"
  fi
else
  echo "pass: brew not installed; skipping brew-managed CLIs"
fi

# Codex: prefer Homebrew when it manages the active install.
if is_brew_cask_installed codex || is_brew_formula_installed codex; then
  run_step "codex via brew" update_brew_package codex
elif active_path_contains codex "/node_modules/" || is_npm_global_installed "@openai/codex"; then
  run_step "codex via npm" update_npm_package "@openai/codex"
else
  pass_missing codex "no brew package and no npm global package"
fi

# Keep a stale npm Codex install current only if it exists AND is not shadowing brew unexpectedly.
# This prevents future PATH flips from resurrecting an old Codex binary.
if is_npm_global_installed "@openai/codex"; then
  if is_npm_global_package_writable "@openai/codex"; then
    run_optional_step "codex npm shadow copy" update_npm_package "@openai/codex"
  else
    echo "warn: optional codex npm shadow copy is installed but not writable; skipping stale shadow update"
    echo "      cleanup manually with sudo if needed: $(npm_global_package_path "@openai/codex" 2>/dev/null || echo "@openai/codex")"
  fi
fi

if command -v agy >/dev/null 2>&1; then
  run_step "antigravity cli via agy" update_agy_cli
else
  pass_missing agy "command not found"
fi

echo
echo "== after versions =="
hash -r || true
version_of codex
version_of agy

echo
echo "log_file=$LOG_FILE"

if ((${#failures[@]} || ${#version_failures[@]})); then
  failure_summary=""
  if ((${#failures[@]})); then
    failure_summary="${failures[*]}"
  fi
  if ((${#version_failures[@]})); then
    failure_summary="${failure_summary:+$failure_summary }${version_failures[*]}"
  fi
  echo "[$(ts)] AI CLI update finished with failures: $failure_summary"
  exit 1
fi

echo "[$(ts)] AI CLI update finished successfully"
