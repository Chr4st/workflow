# Install WisprFlow First. Claude Code Workflow Playbook

This repository is the operational playbook for running Claude Code against three distinct kinds of software work: greenfield projects, feature development inside a large existing codebase, and debug plus regression hardening. It is written for Chris's specific setup (`everything-claude-code@1.7.0`, `codex@1.0.2`, `caveman@600e8efc`, plus the engram / gitnexus / exa / firecrawl / github / supabase / context7 / sequential-thinking / filesystem MCPs) but it works unchanged for anyone who installs the same plugins and MCP bundle. The value is not in the commands themselves — those already exist in the plugins — but in the *ordering* of them. Each workflow is a linear, plugin-specific pipeline that removes the cost of re-deciding order every session. You run the slash command, you follow the phases, you finish with a committed change plus updated memory, vault note, and code graph. No improvisation required.

## Quick install

```bash
git clone https://github.com/Chr4st/workflow.git
cd workflow
./install.sh
```

Idempotent, with automatic backups. See `docs/BUNDLE.md` for what gets installed and `docs/TROUBLESHOOTING.md` if something breaks.

For real-time telemetry (context usage, tokens, active agents), also run: `claude plugin install claude-hud@claude-hud`. See `INSTALL.md` § 9e.

## Quickstart

1. **Install the three plugins and MCP servers.** See `INSTALL.md` for the full procedure. At minimum you need `everything-claude-code`, `codex`, and `caveman` installed, plus engram and gitnexus running as MCP servers. The other MCPs (exa-web-search, firecrawl, github, supabase, context7, sequential-thinking, filesystem) are used by at least one phase of at least one workflow; install all of them or accept that some steps will be no-ops.
2. **Copy the command files into your Claude Code commands directory.** The three slash commands live in `commands/zero-to-one.md`, `commands/one-to-n.md`, and `commands/debug-test.md`. They must be linked or copied into `~/.claude/commands/` so Claude Code can discover them. `INSTALL.md` covers the symlink approach so updates in this repo take effect immediately.
3. **Verify plugins are loaded.** Run `/projects` (loads instinct stats), `/codex:setup` (confirms Codex CLI bridge), and `mem_stats` (confirms engram is writing). If any of the three fail, fix them before running a workflow. The playbook assumes all three plugin surfaces are healthy.
4. **Run the workflow for the work you're about to do.** `/zero-to-one <project-name> [description]` for greenfield, `/one-to-n <feature> [target-area]` for features in an existing repo, `/debug-test <bug-description> [suspect]` for bugs. Each one self-narrates its phases so you always know where you are in the pipeline.
5. **When something goes wrong, read the "Common pitfalls" section of the relevant workflow below.** Every pipeline has known failure modes and the guardrails that prevent them are documented in this file. If you're stuck on a bug, Workflow C's Codex rescue phase is the escape hatch — do not grind in a loop.

## Why these three workflows?

The three categories are not arbitrary. They correspond to the three dominant constraints in software work, and one generic pipeline would be mediocre at all of them because the failure modes are different.

**0→1 development is constrained by unknowns.** When you start a project you do not know the right framework, the right structure, the right abstractions, or even the right problem statement. Premature code is the enemy because every line written before the plan stabilizes gets thrown away. The right response is to spend tokens on research and planning — prior art search, skeleton discovery, multi-model plan critique — and only then write code against a chosen skeleton with TDD. If you skip research you rebuild something that already exists; if you skip planning you build the wrong thing; if you skip the skeleton you hand-roll boilerplate that battle-tested repos already solved.

**1→n development is constrained by blast radius.** The code already exists, the patterns are already chosen, and your change will touch a subset of it. The dominant failure mode is a "small" edit that cascades — a field rename that breaks a dozen call sites, a handler change that drifts an API contract, a schema tweak that corrupts a migration. Research matters less because the answers are already in the repo; impact analysis matters enormously because you cannot see the call graph by eyeballing files. The right response is to map the relevant slice of the code graph with gitnexus *before* touching anything, plan the edit against the impact report, then parallelize the edit across files with worker agents and verify with stack-specific checks.

**Debug and test is constrained by reproducibility.** You have a symptom, maybe a stack trace, and an unknown root cause. The dominant failure mode is "fixing" a symptom that returns a week later because you did not lock the bug with a failing test first. The secondary failure mode is grinding in a loop on a hard bug when an independent diagnostic lens would have found it in one pass. The right response is reproduce-first, lock-with-failing-test, fix-minimally, and if you loop more than twice hand investigation to Codex via `/codex:rescue`. Feature work does not belong in this pipeline because feature work has no defect to reproduce; conflating the two produces either over-engineered fixes or under-tested features.

Each workflow below is tuned to its specific constraint. The commands, agents, and skills overlap — TDD and code review appear in all three — but the *ordering* and the *gates* are different, and that is the entire point.

## Workflow A — 0→1 Development

### When to use

