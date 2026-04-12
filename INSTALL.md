# Installation Guide — Claude Code Workflow Playbook

## Recommended: automated install

```bash
git clone https://github.com/Chr4st/workflow.git
cd workflow
./install.sh
```

That handles steps 1–11 below automatically, with backups. The manual steps below are for debugging, partial reinstalls, or users who want to understand each action.

---

This guide walks you through setting up a Claude Code environment that can run all three workflows in the playbook end-to-end: `zero-to-one` (greenfield), `one-to-n` (features in large codebases), and `debug-test` (reproduce → lock → fix → persist). When you finish, you will have three plugins installed (`everything-claude-code`, `codex`, `caveman`), nine MCP servers wired up (`engram`, `gitnexus`, `exa-web-search`, `firecrawl`, `github`, `supabase`, `context7`, `sequential-thinking`, `filesystem`), lifecycle hooks active (session context load, auto-format, pattern extraction, terse-mode toggle), an optional Obsidian Brain vault for long-term memory, and the three workflow slash commands registered with Claude Code. Expect **~30 minutes** of wall-clock time if prerequisites are already in place, or **~60 minutes** from a clean Mac. Primary target is **macOS 14+**. Linux works with minor path adjustments (noted inline); Windows requires WSL2.

---

## Prerequisites

Before you begin, make sure the following are installed and working:

