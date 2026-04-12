---
description: Run the 0→1 development pipeline — research, plan, scaffold, TDD, review, ship, persist learnings
argument-hint: [project-name] [optional: one-line description]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill, WebFetch, WebSearch, Task, TaskCreate, TaskUpdate, EnterPlanMode, ExitPlanMode, AskUserQuestion
---

# /zero-to-one — New Project Pipeline

## Purpose
Runs Workflow A from `/Users/christxu/.claude/plans/steady-sprouting-rabbit.md` end-to-end: a 38-step pipeline for greenfield projects that spends tokens on research and planning up front, forks battle-tested skeletons over writing new code, and locks in TDD + memory from day one. Use this when you are starting a brand-new project from scratch. The expected outcome is a scaffolded repo with tests, a reviewed first commit, a PR, a vault session note, and episodic memory saved for later 1→n work.

## Prerequisites
- Plugins installed: `everything-claude-code@1.7.0`, `codex@1.0.2`, `caveman@600e8efc`
- MCPs configured and reachable: `engram`, `gitnexus`, `exa-web-search`, `context7`, `github`
- `gh` CLI authenticated (`gh auth status`)
- Codex CLI ready (`/codex:setup` returns green)
- Brain vault present at `~/Desktop/Brain` (for `/vault-session`)
- Wispr Flow optional but recommended for long-form dictation during planning

## Clarification Gates (MANDATORY)

This command must not proceed past any gate with an assumption. When a decision is ambiguous, use `AskUserQuestion` with 2-4 labeled options. If the user is unresponsive, output `[BLOCKED: awaiting <decision>]` and stop. See global policy at `~/.claude/rules/common/clarification.md`.

**Rule of thumb:** ask A-or-B, not "is this ok?". Ask at the start of a phase, not the end. Silent defaults are forbidden.

### Phase 0 — Intake (before Phase 1 starts)

Batch these into `AskUserQuestion` calls (up to 3 per call, grouped by topic). Every one of these is a gate — do not infer from `$2`:

- **Target runtime** — Node / Python / Go / Rust / other
- **Deployment target** — local / Docker / Vercel / Cloudflare / AWS / Railway / self-hosted
- **Package manager** — npm / pnpm / yarn / bun (or pip / poetry / uv / cargo / go mod)
- **Persistence layer** — none / SQLite / Postgres / Redis / file
- **Auth model** — none / API key / OAuth / JWT / session / magic link
- **Test framework** — ask when the chosen language has >1 idiomatic option (e.g. Python: pytest vs unittest; JS: vitest vs jest)
- **License** — MIT / Apache-2.0 / GPL-3.0 / proprietary
- **Repo visibility** — public / private
- **Budget / timebox** — quick prototype (hours) / weekend spike / production-ready (days+)
- **Skeleton selection** — when A7 surfaces 2+ forkable candidates, present the top 3 with trade-offs (stars, last commit, license, fit) and ask which to fork. Never pick silently.

### Between-phase gates

Stop and confirm at each of these transitions. Do not chain phases silently.

- **Before Phase 2 (Plan & Design)** — confirm Phase 1 research findings and which skeleton (if any) was chosen. Show the user the shortlist before entering plan mode.
- **Before Phase 3 (Scaffold)** — confirm the plan was approved. `ExitPlanMode` enforces this structurally, but also explicitly ask: "Approve as-is, or revise X/Y/Z?"
- **Before Phase 4 (TDD)** — confirm the test framework (if not pinned in Phase 0) and the first vertical slice's test targets. Ask: "Which slice do we RED first — A, B, or C?"
- **Before Phase 5 (Review)** — confirm what "done" looks like for this session. Ask: "Ship one slice and stop, or keep looping until the Phase 2 milestone is complete?"
- **Before Phase 6 (Ship)** — confirm commit authorship attribution, PR target branch (`main` / `master` / other), and whether to `git push` immediately or stage locally.
- **Before `mem_save` / `/vault-session`** — confirm what's worth saving to long-term memory. Ask: "Save full ADR, save learnings only, or skip memory write?"

### Hard stops (never proceed past without an explicit answer)

- **Any destructive git op** — `reset --hard`, `push --force`, `branch -D`, `clean -f`, `checkout .`
- **`gh repo create`** — confirm name, visibility, and org/owner before creating. One-way door.
- **Installing dependencies** — confirm each new dep before `npm install` / `pip install` / `cargo add`. No silent adds.
- **Touching files outside `$1` project directory** — ask before writing anywhere that is not the new repo root.
- **Any choice between two non-equivalent architectural approaches** — monolith vs services, sync vs queue, SQL vs document, server-rendered vs SPA, etc.