Signals that you are in Workflow A territory: you are creating a new repo or a new top-level package, there is no existing code to respect, you have a problem statement but not a solution, and the first decision you need to make is "what framework / language / skeleton / structure should this even be?" If you find yourself writing `package.json` or running `cargo new` or `django-admin startproject`, you are in Workflow A. If you are editing an existing file, you are in Workflow B. If you are chasing a stack trace, you are in Workflow C.

### Intent

The governing intent is **research before code, plan before scaffolding, and TDD before features**. Greenfield time spent on research compounds: the difference between "chose the right Rust async runtime" and "found out three weeks in that tokio was the wrong call" is measured in weeks of rewrites. The workflow therefore front-loads prior-art discovery, multi-model planning, and skeleton selection. Only once the plan survives adversarial review does any code get written, and the first code written is always a failing test.

### Pipeline walk-through

The pipeline is 38 steps across 6 phases. The following is a phase-by-phase summary of what each phase does and why it is ordered where it is.

**Phase 1 — Context and research (steps A1–A8).** Start by setting `/caveman full` so exploration output is terse and token-cheap, then open or resume a session with `/sessions`. Pull recent episodic memory with `mem_context` from the engram MCP so you do not lose the thread from prior sessions. Search the Brain vault with `/vault-find "<domain>"` and engram across projects with `mem_search "<domain>"` — between the two you capture both written notes and past decision context. Then go external: `exa-web-search` for broad prior art and benchmarks, `gh search repos` and `gh search code` to find forkable skeletons (this is what the `search-first` skill is for), and `context7` for live docs of any stack you are already leaning toward. The point of this phase is to refuse to write code until you have looked hard for code that already solves the problem.

**Phase 2 — Plan and design (steps A9–A15).** Enter plan mode with `EnterPlanMode` to block accidental writes. Run `/multi-plan` to route Research → Ideation → Plan across Codex GPT-5.4, Gemini, and Claude simultaneously — three models stress-testing the same problem is how you catch blind spots a single model would miss. In parallel, dispatch `Agent(planner)` to produce a PRD with phased breakdown and risk list, and `Agent(architect)` to critique system design and flag scalability concerns. Then run `/codex:adversarial-review` to hand the current plan document to GPT-5.4 for attack-surface review — auth holes, data loss paths, race conditions, schema drift. Use `AskUserQuestion` to resolve any loose decisions, then `ExitPlanMode` when the plan is approved. Opus 4.6 is the right model for this phase per `performance.md` because planning is deep-reasoning work.

**Phase 3 — Scaffold (steps A16–A19).** Run `/setup-pm` to lock your package manager before any code is written (npm / pnpm / yarn / bun decisions later in a project are painful). Either `gh repo fork` the skeleton you picked in Phase 1 or `gh repo create` for a new repo. From this point forward, the stack-specific skill (`backend-patterns`, `frontend-patterns`, `django-patterns`, `springboot-patterns`, `golang-patterns`, `swiftui-patterns`, and so on) auto-loads on writes so conventions are enforced at generation time rather than fixed in review. Dispatch `Agent(doc-updater)` to bootstrap README and CODEMAPS immediately — you want docs living alongside code from step one, not bolted on at the end.

**Phase 4 — TDD implementation (steps A20–A24).** Run `/tdd` to invoke the tdd-guide agent and produce a RED test before any implementation. The stack-specific testing skill (`python-testing`, `golang-testing`, `springboot-tdd`, `django-tdd`, `e2e-testing`, or `cpp-testing`) supplies framework idioms so the test looks the way the framework expects. Switch to Sonnet 4.6 for the minimal GREEN implementation — per `performance.md` Sonnet is the best coding model and Opus is reserved for Phase 2 planning. After each green bar, `/refactor-clean` removes dead imports and unused exports (knip / depcheck / ts-prune), and `/verify quick` runs a fast build-plus-types check to catch regressions immediately. Do not batch TDD cycles; one RED-GREEN-REFACTOR per unit.

**Phase 5 — Review and harden (steps A25–A30).** Run `/orchestrate feature` which sequences planner → tdd-guide → code-reviewer → security-reviewer in the correct order for feature work. On top of that, dispatch `Agent(code-reviewer)` (mandatory per global CLAUDE.md rules) and `Agent(security-reviewer)` in parallel for OWASP coverage. If you added persistence, dispatch `Agent(database-reviewer)` for schema and query review. Then run `/codex:adversarial-review` one more time — GPT-5.4 looking at the actual code rather than the plan catches different issues than Claude's reviewers. Close the phase with `/verify pre-pr` which runs the full verification loop: build, types, lint, tests, console.log check, git status check.

**Phase 6 — Ship and persist (steps A31–A38).** Commit with `/caveman-commit` which writes a terse conventional commit. Open a PR with `gh pr create` including the test plan. Run `/checkpoint` to snapshot git diffs and coverage. Then comes the learning loop that is the entire reason you care about the next 0→1 to-be-1→n transition: `mem_save` persists the architectural decision to engram with a structured what/why/where/learned entry, `/vault-session` writes a session note into Brain, `/learn-eval` evaluates the session for extractable patterns that should become instincts, and `/evolve --generate` clusters any stable instincts into new skills. Finally `mem_session_summary` saves the end-of-session memory — this is mandatory per the engram rule, not optional. Skipping it loses the session.