- **macOS 14+** (Sonoma or later). Linux works with path adjustments; Windows users should run everything inside WSL2.
- **Node.js 20+** with `npm` or `pnpm`. Install via `brew install node` or [nvm](https://github.com/nvm-sh/nvm).
- **Python 3.10+** (required by `caveman-compress` and several hooks). `brew install python@3.12`.
- **Homebrew** — [brew.sh](https://brew.sh).
- **Git 2.40+** — `brew install git`.
- **GitHub CLI** authenticated — `brew install gh && gh auth login`. Needed for `gh search repos/code`, `gh pr create`, and the `github` MCP.
- **Claude Code CLI** installed and logged in. Follow Anthropic's install instructions; confirm with `claude --version` and one successful session.
- **Anthropic API key** (`ANTHROPIC_API_KEY`) **or** an active Claude Max/Pro subscription linked to the CLI.
- **OpenAI API key** — required by the `codex` plugin's CLI bridge. Store in `$OPENAI_API_KEY` or let `codex login` handle it interactively.
- **Wispr Flow** installed and configured for voice-to-text (required prerequisite per Chris's setup). Download from [wisprflow.ai](https://wisprflow.ai), grant Accessibility + Microphone permissions, pick a global hotkey.
- **Obsidian** with a vault at `~/Desktop/Brain` (optional but strongly recommended — the `/vault-*` commands assume this path).
- **tmux** — `brew install tmux`. Several PreToolUse hooks remind you to wrap long-running commands in tmux.

Quick sanity check:

```bash
node --version      # >= v20
python3 --version   # >= 3.10
git --version
gh auth status
claude --version
tmux -V
```

If any of these fail, fix them before proceeding.

---

## Step 1 — Install Claude Code plugins

Claude Code's plugin system installs from marketplaces. The three plugins in this playbook live in three different marketplaces, so the first step is to register the marketplaces, then install the plugins.

### 1a. Add the marketplaces

Inside a running Claude Code session:

```
/plugin marketplace add affaan-m/everything-claude-code
/plugin marketplace add openai/codex-plugin-cc
/plugin marketplace add JuliusBrussee/caveman
```

(Exact syntax may vary slightly by Claude Code version — run `/plugin help` if the above errors.)

Alternately, add them declaratively in `~/.claude/settings.json` under `extraKnownMarketplaces`:

```json
{
  "extraKnownMarketplaces": {
    "everything-claude-code": {
      "source": { "source": "github", "repo": "affaan-m/everything-claude-code" }
    },
    "openai-codex": {
      "source": { "source": "github", "repo": "openai/codex-plugin-cc" }
    },
    "caveman": {
      "source": { "source": "github", "repo": "JuliusBrussee/caveman" }
    }
  }
}
```

### 1b. Install each plugin

```
/plugin install everything-claude-code@everything-claude-code
/plugin install codex@openai-codex
/plugin install caveman@caveman
```

Then enable them by adding (or confirming) this block in `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "everything-claude-code@everything-claude-code": true,
    "codex@openai-codex": true,
    "caveman@caveman": true
  }
}
```

### 1c. Verify

Run `/plugin list` — you should see all three listed as `enabled`. If a plugin is missing, re-run `/plugin install <name>` and check the Claude Code output for errors.

### 1d. What each plugin provides

| Plugin | Version | Ships |
|---|---|---|
| `everything-claude-code` | 1.7.0 | 37 commands, 14 agents, 60 skills, bundled MCP stubs, lifecycle hooks (SessionStart context load, PostToolUse auto-format, SessionEnd pattern extraction), instinct/learning system |
| `codex` | 1.0.2 | 7 commands (`/codex:setup`, `/codex:rescue`, `/codex:adversarial-review`, `/codex:status`, `/codex:result`, `/codex:cancel`, plus config), `codex-rescue` agent, 3 skills (`gpt-5-4-prompting`, `codex-cli-runtime`, `codex-result-handling`), session lifecycle hooks |
| `caveman` | 600e8efc | 3 commands (`/caveman`, `/caveman-commit`, `/caveman-review`), 5 skills, SessionStart terse-mode activation, UserPromptSubmit mode tracker, statusline badge |

---

## Step 2 — Install Codex CLI and authenticate

The `codex` plugin is a bridge to OpenAI's Codex CLI. You must install the CLI separately and authenticate it before the plugin commands work.

```bash
npm install -g @openai/codex
codex --version       # confirm install
codex login           # opens browser for OpenAI OAuth
```

If `codex login` fails, set `OPENAI_API_KEY` in your shell profile instead:

```bash
echo 'export OPENAI_API_KEY="sk-..."' >> ~/.zshrc
source ~/.zshrc
```

Then verify from inside Claude Code:

```
/codex:setup
```

This command runs the plugin's readiness check: it confirms the CLI is on `$PATH`, the auth token is valid, and the session lifecycle hook is wired. A green `ready` message means you can use `/codex:rescue` and `/codex:adversarial-review` in the workflows.

**Trade-off note:** `codex:setup` is idempotent — re-run it any time you rotate an OpenAI key or upgrade the CLI.

---

## Step 3 — Configure MCP servers

Claude Code loads MCP servers from `~/.claude/mcp.json` (or from the `mcpServers` block in `~/.claude/settings.json`, depending on version). Below is a minimal working set for this playbook. **Drop the servers you don't need** — each one adds startup latency.

### 3a. Template `~/.claude/mcp.json`

```json
{
  "mcpServers": {
    "engram": {
      "command": "engram-mcp",
      "args": [],
      "env": { "ENGRAM_DATA_DIR": "/Users/christxu/.engram" }
    },
    "gitnexus": {
      "command": "gitnexus-mcp",
      "args": ["--service-url", "http://localhost:8787"],
      "env": {}
    },
    "exa-web-search": {
      "command": "npx",
      "args": ["-y", "exa-mcp-server"],
      "env": { "EXA_API_KEY": "${EXA_API_KEY}" }
    },
    "firecrawl": {
      "command": "npx",
      "args": ["-y", "firecrawl-mcp"],
      "env": { "FIRECRAWL_API_KEY": "${FIRECRAWL_API_KEY}" }
    },
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": { "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PAT}" }
    },
    "supabase": {
      "command": "npx",
      "args": ["-y", "@supabase/mcp-server-supabase"],
      "env": {
        "SUPABASE_PROJECT_REF": "${SUPABASE_PROJECT_REF}",
        "SUPABASE_ACCESS_TOKEN": "${SUPABASE_ACCESS_TOKEN}"
      }
    },
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"],
      "env": {}
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"],
      "env": {}
    },
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/Users/christxu/workflow",
        "/Users/christxu/Desktop/Brain",
        "/Users/christxu/code"
      ],
      "env": {}
    }
  }
}
```

### 3b. Per-server notes

| Server | Purpose | Required credential | Verify |
|---|---|---|---|
| `engram` | Persistent memory across sessions (decisions, bug fixes, discoveries) | None — local file store at `$ENGRAM_DATA_DIR` | `mem_stats` returns counts; `mem_context` returns recent timeline |
| `gitnexus` | Code knowledge graph (impact, route_map, tool_map, api_impact, shape_check) | Running local service + repo indexed | `mcp__gitnexus__list_repos` returns your repos |
| `exa-web-search` | Broad prior-art discovery during planning | `EXA_API_KEY` from [exa.ai](https://exa.ai) | Any `/multi-plan` Research phase call succeeds |
| `firecrawl` | Scraped web content ingestion | `FIRECRAWL_API_KEY` from [firecrawl.dev](https://firecrawl.dev) | Fetching any URL returns markdown |
| `github` | `gh search`, PR ops, issues | `GITHUB_PAT` with `repo, read:org` scopes | `gh auth status` already covers it; MCP tool calls return JSON |
| `supabase` | Project DB + auth ops (optional) | `SUPABASE_PROJECT_REF` + `SUPABASE_ACCESS_TOKEN` | Project info call returns schema |
| `context7` | Live docs lookup for stacks | None | Any library docs query returns versioned docs |
| `sequential-thinking` | Chain-of-thought reasoning scaffold | None | Tool list shows `sequentialthinking` |
| `filesystem` | Scoped file access outside cwd | Allowed paths in args | File read inside an allowed path works |

### 3c. Export credentials

Add to `~/.zshrc` (or `~/.bashrc` on Linux):

```bash
export EXA_API_KEY="exa_..."
export FIRECRAWL_API_KEY="fc_..."
export GITHUB_PAT="ghp_..."
export SUPABASE_PROJECT_REF="..."
export SUPABASE_ACCESS_TOKEN="..."
# Optional:
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."
export MAX_THINKING_TOKENS=10000
```

Then `source ~/.zshrc` and restart Claude Code so MCP servers re-read the env.

### 3d. GitNexus setup (deeper)

GitNexus needs a running service and per-repo indexing:

```bash
# One-time: start the gitnexus service (adjust to your install path)
brew services start gitnexus      # if available via Homebrew
# or run from the gitnexus repo:
cd ~/code/gitnexus && ./run.sh &

# Per-repo: index the repo you want graph queries for
mcp__gitnexus__list_repos          # confirm service is reachable
# Indexing is triggered automatically on first impact/context call, or manually via the gitnexus CLI
```

If `mcp__gitnexus__list_repos` returns empty after you've opened a repo, re-run it after the first successful `mcp__gitnexus__context <symbol>` call — gitnexus indexes lazily.

---

## Step 4 — Enable hooks

Good news: **most hooks ship with the plugins and need zero configuration**. Here's what's already wired once plugins are enabled:

### 4a. Plugin-provided hooks (automatic)

- **`everything-claude-code` hooks:**
  - `SessionStart` — loads previous context, detects package manager
  - `PreToolUse` — blocks dev servers outside tmux, reminds before `git push`, captures tool observations (continuous-learning-v2)
  - `PostToolUse` — auto-format JS/TS, TypeScript type-check, `console.log` warning, PR URL logging, async build analysis
  - `PreCompact` — saves state before compaction
  - `SessionEnd` — persists session + extracts patterns
- **`caveman` hooks:**
  - `SessionStart` — activates caveman full mode, writes statusline flag
  - `UserPromptSubmit` — tracks active mode so the statusline stays in sync
- **`codex` hooks:**
  - `SessionStart` + `SessionEnd` — `session-lifecycle-hook.mjs` tracks Codex job state
  - `Stop` (optional, 15 min timeout) — stop-time review gate

### 4b. Your own settings.json hooks

Chris's `~/.claude/settings.json` also registers three custom Node.js hooks on top of the plugins:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node ~/.claude/scripts/hooks/session-start.js",
            "timeout": 30,
            "statusMessage": "Loading previous session context..."
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node ~/.claude/scripts/hooks/post-tool-learning.js",
            "timeout": 10,
            "statusMessage": "Capturing learning..."
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "node ~/.claude/scripts/hooks/session-end.js",
            "timeout": 60,
            "statusMessage": "Saving session summary..."
          },
          {
            "type": "command",
            "command": "node ~/.claude/scripts/hooks/mentor-stop.js",
            "timeout": 10,
            "statusMessage": "Mentor checkpoint..."
          }
        ]
      }
    ]
  }
}
```

These are optional but recommended — they power the mentor system and engram auto-capture. If you don't have the scripts, omit this block (the plugin hooks still run).

### 4c. Caveman statusline

Add the caveman badge to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash \"/Users/christxu/.claude/plugins/cache/caveman/caveman/600e8efcd6ac/hooks/caveman-statusline.sh\""
  }
}
```

