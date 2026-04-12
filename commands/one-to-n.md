---
description: Run the 1→n development pipeline — map codebase, impact analysis, parallel execution, verify, ship
argument-hint: [feature-description] [optional: target area/module]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill, WebFetch, Task, TaskCreate, TaskUpdate, EnterPlanMode, ExitPlanMode, AskUserQuestion
---

# /one-to-n — Feature Pipeline for Large Codebases

## Purpose
Use this pipeline when adding a feature to an existing, non-trivial codebase where you cannot hold the whole tree in your head. It front-loads mapping and blast-radius analysis via the `gitnexus` MCP, parallelizes execution with `/multi-execute` worker agents, and stages verification from cheap to expensive. Expected outcome: a PR whose reviewer can trust that every call site of every touched symbol was considered.

**When to run this instead of other workflows**:
- Greenfield / new project from scratch → run `/zero-to-one` (different intent: research + scaffold, not mapping + impact).
- Pure bug fix with a reproducible failure → run `/debug-test` (locks the bug with a RED test first).
- Feature in an existing repo where the blast radius matters → `/one-to-n` (this command).

If you are not sure which workflow applies, default to this one; the mapping phase is cheap enough that it is worth running even if the change turns out to be smaller than feared.

## Prerequisites
- Plugins installed: `everything-claude-code@1.7.0`, `codex@1.0.2`, `caveman@600e8efc`.
- MCP servers reachable: `gitnexus` (REQUIRED — must be indexed for this repo; run `mcp__gitnexus__list_repos` if unsure), `engram`, `exa-web-search`, `context7`, `github`.
- `gh` CLI authenticated (`gh auth status`).
- Test suite is GREEN on the base branch before you start. If it is red, fix that first — do not build on top of a red tree.
- You are in a real git repo with a working tree clean enough to branch from.
- `MAX_THINKING_TOKENS` set if you want deeper planning on B14–B17.

## Arguments
- `$1` — feature description (required). One or two sentences; this becomes the query string for every mapping tool below.
- `$2` — target area/module (optional). A directory, package, service name, or route prefix. Sharpens the focus of `mcp__gitnexus__context`, `route_map`, and the Explore agents; also narrows `/vault-find` and `mem_search`.

If `$1` is empty, stop and run `AskUserQuestion` for a description before anything else.

### Invocation examples

```
/one-to-n "Add rate limiting to the /api/search endpoint with per-user quotas"
/one-to-n "Switch session storage from in-memory to Redis" "packages/auth"
/one-to-n "Emit OpenTelemetry spans around every outbound HTTP call" "internal/httpclient"
```

The second argument is the biggest multiplier on Phase 1 quality. Without it, `mcp__gitnexus__context` returns the full graph neighbourhood and Explore agents wander; with it, they focus on the right module immediately.

---

## Pipeline

### Phase 1 — Mapping (READ-ONLY, no edits permitted)

This phase is strictly read-only. Do not touch files. Do not stage changes. If you catch yourself wanting to edit something, stop and write it down as a plan note instead — edits happen in Phase 5, never earlier.

- **B1** — Run `/caveman full` to switch to terse mode. Large-repo mapping dumps a lot of text; terse output saves input tokens.
- **B2** — Run `/sessions` to resume or open a fresh named session for this feature. All subsequent memory saves will attach to it.
- **B3** — Call `mcp__gitnexus__list_repos` to confirm the current repo is indexed. If it is not indexed, STOP and ask the user to index it; do not proceed without the knowledge graph — this whole workflow depends on it.
- **B4** — Call `mcp__gitnexus__context` with the feature area (use `$2` if provided, otherwise keywords from `$1`). This returns the knowledge-graph slice: modules, classes, functions, and their relationships around the feature.
- **B5** — Call `mcp__gitnexus__route_map` and `mcp__gitnexus__tool_map` to trace request → handler → service → repository paths and tool-call sites. This is how you discover the real seams, not the ones the README claims exist.
- **B6** — If the codemap looks stale (new files not in graph, old files still present), run `/update-codemaps` to refresh the project codemap before deeper exploration.
- **B7** — Launch **three Explore agents in parallel** with thoroughness set to "very thorough". Give each a different angle so they do not duplicate work:
  1. "Find every existing implementation of <feature> or adjacent functionality, and every test that exercises it."
  2. "Find every caller of the symbols returned by gitnexus in B4/B5, including indirect callers via reflection, DI, or string dispatch."
  3. "Find the most similar feature already in the repo and list the files it touches and the conventions it follows."
  Three angles beats one sequential pass — this is where you find the 14 call sites instead of the 1 obvious one.