### What to expect

A disciplined 0→1 run on a 100-LOC project should complete in under 30 minutes, most of which is spent in Phase 1 research and Phase 2 planning. The MCPs that get hit hardest are `exa-web-search` and `context7` in Phase 1, engram in Phase 6, and the github MCP throughout. The gates that most commonly block are `/codex:adversarial-review` flagging a plan flaw in Phase 2 (this is good — you want to find it there rather than after you have shipped it) and `/verify pre-pr` catching a missed test in Phase 5. Both are cheap to fix if you catch them on first pass; both are expensive to fix if you ignore them.

### Common pitfalls and how the pipeline prevents them

The first pitfall is **writing code before planning**, and the pipeline blocks this by putting `EnterPlanMode` at step A9 so Phase 2 literally cannot produce writes. The second is **reinventing existing libraries**, which the `search-first` skill in Phase 1 prevents by forcing `gh search` to run before any scaffolding. The third is **single-model planning blind spots**, which `/multi-plan` plus `/codex:adversarial-review` defuse by routing the plan through at least three independent reasoning engines. The fourth is **skipping the learning loop**, which costs you in the 1→n phase because you have no recorded decisions to reference — Phase 6's mandatory `mem_session_summary` prevents this by making session close impossible without memory persistence.

### Command

`/zero-to-one <project-name> [description]`

The command file at `commands/zero-to-one.md` narrates each phase as it runs, so you know where you are and what the next gate is.

## Workflow B — 1→n Development

### When to use

Signals that you are in Workflow B: the repo already exists and has real users or test coverage, you are adding a feature or modifying existing behavior, the change touches code that other code depends on, and you need to not break that other code. If you are about to edit a file that has any callers, you are in Workflow B. If the repo has a PR template, a CI pipeline, and more than one contributor, you are almost certainly in Workflow B.

### Intent

The governing intent is **blast-radius control**. In a mature codebase, the cost of a broken assumption scales with the number of dependents. A field rename that looks local might touch fourteen call sites, four migrations, three API contracts, and two integration tests — and the only way to know that before you edit is to ask the code graph. GitNexus is the non-negotiable part of this workflow because it is the only tool that gives you symbol-level impact analysis in one call. Planning, TDD, parallel execution, and review are all important, but the single most important step is `mcp__gitnexus__impact <symbol>` before any edit.

### Pipeline walk-through

The pipeline is 48 steps across 8 phases. The ordering is deliberately front-loaded with read-only mapping so that the planning phase has accurate context.

**Phase 1 — Mapping, read-only (steps B1–B9).** Set `/caveman full` and open or resume a session with `/sessions`. Confirm the codebase is indexed with `mcp__gitnexus__list_repos` — if it is not, you have no impact graph and the rest of the workflow degrades badly. Then pull the knowledge-graph slice around the feature area with `mcp__gitnexus__context "<feature area>"` and trace request paths with `mcp__gitnexus__route_map` and `tool_map` so you know which handlers, services, and repos matter. If the codemap looks stale run `/update-codemaps` to refresh it. Dispatch up to three parallel `Agent(Explore, "very thorough")` subagents to find existing implementations, related components, and test patterns — the "very thorough" instruction is load-bearing because it is the difference between finding one call site and all fourteen. Finally, `mem_search "<repo>/<area>"` retrieves prior decisions in this zone and `/vault-find "<feature>"` pulls Brain notes tied to this codebase. No edits happen in this phase; it is pure read.

**Phase 2 — Impact analysis (steps B10–B13).** This is the phase that justifies the whole workflow. For every symbol you plan to touch, run `mcp__gitnexus__impact <symbol>` to get the blast-radius report. For every endpoint you plan to modify, run `mcp__gitnexus__api_impact <endpoint>` to check API contract breakage. Run `mcp__gitnexus__shape_check` to validate data-shape compatibility across the call graph, and `mcp__gitnexus__detect_changes` to see what has drifted since the last index run. If any of these reports surprise you, the plan from Phase 3 has to account for it. Skipping this phase is the single biggest 1→n failure mode and the entire reason to pick Workflow B over a generic pipeline.

**Phase 3 — Plan (steps B14–B18).** Enter plan mode with `EnterPlanMode`, run `/multi-plan` for the multi-model research/ideation/plan routing, and dispatch `Agent(planner)`, `Agent(architect)`, and `Agent(security-reviewer)` in parallel as a split-role critique per the multi-perspective pattern in global agents rules. Then run `/codex:adversarial-review` on the plan text so GPT-5.4 attacks it before any code is touched. `ExitPlanMode` when approved. Opus 4.6 is the reasoning model here; Sonnet is for Phase 5.