The `600e8efcd6ac` segment is the installed version hash and **will differ on your machine**. Find yours with:

```bash
ls ~/.claude/plugins/cache/caveman/caveman/
```

Take the single directory name that appears and substitute it into the path. After restart, the status line should show `[CAVEMAN]` or similar when terse mode is active.

---

## Step 5 — Install the workflow playbook commands

> Automated path: `./install.sh` handles this in step 6 (copy files) and step 7 (symlink commands). Manual steps below are for debugging.

The three playbook commands live in `~/workflow/commands/`:

- `zero-to-one.md` — Workflow A (greenfield)
- `one-to-n.md` — Workflow B (features in large codebases)
- `debug-test.md` — Workflow C (reproduce → lock → fix → persist)

Claude Code discovers slash commands from `~/.claude/commands/`. Pick **one** of the three registration strategies below.

### Option 1 — Symlink (recommended)

Keeps `~/workflow/` as the source of truth so `git pull` in that directory updates live commands instantly.

```bash
mkdir -p ~/.claude/commands
ln -sf ~/workflow/commands/zero-to-one.md ~/.claude/commands/zero-to-one.md
ln -sf ~/workflow/commands/one-to-n.md    ~/.claude/commands/one-to-n.md
ln -sf ~/workflow/commands/debug-test.md  ~/.claude/commands/debug-test.md
```

