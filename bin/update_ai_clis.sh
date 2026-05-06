#!/usr/bin/env bash
set -Eeuo pipefail

# Auto-update local AI coding CLIs.
# Targets:
#   - Codex CLI: Homebrew cask/formula when present; npm global only if it is the active command
#   - Claude Code: npm global if active; also run built-in claude update when available
#   - Gemini CLI: Homebrew formula/cask when present; npm global only if active
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
case "${1:-}" in
  --dry-run|--check) DRY_RUN=true ;;
  -h|--help)
    echo "Usage: $0 [--dry-run|--check]"
    exit 0
    ;;
esac

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

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

version_of() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '%s: ' "$cmd"
    "$cmd" --version 2>&1 | head -1 || true
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
    outdated="$("$BREW" outdated --cask "$name" 2>&1)"
    rc=$?
    if ((rc != 0)); then
      echo "$outdated"
      return "$rc"
    fi
    if [[ -n "$outdated" ]]; then
      "$BREW" upgrade --cask "$name"
    else
      echo "brew cask already up-to-date: $name"
    fi
  elif is_brew_formula_installed "$name"; then
    outdated="$("$BREW" outdated --formula "$name" 2>&1)"
    rc=$?
    if ((rc != 0)); then
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

echo "[$(ts)] AI CLI update started"
echo "host=$(hostname) user=$(id -un) dry_run=$DRY_RUN"

echo
echo "== before versions =="
version_of codex
version_of claude
version_of gemini

if command -v "$BREW" >/dev/null 2>&1; then
  if is_brew_cask_installed codex || is_brew_formula_installed codex || is_brew_cask_installed gemini-cli || is_brew_formula_installed gemini-cli; then
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
  run_optional_step "codex npm shadow copy" update_npm_package "@openai/codex"
fi

claude_updated=false
if active_path_contains claude "/node_modules/" || is_npm_global_installed "@anthropic-ai/claude-code"; then
  run_step "claude-code via npm" update_npm_package "@anthropic-ai/claude-code"
  claude_updated=true
elif ! command -v claude >/dev/null 2>&1; then
  pass_missing claude "command not found and npm global package not installed"
fi
if [[ "$claude_updated" != "true" ]] && command -v claude >/dev/null 2>&1; then
  run_optional_step "claude built-in update" claude update
fi

# Gemini: active install is Homebrew formula gemini-cli on this machine.
if is_brew_cask_installed gemini-cli || is_brew_formula_installed gemini-cli; then
  run_step "gemini-cli via brew" update_brew_package gemini-cli
elif active_path_contains gemini "/node_modules/" || is_npm_global_installed "@google/gemini-cli"; then
  run_step "gemini-cli via npm" update_npm_package "@google/gemini-cli"
else
  pass_missing gemini "no brew gemini-cli package and no npm global package"
fi

echo
echo "== after versions =="
hash -r || true
version_of codex
version_of claude
version_of gemini

echo
echo "log_file=$LOG_FILE"

if ((${#failures[@]})); then
  echo "[$(ts)] AI CLI update finished with failures: ${failures[*]}"
  exit 1
fi

echo "[$(ts)] AI CLI update finished successfully"