**Phase 4 — TDD at integration seams (steps B19–B21).** Run `/tdd` but target the integration boundaries, not implementation details — the point of a test in a 1→n workflow is to lock the contract between modules, not to specify internal structure. The stack-specific testing skill (django-tdd, springboot-tdd, python-testing, golang-testing, e2e-testing) supplies framework idioms. Add contract tests for any cross-module call the change affects. This prevents silent breakage of callers that Phase 2's impact report flagged as dependents.

**Phase 5 — Parallel execution (steps B22–B26).** Run `/multi-execute` to dispatch Haiku 4.5 worker agents in parallel across the files you need to edit, with Sonnet 4.6 orchestrating. Per `performance.md` this is the intended model split: Haiku is 90% of Sonnet's capability at a third of the cost, and for mechanical edits across many files that is the right trade-off. If the feature is backend-heavy, run `/multi-backend` to route business logic through the Codex authority lane. If it is UI-heavy, run `/multi-frontend` to route through Gemini for UI and UX diversity. Write-time skills (`plankton-code-quality`, `coding-standards`, and whichever language skill applies) enforce idioms during generation. After each meaningful chunk run `/refactor-clean` to remove anything the change made dead.

**Phase 6 — Verification, stack-aware (steps B27–B31).** Run `/verify` for the comprehensive loop: build, types, lint, tests, console.log check, git status check. Then the stack-specific verification skill (`django-verification`, `springboot-verification`, or the language-appropriate one) catches framework-specific issues a generic verifier misses. `/test-coverage` enforces the 80% gate from global testing rules. `/e2e` runs the end-to-end suite — Vercel Agent Browser preferred, Playwright fallback. If the build is red run `/build-fix` (or `/go-build` for Go) to hand it to the build-error-resolver agent with a minimal-diff mandate. The ordering is intentional: cheap checks run before expensive ones so you fail fast.

**Phase 7 — Review (steps B32–B37).** Run `/code-review` (always, per global CLAUDE.md rules) and the language-specific variant (`/go-review` or `/python-review`) for deeper idiom analysis. If the change touches schema or queries, dispatch `Agent(database-reviewer)`. `Agent(security-reviewer)` runs always. `/codex:adversarial-review` provides the pre-merge GPT-5.4 second opinion. `/caveman-review` produces one-line PR comments suitable for actually posting.

**Phase 8 — Document and ship (steps B38–B48).** Run `/update-codemaps` to refresh the codemap, `/update-docs` and `Agent(doc-updater)` for README and guides, and `mcp__gitnexus__detect_changes` to re-index so the next 1→n run starts from accurate state. Commit with `/caveman-commit`, open a PR with `gh pr create` citing any prior art you found in Phase 1, and `/checkpoint` for the diff-plus-coverage snapshot. Then the learning loop: `mem_save` with pattern or decision or bugfix type per the engram proactive save rule, `/vault-session` for the Brain note, `/learn` for pattern extraction, `/evolve` to promote stable instincts, and `mem_session_summary` to close the session. `mem_session_summary` is mandatory; the session is not "done" until it has run.

### Why gitnexus impact analysis is non-negotiable

The temptation in a 1→n workflow is to skip Phase 2 because it "feels slow" — you have a picture in your head of which files need to change and you want to get editing. This is exactly wrong. In a codebase of any real size, your mental model of the call graph is wrong in at least one place, and the place it is wrong is the place your change will break things. GitNexus is the only tool that gives you the *actual* graph in under a second. `mcp__gitnexus__impact <symbol>` enumerates every caller, every field reference, every test that exercises the symbol. `mcp__gitnexus__api_impact <endpoint>` enumerates every consumer of the endpoint's contract. `mcp__gitnexus__shape_check` catches type-level incompatibilities the linter will not see. Running these four calls takes under a minute in aggregate and it is the difference between shipping the feature and shipping a regression. There is no version of "I know this code well enough to skip impact analysis" that holds up in practice. Run it.

### How parallel worker agents accelerate the edit phase

`/multi-execute` dispatches a pool of Haiku 4.5 worker agents across the files Phase 2's impact report flagged, while Sonnet 4.6 acts as orchestrator. Each worker takes one file or one tightly-scoped subset of files, applies the planned edit, and reports back. Sonnet aggregates, resolves conflicts, and handles anything that needs cross-file reasoning. This is the performance-tuned model split from `performance.md`: Haiku for mechanical edits where you need throughput, Sonnet for reasoning where you need quality. For a 14-file rename, `/multi-execute` finishes in roughly the time it takes Sonnet to do one file sequentially, and the cost is dramatically lower than running Sonnet across all fourteen. The quality is comparable because the rename itself is mechanical — all the reasoning already happened in Phase 3's plan.

### Common pitfalls and how the pipeline prevents them