Verify:

```bash
ls -l ~/.claude/commands/ | grep workflow
```

Inside Claude Code, type `/` and confirm `zero-to-one`, `one-to-n`, and `debug-test` appear in the slash command picker.

### Option 2 — Copy

Simpler, but you must re-copy after every `~/workflow/` edit.

```bash
mkdir -p ~/.claude/commands
cp ~/workflow/commands/*.md ~/.claude/commands/
```

### Option 3 — Read on demand

Skip registration and invoke with `Read ~/workflow/commands/zero-to-one.md` at session start. Useful if you want to experiment with the content without registering new slash commands yet.

**Trade-off:** symlink = zero drift but fragile to path moves; copy = stable but stale; read = zero install but extra tokens per session.

---

## Step 6 — Configure global rules

> Automated path: `./install.sh` handles this in step 6 (copy files) and step 7 (symlink commands). Manual steps below are for debugging.

Chris's global rules live in `~/.claude/CLAUDE.md` and `~/.claude/rules/common/*.md`. They define:

- **`coding-style.md`** — immutability, many small files (<800 LOC), error handling, input validation
- **`testing.md`** — 80%+ coverage minimum, TDD workflow (RED → GREEN → REFACTOR)
- **`git-workflow.md`** — Conventional Commits, PR workflow, commit message format
- **`performance.md`** — Opus/Sonnet/Haiku model selection strategy, context window hygiene
- **`patterns.md`** — skeleton-first search, repository pattern, consistent API envelope
- **`mentor.md`** — trade-off reasoning on every implementation, growth-edge flagging
- **`security.md`** — mandatory pre-commit checks, secret management
- **`hooks.md`** — hook type reference
- **`agents.md`** — agent orchestration, parallel Task execution
- **`development-workflow.md`** — Research → Plan → TDD → Review → Commit pipeline

