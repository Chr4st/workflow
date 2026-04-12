# Troubleshooting

`install.sh` is idempotent — if a step fails, fix the underlying problem and re-run. Every re-run creates a fresh timestamped backup before making changes, so you cannot lose state by re-running. This document covers the failure modes that actually happen in practice, in rough order of how common they are.

## "claude: command not found"

The installer needs the Claude Code CLI on your `PATH`. Install Claude Code first: see [docs.claude.com/en/docs/claude-code](https://docs.claude.com/en/docs/claude-code) for the official instructions. Confirm with `claude --version` before re-running `./install.sh`.

## "jq: command not found"

The installer uses `jq` to merge the settings.json template with any existing settings you already have. Install it:

- macOS: `brew install jq`
- Debian / Ubuntu: `sudo apt install jq`
- Fedora: `sudo dnf install jq`
- Arch: `sudo pacman -S jq`

Then re-run `./install.sh`.

## "Plugin already installed" warning

Benign. `install.sh` detects existing plugin installations and skips the install step for any plugin that is already present at the pinned version. The warning is emitted so you know the step was skipped intentionally, not silently. No action required — continue reading the install log for later steps.

## "Settings.json merge failed"

Almost always a malformed existing `~/.claude/settings.json`. Check it with:

```bash
jq . ~/.claude/settings.json
```

If `jq` reports a syntax error, fix the syntax (most often a trailing comma or an unclosed brace), then re-run `./install.sh`. The installer backs up the old file before merging, so you can always recover from `~/.claude/.backup.<timestamp>/settings.json` if you need the original.

## Statusline doesn't appear

The caveman statusline hook needs its script file to exist at a fully qualified path. Check:

```bash
ls ~/.claude/plugins/cache/caveman/caveman/
```

If that directory is empty or missing, re-install the caveman plugin:

```bash
claude plugin uninstall caveman
claude plugin install caveman@600e8efcd6ac
```

Then re-run `./install.sh` so the HOME_PATH substitution re-writes the statusline path into `settings.json`.

## "Permission denied" on install.sh

The script lost its executable bit (common after a fresh clone on some shells). Fix:

```bash
chmod +x install.sh
./install.sh
```

Same applies to `uninstall.sh` and `verify.sh`.

## Symlinks broken after moving the repo

`install.sh` creates symlinks from `~/.claude/commands/` back to the repo's `commands/` directory. If you `mv` the repo to a new path, the symlinks point at the old location and break. Fix by re-running `./install.sh` from the new location — step 7 re-links the commands to the current repo path.

## "codex: command not found" after opting in

The `codex` plugin installs the `@openai/codex` npm package globally. If that install failed silently, the plugin is present but the CLI is not. Check your npm global prefix:

```bash
npm config get prefix
```

Confirm that directory is writable and on your `PATH`. If not, either fix the prefix (`npm config set prefix ~/.npm-global`) or run `npm install -g @openai/codex` with `sudo` as a last resort. Then re-run `./install.sh`.

## Want to roll back completely

Run `./uninstall.sh` and answer `yes` to both prompts. The first prompt removes the command symlinks and the copied rules/agents/scripts. The second prompt optionally restores `CLAUDE.md` and `settings.json` from the most recent backup. Backups at `~/.claude/.backup.*/` are always retained — uninstall never deletes them, so you can manually recover any prior state.

## Hook scripts throwing errors on SessionStart

A syntax error in one of the copied hook scripts. Verify the session-start hook first:

```bash
node --check ~/.claude/scripts/hooks/session-start.js
```

If Node reports a syntax error, the copy got corrupted. Restore from the most recent backup:

```bash
cp ~/.claude/.backup.<timestamp>/scripts/hooks/session-start.js ~/.claude/scripts/hooks/
```

Then re-run `./install.sh`.

## Plan mode stuck, clarification gate not firing

The clarification gate is enforced by `~/.claude/rules/common/clarification.md`. If that file is missing or empty, the gate silently disappears. Verify:

```bash
ls -l ~/.claude/rules/common/clarification.md
wc -l ~/.claude/rules/common/clarification.md
```

If the file is missing or zero bytes, re-run `./install.sh` — step 6 (copy rules) will restore it from the bundle.

## "Verify failed: N/8 checks passed"

`verify.sh` runs 8 independent checks and prints the path it inspected for each failing check. Fix them individually:

- **Commands not symlinked** — `./install.sh` step 7 failed or the symlink target is wrong. Re-run.
- **Rules not copied** — `./install.sh` step 6 failed. Check `~/.claude/rules/common/` permissions and re-run.
- **Agents not copied** — same fix as rules.
- **Hook scripts not copied** — same fix, step 5.
- **Lib files not copied** — same fix, step 5.
- **CLAUDE.md missing** — step 8 failed. Check `~/.claude/CLAUDE.md` is writable.
- **settings.json invalid** — run `jq . ~/.claude/settings.json` to find the syntax error.
- **Plugin not installed** — a plugin install step failed upstream. Scroll up in the install log to find the actual error.

Each check is independent, so fixing one does not require rolling back others. After fixing, re-run either `./install.sh` (full install, safe) or just `./verify.sh` (check only).