The first pitfall is **editing without impact analysis**, which Phase 2 prevents by making the impact, api_impact, shape_check, and detect_changes calls mandatory gates before Phase 3 begins. The second is **one-thorough-pass exploration** that misses half the call sites — Phase 1's three parallel `Agent(Explore, "very thorough")` dispatches fix this by stress-testing the search from different angles. The third is **stale codemaps causing the next feature to plan against wrong context**, which Phase 8's `/update-codemaps` plus `mcp__gitnexus__detect_changes` explicitly prevent. The fourth is **serial edits burning Sonnet budget on mechanical changes**, which `/multi-execute` defuses by moving mechanical work to Haiku workers.

### Command

`/one-to-n <feature> [target-area]`

The command file at `commands/one-to-n.md` walks through each phase in order. The target-area argument is optional but strongly recommended because it scopes the Phase 1 mapping calls and makes Phase 2's impact analysis sharper.

## Workflow C — Debug + Test

### When to use

Signals that you are in Workflow C: a test is failing, a production incident has a reproducible symptom, a user reported a bug, a deploy went red, or something that worked yesterday does not work today. Do not use this workflow for feature work. Feature work does not have a defect to reproduce, and conflating the two produces either over-engineered fixes or under-tested features. If you are not chasing a specific symptom, you are not in Workflow C.

### Intent

The governing intent is **reproduce first, lock with a failing test, fix minimally, and escape to Codex when stuck**. Every part of this is load-bearing. Reproduce first because you cannot fix what you cannot measure. Lock with a failing test because otherwise your fix is a guess and the regression will return. Fix minimally because a debug session is not a refactor window — you do one thing, you verify it works, you stop. And escape to Codex when stuck because Claude Code tends to loop on hard bugs and an independent diagnostic lens from GPT-5.4 via the `codex-rescue` agent will often find what Claude missed. The workflow treats Codex rescue as a first-class phase, not an afterthought.

### Pipeline walk-through

The pipeline is 35 steps across 7 phases.

**Phase 1 — Reproduce (steps C1–C4).** Set `/caveman full` for terse output. Reproduce the bug manually in your local state to confirm it exists outside of CI — an intermittent CI failure and a reproducible local failure need different handling. Capture the exact error, stack trace, and inputs verbatim; the caveman terse rule explicitly requires errors to be quoted, not summarized. Run `mcp__gitnexus__detect_changes` to see what has changed recently in the neighborhood of the bug, because recent changes are the highest-prior suspect.

**Phase 2 — Investigate (steps C5–C10).** Run `mcp__gitnexus__impact <suspect symbol>` to see what touches the suspect, and `mcp__gitnexus__context <suspect symbol>` for the knowledge-graph neighborhood. Dispatch `Agent(Explore, "medium")` with a specific question — typically "where is X called, and what does X call back into" — to surface the relevant code without over-searching. Search engram with `mem_search "<error keyword>"` because you may have seen this bug class before and your past self will have recorded how you fixed it. Search Brain with `/vault-find "<error or symbol>"` for any notes tied to the issue. If the bug smells structural rather than local, dispatch `Agent(architect)` to check whether it is a symptom of a deeper design break — fixing a symptom of a design problem creates more bugs than it closes.

**Phase 3 — Lock with a failing test (steps C11–C13).** Run `/tdd` to produce a RED test that reproduces the bug at the right seam. The stack-specific testing skill supplies framework idioms. The critical check is that the test fails for the *right reason* — a flaky assertion or a test that fails for a different reason than the real bug does more harm than not having a test at all. Read the failure message, confirm it matches the captured stack trace from Phase 1, and only then proceed. This step is the single most important thing in the entire debug workflow. Skipping it produces fixes that do not address the real defect.

**Phase 4 — Fix minimally (steps C14–C17).** Apply the minimal diff that makes the RED test go GREEN. Do not refactor neighboring code while you are here; that is a separate pass and conflating it with the fix is how debug sessions balloon into week-long rewrites. Run the locked test to confirm GREEN. Run `/verify` for the full loop: build, types, lint, tests, console.log check, git status check. Run `/test-coverage` to confirm the new test actually counts toward coverage.

**Phase 5 — Escape hatch for stuck loops (steps C18–C22).** If steps C2 through C16 have looped more than twice without converging on a fix, stop grinding and invoke `/codex:rescue`. This hands the investigation to Codex GPT-5.4 for a second opinion and fix attempt. Track the job with `/codex:status`. Fetch the final output with `/codex:result <job-id>`. Kill it with `/codex:cancel` if the job is obviously stuck or producing garbage. When Codex returns a proposed fix, run `/codex:adversarial-review` on it as a pre-merge stress test. The Codex rescue protocol is the explicit reason the `codex@1.0.2` plugin exists in this workflow — use it when stuck. Its `codex-rescue` agent is documented as a forwarding wrapper that hands investigation to GPT-5.4 and returns verdict, findings, artifacts, and next steps as a structured result.