These are already set up for Chris. **For a new user**, either:

1. **Clone Chris's rules wholesale** (if they're in a public repo):
   ```bash
   git clone <rules-repo> ~/.claude/rules
   ```
2. **Start minimal** — copy just `coding-style.md` and `testing.md` into `~/.claude/rules/common/` and add a `~/.claude/CLAUDE.md` with an `@import` or paste:
   ```bash
   mkdir -p ~/.claude/rules/common
   # paste your own or fetch from a template repo
   ```

The playbook commands reference these rules by name in several places (e.g., `/tdd` defers to `testing.md`), so a totally empty rules dir will leave some behaviors underspecified but still functional.

---

## Step 7 — Configure Obsidian vault (optional but recommended)

The `/vault-*` commands all default to `~/Desktop/Brain`. If you don't have it yet:

### 7a. Create the vault

```bash
mkdir -p ~/Desktop/Brain/{daily,weekly,sessions,notes,code-projects}
```

Then in Obsidian: **File → Open vault → Open folder as vault → `~/Desktop/Brain`**.

### 7b. Install recommended plugins

Enable Community plugins in Obsidian settings, then install:

- **Dataview** — SQL-like queries over frontmatter (used by `/vault-find`)
- **Smart Connections** — semantic search across notes
- **Obsidian Charts** — inline chart rendering for weekly reviews

### 7c. Frontmatter conventions

Every new note must carry YAML frontmatter. The playbook commands write these fields automatically, but if you create notes by hand follow these schemas:

**`daily/YYYY-MM-DD.md`:**
```yaml
---
type: daily
cssclasses: [daily-note]
date: 2026-04-11
sessions: []
projects: []
---
```

**`sessions/YYYY-MM-DD-<slug>.md`:**
```yaml
---
type: session
cssclasses: [session-note]
status: active
source: claude-code
project: workflow-playbook
started_at: 2026-04-11T09:00:00-07:00
aliases: []
---
```

**`weekly/<year>-W<week>.md`:** same structure as daily, `type: weekly`.

Rules (from `~/.claude/CLAUDE.md`):
- Always use `[[wikilink]]` style for cross-note references.
- **Never delete vault files** — append or update only.
- Preserve existing frontmatter fields on update.
- Prefer `/vault-find` over raw `Read` for searching — it's cheaper per token.

### 7d. Verify

Inside Claude Code:

```
/vault-daily          # creates today's daily note if missing
/vault-find "test"    # searches Brain for matches
```

Both should succeed. If they fail with a path error, check that `~/Desktop/Brain` exists and that the `filesystem` MCP has it in its allowed paths list (Step 3a).

---

## Step 8 — Verify install

Run these in order inside a fresh Claude Code session. Each step is independent, so a failure isolates one sub-system.

### 8a. Plugin checks

```
/plugin list
```
Expected: `everything-claude-code`, `codex`, `caveman` all marked enabled.

```
/codex:setup
```
Expected: `ready` message. If not, re-check Step 2.

```
/projects
```
Expected: instinct stats load from `everything-claude-code`'s continuous-learning system. Failure here means the plugin's data dir isn't writable — check `~/.claude/plugins/cache/`.

### 8b. MCP checks

```
mem_stats
```
Expected: JSON with entity/observation counts. Failure means engram isn't reachable — check `ENGRAM_DATA_DIR` and restart Claude Code.