- **B8** — Run `mem_search` with `<repo-name>/<area>` to surface prior decisions, bug fixes, and conventions from past sessions on this codebase. Also call `mem_context` for recent session history.
- **B9** — Run `/vault-find` with the feature keyword to pull Brain notes tied to this codebase. Prefer this over hand-reading vault files.

Output of Phase 1 is a mental model of: every file that is likely to change, every file that merely calls what will change, and every test that currently pins behaviour near the change. Write this mental model into the plan file in Phase 3 — do not try to hold it.

---

### Phase 2 — Impact Analysis (NON-NEGOTIABLE before any edit)

This phase is the reason you are running this workflow instead of `/zero-to-one`. Editing a large repo without an impact check is the single biggest 1→n failure mode. Do every check below, even if "the change is small" — the graph knows better than your intuition.

- **B10** — For every symbol (function, class, type, method) you plan to touch, call `mcp__gitnexus__impact <symbol>`. Collect the full blast radius list. If any symbol has more than ~20 direct callers, or touches more than ~5 modules, treat that as a hard gate and stop to discuss the approach with the user before continuing (see "Hard gates" below).
- **B11** — For every HTTP route, RPC method, CLI flag, or public API surface you plan to modify, call `mcp__gitnexus__api_impact` to check for contract breaks. Pay attention to clients outside the repo (mobile apps, scripts, downstream services) — `api_impact` flags them if the graph knows about them.
- **B12** — Call `mcp__gitnexus__shape_check` on any data structure you plan to add a field to, remove a field from, or rename. Data-shape compatibility is where migrations and serializers silently break.
- **B13** — Call `mcp__gitnexus__detect_changes` to see what has drifted since the last indexing run. If the graph is significantly out of date (many detected changes), re-run `/update-codemaps` before trusting B10–B12.

**Stop condition**: if B10 returns a blast radius that is materially larger than what you assumed in your plan, DO NOT proceed to Phase 3 as written. Go back to Phase 1, re-scope, and tell the user what you found. Silent scope creep in a 1→n workflow is how regressions ship.

---

### Phase 3 — Plan

- **B14** — `EnterPlanMode`. From here until `ExitPlanMode`, writes are blocked by the harness; lean into that.
- **B15** — Run `/multi-plan` to execute Research → Ideation → Plan across Claude (Opus 4.6), Codex (GPT-5.4), and Gemini in parallel. Three independent plans stress-test assumptions better than one.
- **B16** — Launch three split-role reviewers **in parallel** on the merged plan:
  - `Agent(planner)` — phased breakdown, task list, dependencies, risks
  - `Agent(architect)` — system design critique, scalability and coupling
  - `Agent(security-reviewer)` — auth, input validation, rate limiting, secret handling
  Merge their findings into the plan file. If any of them flags a CRITICAL or HIGH issue, resolve it before moving on.
- **B17** — Run `/codex:adversarial-review` on the plan text. GPT-5.4 attacks design choices (races, data loss, schema drift, auth holes) rather than syntax — that is its unique value at this gate.
- **B18** — `ExitPlanMode`. Before exiting, confirm with `AskUserQuestion` on any non-obvious trade-off the reviewers surfaced. This is the second hard gate (see "Hard gates").

Plan file lives at `/Users/christxu/.claude/plans/<slug>.md` so subsequent phases can reference it by path.

---

### Phase 4 — TDD at Integration Seams