**Phase 6 — Regression harden (steps C23–C28).** Dispatch `Agent(code-reviewer)` to catch neighboring breakage the fix might have introduced. Run the language-specific reviewer (`/go-review`, `/python-review`, or the appropriate one) for language-specific pitfalls. If the bug was security-relevant, dispatch `Agent(security-reviewer)` to ensure the fix does not introduce new attack surface. If the bug was user-facing, run `/e2e` for a Playwright or Vercel Agent Browser end-to-end pass. If the build is red after the fix run `/build-fix` or `/go-build` for a minimal-diff build repair. Finally `/refactor-clean` to remove anything the fix made dead.

**Phase 7 — Persist knowledge (steps C29–C35).** Commit with `/caveman-commit`, using the `fix:` conventional commit type. Open a PR with `gh pr create` that includes reproduction steps and root cause in the body — future you will thank you. Run `/checkpoint` for the diff-plus-coverage snapshot. Run `mem_save` with `type: bugfix`. Run `/vault-session` for the Brain note and `/learn-eval` for instinct extraction. Close the session with `mem_session_summary`, which is mandatory.

### The Codex rescue protocol in detail

Claude Code is not infallible. On hard bugs — memory ordering, async race conditions, framework-specific initialization quirks, native-code interop — it will loop. The symptom is that it tries the same three hypotheses over and over, each time with slightly different phrasing, and none of them reproduce the GREEN. When you see this pattern, stop immediately. Running Opus in circles costs tokens and does not converge. Instead, invoke `/codex:rescue`, which packages the current state of the investigation (files touched, tests run, captured stack trace, current hypothesis) and hands it to Codex GPT-5.4 via the Codex CLI bridge. GPT-5.4 brings an independent diagnostic lens — different training data, different reasoning priors, different failure modes. On bugs where Claude loops, Codex often converges in one pass.

While Codex is running, use `/codex:status` to watch the job. Do not close the session — the stop-time review gate has a 15-minute timeout and if you close too early you lose the result. When the job finishes, fetch the output with `/codex:result <job-id>`. Critically, **do not auto-apply Codex's proposed fix**. The `codex@1.0.2` plugin rules explicitly forbid this. Always read the verdict, findings, artifacts, and next steps sections first, decide which parts you agree with, and then apply them yourself. If Codex produces a fix that looks correct, run `/codex:adversarial-review` on it as a final stress test before committing — yes, review a Codex fix with another Codex pass. The adversarial review catches cases where Codex found a fix that works locally but breaks something subtle. If Codex is obviously going sideways, `/codex:cancel` kills the job cleanly.

The rescue protocol is an escape hatch, not a first resort. Invoke it on the third loop, not the first. But when you do need it, use the full protocol (`rescue → status → result → adversarial-review → selective apply`), not a shortcut.

### Why mem_save with type: bugfix is required, not optional

The engram proactive save rule says "save decisions, bug fixes, and discoveries PROACTIVELY — do not wait to be asked." This is not a style preference. It is how you stop hitting the same class of bug twice. A `mem_save` with `type: bugfix` and a structured what/why/where/learned entry becomes searchable in every future session. Six months from now, when a similar symptom appears, `mem_search "<error keyword>"` in Phase 2 of a new debug session will surface the saved entry, and you will solve in five minutes what would otherwise take another full Workflow C pass. Skipping the save feels cheap — it saves thirty seconds — but it costs hours on the next occurrence. Phase 7's `mem_save` step is not an afterthought; it is the entire reason the workflow has a Phase 7.

### Common pitfalls and how the pipeline prevents them

The first pitfall is **fixing a symptom instead of a root cause**, which Phase 3's reproduce-with-test gate prevents by refusing to accept any fix that does not flip a RED test to GREEN. The second is **refactoring during a debug session**, which the minimal-diff discipline in Phase 4 prevents explicitly. The third is **grinding in a loop on a hard bug**, which Phase 5's Codex rescue escape hatch addresses — the rule is "loop twice, then escape." The fourth is **forgetting to persist the bug class**, which Phase 7's mandatory `mem_save` plus `mem_session_summary` prevent.

### Command

`/debug-test <bug-description> [suspect]`

The command file at `commands/debug-test.md` narrates each phase. The `[suspect]` argument is optional but useful: if you have a hunch about which symbol is at fault, passing it lets Phase 2 start from `mcp__gitnexus__impact <suspect>` directly instead of having to hunt for the suspect first.

## Clarification gates (always on)

Every workflow enforces mandatory clarification gates at phase boundaries. The principle is simple: when in doubt, **ask** via `AskUserQuestion` with labeled options — never guess on anything that affects correctness, scope, reversibility, or shared state.

The full policy lives at `~/.claude/rules/common/clarification.md` and is loaded globally. Each workflow command file adds its own phase-specific triggers on top. Universal triggers include tech-stack picks, destructive git ops, scope creep, schema changes, secrets, and any plan touching more than three files. Workflow-specific triggers include runtime/deployment/persistence/auth decisions in 0→1, blast-radius and migration decisions in 1→n, and reproduction/rollback/codex-rescue decisions in debug+test.