### How to ask

Use `AskUserQuestion` with labeled options. Batch up to 3 related questions per call. Never ask "is this ok?" — ask "A or B?".

### Anti-patterns (do NOT do these)

- **Silent defaults** — picking Node + npm + Vercel because "it's common". Ask.
- **Prose questions without tool calls** — writing "I'll assume X, let me know if not" and continuing. Stop and fire `AskUserQuestion`.
- **Approval at the end instead of the start** — asking "ok to commit?" after scaffolding 20 files. Ask before the files exist.
- **Multiple variations of the same question** — re-asking runtime after it was answered in Phase 0. Persist answers across the run.

## Arguments
- `$1` — project name (required). Used for session slug, repo name, vault note.
- `$2` — one-line description (optional). Used as the domain seed for A4–A7 searches.

If `$1` is missing, stop immediately and ask the user for it via `AskUserQuestion`.

## Step map (38 steps, 6 phases)

| Phase | Steps | Focus | Gate |
|---|---|---|---|
| 1 — Context & Research | A1–A8 | Prior art, past notes, episodic memory, skeletons, docs | No writes |
| 2 — Plan & Design | A9–A15 | Multi-model plan, adversarial review, user approval | User approves plan |
| 3 — Scaffold | A16–A19 | PM lock, repo init, docs bootstrap | Confirm before `gh` remote ops |
| 4 — TDD Implementation | A20–A24 | RED → GREEN → REFACTOR per slice | `/verify quick` green |
| 5 — Review & Harden | A25–A30 | Orchestrated agents, Codex second opinion, full verify | No unresolved CRITICAL/HIGH |
| 6 — Ship & Persist | A31–A38 | Commit, PR, checkpoint, memory, vault, learn | `mem_session_summary` |

## Pipeline

### Phase 1 — Context & Research (before any code)

Gate: do NOT write any project files in this phase. Read-only discovery only. The goal is to surface every relevant prior art item before you commit to a stack.

1. **A1 — `/caveman full`** — set terse output for the exploration phase (saves ~40% on tokens during broad search per caveman plugin docs).
2. **A2 — `/sessions`** — resume a prior session named `$1` or create a fresh one. This gives `continuous-learning-v2` a session boundary to attach observations to and activates the SessionStart hooks.
3. **A3 — `mcp__engram__mem_context`** — pull recent episodic memory from past sessions. Hydrates prior decisions that may apply to `$1`. Required per engram rules at every session start.
4. **A4 — `/vault-find "$2"`** (or `$1` if `$2` omitted) — surface any Brain notes already written about this domain. Prefer this over raw file reads; it is cheaper per token. Record any wikilinks surfaced so A35 can back-link to them.
5. **A5 — `mcp__engram__mem_search "$2"`** — cross-project episodic matches on the domain keyword. Look for `type: architecture`, `type: decision`, and `type: learning` hits from prior projects.
6. **A6 — `mcp__exa-web-search`** — broad prior-art discovery: benchmarks, state-of-the-art articles, academic papers, blog post-mortems. Parallelize with A7.
7. **A7 — `gh search repos "$2"` + `gh search code "$2"`** — find forkable skeletons. Rank by stars, last-commit recency, license compatibility, and `coding-standards` skill applicability. This triggers the `search-first` skill automatically. Capture 3–5 candidates for the A14 user decision.
8. **A8 — `context7` MCP** — live docs for whichever stack the prior-art search pointed toward. Do not guess URLs — let `context7` resolve library names to canonical doc URLs.

Parallelization: A4–A7 are independent; fire them in a single batch. A3 and A5 both hit engram and should also run concurrently. A8 depends on A6/A7's output and runs after.

### Phase 2 — Plan & Design

Gate: this phase produces an approved plan file. Do not exit plan mode until the user explicitly approves. See plan section "Workflow A rationale" for why multi-model planning + adversarial review are non-negotiable here.

