# Bundle Contents

This repo ships a reproducible Claude Code setup. After `./install.sh`, your machine has Chris's workflow playbook, rule set, agents, hook scripts, and slash commands — minus personal project data. The bundle is intentionally core-only: the three workflow slash commands plus the supporting global configuration they depend on, and nothing that is tied to a specific vault, project, or credential.

This document describes exactly what lands on your machine after install, what was deliberately left out, and the few places where sanitization replaced personal references with placeholders you can fill in.

## What's included

| Path | Purpose | Notes |
|------|---------|-------|
| `commands/*.md` | 3 workflow slash commands (`/zero-to-one`, `/one-to-n`, `/debug-test`) | Symlinked to `~/.claude/commands/` so `git pull` in this repo updates the live commands instantly. |
| `rules/common/*.md` | 11 global rule files (clarification, testing, security, coding-style, git-workflow, performance, patterns, mentor, hooks, development-workflow, agents) | Copied to `~/.claude/rules/common/`. These are referenced by every workflow phase and by the global `CLAUDE.md`. |
| `agents/*.md` | 14 agent definitions (planner, architect, tdd-guide, code-reviewer, security-reviewer, build-error-resolver, e2e-runner, refactor-cleaner, doc-updater, and 5 more) | Copied to `~/.claude/agents/`. Each agent is a single markdown file with its own frontmatter and role prompt. |
| `scripts/hooks/*.js` | 5 SessionStart / PostToolUse / Stop hooks (including semgrep SAST scanner) | Copied to `~/.claude/scripts/hooks/`. Wired into `settings.json` via the hook registration block. |
| `scripts/lib/*.js` | 6 shared lib files (utils, project-detect, session-manager, mentor-detect, pattern-extract, formatter) | Copied to `~/.claude/scripts/lib/`. Imported by the hook scripts; not invoked directly. |
| `templates/CLAUDE.md.template` | Stub global instructions file | Merged into `~/.claude/CLAUDE.md`. If a `CLAUDE.md` already exists, install.sh backs it up before merging so existing content is preserved. |
| `templates/settings.json.template` | Baseline settings (plugins, hooks, statusLine) | jq-merged into `~/.claude/settings.json`. Never overwrites — existing keys win over template keys during the merge so your personal tweaks survive a re-run. |
| `templates/env.template` | Env var names only (no values) | Copied to `.env.example` in the repo root of your target project. You fill in your own secrets; the template ships with empty strings and comments explaining what each var is for. |
| `install.sh` | Idempotent installer | Creates `~/.claude/.backup.<timestamp>/` before any change. Safe to re-run. Uses `set -euo pipefail` so a failure at any step aborts cleanly without half-applying changes. |
| `verify.sh` | 8-check post-install verifier | Runs automatically at the end of `install.sh`. Checks: commands symlinked, rules copied, agents copied, hook scripts copied, lib files copied, CLAUDE.md present, settings.json valid JSON, all three plugins installed. |
| `uninstall.sh` | Removes symlinks and optional restore | Never deletes memory or sessions. Prompts before touching `CLAUDE.md` or `settings.json`. Backups at `~/.claude/.backup.*/` are retained so you can manually roll back further if you want. |

## What's NOT included

The bundle is deliberately scoped down. These things were left out and why:

- **Third-party plugin source** (`everything-claude-code`, `codex`, `caveman`) — these are installed via `claude plugin install` from the three official marketplaces. Shipping their source would fork them, and forks drift. Install.sh calls the plugin CLI so you always get the pinned upstream version.
- **Vault commands** (`/vault-find`, `/vault-session`, `/vault-daily`, `/vault-consolidate`, etc.) — these assume a specific Obsidian vault at `~/Desktop/Brain` with a specific folder layout and frontmatter schema. Too Brain-specific for a core bundle. The core ships only the three workflow commands.
- **Bug-bounty command** — a 26KB OWASP pipeline that most users do not need. Kept out of core; can be added back by copying `commands/bug-bounty.md` from the private playbook into `~/.claude/commands/` manually.
- **Python-specific rules** (`rules/python/`) — out of core scope. The global rules in `rules/common/` are language-agnostic; the Python-specific rules are packaged separately.
- **Personal memory, session history, plan files** — user-specific runtime state. `~/.claude/projects/`, `~/.claude/sessions/`, and any `memory/MEMORY.md` files are never touched by install.sh or uninstall.sh.
- **Real API keys** — `env.template` ships names only. There are no real secrets anywhere in this repo. The git history is audited and `git-secrets` scan hooks are recommended before every push.

## HOME_PATH substitution

`settings.json.template` uses the literal string `HOME_PATH` as a placeholder where an absolute home directory path is needed. `install.sh` replaces every occurrence of `HOME_PATH` with `$HOME` via `sed` before writing the merged file.

Why this matters: JSON does not support environment variable expansion at read time, and the caveman statusline hook needs a fully qualified absolute path to its script file. Writing `~/.claude/plugins/cache/caveman/caveman/statusline.sh` in a JSON string does not expand the tilde when Claude Code reads the file — the hook would fail silently with "file not found". Writing `$HOME/.claude/...` does not expand either. The only portable fix is a pre-write substitution, which is what `install.sh` does.