Tests go at the boundaries between the modules you touched, not at implementation details inside them. Implementation-detail tests over-fit and have to be rewritten when Phase 5 refactors. Contract-level tests survive.

An "integration seam" for this workflow means: the outermost point at which data crosses a module boundary and the behaviour you are changing is observable. That is usually one of: an HTTP route handler, a queue consumer, a CLI entry point, a public service method, or a repository interface. Test *there*, not inside the private function you are editing.

- **B19** — Run `/tdd` to enter RED-first mode under `tdd-guide`. Write the first failing test at the outermost integration seam the feature crosses. Name it after the user-visible behaviour, not the internal helper.
- **B20** — Load the stack-specific testing skill so the tests use framework idiom, not generic test scaffolding:
  - Python / Django → `python-testing`, `django-tdd`
  - Go → `golang-testing`
  - Spring Boot → `springboot-tdd`
  - C/C++ → `cpp-testing`
  - Browser flows → `e2e-testing`
  Using the framework skill is not optional — hand-rolled scaffolding in a codebase that has a test framework creates two parallel test styles, and the next maintainer will delete one of them without asking which.
- **B21** — For every cross-module call that Phase 2 flagged as part of the blast radius, write a **contract test** that pins the current behaviour of the caller. The goal is: if your Phase 5 changes break a caller, this test fails loudly at Phase 6 instead of the bug slipping through into production. Contract tests are cheap insurance compared to the cost of a hotfix.

All tests written in this phase should be RED after Phase 4. If any is already GREEN, it is testing the wrong thing — rewrite it. A passing test in Phase 4 is a false negative; it tells you nothing about whether your Phase 5 implementation will actually land the change.

---

### Phase 5 — Parallel Execution

This is where `/multi-execute` earns its keep. Per `performance.md`, the worker pool is Haiku 4.5 (3× cheaper, 90% capability), orchestrated by Sonnet 4.6. You stay the orchestrator — your job is to decide the chunking, not to do the edits.

- **B22** — Run `/multi-execute` to spawn parallel worker agents, one per file in the change set (or per logical chunk if files are small). Workers execute the plan items in parallel; the orchestrator merges their diffs and resolves conflicts. Chunking rule: each worker should touch files that do not import each other, so merges are mechanical. If two files must change together, assign them to the same worker.
- **B23** — If the feature is backend-heavy (business logic, data layer, API handler), additionally route through `/multi-backend` so the Codex authority path reviews business-logic choices. Codex is your second-opinion voice on backend decisions — use it when the cost of a wrong business rule is high.
- **B24** — If the feature is UI-heavy, route through `/multi-frontend` so the Gemini authority path reviews UX choices. Gemini's diverse-model lens is most valuable for design-level trade-offs; for pure refactors it is overkill.
- **B25** — Write-time skills fire automatically on each edit: `plankton-code-quality`, `coding-standards`, and any language-specific skill (`golang-patterns`, `django-patterns`, `springboot-patterns`, `swiftui-patterns`, `python-patterns`, `backend-patterns`, `frontend-patterns`, `jpa-patterns`, `postgres-patterns`, `docker-patterns`, etc.). These enforce idiom at the moment of writing — do not disable them to "move faster". The two seconds they add per edit save ten minutes of review comments.
- **B26** — After each chunk lands, run `/refactor-clean` to remove code the change made dead (`knip` / `depcheck` / `ts-prune` / language-specific equivalents). Dead code left in place obscures the next feature and inflates the diff reviewers have to read.

Keep the Phase 4 tests running locally during Phase 5 where possible — instant RED→GREEN feedback beats waiting for Phase 6. If you cannot run tests locally (large repo, slow suite), run them after each chunk rather than waiting until the end.

---

### Phase 6 — Verification (stack-aware, staged: cheap first, expensive last)

Run checks in order so you fail fast on the cheap ones. Do NOT skip to the expensive ones just because "tests passed locally". The staging order matters: every minute saved by failing at B27 instead of B30 is a minute you do not spend rerunning a Playwright suite on a fix that was going to fail the type checker anyway.