9. **A9 — `EnterPlanMode`** — block writes and enter structured planning. Every output from this point through A15 is plan text only.
10. **A10 — `/multi-plan`** — multi-model collaborative planning across Codex (GPT-5.4), Gemini, and Claude. The command itself handles Research → Ideation → Plan staging. Feed it the Phase 1 research bundle (A4–A8 outputs) as context.
11. **A11 — `Agent(planner)`** — generate PRD, phased breakdown, risk list. Use **Opus 4.6** for this agent (deepest reasoning per `performance.md`). Output format: PRD, phases with acceptance criteria, risk list with mitigation, tech stack decision record.
12. **A12 — `Agent(architect)`** _(parallel with A11)_ — system design critique and scalability call-outs. Specifically probe: data model, auth boundaries, failure modes, scaling cliffs, deployment target constraints.
13. **A13 — `/codex:adversarial-review`** — run against the draft plan text once A10–A12 converge. GPT-5.4 attacks auth, data loss, race conditions, schema drift, and design-level assumptions. Collect findings into the plan's risk list.
14. **A14 — `AskUserQuestion`** — tie loose ends: resolve any conflicting recommendations from A10–A13, pick between candidate skeletons from A7, confirm the target stack, confirm deployment target. Do not guess — ask.
15. **A15 — `ExitPlanMode`** — STOP HERE. The user must explicitly approve the plan before you proceed to Phase 3. Write the approved plan to `/Users/christxu/.claude/plans/<slug>-$1.md` so it is referenceable from A32 (PR body) and A34 (`mem_save`).

### Phase 3 — Scaffold

Gate: before A17, confirm with the user which skeleton (if any) to fork, and confirm repo visibility (public/private). Creating remote state is one-way — ask first.

16. **A16 — `/setup-pm`** — lock the package manager (npm / pnpm / yarn / bun / pip / poetry / uv / cargo / go mod). Record the choice in the session so PostToolUse hooks know which formatter to run.
17. **A17 — Initialize the repo** (STOP and confirm with the user first):
    - **If a skeleton was chosen in A14:** `gh repo fork <owner/repo> --clone --remote-name origin` then rename locally to `$1`. Preserve the upstream remote for future rebases.
    - **Otherwise:** `gh repo create $1 --private --clone` (default private unless user explicitly said public). Add `.gitignore`, `LICENSE`, and README at creation time via `--gitignore` / `--license` flags.
    - Verify the clone landed and `cd` into it before proceeding. All subsequent steps assume cwd is the new repo root.
18. **A18 — Write-time skill auto-load** — based on stack detected at A16/A17, the following skills attach automatically at write time: `coding-standards` (always), plus the matching language/framework pattern skill (`backend-patterns`, `frontend-patterns`, `django-patterns`, `springboot-patterns`, `golang-patterns`, `swiftui-patterns`, `python-patterns`, `jpa-patterns`, `postgres-patterns`, `docker-patterns`, etc.). No explicit invocation needed; they attach on edit.
19. **A19 — `Agent(doc-updater)`** — bootstrap `README.md` and `CODEMAPS.md` from the approved plan file written in A15. Include: project purpose, stack, install/run instructions, module map, contribution notes. This seeds the project docs so later 1→n work (Workflow B) has an accurate starting map.

### Phase 4 — TDD Implementation

Gate: every unit follows RED → GREEN → REFACTOR. Do not advance to Phase 5 until `/verify quick` is green on the implemented slice. Per `testing.md`, tests come first — non-negotiable.

20. **A20 — `/tdd`** — invokes the `tdd-guide` agent to write failing tests first for the first vertical slice. Confirm the test actually fails before implementing — a test that passes without code is a false positive.
21. **A21 — Stack testing skill** auto-loads based on stack: `python-testing`, `golang-testing`, `springboot-tdd`, `django-tdd`, `e2e-testing`, or `cpp-testing`. These encode framework idioms (fixtures, test discovery, mocking, coverage flags).
22. **A22 — Implement minimal GREEN code**. Use **Sonnet 4.6** as the implementation model (best coding model per `performance.md`). Constraints from `coding-style.md`: files under 400 LOC, functions under 50 lines, no nesting deeper than 4, immutable data, no hardcoded values. Extract utilities aggressively.
23. **A23 — `/refactor-clean`** — after each green bar run `knip` / `depcheck` / `ts-prune` (JS/TS), `vulture` / `pyflakes` (Python), `go vet` / `staticcheck` (Go), or language equivalent. Remove anything the new code made dead. PostToolUse auto-format hooks fire here.
24. **A24 — `/verify quick`** — fast inner loop: build + types only, no full test run. This is the per-unit checkpoint; full tests run in A30.

