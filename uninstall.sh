#!/usr/bin/env bash
# uninstall.sh — remove workflow slash-command symlinks and optionally restore backup.
# Never touches ~/.claude/projects (memory), sessions, or plans.
set -euo pipefail

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[0;33m'
BOLD=$'\033[1m'
NC=$'\033[0m'

say()  { printf "%s\n" "$*"; }
ok()   { printf "%s✓%s %s\n" "$GREEN" "$NC" "$*"; }
warn() { printf "%s!%s %s\n" "$YELLOW" "$NC" "$*"; }
info() { printf "%s%s%s\n" "$BOLD" "$*" "$NC"; }

info "This will remove workflow slash-command symlinks and optionally restore the latest backup."
warn "User memory (~/.claude/projects), sessions, and plans are NEVER touched."
read -r -p "Proceed? (y/N) " ans || true
case "${ans:-}" in
  y|Y|yes|YES) ;;
  *) say "aborted."; exit 0 ;;
esac

# ---------- 2) remove symlinks ----------
info "Removing slash-command symlinks"
for cmd in zero-to-one.md one-to-n.md debug-test.md; do
  target="$HOME/.claude/commands/$cmd"
  if [ -L "$target" ] || [ -f "$target" ]; then
    rm -f "$target"
    ok "removed commands/$cmd"
  else
    warn "commands/$cmd not present — skipping"
  fi
done

# ---------- 3) optional backup restore ----------
read -r -p "Restore the latest ~/.claude backup? (y/N) " ans || true
case "${ans:-}" in
  y|Y|yes|YES)
    latest_backup=""
    if compgen -G "$HOME/.claude/.backup.*" >/dev/null; then
      # pick newest by mtime
      latest_backup=$(ls -1dt "$HOME"/.claude/.backup.*/ 2>/dev/null | head -n1)
    fi
    if [ -z "${latest_backup:-}" ] || [ ! -d "$latest_backup" ]; then
      warn "no backup dirs found under ~/.claude/.backup.*"
    else
      info "Restoring from $latest_backup"
      # copy everything in the backup tree back into ~/.claude, preserving paths
      ( cd "$latest_backup" && find . -type f -print ) | while IFS= read -r rel; do
        rel=${rel#./}
        src="$latest_backup/$rel"
        dst="$HOME/.claude/$rel"
        mkdir -p "$(dirname "$dst")"
        cp -a "$src" "$dst"
        ok "restored $rel"
      done
      ok "restore complete (backup preserved at $latest_backup)"
    fi
    ;;
  *) info "skipping restore" ;;
esac

# ---------- 4) optional plugin uninstall ----------
read -r -p "Also uninstall the 3 Claude Code plugins (everything-claude-code, codex, caveman)? (y/N) " ans || true
case "${ans:-}" in
  y|Y|yes|YES)
    for p in "everything-claude-code@everything-claude-code" "codex@openai-codex" "caveman@caveman"; do
      if claude plugin uninstall "$p" >/dev/null 2>&1; then
        ok "uninstalled $p"
      else
        warn "failed to uninstall $p (may not be installed)"
      fi
    done
    ;;
  *) info "keeping plugins installed" ;;
esac

# ---------- 5) final message ----------
printf "\n%sUninstall complete.%s Backups retained at %s~/.claude/.backup.*/%s\n" \
  "$BOLD" "$NC" "$YELLOW" "$NC"
