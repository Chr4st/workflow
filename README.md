# Claude Code Workflow Playbook

Four deterministic pipelines for Claude Code: research, greenfield, feature dev, and debug. Each is a state-machine-driven sequence of plugins, agents, and MCP calls — run the slash command, follow the phases, ship with memory + vault + code graph updated.

## Quick install

```bash
git clone https://github.com/Chr4st/workflow.git
cd workflow
./install.sh
```

Idempotent, automatic backups. See `docs/BUNDLE.md` for details, `docs/TROUBLESHOOTING.md` if something breaks.

Optional extras: `claude plugin install claude-hud@claude-hud` (telemetry), `brew install rtk && rtk init -g` (60-90% token savings), `pip3 install semgrep` (SAST on every write).

## Commands

| Command | When | Steps | Key constraint |
|---------|------|-------|----------------|
| `/research <name> [keywords]` | Domain exploration before building | 24 across 5 phases | Information quality — discover before committing |
| `/zero-to-one <name> [desc]` | New project from scratch | 39 across 6 phases | Unknowns — research before code, plan before scaffold |
| `/one-to-n <feature> [area]` | Feature in existing codebase | 48 across 8 phases | Blast radius — impact analysis before every edit |
| `/debug-test <bug> [suspect]` | Bug fix + regression hardening | 35 across 7 phases | Reproducibility — lock with failing test, fix minimally |

## Workflow R — Research (24 steps)

Standalone discovery that produces a research bundle for `/zero-to-one`.

| Phase | Steps | What happens |
|-------|-------|-------------|
| 0 — Intake | R0–R0.5 | Clarification gates: focus (technical/market/both), depth, known prior art |
| 1 — Context | R1–R4 | Caveman, session, engram memory, vault search |
| 2 — Discovery | R5–R7 | **4 parallel branches**: web research, GitHub skeleton survey, paper ingestion (Opus), market/resource analysis. Then Context7 docs + knowledge graph construction |
| 3 — Analysis | R8–R10.5 | Gap detection + novelty assessment (parallel). Synthesis → adversarial review → user gate |
| 4 — Bundle | R11–R15 | Write `research-bundle-{name}.json`, persist to engram + vault |

**Knowledge graph** (adapted from OmegaWiki): 9 entity types (paper, concept, topic, tool, skeleton, claim, gap, market_data, decision_point) with 9 relationship types (extends, contradicts, supports, implements, competes_with, depends_on, supersedes, costs, integrates_with).

**Integration**: `/zero-to-one` checks for a bundle at A3.5 — if found, skips Phase 1 discovery entirely.

## Workflow A — 0→1 Development (39 steps)

| Phase | Steps | What happens |
|-------|-------|-------------|
| 1 — Research | A1–A8 | Caveman, session, engram, vault, web search, GitHub skeletons, Context7 docs. Skipped if research bundle exists (A3.5) |
| 2 — Plan | A9–A15.5 | `EnterPlanMode` → `/multi-plan` (3 models) → planner + architect agents (Opus) → `/codex:adversarial-review` → user approval → `ExitPlanMode` |
| 3 — Scaffold | A16–A19 | Package manager lock, repo create/fork, coding standards auto-load, doc bootstrap |
| 4 — TDD | A20–A24 | RED test → GREEN implementation (Sonnet) → refactor-clean → verify |
| 5 — Review | A25–A30.5 | Orchestrate → security/language/database reviewers → Codex pre-commit review → verify pre-PR → mutation testing |
| 6 — Ship | A31–A38 | Commit → PR → checkpoint → mem_save → vault session → learn-eval → evolve → session summary |

## Workflow B — 1→n Development (48 steps)