Repeat A20–A24 per vertical slice until the Phase 2 plan's first milestone is met. If any slice needs more than two RED→GREEN cycles, stop and ask whether the slice is too big (break it down) or the approach is wrong (revisit plan).

### Phase 5 — Review & Harden

Gate: all CRITICAL and HIGH issues from every reviewer must be resolved before moving to Phase 6. MEDIUM issues should be fixed when cheap. Do not ship red.

25. **A25 — `/orchestrate feature`** — sequences `planner → tdd-guide → code-reviewer → security-reviewer` automatically. Per the plan's "critical files" note, **call this command, do not reimplement the sequence**. Wait for it to complete before A26.
26. **A26 — `Agent(code-reviewer)`** — launch explicitly even though `/orchestrate` already ran it. Mandatory per CLAUDE.md and catches anything added since A25. Use **Sonnet 4.6**.
27. **A27 — `Agent(security-reviewer)`** _(parallel with A26)_ — OWASP top-10, secrets scan, injection review, authn/authz surface, rate limiting, error-message leakage. Per `security.md` mandatory checklist.
28. **A28 — `Agent(database-reviewer)`** _(parallel, conditional)_ — if the project uses persistence (SQL, NoSQL, ORM, file DB), review schema, indexes, migration strategy, N+1 query patterns. Skip entirely if no persistence layer.
29. **A29 — `/codex:adversarial-review`** — pre-commit second opinion from GPT-5.4 on the actual code, not just the plan. Per `codex` plugin rules: **never auto-apply** Codex fixes. Review `/codex:result` output first, then ask the user which findings to fix now vs file as follow-ups.
30. **A30 — `/verify pre-pr`** — slow outer loop: build + types + lint + tests + coverage + console.log scan + git status. Must be green before Phase 6. Coverage must clear the 80% gate from `testing.md`; if it does not, loop back to A20 for the missing slice.

### Phase 6 — Ship & Persist

Gate: STOP and show the user the first commit diff before running `/caveman-commit`. This is the first time anything lands on main. The learning-loop tail (A33–A38) is non-optional; this is what makes the next 0→1 project cheaper.

31. **A31 — `/caveman-commit`** — produce a terse Conventional Commit message (`feat:`, `chore:`, `docs:`, etc., per `git-workflow.md`). Confirm the message with the user before it lands. Never `--amend`, never `--no-verify`.
32. **A32 — `gh pr create`** — PR body must include: link to the approved plan from A15, test plan checklist, prior-art citations from A7, coverage number from A30, list of Codex findings from A29 and how they were addressed.
33. **A33 — `/checkpoint`** — snapshot git diff + coverage + session state. This is the project's day-one baseline; every future `/checkpoint` compares to this one.
34. **A34 — `mcp__engram__mem_save`** — structured architecture decision record. Fields:
    - **What:** project name `$1`, stack, deployment target
    - **Why:** problem statement, approach chosen, alternatives rejected
    - **Where:** repo URL, main modules, key files
    - **Learned:** anything surprising from A10–A13 (adversarial review findings, model disagreements)
    - **Topic key:** `$1/architecture/bootstrap`
    - **Type:** `architecture`

    This is the PROACTIVE SAVE RULE from `mentor.md` and engram rules — do not wait to be asked.
35. **A35 — `/vault-session`** — write a Brain session note at `~/Desktop/Brain/sessions/YYYY-MM-DD-$1.md`. Required frontmatter per CLAUDE.md: `type`, `cssclasses`, `status`, `source`, `project`, `started_at`, `aliases`. Use `[[wikilink]]` style for every reference. Back-link to the notes surfaced by A4.
36. **A36 — `/learn-eval`** — evaluate the session for extractable instincts: patterns that recurred, surprising corrections, repeated tool sequences, decisions that would apply to future greenfield projects.
37. **A37 — `/evolve --generate`** _(conditional)_ — if `/learn-eval` flags enough density, cluster instincts into new skills. **Skip if density is low** — forcing skill creation on thin data creates noise and pollutes future sessions. Err on the side of skipping.
38. **A38 — `mcp__engram__mem_session_summary`** — MANDATORY end-of-session save per engram rules. **Never say "done" before this runs.** This is the last step, always.

## Execution notes