If you move your home directory or switch users, re-run `./install.sh` and the substitution runs again with the new value. The jq merge is designed so re-running is idempotent: the template path overwrites the old path but your other settings.json keys are preserved.

## Sanitization

Three files in the bundle contain placeholders instead of the original personal references. If you want the bundle to feel properly personalized, edit these three files with your own values after install.

- **`rules/common/mentor.md`** — personal project refs (RunVault, ObsidianTool, EVS) were replaced with `<your-past-project>` placeholders. The mentor rule encourages cross-project pattern references, and the original file had concrete examples citing Chris's repos. The bundled version keeps the cross-project reference pattern but strips the specific project names, so you can fill in your own past projects as you accumulate them.
- **`scripts/lib/mentor-detect.js`** — the project name map was emptied. The original file mapped directory basenames to canonical project names (e.g. `runvault-web` → `RunVault`). The bundled version ships with an empty map so you can add your own `dir → canonical` mapping. Without a mapping, the mentor detection still works but uses the raw directory name instead of a prettier canonical name.
- **`templates/CLAUDE.md.template`** — the Obsidian vault section was replaced with a stub. The original global `CLAUDE.md` documented the `~/Desktop/Brain` vault layout, frontmatter schema, and vault conventions in detail. The bundled template leaves a commented placeholder section for you to fill in if you use Obsidian, or delete if you do not.

None of the sanitization affects functionality. The three workflow commands and all 14 agents work identically whether or not you fill in the placeholders.

## Security

- **No real secrets** — the env template ships names and comments only. Every value is an empty string or a placeholder. There are no hardcoded API keys, tokens, or credentials anywhere in the bundle.
- **`install.sh` runs `set -euo pipefail`** — any failure at any step aborts the install cleanly. `-e` exits on error, `-u` treats unset variables as errors, `-o pipefail` propagates errors through pipes so a failure in any stage of a pipeline aborts the whole pipeline.
- **All copies back up first** — before any file is written, its existing version (if any) is moved to `~/.claude/.backup.<timestamp>/` with the original directory structure preserved. Re-running install.sh creates a new timestamped backup each time, so you can always roll back to the exact state before a specific re-install.
- **Plugin install happens via official marketplace only** — the three plugins are installed with `claude plugin install <name>@<version>` from the three marketplaces registered in step 1. No source is cloned from arbitrary URLs, no binaries are downloaded from non-official locations, and the version pins are enforced.
- **Verify step runs before declaring success** — `verify.sh` runs automatically at the end of `install.sh` and fails loudly if any of the 8 checks does not pass. The install is not "done" until verify is green.

## Plugin matrix

The bundle depends on three third-party plugins, each pinned to a specific version and installed from a specific marketplace. The pins are load-bearing: the workflows reference commands by name, and command names can drift between plugin versions.

| Plugin | Version pinned | Marketplace |
|--------|----------------|-------------|
| `everything-claude-code` | `1.7.0` | `affaan-m/everything-claude-code` |
| `codex` | `1.0.2` | `openai/codex-plugin-cc` |
| `caveman` | `600e8efcd6ac` | `JuliusBrussee/caveman` |
| `claude-hud` | latest | `jarrodwatts/claude-hud` |

### CLI Tools

| Tool | Purpose | Install |
|------|---------|---------|
| `rtk` | Compress Bash output before it enters context (PreToolUse hook). 60-90% token savings. | `brew install rtk && rtk init -g` |
| `semgrep` | Deterministic SAST on every Write/Edit (PostToolUse hook). 2,000+ rules. | `pip3 install semgrep` |
| Stryker / mutmut | Mutation testing — measures test strength beyond coverage. Per-project. | `npx stryker run` (JS/TS) / `mutmut run` (Python) |

The `caveman` pin is a git SHA rather than a semver tag because the caveman marketplace does not publish semver releases. `install.sh` passes the SHA to `claude plugin install` which resolves it against the marketplace's git history. If the SHA ever gets garbage collected upstream, pin-bumping is a one-line change in `install.sh`.

Each plugin provides a different slice of the workflow surface:

- `everything-claude-code@1.7.0` — 37 commands, 14 agents, 60 skills, most lifecycle hooks, and most of the MCP bundle. This is the biggest plugin and most of the playbook commands live inside it.
- `codex@1.0.2` — 7 Codex commands, the `codex-rescue` agent, 3 Codex skills, and the Codex CLI bridge that talks to GPT-5.4. Required for `/codex:adversarial-review`, `/codex:rescue`, and the multi-model routing in `/multi-plan`.
- `caveman@600e8efcd6ac` — 3 caveman commands, 5 compression skills, SessionStart and UserPromptSubmit hooks that enforce terse output, and the statusline script. Required for `/caveman full` and the compressed-mode workflows.

Without all three plugins installed, some steps in the workflows will become no-ops but the playbook will still produce useful output. The degradation is graceful — commands that depend on a missing plugin will skip with a warning rather than fail the session.