```
mem_context
```
Expected: recent timeline entries (may be empty on first install — that's fine).

```
mcp__gitnexus__list_repos
```
Expected: array of indexed repos. Empty is OK if you haven't indexed anything yet.

### 8c. Caveman check

After restart, look at the status bar at the bottom of the Claude Code window. You should see a `[CAVEMAN]` or similar badge. If not, re-check the path hash in Step 4c.

### 8d. Workflow dry run

Pick one of the three workflows and do a 100-LOC dry run. The plan doc recommends:

1. **Workflow A** — run `zero-to-one` on a throwaway CLI that prints the date. Confirm `/sessions`, `/multi-plan`, `/codex:adversarial-review`, `/orchestrate feature`, `/checkpoint`, `mem_save`, and `/vault-session` all succeed. Target under 30 min.
2. **Workflow B** — run `one-to-n` on a repo you already have (e.g., a sandbox fork). Confirm `mcp__gitnexus__impact` returns a call graph, `/multi-execute` parallelizes, `/update-codemaps` refreshes.
3. **Workflow C** — break a known test and run `debug-test`. Confirm `/tdd` produces a RED test, `/verify` runs cheap-to-expensive, `mem_save` with `type: bugfix` persists.

See `~/workflow/README.md` → Verification section for step-by-step.

---

## Step 9 — Optional extras

### 9a. Wispr Flow

Already listed as a prerequisite. Tips for integrating with Claude Code:

- Pick a hotkey that doesn't collide with tmux (e.g., `Fn` instead of `Ctrl+Space`).
- Enable "Smart formatting" so code fragments dictate cleanly.
- Claude Code reads raw text from Wispr's transcription — no further wiring required.

### 9b. Keybindings

Customize `~/.claude/keybindings.json` if defaults feel wrong:

```json
{
  "submit": "cmd+enter",
  "toggleThinking": "alt+t",
  "verboseMode": "ctrl+o"
}
```

Run the `keybindings-help` skill inside Claude Code for the full list.

### 9c. Token budget

Cap extended thinking to stay within daily quotas:

```bash
export MAX_THINKING_TOKENS=10000
```

Add to `~/.zshrc` and restart the CLI.

### 9d. Model routing

Per `performance.md`, the workflow commands route work to three different models:

| Task | Model | Why |
|---|---|---|
| Planning, architecture, research | Opus 4.6 | Deepest reasoning |
| Main implementation, review | Sonnet 4.6 | Best coding model |
| `/multi-execute` workers, high-frequency agents | Haiku 4.5 | 3x cost savings, 90% capability |
| Adversarial review, stuck loops | GPT-5.4 via Codex | Independent reasoning lens |
| Optional frontend authority | Gemini via `/multi-frontend` | Diverse model for UI/UX |

The default model in `~/.claude/settings.json` should be `claude-opus-4-6` for planning-heavy work, `claude-sonnet-4-6` for implementation-heavy work. Swap via `/model <name>` at any time.

### 9e. Telemetry with claude-hud (optional)

For real-time visibility into context usage, active tools, and agent tracking, install the `claude-hud` plugin:

```
claude plugin install claude-hud@claude-hud
```

Then add the marketplace and enable in `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "claude-hud@claude-hud": true
  },
  "extraKnownMarketplaces": {
    "claude-hud": {
      "source": { "source": "github", "repo": "jarrodwatts/claude-hud" }
    }
  }
}
```

This gives you a statusline overlay showing tokens consumed per turn, context window fill %, and active agent count. No configuration beyond install — it reads Claude Code's runtime state directly.

### 9f. ck / bp plugins (Chris's local plugins)

Chris's `settings.json` also enables `ck@cavekit-local` and `bp@cavekit-local` from a local marketplace at `~/.claude/plugins/local/cavekit-marketplace`. These are personal and not required for the playbook — skip unless you have the source.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| Plugin not found during `/plugin install` | Run `/plugin marketplace list` to confirm the marketplace is registered; re-add if missing |
| `/codex:setup` reports `auth failed` | Re-run `codex login`, or set `OPENAI_API_KEY` explicitly in `~/.zshrc` and restart the session |
| `mcp__gitnexus__list_repos` returns empty | Confirm the gitnexus service is running; index the repo manually; check service URL in `mcp.json` |
| `mem_context` returns nothing after install | Call `mem_save` once manually to seed the store, then retry |
| Caveman badge not showing in status line | Verify the cache hash with `ls ~/.claude/plugins/cache/caveman/caveman/` and update `statusLine.command` in `settings.json` |
| `/vault-find` fails with path error | Confirm `~/Desktop/Brain` exists and is in the `filesystem` MCP allowed paths |
| PostToolUse auto-format breaks on large edits | Increase the hook `timeout` field in `settings.json` or move the format step to `/verify` |
| `gh search repos` fails inside workflow | Run `gh auth status`; re-run `gh auth login --scopes "repo,read:org"` |
| `/multi-execute` workers hang | Kill with `/codex:cancel` if Codex-backed, or `Ctrl+C` the session and check the Task logs via `TaskList` |
| `EXA_API_KEY` not found at runtime | Env vars must be exported **before** Claude Code launches; restart the CLI after editing `~/.zshrc` |

If something goes sideways and you can't recover, nuke the session cache (`rm -rf ~/.claude/plugins/cache/<plugin>/<hash>`) and re-run `/plugin install <name>` — plugins re-fetch from the marketplace on next start.

---

## Updating

**Plugins:**
```
/plugin update everything-claude-code
/plugin update codex
/plugin update caveman
```
After updating `caveman`, **re-check the statusline cache hash** — the path hash changes on upgrade.

**Playbook commands:**
```bash
cd ~/workflow && git pull
```
If you used symlinks (Option 1 in Step 5), updates are live immediately. If you used copies (Option 2), re-copy:
```bash
cp ~/workflow/commands/*.md ~/.claude/commands/
```

**MCP servers** — `npm -g update` for the `npx` servers; for `engram` and `gitnexus`, follow their project-specific upgrade instructions (`brew upgrade engram`, `git pull && ./install.sh` in the gitnexus repo, etc.).

**Rules** — `cd ~/.claude/rules && git pull` if you track them in git.

---

## Uninstall

Clean removal, in order:

```bash
# 1. Unregister the workflow slash commands
rm -f ~/.claude/commands/zero-to-one.md \
      ~/.claude/commands/one-to-n.md \
      ~/.claude/commands/debug-test.md

# 2. Disable and uninstall plugins
#    (inside Claude Code)
/plugin disable caveman
/plugin disable codex
/plugin disable everything-claude-code
/plugin uninstall caveman
/plugin uninstall codex
/plugin uninstall everything-claude-code

# 3. Remove MCP entries from ~/.claude/mcp.json (or settings.json)
#    Edit by hand — remove the mcpServers keys you no longer want.

# 4. Remove state files
rm -rf ~/.claude/plugins/cache/caveman
rm -rf ~/.claude/plugins/cache/codex
rm -rf ~/.claude/plugins/cache/everything-claude-code
rm -f  ~/.claude/.caveman-active      # caveman mode flag
# (optional) rm -rf ~/.engram          # engram local store — careful, this is your memory
# (optional) rm -rf ~/Desktop/Brain    # vault — NEVER do this without a backup

# 5. Uninstall Codex CLI if you no longer want it
npm uninstall -g @openai/codex

# 6. Remove env vars from ~/.zshrc
#    Delete the EXA_API_KEY, FIRECRAWL_API_KEY, OPENAI_API_KEY, etc. lines.

# 7. Restart Claude Code
```

Do **not** delete `~/.claude/CLAUDE.md` or `~/.claude/rules/` unless you're fully resetting — those are shared across every project, not just this playbook.

---

## Summary

Once Steps 1–8 pass, you have a Claude Code install that can run all three workflows in `~/workflow/commands/`. The playbook relies on plugin-provided hooks (no manual wiring beyond the statusline), MCP-backed context (engram for memory, gitnexus for impact analysis, exa for research), and the `~/.claude/rules/common/` rule files for coding/testing/mentor behavior. For the full workflow walkthroughs, see `~/workflow/README.md`. For day-to-day use, type `/zero-to-one`, `/one-to-n`, or `/debug-test` inside any Claude Code session.