If a gate is hit and the user is unresponsive, Claude must output `[BLOCKED: awaiting <decision>]` and stop rather than proceeding on an assumption. The one exception is reversible, local, read-only actions (reads, greps, listings) — those never require clarification.

This gate system exists specifically to stop the failure mode where an agent interprets a vague prompt, picks a default, ships it, and the user discovers thirty minutes later that the wrong framework / database / branch / auth model was used. It is verbose by design. If the verbosity becomes a drag, tell Claude "skip clarifications for this task" and it will record the defaults it picked so you can audit them at the end.

## Cross-cutting defaults

These defaults apply to all three workflows. They are enforced by hooks and skills that are already installed, so in most cases you do not have to do anything — you just need to know they exist so you can trust what is automatic versus what you must invoke manually.

**Model selection.** Opus 4.6 runs planning, architecture, and research synthesis because it has the deepest reasoning — Phase 2 of Workflow A and Phase 3 of Workflow B are the Opus phases. Sonnet 4.6 runs main implementation, code review, and orchestration because it is the best coding model — it is the default for everything that touches actual code. Haiku 4.5 runs `/multi-execute` worker agents and high-frequency lightweight agents because it is 90% of Sonnet's capability at a third of the cost. GPT-5.4 via Codex runs adversarial review, stuck-loop rescue, and the pre-merge second opinion — it is the *independent* reasoning lens, which is the part that matters for catching things Claude missed. Gemini runs frontend authority routes via `/multi-frontend` when the feature is UI-heavy and a diverse model voice on UX is valuable. This split comes from `performance.md` and is not negotiable.

**Caveman intensity policy.** The default intensity is `full` because session work is where the token savings compound most. The SessionStart hook activates `/caveman full` automatically — you do not need to invoke it manually at the start of every session, but the workflows explicitly call `/caveman full` as step 1 because making the setting explicit prevents surprises. Intensity auto-drops to normal when you are reading security warnings, confirming destructive operations (`git reset --hard`, `git push --force`, dropping tables, deleting branches), or working through multi-step sequences where fragment order risks misread. Escalate to `ultra` for high-volume exploration like big grep dumps or log analysis. And when a markdown document in `~/.claude/` exceeds 200 LOC, run `/caveman-compress` on it to save input tokens — the plugin docs report roughly 46% savings per compressed file.

**Hooks that run automatically.** The SessionStart hook (everything-claude-code) loads previous context and detects the package manager. The SessionStart hook (caveman) activates `/caveman full` and writes the statusline flag. The SessionStart hook (codex) runs `session-lifecycle-hook.mjs` to track lifecycle. The PreToolUse hooks block dev servers outside tmux, remind you to use tmux for long-running commands, remind you before `git push`, and capture tool-use observations for the continuous-learning-v2 skill. The PostToolUse hooks auto-format JS/TS after edits, run the TypeScript type check after edits, warn about leftover console.log calls, log PR URLs, and kick off async build analysis. The PreCompact hook saves state before compaction so nothing is lost. The Stop hook (codex, 15-minute timeout) runs the optional stop-time review gate. The SessionEnd hook (everything-claude-code) persists the session and extracts reusable patterns. None of these need configuration; they are already wired up. The only reason to know about them is so you can trust what is automatic and stop manually invoking things the hooks already cover.

**MCP hygiene.** For engram: `mem_save` proactively after any decision, bug, or discovery — do not wait to be asked; `mem_search` at session start so you do not lose the thread from prior sessions; and `mem_session_summary` before ever saying "done" — it is mandatory, not optional. For gitnexus: `list_repos` first to confirm the index is present; `impact` before any edit in any large repo, without exception; and `detect_changes` plus `/update-codemaps` after the edit to keep the graph fresh for the next run. For research: `exa-web-search` and `context7` for anything external — do not guess URLs, do not hallucinate documentation. For GitHub: `gh search repos`, `gh search code`, `gh search issues`, `gh search prs`, `gh pr create`, and `gh pr review` — never hand-roll PR creation.

**Memory and vault discipline.** The default vault is Brain at `~/Desktop/Brain`. The secondary vault ResearchTree at `~/Documents/ResearchTree/ResearchTree` is out of scope unless the user names it explicitly. All links inside Brain are `[[wikilink]]` style. Frontmatter is YAML and required on every new note; daily notes carry `type`, `cssclasses`, `date`, `sessions`, and `projects`; session notes carry `type`, `cssclasses`, `status`, `source`, `project`, `started_at`, and `aliases`. Preserve existing frontmatter fields on update — do not strip them. Prefer `/vault-find` over raw file reads because it is dramatically cheaper per token. Prefer the other `/vault-*` slash commands for writes. Never delete vault files; append and update only. These rules come from the global CLAUDE.md and are inherited into every workflow.

**Safety gates when caveman drops to normal.** Any destructive git operation (`git reset --hard`, `git push --force`, deleting branches) requires a confirmation prompt before execution. Any database operation that drops tables or runs destructive migrations requires confirmation. Any auto-apply of Codex fixes is forbidden — always review the result and ask the user which suggested changes to apply. Security warnings are always narrated in full, not fragments, regardless of caveman intensity.