- **B27** — `/verify` for the comprehensive fast loop: build → types → lint → unit tests → console.log scan → git status sanity. This should pass in under a minute on most repos; if it takes longer your build is the problem, not this step.
- **B28** — Load the stack-specific verification skill for framework-aware checks. General-purpose lint catches about 60% of framework pitfalls; the framework skill catches the other 40%:
  - Django → `django-verification`
  - Spring Boot → `springboot-verification`
  - Others → use the closest language skill above plus `verification-loop`
- **B29** — `/test-coverage` to confirm the 80% gate from `testing.md`. Treat coverage on **new/changed lines** as the gate, not global coverage — the global number moves too slowly to be a signal on a single PR, and rewarding global coverage incentivises writing tests for unchanged code instead of changed code.
- **B30** — `/e2e` via `e2e-runner` (prefers Vercel Agent Browser, falls back to Playwright) for any user-facing change. Skip only if the change is strictly backend-internal and no API contract moved; if you are in doubt, run it.
- **B31** — If the build went red at any step above, run `/build-fix` (or `/go-build` for Go) to invoke `build-error-resolver` for a minimal-diff fix. Do not hand-edit build errors while the rest of the verification state is unknown — you will mask one failure with another.

Phase 6 ends only when every step from B27 through B30 passes. If coverage is below 80% on changed lines, go back to Phase 4 and add tests at the seams you missed; do not lower the gate.

---

### Phase 7 — Review

Three reviewers in parallel, then two sequential second opinions. Parallelism here is the throughput win — a sequential review pass on a 20-file change is slow enough that you will be tempted to skip reviewers, and skipped reviewers are how bugs ship.

- **B32** — `/code-review` always. Per CLAUDE.md, this is mandatory after any code write. No exceptions for "trivial" changes — trivial changes are where reviewers stop paying attention and that is exactly where regressions hide.
- **B33** — Launch the language-specific deeper review in parallel with B32: `/go-review` for Go, `/python-review` for Python, equivalent for other stacks. These catch language-specific pitfalls general review misses (goroutine leaks, GIL assumptions, N+1 queries in an ORM the general reviewer does not know, etc.).
- **B34** — `Agent(database-reviewer)` in parallel with B32/B33, but only if the change touches schema, queries, or migrations. For query-heavy changes, pair this with the `database-migrations` skill so the reviewer has the migration context in scope.
- **B35** — `Agent(security-reviewer)` in parallel — always, regardless of whether you think the change is security-relevant. You are not the best judge of what is security-relevant in a codebase this size; the reviewer is.
- **B36** — After the three parallel reviewers return, run `/codex:adversarial-review` for the pre-merge second opinion. This is the second GPT-5.4 gate (first was B17 on the plan). Review `/codex:result` output manually — do not auto-apply any fixes it proposes (forbidden by the codex plugin rules).
- **B37** — `/caveman-review` last — produces the one-line PR-comment version of everything the reviewers found, which is what you will paste into the PR description.

Address CRITICAL and HIGH findings before Phase 8. MEDIUM findings: fix if cheap, defer with a one-line note in the PR body otherwise. LOW findings: note in the session memory entry at B44 for later sweeps, do not block the PR on them.

---

### Phase 8 — Document & Ship

The goal of this phase is to leave the knowledge graph, the memory store, and the docs in a state where the *next* feature starts from accurate context. Skipping any of B38–B40 shifts cost onto your future self.