| Phase | Steps | What happens |
|-------|-------|-------------|
| 1 — Map | B1–B9 | GitNexus context + route/tool maps, 3 parallel Explore agents, vault + engram search |
| 2 — Impact | B10–B13 | `gitnexus_impact` per symbol, `api_impact`, `shape_check`, `detect_changes`. **Gate**: stop if blast radius exceeds threshold |
| 3 — Plan | B14–B18.5 | `/multi-plan` → planner + architect + security agents (parallel) → Codex review → approval |
| 4 — TDD | B19–B21.8 | Integration seam tests, contract tests for blast-radius calls. RED gate before Phase 5 |
| 5 — Execute | B22–B26 | `/multi-execute` with Haiku workers + Sonnet orchestrator. Optional `/multi-backend` or `/multi-frontend` |
| 6 — Verify | B27–B31 | Lint → stack verification → coverage (80% gate) → mutation testing → e2e → build-fix |
| 7 — Review | B32–B37 | Security → language → database → Codex reviewers (sequential chain with escalation) |
| 8 — Ship | B38–B48 | Update codemaps → docs → commit → PR → checkpoint → mem_save → vault → learn → evolve → session summary |

## Workflow C — Debug + Test (35 steps)

| Phase | Steps | What happens |
|-------|-------|-------------|
| 1 — Reproduce | C1–C4 | Caveman, reproduce locally, capture exact error verbatim, check recent changes |
| 2 — Investigate | C5–C10 | GitNexus impact/context, 3 parallel Explore agents, engram + vault search. **Gate**: state hypothesis |
| 3 — Lock | C11–C13 | `/tdd` → RED test matching the captured error. **Gate**: must fail for the right reason |
| 4 — Fix | C14–C17.5 | Minimal diff → GREEN → verify → coverage. No refactoring during debug |
| 5 — Codex Escape | C18–C22 | If looped >2x: `/codex:rescue` → status → result → adversarial review. Never auto-apply |
| 6 — Harden | C22.5–C28 | Security → code → language reviewers, e2e, build-fix, refactor-clean |
| 7 — Persist | C29–C35 | Commit (`fix:`) → PR with root cause → checkpoint → mem_save (bugfix) → vault → session summary |

## State Machines

Each workflow is backed by a deterministic JSON state machine in `state-machines/`. States define type (sequential/parallel/conditional), model routing (haiku/sonnet/opus), user input gates, and exit conditions. The `workflow-runner.js` library manages transitions including parallel fork/join. The `workflow-verifier.js` PostToolUse hook tracks progress and warns on step-skipping.

## Model Routing

| Model | Role |
|-------|------|
| **Opus 4.6** | Planning, architecture, research synthesis, paper comprehension |
| **Sonnet 4.6** | Implementation, code review, orchestration |
| **Haiku 4.5** | Worker agents, mechanical edits, lightweight steps |
| **GPT-5.4** (Codex) | Adversarial review, stuck-loop rescue, independent second opinion |
| **Gemini** | Frontend authority via `/multi-frontend` |

Reviewers output `[CONFIDENCE: HIGH/MEDIUM/LOW]`. Low confidence escalates the next reviewer one tier.

## Clarification Gates

Every workflow enforces mandatory gates at phase boundaries via `AskUserQuestion` with labeled options. Universal triggers: tech stack, destructive git, schema changes, scope creep, plans >3 files. If unresponsive: `[BLOCKED: awaiting <decision>]`. Override with "skip clarifications for this task".

## Plugins & Dependencies

| Plugin | Version | Purpose |
|--------|---------|---------|
| `everything-claude-code` | 1.7.0 | 37 commands, 14 agents, 60 skills, hooks, MCP bundle |
| `codex` | 1.0.2 | Codex CLI bridge to GPT-5.4, adversarial review, rescue |
| `caveman` | 600e8efc | Terse output compression, token savings |
| `claude-hud` | latest | Real-time context/token telemetry |

MCPs: engram (memory), gitnexus (code graph), exa-web-search, context7, firecrawl, github, supabase, sequential-thinking, filesystem.

## Repository Layout

```
workflow/
├── commands/          # 4 workflow slash commands
├── rules/common/      # 11 global rule files
├── agents/            # 16 agent definitions
├── scripts/
│   ├── hooks/         # 6 lifecycle hooks
│   └── lib/           # 7 shared libraries
├── state-machines/    # 4 deterministic workflow state machines
├── templates/         # CLAUDE.md, settings.json, env templates
├── docs/              # BUNDLE.md + TROUBLESHOOTING.md
├── install.sh
├── uninstall.sh
├── verify.sh
└── INSTALL.md
```

## License

MIT. Fork it, modify it, use it as a template. The commands are configuration for third-party plugins — their respective licenses apply.