- **Parallelization opportunities:**
  - Phase 1: A4–A7 in one tool-call batch, A3 and A5 concurrent (both hit engram). A8 runs after A6/A7 since it depends on their output.
  - Phase 2: `Agent(planner)` + `Agent(architect)` in parallel (A11 ‖ A12). A13 waits for both, then feeds their output to `/codex:adversarial-review`.
  - Phase 5: `Agent(code-reviewer)` + `Agent(security-reviewer)` + `Agent(database-reviewer)` in parallel (A26 ‖ A27 ‖ A28). A25 `/orchestrate feature` runs first since it is a sequencer.
  - Phase 6: A36 and A37 are sequential (learn-eval must complete before evolve can decide density). A34 and A35 can run in parallel since they write to different stores (engram vs Brain vault).
- **Model selection (from `performance.md`):**
  - Phase 2 planning/architecture (A10–A13): **Opus 4.6** (deepest reasoning, reserved for plan phase only).
  - Phase 4 implementation (A22) and Phase 5 review (A25–A28): **Sonnet 4.6** (best coding model).
  - Adversarial review (A13, A29): **GPT-5.4 via Codex** (independent reasoning lens, second opinion).
  - Haiku 4.5 not used here — no worker-agent parallelism in 0→1. Reserve Haiku for Workflow B `/multi-execute`.
- **Caveman intensity policy:**
  - `full` by default per the SessionStart hook.
  - Drops to `normal` automatically for destructive-op confirmations (A17 repo create, A31 first commit) and for any security warnings from A27 / A29.
  - Escalate to `ultra` only if research dumps in Phase 1 get unwieldy (hundreds of search hits).
  - Use `/caveman-compress` on any plan file written in A15 if it crosses ~200 LOC — saves ~46% input tokens in later phases.
- **Hooks already active (do not reinvoke):**
  - SessionStart (everything-claude-code + caveman + codex): loads context, activates caveman full, starts lifecycle tracking.
  - PreToolUse: blocks dev servers outside tmux, reminds before `git push`, captures tool observations for continuous-learning-v2.
  - PostToolUse: auto-formats JS/TS after edit, TypeScript type-check after edit, console.log warnings, PR URL logging.
  - SessionEnd: persists session + extracts patterns.
- **Do not reimplement existing orchestration:** call `/orchestrate feature`, `/multi-plan`, `/codex:adversarial-review`, and `/verify` as-is. The plan's "critical files" section explicitly flags reimplementation as wasted work — they already route through planner / tdd-guide / code-reviewer / security-reviewer internally.
- **Token discipline:** Phase 1 and Phase 5 are the two token-heavy phases. Prefer `/vault-find` over raw file reads in Phase 1 (cheaper per token). In Phase 5, let reviewer agents summarize rather than dumping full diffs back into context.
- **File-size hygiene:** flag at write time any file crossing 400 LOC (per `coding-style.md` and `mentor.md`). Suggest extraction to a separate module immediately — do not defer.

## When to stop for user input

Hard gates — stop and ask, do not proceed silently. These are one-way doors or trust boundaries.

- **Before A1** — if `$1` is missing, ask for project name via `AskUserQuestion`. Never invent one.
- **At A14, before A15** — present the synthesized plan (A10 `/multi-plan` output + A11 planner + A12 architect + A13 Codex adversarial findings). Ask the user to approve, revise, or reject. Do not `ExitPlanMode` until they approve.
- **Before A17** — confirm skeleton choice (if any), repo visibility (public vs private), and repo name. `gh repo fork` and `gh repo create` are one-way — always confirm.
- **During A20** — if the initial RED test is hard to write, stop and ask whether the API surface is wrong rather than grinding. Bad tests signal bad design.
- **After A23 if `/refactor-clean` surfaces a pattern touching many files** — stop and confirm before large refactors.
- **After A29** — if Codex surfaces any CRITICAL finding, show findings in full (caveman drops to normal per safety-gates policy), then ask which to fix before committing. **Never auto-apply Codex fixes.**
- **If A26 / A27 / A28 return CRITICAL issues** — stop, fix, re-run the reviewer, do not continue to Phase 6 until green.
- **Before A31** — show the staged diff and the proposed commit message. Confirm both.
- **Before A32** — confirm PR body contents and base branch. `gh pr create` is a notification event to collaborators.
- **Before A37** — confirm whether to actually generate new skills. Err on the side of "no" if density is marginal.

## Success criteria

Verify each item explicitly before reporting the workflow complete. If any is missing, loop back to the owning phase rather than hand-waving.