- **B38** — `/update-codemaps` to refresh the project codemap so the next 1→n run starts from accurate state. This is the step people skip that breaks the *next* feature — the one you run next week that plans against the stale graph.
- **B39** — `/update-docs` plus `Agent(doc-updater)` for README, guides, and CODEMAPS. If public API changed, update docs in the same PR — never in a follow-up. "I'll document it later" is how stale docs get created.
- **B40** — `mcp__gitnexus__detect_changes` to re-index the knowledge graph. Together with B38, this closes the graph-staleness loop and means the next Phase 2 blast-radius check reflects today's state.
- **B41** — `/caveman-commit` for a terse Conventional Commit message. Types per git-workflow.md: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `ci`.
- **B42** — `gh pr create` with a body that cites the gitnexus impact findings from Phase 2, the test plan from Phase 4, and the review findings from Phase 7. Use a HEREDOC per the git workflow rules so the body formats correctly.
- **B43** — `/checkpoint` to record the diff + coverage snapshot for later reference. This is how you compare "what changed" between sessions without reading the git log.
- **B44** — `mem_save` (via `mcp__engram__mem_save`) with a structured entry: What / Why / Where / Learned. Type depends on the change: `pattern`, `decision`, `architecture`, `bugfix`, or `discovery`. Topic key format: `<project-name>/<category>/<topic>`. This is a manual save on top of continuous-learning-v2's automatic tool-use capture — save the *decision*, not the diff.
- **B45** — `/vault-session` to write the session note into Brain under `sessions/YYYY-MM-DD-<slug>.md` with the required frontmatter fields (`type`, `cssclasses`, `status`, `source`, `project`, `started_at`, `aliases`). Preserve existing fields if updating a prior note; never delete vault files.
- **B46** — `/learn` to extract reusable patterns from the session. The output feeds into the instinct pipeline.
- **B47** — `/evolve` to promote stable instincts into durable skills, if the session produced any. Only run `--generate` if the instinct has appeared across multiple sessions; one-offs are noise.
- **B48** — `mem_session_summary` — MANDATORY before you say "done". End-of-session summary anchors the memory graph for the next 1→n run, and the engram rule is explicit: never declare completion without this step.

---

## Phase-to-plugin map

Quick reference for which plugin each phase leans on, so you can debug coverage gaps if something is not firing.

| Phase | everything-claude-code | codex | caveman | MCPs |
|---|---|---|---|---|
| 1 Mapping | `/sessions`, `/update-codemaps`, Explore agents, `/vault-find` | — | `/caveman full` | `gitnexus` (`list_repos`, `context`, `route_map`, `tool_map`), `engram` (`mem_search`, `mem_context`) |
| 2 Impact | — | — | — | `gitnexus` (`impact`, `api_impact`, `shape_check`, `detect_changes`) |
| 3 Plan | `/multi-plan`, `Agent(planner)`, `Agent(architect)`, `Agent(security-reviewer)`, `EnterPlanMode`/`ExitPlanMode` | `/codex:adversarial-review` | — | — |
| 4 TDD | `/tdd`, stack testing skills | — | — | — |
| 5 Execute | `/multi-execute`, `/multi-backend`, `/multi-frontend`, write-time skills, `/refactor-clean` | — | — | — |
| 6 Verify | `/verify`, stack verification skills, `/test-coverage`, `/e2e`, `/build-fix` | — | — | — |
| 7 Review | `/code-review`, language-specific review, `Agent(database-reviewer)`, `Agent(security-reviewer)` | `/codex:adversarial-review` | `/caveman-review` | — |
| 8 Ship | `/update-codemaps`, `/update-docs`, `Agent(doc-updater)`, `/checkpoint`, `/vault-session`, `/learn`, `/evolve` | — | `/caveman-commit` | `gitnexus` (`detect_changes`), `engram` (`mem_save`, `mem_session_summary`), `github` (`gh pr create`) |

---

## Execution notes

**Parallelization map**:
- Phase 1: **3 Explore agents in parallel** (B7) with different angles
- Phase 3: **3 reviewer agents in parallel** (B16) — planner, architect, security
- Phase 5: **N worker agents in parallel** via `/multi-execute` (B22), one per file or logical chunk
- Phase 7: **3 reviewers in parallel** (B32–B35), then sequential adversarial review

