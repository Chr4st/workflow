#!/usr/bin/env bash
# verify.sh — post-install sanity checks for the workflow bundle.
set -uo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
NC=$'\033[0m'

pass=0
fail=0
total=11

pass_line() { printf "%s✓%s %s\n" "$GREEN" "$NC" "$*"; pass=$((pass+1)); }
fail_line() { printf "%s✗%s %s\n" "$RED"   "$NC" "$*"; fail=$((fail+1)); }
warn_line() { printf "%s!%s %s\n" "$YELLOW" "$NC" "$*"; }

SETTINGS="$HOME/.claude/settings.json"

# 1) plugins enabled
if [ -f "$SETTINGS" ] \
   && jq -e '.enabledPlugins["everything-claude-code@everything-claude-code"] // false' "$SETTINGS" >/dev/null 2>&1 \
   && jq -e '.enabledPlugins["codex@openai-codex"] // false'                       "$SETTINGS" >/dev/null 2>&1 \
   && jq -e '.enabledPlugins["caveman@caveman"] // false'                          "$SETTINGS" >/dev/null 2>&1; then
  pass_line "all 3 required plugins enabled in settings.json"
else
  fail_line "one or more required plugins are not enabled"
fi

# 2) clarification.md present and non-empty
if [ -s "$HOME/.claude/rules/common/clarification.md" ]; then
  pass_line "rules/common/clarification.md present and non-empty"
else
  fail_line "rules/common/clarification.md missing or empty"
fi

# 3) at least 14 agent .md files
if [ -d "$HOME/.claude/agents" ]; then
  agent_count=$(find "$HOME/.claude/agents" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  if [ "${agent_count:-0}" -ge 14 ]; then
    pass_line "~/.claude/agents has $agent_count .md files (>=14)"
  else
    fail_line "~/.claude/agents has only ${agent_count:-0} .md files (need >=14)"
  fi
else
  fail_line "~/.claude/agents directory missing"
fi

# 4) session-start.js exists and parses as node
SS="$HOME/.claude/scripts/hooks/session-start.js"
if [ -f "$SS" ] && node --check "$SS" >/dev/null 2>&1; then
  pass_line "scripts/hooks/session-start.js is valid node syntax"
else
  fail_line "scripts/hooks/session-start.js missing or invalid"
fi

# 5) all 3 command symlinks exist and point to valid files
symlink_ok=true
for cmd in zero-to-one.md one-to-n.md debug-test.md research.md; do
  dst="$HOME/.claude/commands/$cmd"
  if [ -L "$dst" ]; then
    target=$(readlink "$dst" 2>/dev/null || echo "")
    if [ ! -f "$target" ]; then
      fail_line "commands/$cmd is a dangling symlink → $target"
      symlink_ok=false
    fi
  else
    fail_line "commands/$cmd is not a symlink"
    symlink_ok=false
  fi
done
if [ "$symlink_ok" = true ]; then
  pass_line "all 4 command symlinks valid and targets exist"
fi

# 6) statusLine key present
if [ -f "$SETTINGS" ] && jq -e '.statusLine' "$SETTINGS" >/dev/null 2>&1; then
  pass_line ".statusLine present in settings.json"
else
  fail_line ".statusLine missing from settings.json"
fi

# 7) codex CLI on PATH (only fail if user opted in)
OPTIN="$HOME/.claude/.workflow_codex_optin"
if command -v codex >/dev/null 2>&1; then
  pass_line "codex CLI is on PATH"
elif [ -f "$OPTIN" ]; then
  fail_line "codex CLI not on PATH (you opted in during install)"
else
  warn_line "codex CLI not installed — user did not opt in"
  pass_line "codex check skipped (opt-out)"
fi

# 7b) all rule files present
rule_count=$(find "$HOME/.claude/rules/common" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "${rule_count:-0}" -ge 11 ]; then
  pass_line "~/.claude/rules/common has $rule_count .md files (>=11)"
else
  fail_line "~/.claude/rules/common has only ${rule_count:-0} .md files (need >=11)"
fi

# 7c) hooks registered in settings.json
hooks_ok=true
for hook_cmd in "session-start.js" "post-tool-learning.js" "semgrep-posttool.js" "session-end.js" "mentor-stop.js" "workflow-verifier.js"; do
  if [ -f "$SETTINGS" ] && grep -q "$hook_cmd" "$SETTINGS" 2>/dev/null; then
    :
  else
    fail_line "hook $hook_cmd not registered in settings.json"
    hooks_ok=false
  fi
done
if [ "$hooks_ok" = true ]; then
  pass_line "all 6 hook scripts registered in settings.json"
fi

# 8) semgrep-posttool.js exists and parses
SP="$HOME/.claude/scripts/hooks/semgrep-posttool.js"
if [ -f "$SP" ] && node --check "$SP" >/dev/null 2>&1; then
  pass_line "scripts/hooks/semgrep-posttool.js is valid node syntax"
else
  fail_line "scripts/hooks/semgrep-posttool.js missing or invalid"
fi

# 9) claude --help works
if claude --help >/dev/null 2>&1; then
  pass_line "claude --help works"
else
  fail_line "claude --help failed"
fi

printf "\n%s/%s checks passed\n" "$pass" "$total"
[ "$fail" -eq 0 ] && exit 0 || exit 1