- **Session live** — `/sessions` shows an active session named `$1`; continuous-learning-v2 observations are attaching.
- **Plan approved** — a plan file exists (preferably at `/Users/christxu/.claude/plans/<slug>-$1.md`), was stress-tested by `/multi-plan` + `Agent(planner)` + `Agent(architect)` + `/codex:adversarial-review`, and the user explicitly approved it at A14–A15.
- **Repo initialized** — `gh repo view $1` returns the new repo; package manager is locked (lockfile committed); `README.md` and `CODEMAPS.md` exist and reflect the approved plan.
- **Vertical slice shipped** — at least one vertical slice is implemented TDD-first. `/verify pre-pr` is green. `/test-coverage` reports ≥80% per `testing.md`.
- **Reviewers clean** — `/orchestrate feature` completed. `Agent(code-reviewer)`, `Agent(security-reviewer)`, and (if applicable) `Agent(database-reviewer)` returned zero unresolved CRITICAL or HIGH issues. Any MEDIUM issues are either fixed or explicitly deferred with rationale.
- **Codex second opinion processed** — `/codex:adversarial-review` ran at both A13 (plan) and A29 (code). All CRITICAL findings were addressed or consciously deferred with user approval.
- **Shipped** — a first commit exists on main (or the feature branch), a PR is open via `gh pr create`, `/checkpoint` captured the day-one baseline with diff + coverage numbers.
- **Memory persisted** — `mcp__engram__mem_save` wrote an architecture decision record with topic key `$1/architecture/bootstrap` and type `architecture`. Verify with `mcp__engram__mem_search "$1/architecture"`.
- **Vault note written** — a Brain session note exists at `~/Desktop/Brain/sessions/YYYY-MM-DD-$1.md` with required frontmatter (`type`, `cssclasses`, `status`, `source`, `project`, `started_at`, `aliases`) and `[[wikilink]]` back-links to A4 hits.
- **Learning loop closed** — `/learn-eval` ran; `/evolve --generate` either ran or was consciously skipped for low density.
- **Session summarized** — `mcp__engram__mem_session_summary` ran as the final step. This is the signal that the workflow is safe to declare done.

## Example invocations

```
/zero-to-one runvault-cli "port the RunVault adapter layer to a standalone CLI"
/zero-to-one pdf-ocr-service "OCR + layout extraction microservice for invoices"
/zero-to-one daily-standup-bot "Slack bot that summarizes yesterday's commits per repo"
```

For each invocation, Claude should:
1. Parse `$1` and `$2`.
2. Run the Phase 1 research sweep before choosing any stack — the right answer often differs from the user's gut.
3. Drive every gate above explicitly. Do not chain phases silently.
4. Report progress after each phase transition so the user can steer mid-run.

## Failure modes and recovery

- **Phase 1 returns nothing relevant** — broaden the search terms, re-run A4–A7 with synonyms. If still nothing, proceed to Phase 2 but flag to the user that this is a novel domain so planning needs extra adversarial review.
- **Phase 2 models disagree sharply** — do not pick arbitrarily. Surface the disagreement to the user at A14 with each model's position summarized.
- **Phase 4 slice cannot be made GREEN in two cycles** — stop. Usually means the slice is too big or the test boundary is wrong. Break down or revisit plan.
- **Phase 5 reviewer floods with HIGH findings** — pause, batch-fix, re-run the reviewer. Do not ship through noise.
- **Codex (`/codex:rescue` / adversarial-review) hangs** — `/codex:status` to check, `/codex:cancel` if stuck, proceed without the Codex second opinion but note in the PR body that it was skipped.
- **`mem_session_summary` fails at A38** — do not say "done". Retry; if persistently broken, dump session state to a note in Brain manually before closing.

## Reference

- Source plan: `/Users/christxu/.claude/plans/steady-sprouting-rabbit.md` (section "Workflow A — 0→1 Development")
- Related workflows: `/one-to-n` (Workflow B for large codebase features), `/debug-test` (Workflow C for bug hunts)
- Style and safety rules referenced above: `~/.claude/rules/common/coding-style.md`, `~/.claude/rules/common/testing.md`, `~/.claude/rules/common/security.md`, `~/.claude/rules/common/performance.md`, `~/.claude/rules/common/git-workflow.md`, `~/.claude/rules/common/mentor.md`
- CLAUDE.md vault conventions: `~/.claude/CLAUDE.md`