**Model selection** (from `performance.md`):
- **Opus 4.6** — Phases 3 and 7 (planning, architecture, adversarial synthesis)
- **Sonnet 4.6** — Phase 5 orchestration, Phase 4 test writing, Phase 6 verification
- **Haiku 4.5** — `/multi-execute` workers (Phase 5 file-level edits)
- **GPT-5.4 via Codex** — B17 and B36 adversarial reviews
- **Gemini** — B24 frontend authority route if applicable

**gitnexus is the backbone**: `mcp__gitnexus__list_repos`, `context`, `route_map`, `tool_map`, `impact`, `api_impact`, `shape_check`, `detect_changes`. If gitnexus is unreachable or the repo is not indexed, this workflow is not safe to run — fall back to `/zero-to-one`-style exploratory mapping and warn the user you are flying blind.

---

## Hard gates (stop and ask the user)

Do not pass these checkpoints silently. Use `AskUserQuestion`.

- **After Phase 2 / before Phase 3**: if `mcp__gitnexus__impact` returns more than **20 direct callers** on any symbol, or touches more than **5 modules**, or `mcp__gitnexus__api_impact` reveals any external consumer contract change. Stop and confirm approach.
- **After Phase 3 / before Phase 5**: if any of `Agent(planner)`, `Agent(architect)`, `Agent(security-reviewer)`, or `/codex:adversarial-review` flagged a CRITICAL issue the plan did not resolve. Stop and confirm.
- **Before `gh pr create` (B42)**: if Phase 6 has any skipped step, if Phase 7 has an unresolved CRITICAL/HIGH, or if coverage on changed lines is below 80%. Stop and confirm.
- **Any time** `/caveman full` would drop to normal mode (destructive ops, security warnings, schema drops, force pushes). Confirm in full sentences, not fragments.
- **Never auto-apply** Codex fixes from B17/B36. Per codex plugin rules: review `/codex:result` output and ask the user which issues to fix.

---

## Common failure modes (and how this workflow prevents them)

- **"Small change" that touches 40 files.** Phase 2's `mcp__gitnexus__impact` surfaces the real count before the edit, not during the review. If the number shocks you, Phase 3's hard gate catches it.
- **Silent API contract break for a downstream consumer.** `mcp__gitnexus__api_impact` in B11 is the only check that catches this reliably; grep for the endpoint string is not sufficient because callers use builders, constants, and string templates.
- **Data-shape drift between producer and consumer.** `mcp__gitnexus__shape_check` in B12 catches schema/serializer mismatches that type checkers miss because the types live in different modules.
- **Tests over-fit to the old implementation, go GREEN after a rewrite that actually broke behaviour.** Phase 4's contract tests at integration seams survive refactors; implementation-detail tests do not, which is why this workflow avoids them.
- **Merge conflicts from parallel workers stepping on each other.** `/multi-execute` assigns one file (or logical chunk) per worker in B22 and the orchestrator merges. Do not hand out overlapping file lists.
- **Stale knowledge graph causing the *next* feature to plan against old state.** B38 and B40 refresh gitnexus + codemaps before the session ends. Skipping them is a common cause of "this workflow worked last week and failed this week".
- **Codex adversarial review findings silently auto-applied.** Forbidden by the codex plugin rules and by B17/B36: always review `/codex:result` output and ask the user which issues to fix.

---

## Success criteria

- Every symbol touched had a `mcp__gitnexus__impact` check recorded in the plan file before it was edited.
- Every integration seam in the blast radius has a contract test from Phase 4 that was RED before Phase 5 and GREEN after.
- Phase 6 passed end-to-end without skipped steps; coverage on changed lines ≥ 80%.
- Phase 7 ran three parallel reviewers plus the Codex adversarial pass with no unresolved CRITICAL/HIGH findings.
- gitnexus and codemaps refreshed in Phase 8 (B38 + B40) so the *next* 1→n run starts from accurate state.
- `mem_save` recorded the decision (not just the diff) and `mem_session_summary` fired before you said "done".
- PR body cites the impact findings, the test plan, and the review findings — a reviewer can trust the change without reading the whole diff first.
- No hard gate was silently passed; every confirmation from the user is logged in the session note written by `/vault-session`.
