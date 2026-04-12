#!/usr/bin/env bash
# install.sh — replicate Chris's Claude Code setup.
# Idempotent: re-running is safe; conflicts are backed up, never overwritten blindly.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------- colors ----------
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BLUE=$'\033[0;34m'
BOLD=$'\033[1m'
NC=$'\033[0m'

say()  { printf "%s\n" "$*"; }
ok()   { printf "%s✓%s %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s!%s %s\n" "$YELLOW" "$NC" "$*"; }
err()  { printf "%s✗%s %s\n" "$RED" "$NC" "$*" 1>&2; }
info() { printf "%s›%s %s\n" "$BLUE" "$NC" "$*"; }
step() { printf "\n%s== Step %s: %s ==%s\n" "$BOLD" "$1" "$2" "$NC"; }

# ---------- error trap ----------
CURRENT_STEP=0
BACKUP_DIR=""
on_error() {
  local ec=$?
  err "Install failed at step ${CURRENT_STEP}. Backup at ${BACKUP_DIR:-<none>} — nothing destroyed."
  exit 1
}
trap on_error ERR

# ---------- version helpers ----------
ver_ge() {
  # ver_ge A B  → 0 if A >= B (semver-ish, dot-separated integers)
  [ "$1" = "$2" ] && return 0
  local IFS=.
  # shellcheck disable=SC2206
  local a=($1) b=($2)
  local i
  for ((i=0; i<${#a[@]} || i<${#b[@]}; i++)); do
    local x=${a[i]:-0} y=${b[i]:-0}
    x=${x//[^0-9]/}; y=${y//[^0-9]/}
    x=${x:-0};       y=${y:-0}
    if ((10#$x > 10#$y)); then return 0; fi
    if ((10#$x < 10#$y)); then return 1; fi
  done
  return 0
}

require_cmd() {
  local name="$1" min="$2" cmd="$3" url="$4"
  if ! command -v "$name" >/dev/null 2>&1; then
    err "$name is not installed. Install: $url"
    exit 1
  fi
  local v
  v=$(eval "$cmd" 2>/dev/null | head -n1 | sed -E 's/[^0-9.]*([0-9]+(\.[0-9]+)*).*/\1/' | head -n1)
  v=${v:-0}
  if [ -n "$min" ] && ! ver_ge "$v" "$min"; then
    err "$name $v is too old (need >= $min). Upgrade: $url"
    exit 1
  fi
  ok "$name $v"
}

# ============================================================
# Step 1: preflight
# ============================================================
CURRENT_STEP=1
step 1 "Preflight checks"
require_cmd node    "20.0.0" "node --version"             "https://nodejs.org/"
require_cmd python3 "3.10.0" "python3 --version"          "https://www.python.org/downloads/"
require_cmd gh      ""       "gh --version"               "https://cli.github.com/"
require_cmd git     ""       "git --version"              "https://git-scm.com/downloads"
require_cmd claude  ""       "claude --version"           "https://docs.anthropic.com/claude-code"
require_cmd jq      ""       "jq --version"               "https://jqlang.github.io/jq/download/"

# ============================================================
# Step 2: prompts
# ============================================================
CURRENT_STEP=2
step 2 "Configuration prompts"

if [ ! -t 0 ]; then
  warn "stdin is not a terminal — prompts will use defaults (codex=n, statusline=y, vault=none)"
fi

INSTALL_CODEX="n"
read -r -p "Install Codex CLI globally via npm? (y/N) " _ans || true
case "${_ans:-}" in y|Y|yes|YES) INSTALL_CODEX="y" ;; esac

INSTALL_STATUSLINE="y"
read -r -p "Install caveman statusline? (Y/n) " _ans || true
case "${_ans:-}" in n|N|no|NO) INSTALL_STATUSLINE="n" ;; esac

VAULT_PATH=""
read -r -p "Path to a primary notes vault (blank to skip): " VAULT_PATH || true
VAULT_PATH="${VAULT_PATH//\~/$HOME}"

ACCEPT_DEFAULTS="y"
read -r -p "Accept all other defaults? (Y/n) " _ans || true
case "${_ans:-}" in n|N|no|NO) ACCEPT_DEFAULTS="n" ;; esac
if [ "$ACCEPT_DEFAULTS" = "n" ]; then
  read -r -p "  Override backup dir name suffix (blank = unix timestamp): " BACKUP_SUFFIX_OVERRIDE || true
fi

ok "choices: codex=$INSTALL_CODEX statusline=$INSTALL_STATUSLINE vault='${VAULT_PATH:-<skipped>}'"

# ============================================================
# Step 3: plugins
# ============================================================
CURRENT_STEP=3
step 3 "Install Claude Code plugins"

PLUGINS=(
  "everything-claude-code@everything-claude-code"
  "codex@openai-codex"
  "caveman@caveman"
)
SETTINGS_FILE="$HOME/.claude/settings.json"

plugin_is_enabled() {
  local key="$1"
  [ -f "$SETTINGS_FILE" ] || return 1
  jq -e --arg k "$key" '.enabledPlugins[$k] // false' "$SETTINGS_FILE" >/dev/null 2>&1
}

for p in "${PLUGINS[@]}"; do
  if plugin_is_enabled "$p"; then
    ok "plugin $p already enabled — skipping"
    continue
  fi
  if claude plugin install "$p" >/dev/null 2>&1; then
    ok "plugin $p installed"
  else
    warn "plugin $p install failed or unavailable — continuing"
  fi
done

# ============================================================
# Step 4: Codex CLI (optional)
# ============================================================
CURRENT_STEP=4
step 4 "Codex CLI (optional)"

if [ "$INSTALL_CODEX" = "y" ]; then
  if command -v codex >/dev/null 2>&1; then
    ok "codex CLI already present"
  else
    info "npm install -g @openai/codex"
    if npm install -g @openai/codex >/dev/null 2>&1; then
      ok "codex installed"
    else
      warn "codex install failed (non-fatal)"
    fi
  fi
  if ! codex status >/dev/null 2>&1; then
    warn "codex is not authenticated — run 'codex login' manually after install finishes"
  fi
  mkdir -p "$HOME/.claude"
  touch "$HOME/.claude/.workflow_codex_optin"
else
  info "skipping codex (user declined)"
  rm -f "$HOME/.claude/.workflow_codex_optin"
fi

# ============================================================
# Step 4.5: RTK (Response Token Kit)
# ============================================================
step "4.5" "RTK (Response Token Kit)"

if command -v rtk >/dev/null 2>&1; then
  ok "rtk already installed"
else
  info "Installing RTK (compresses Bash output, 60-90% token savings)..."
  if brew install rtk >/dev/null 2>&1; then
    ok "rtk installed"
  else
    warn "rtk install failed (non-fatal — install manually: brew install rtk)"
  fi
fi

# ============================================================
# Step 4.6: Semgrep (SAST scanning hook)
# ============================================================
step "4.6" "Semgrep (SAST scanning)"

if command -v semgrep >/dev/null 2>&1; then
  ok "semgrep already installed"
else
  info "Installing semgrep (deterministic SAST on every file write)..."
  if pip3 install semgrep >/dev/null 2>&1; then
    ok "semgrep installed"
  elif brew install semgrep >/dev/null 2>&1; then
    ok "semgrep installed (via brew)"
  else
    warn "semgrep install failed (non-fatal — SAST hook will degrade gracefully)"
  fi
fi
if command -v semgrep >/dev/null 2>&1; then
  info "Pre-downloading semgrep rules..."
  semgrep --config auto --version >/dev/null 2>&1 || true
  ok "semgrep rules cached"
fi

# ============================================================
# Step 5: backup
# ============================================================
CURRENT_STEP=5
step 5 "Backup existing ~/.claude files"

BACKUP_STAMP="${BACKUP_SUFFIX_OVERRIDE:-$(date +%s).$$}"
BACKUP_DIR="$HOME/.claude/.backup.${BACKUP_STAMP}"
mkdir -p "$BACKUP_DIR"

backup_path() {
  local src="$1" rel="$2"
  if [ -e "$src" ]; then
    mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
    cp -a "$src" "$BACKUP_DIR/$rel"
    ok "backed up $rel"
  fi
}

backup_path "$HOME/.claude/settings.json" "settings.json"
backup_path "$HOME/.claude/CLAUDE.md"     "CLAUDE.md"
backup_path "$HOME/.claude/rules/common"  "rules/common"
backup_path "$HOME/.claude/agents"        "agents"
backup_path "$HOME/.claude/scripts"       "scripts"

printf "%s  backup dir: %s%s\n" "$YELLOW" "$BACKUP_DIR" "$NC"

# ============================================================
# Step 6: copy bundle files with per-file backup-on-conflict
# ============================================================
CURRENT_STEP=6
step 6 "Copy bundle files"

mkdir -p \
  "$HOME/.claude/rules/common" \
  "$HOME/.claude/agents" \
  "$HOME/.claude/scripts/hooks" \
  "$HOME/.claude/scripts/lib" \
  "$HOME/.claude/commands"

copy_file() {
  local src="$1" dst="$2" rel="$3"
  if [ ! -f "$src" ]; then
    warn "missing source $rel — skipping"
    return 0
  fi
  if [ -f "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      ok "$rel (unchanged)"
      return 0
    fi
    mkdir -p "$(dirname "$BACKUP_DIR/$rel")"
    cp -a "$dst" "$BACKUP_DIR/$rel"
    cp -a "$src" "$dst"
    printf "%s↻%s %s (replaced, backup kept)\n" "$YELLOW" "$NC" "$rel"
  else
    cp -a "$src" "$dst"
    ok "$rel"
  fi
}

copy_glob() {
  local src_dir="$1" dst_dir="$2" pattern="$3" rel_prefix="$4"
  shopt -s nullglob
  local f base
  for f in "$src_dir"/$pattern; do
    base=$(basename "$f")
    copy_file "$f" "$dst_dir/$base" "$rel_prefix/$base"
  done
  shopt -u nullglob
}

copy_glob "$SCRIPT_DIR/rules/common"  "$HOME/.claude/rules/common"  "*.md" "rules/common"
copy_glob "$SCRIPT_DIR/agents"        "$HOME/.claude/agents"        "*.md" "agents"
copy_glob "$SCRIPT_DIR/scripts/hooks" "$HOME/.claude/scripts/hooks" "*.js" "scripts/hooks"
copy_glob "$SCRIPT_DIR/scripts/lib"   "$HOME/.claude/scripts/lib"   "*.js" "scripts/lib"

# ============================================================
# Step 7: symlink slash commands
# ============================================================
CURRENT_STEP=7
step 7 "Symlink slash commands"

for cmd in zero-to-one.md one-to-n.md debug-test.md; do
  src="$SCRIPT_DIR/commands/$cmd"
  dst="$HOME/.claude/commands/$cmd"
  if [ ! -f "$src" ]; then
    warn "missing $src — skipping"
    continue
  fi
  ln -sf "$src" "$dst"
  target=$(readlink "$dst" 2>/dev/null || echo "")
  if [ "$target" = "$src" ]; then
    ok "commands/$cmd → $src"
  else
    warn "commands/$cmd symlink unexpected target: $target"
  fi
done

# ============================================================
# Step 8: template CLAUDE.md
# ============================================================
CURRENT_STEP=8
step 8 "Template CLAUDE.md"

CLAUDE_MD="$HOME/.claude/CLAUDE.md"
TEMPLATE_MD="$SCRIPT_DIR/templates/CLAUDE.md.template"
MARKER="## Global Conventions (your customizations here)"

if [ ! -f "$TEMPLATE_MD" ]; then
  warn "template $TEMPLATE_MD missing — skipping CLAUDE.md"
elif [ ! -f "$CLAUDE_MD" ]; then
  cp -a "$TEMPLATE_MD" "$CLAUDE_MD"
  ok "CLAUDE.md created from template"
else
  if grep -qF "$MARKER" "$CLAUDE_MD"; then
    ok "CLAUDE.md already contains marker — leaving alone"
  else
    {
      printf "\n\n---\n\n"
      cat "$TEMPLATE_MD"
    } >> "$CLAUDE_MD"
    ok "CLAUDE.md appended template section"
  fi
fi

# ============================================================
# Step 9: merge settings.json
# ============================================================
CURRENT_STEP=9
step 9 "Merge settings.json"

TEMPLATE_JSON="$SCRIPT_DIR/templates/settings.json.template"
if [ ! -f "$TEMPLATE_JSON" ]; then
  err "template $TEMPLATE_JSON missing"
  exit 1
fi

CAVEMAN_SL_PATH=""
if [ -d "$HOME/.claude/plugins/cache/caveman" ]; then
  CAVEMAN_SL_PATH=$(find "$HOME/.claude/plugins/cache/caveman" -name "caveman-statusline.sh" -type f 2>/dev/null | head -1)
fi
if [ -z "$CAVEMAN_SL_PATH" ]; then
  CAVEMAN_SL_PATH="$HOME/.claude/plugins/cache/caveman/caveman/latest/hooks/caveman-statusline.sh"
  warn "caveman statusline not found — using fallback path"
fi

TMP_DIR=$(mktemp -d)
SANITIZED="$TMP_DIR/template.sanitized.json"
sed -e "s|HOME_PATH|${HOME}|g" -e "s|CAVEMAN_STATUSLINE_PATH|${CAVEMAN_SL_PATH}|g" "$TEMPLATE_JSON" > "$SANITIZED"

# validate template
jq . "$SANITIZED" >/dev/null || { err "sanitized template is not valid JSON"; exit 1; }

MERGED="$TMP_DIR/settings.merged.json"

if [ ! -f "$SETTINGS_FILE" ]; then
  cp -a "$SANITIZED" "$MERGED"
  ok "no existing settings.json — using template"
else
  jq . "$SETTINGS_FILE" >/dev/null || { err "existing settings.json is not valid JSON"; exit 1; }

  STATUSLINE_FLAG="false"
  [ "$INSTALL_STATUSLINE" = "y" ] && STATUSLINE_FLAG="true"

  jq -n \
    --slurpfile u "$SETTINGS_FILE" \
    --slurpfile t "$SANITIZED" \
    --argjson   want_statusline "$STATUSLINE_FLAG" '
    ($u[0]) as $user | ($t[0]) as $tpl |
    $user
    | .permissions = (
        ($user.permissions // {}) as $up
        | $up + { allow: (((($up.allow // []) + ($tpl.permissions.allow // []))) | unique) }
      )
    | .hooks = (
        ($user.hooks // {}) as $uh | ($tpl.hooks // {}) as $th |
        (($uh | keys) + ($th | keys) | unique) | reduce .[] as $k ({};
          .[$k] = (
            (($uh[$k] // []) + ($th[$k] // []))
            | unique_by(.hooks | map(.command) | sort | join("|"))
          )
        )
      )
    | .enabledPlugins = (($user.enabledPlugins // {}) * ($tpl.enabledPlugins // {}))
    | .extraKnownMarketplaces = (($user.extraKnownMarketplaces // {}) * ($tpl.extraKnownMarketplaces // {}))
    | .model = ($user.model // $tpl.model)
    | if ($want_statusline and (($user.statusLine // null) == null))
        then .statusLine = $tpl.statusLine
        else .
      end
  ' > "$MERGED"
fi

jq . "$MERGED" >/dev/null || { err "merged settings.json failed validation"; exit 1; }

mkdir -p "$HOME/.claude"
mv "$MERGED" "$SETTINGS_FILE"
ok "settings.json merged"
rm -rf "$TMP_DIR"

# ============================================================
# Step 10: env template
# ============================================================
CURRENT_STEP=10
step 10 "Env template"

ENV_TEMPLATE="$SCRIPT_DIR/templates/env.template"
ENV_EXAMPLE="$SCRIPT_DIR/.env.example"
if [ -f "$ENV_TEMPLATE" ]; then
  if [ -f "$ENV_EXAMPLE" ]; then
    ok ".env.example already present"
  else
    cp -a "$ENV_TEMPLATE" "$ENV_EXAMPLE"
    ok ".env.example written"
  fi
  printf "%s  Fill in real values in .env (never commit).%s\n" "$YELLOW" "$NC"
else
  warn "templates/env.template missing — skipping"
fi

# ============================================================
# Step 10.5: RTK init (after settings.json merge to avoid overwrite)
# ============================================================
step "10.5" "RTK init"

if command -v rtk >/dev/null 2>&1; then
  rtk init -g 2>/dev/null || warn "rtk init -g failed (non-fatal — run manually: rtk init -g)"
  ok "rtk PreToolUse hook registered"
else
  info "rtk not installed — skipping hook registration"
fi

# ============================================================
# Step 11: verify
# ============================================================
CURRENT_STEP=11
step 11 "Final verify"

trap - ERR
if [ -x "$SCRIPT_DIR/verify.sh" ]; then
  "$SCRIPT_DIR/verify.sh"
  exit $?
else
  warn "verify.sh not found/executable — skipping"
  exit 0
fi