## Verification

The playbook is not self-validating; you should actively verify each workflow end-to-end at least once after installing. The plan file's Verification section specifies the exact tests.

Run **Workflow A on a tiny throwaway project** — a CLI that prints the current date is the canonical test. Confirm that `/sessions` opens, `/multi-plan` returns multi-model results, `/codex:adversarial-review` runs against the plan file, `/orchestrate feature` completes all four review agents, `/checkpoint` creates a checkpoint, `mem_save` persists, and `/vault-session` writes a note into Brain. Target completion time is under 30 minutes for a 100-LOC project. If any step fails, the plugin that owns that step is misconfigured and should be fixed before you run another workflow.

Run **Workflow B on the ObsidianTool repository**, which is the reference codebase from Chris's auto-memory. Pick a deliberately small one-line feature addition. Confirm `mcp__gitnexus__impact` returns a call graph, `/multi-execute` parallelizes the edit across files, and `/update-codemaps` refreshes without errors. If gitnexus returns nothing, the repo is not indexed — run the indexer before treating the workflow as broken.

Run **Workflow C on an intentionally broken test** — change an assertion in an existing test so it fails, then use `/debug-test` to fix it. Confirm `/tdd` produces a RED test that reproduces the failure, `/verify` stages cheap-to-expensive checks in the right order, and `mem_save` with `type: bugfix` actually writes to engram. This is the cheapest workflow to test because you control the "bug."

Confirm caveman is active by checking the statusline badge — it should display `[CAVEMAN]` after the settings.json update documented in INSTALL.md. If the badge is absent, the statusline hook is not wired in, which is a common issue on first install.

Confirm the plugins themselves with `/codex:setup` (Codex CLI is ready), `/projects` (instinct stats load), and `mem_stats` (engram is writing). Each of these is independently runnable so if one fails you can isolate the broken plugin without bisecting the whole playbook.

## Repository layout

```
workflow/
├── commands/          # 3 workflow slash commands
├── rules/common/      # 11 global rule files
├── agents/            # 14 agent definitions
├── scripts/
│   ├── hooks/         # 4 lifecycle hooks
│   └── lib/           # 6 shared libraries
├── templates/         # CLAUDE.md, settings.json, env templates
├── docs/              # BUNDLE.md + TROUBLESHOOTING.md
├── install.sh
├── uninstall.sh
├── verify.sh
├── INSTALL.md         # manual install fallback
└── README.md
```

`README.md` is this document — the central guide and the first thing to read. `INSTALL.md` covers the step-by-step setup for the three plugins, MCP server configuration, hook enablement, `MAX_THINKING_TOKENS` configuration, and Wispr Flow prerequisite installation. The `commands/` directory holds the three runnable slash commands, one per workflow. Each command file narrates its phases as it runs, so you can follow along and know which gate you are at.

## Credits and references

The authoritative design source for this playbook is the plan file at `/Users/christxu/.claude/plans/steady-sprouting-rabbit.md`. That file contains the complete step-by-step tables (A1–A38, B1–B48, C1–C35), the per-step rationales, and the plugin citations. This README is a prose expansion of that plan; the plan is the source of truth if the two ever disagree.

This playbook inherits from the global rules in `~/.claude/rules/common/`, specifically: `coding-style.md` for immutability, file organization, and error handling; `git-workflow.md` for conventional commit format and PR workflow; `testing.md` for the 80% coverage gate and TDD mandate; `performance.md` for the model selection strategy and context window management; `patterns.md` for skeleton project and repository pattern conventions; `mentor.md` for the technical mentor trade-off reasoning and growth-edge monitoring; `hooks.md` for the hook type taxonomy and auto-accept rules; `development-workflow.md` for the full research-plan-TDD-review pipeline; `agents.md` for agent orchestration and parallel task execution; and `security.md` for the mandatory security checks and secret management rules. Every rule in those files applies to every workflow in this playbook without exception.

The three plugins that make it work: `everything-claude-code@1.7.0` provides 37 commands, 14 agents, 60 skills, the lifecycle hooks, and most of the MCP bundle. `codex@1.0.2` provides the 7 Codex commands, the `codex-rescue` agent, the 3 Codex skills, and the Codex CLI bridge to GPT-5.4. `caveman@600e8efc` provides the 3 caveman commands, the 5 compression skills, and the SessionStart plus UserPromptSubmit hooks that enforce terse mode. Without all three plugins the workflows degrade — some steps become no-ops — but the degradation is graceful and the playbook will still produce useful output on a partial install.

## License

MIT-equivalent. Personal use, no warranty. Fork it, modify it, break it into pieces, use it as a template for your own setup. The commands and plans in this repository are configuration for third-party plugins, not software in their own right; the licenses of `everything-claude-code`, `codex`, and `caveman` apply to their respective components. This playbook is offered as-is with no promises about future compatibility when the plugins update.
