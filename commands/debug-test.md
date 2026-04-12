---
description: Run the debug + test pipeline — reproduce, investigate, lock with failing test, minimal fix, Codex rescue fallback, harden
argument-hint: [bug-description-or-error] [optional: suspect-file-or-symbol]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill, WebFetch, Task, TaskCreate, TaskUpdate, AskUserQuestion
---

# /debug-test — Debug and Harden Pipeline

## Purpose
Run this for real bugs, failing tests, and production incidents where the root cause is unknown. The pipeline forces you to reproduce the bug before touching code, lock it with a failing test, apply the smallest possible fix, and persist the learning so the same class of defect never costs you twice. Do NOT use this for feature work (use `/zero-to-one` or `/one-to-n`) — feature scaffolding will pollute your fix diff.

## Prerequisites
- Bug is reproducible on your machine (not just CI). If you cannot reproduce locally, stop and gather repro steps first.
- Test suite runs clean before the bug exists — or you have a baseline to compare against.
- GitNexus index is present for the repo (`mcp__gitnexus__list_repos` returns the target). If not, run `/update-codemaps` before Phase 2.
- Codex CLI is installed and authenticated if you expect to hit the rescue path (`/codex:setup` once per machine).
- Engram MCP reachable (`mem_search` works) — required for Phase 7.
- Caveman full is already active via SessionStart; confirm with the statusline badge.

## Arguments
- `$1` — bug description or exact error message (required). Quote verbatim, including stack frames.
- `$2` — suspect file path or symbol name (optional). Speeds up Phase 2 impact analysis by giving gitnexus a starting node.

---

## Pipeline

### Phase 1 — Reproduce (C1–C4)

**Do not proceed until the bug is reproduced in the user's environment and the exact error is captured verbatim.** A fix applied to an unreproduced bug is a guess.

1. **C1.** Run `/caveman full` (skill `caveman:caveman`) to keep output terse. Bug hunting generates a lot of noise; every saved token is one more iteration you can afford.
2. **C2.** Reproduce the bug manually. Run the exact command, click the exact path, hit the exact endpoint. Confirm the failure occurs in your current working tree, not only in CI. If the bug only reproduces in CI, capture CI logs and ask the user for a local repro seed before going further.
3. **C3.** Capture the error verbatim. Copy the full stack trace, error code, and surrounding log lines into the session. Never paraphrase errors — the caveman rule requires verbatim quoting for diagnostic fidelity. Save the captured trace as `$ERROR_TEXT` for reuse in later phases.
4. **C4.** Run `mcp__gitnexus__detect_changes` to see what has drifted in the codebase recently. Bugs usually correlate with recent edits; drift detection narrows the search space before you even open a file.

**Gate:** If steps C2 or C3 fail (cannot reproduce, cannot get clean error text), STOP and ask the user for additional repro information. Do not speculate.

### Phase 2 — Investigate (C5–C10)

Map the blast radius before forming a hypothesis. Parallelize anything independent.

5. **C5.** `mcp__gitnexus__impact <suspect symbol>` — use `$2` if provided, otherwise derive the suspect from the stack trace. Returns every caller and callee of the suspect symbol so you know what is structurally involved.
6. **C6.** `mcp__gitnexus__context <suspect symbol>` — fetch the knowledge-graph neighborhood (related types, files, tests).
7. **C7.** Launch up to 3 parallel `Agent(Explore, "medium")` invocations with distinct angles:
   - Explorer 1: "Where is `<symbol>` called, and what calls it back?"
   - Explorer 2: "Show every test file that references `<symbol>` or its module."
   - Explorer 3: "Find recent commits touching `<symbol>` and surrounding files."
   Run these in a single message as parallel tool calls — sequential explore is the single biggest waste of wall time in debug work.
8. **C8.** `mem_search "<error keyword>"` against engram. Ask: have I seen this bug class before? Engram's bugfix-typed memories are built exactly for this lookup. Also run `mem_search` on the symbol name and the error code separately.
9. **C9.** `/vault-find "<error or symbol>"` against Brain. Personal notes sometimes beat code search when the bug touches a framework decision you documented months ago.
10. **C10.** If the investigation surfaces a **structural smell** (e.g., the bug is possible because two modules share mutable state, or an interface was violated by accident), invoke `Agent(architect)` to check whether the bug is a symptom of a deeper design break. Skip this if the bug is clearly local.

**Gate:** You should now have a **hypothesis** in plain English: "the bug happens because X under condition Y." If you cannot state this in one sentence, go back to C7 with different angles before moving on.

### Phase 3 — Lock with a Failing Test (C11–C13)

**This is the most important step in the entire pipeline.** A bug without a test cannot be called fixed — it can only be called asleep.

11. **C11.** Run `/tdd` (skill `tdd-workflow`, agent `tdd-guide`). Write a RED test at the right seam — unit if the bug is local, integration if it crosses a boundary, contract if it's a cross-module interaction. The test should fail in exactly the way the user's repro fails.
12. **C12.** Pull in the stack-appropriate testing skill so the test matches framework idiom:
    - Python/Django: `python-testing`, `django-tdd`
    - Go: `golang-testing`
    - Spring Boot: `springboot-tdd`
    - C++: `cpp-testing`
    - E2E / user-facing: `e2e-testing`
13. **C13.** Confirm the test fails **for the right reason**. Run it and read the failure output. A test that fails because of a typo in the assertion, a missing import, or a setup error is worse than no test — it will go green after the "fix" without proving anything. The failure message must match `$ERROR_TEXT` from C3, or clearly describe the same defect.

**Gate:** Do NOT proceed to Phase 4 until the test is RED for the right reason. If you cannot get it RED, your hypothesis from Phase 2 is wrong — return to C7.

### Phase 4 — Fix Minimally (C14–C17)

Minimum viable patch. No refactoring, no tidying, no "while I'm in here" edits. Refactoring is a separate pass after the fix ships.

14. **C14.** Apply the minimal diff. Write the smallest change that turns the RED test GREEN. If you find yourself rewriting a function, stop — extract the rewrite into a follow-up ticket.
15. **C15.** Run the locked test from C11. It must now pass. If it doesn't, revert, re-read the hypothesis, and try again. Do not escalate the diff — escalate the investigation.
16. **C16.** Run `/verify` (skill `verify`, alias `verification-loop`). Full loop: build + types + lint + tests + console.log check + git status. This is the cheap-to-expensive gate. Fail fast here before wasting time on coverage or review.
17. **C17.** Run `/test-coverage` (skill `test-coverage`) to confirm the new test actually counts and the module under repair still meets the 80% threshold from `testing.md`.

**Gate:** If C15 loops without convergence for more than **two full iterations** on the same symptom, do NOT keep grinding — jump to Phase 5. Claude Code has a well-documented tendency to loop on hard bugs; the Codex rescue path exists to break that loop.

### Phase 5 — Codex Escape Hatch (C18–C22)

Trigger condition: you have looped C14–C16 more than twice on the same symptom, or the hypothesis from Phase 2 no longer matches the behavior you're seeing.

18. **C18.** Run `/codex:rescue` (skill `codex:rescue`, agent `codex-rescue`). Pass it three things in the problem description:
    - The verbatim `$ERROR_TEXT` from C3.
    - Your current hypothesis from Phase 2.
    - A bulleted list of what you have already tried and why each attempt failed. Codex needs your failed attempts or it will waste a turn rediscovering them.
    Codex returns verdict, findings, artifacts, and next-step recommendations via GPT-5.4.
19. **C19.** Run `/codex:status` to watch the job. Jobs run in background; do not poll tighter than every minute. If you want deeper instrumentation, the `codex:codex-cli-runtime` skill documents the underlying CLI state machine.
20. **C20.** Once status reports complete, run `/codex:result <job-id>` to retrieve the full output. The `codex:codex-result-handling` skill formats this for review.
21. **C21.** If the job is stuck, hung, or the symptom is now obsolete (e.g., you found the bug independently), run `/codex:cancel` to kill it. Do not leave background jobs running — they cost tokens.
22. **C22.** Before applying any Codex suggestion, run `/codex:adversarial-review` against the proposed fix. This runs GPT-5.4 in adversarial mode against its own earlier output and often catches regressions the original rescue missed.

**CRITICAL — never auto-apply Codex output.** See the Codex rescue protocol section below for the required review-and-select flow. The codex plugin's policy explicitly forbids blind application of rescue results; every hunk must be reviewed and the user must select which issues to fix.

### Phase 6 — Regression Harden (C23–C28)

A fix is not done when the test turns green. It is done when the reviewers certify nothing adjacent broke and no new attack surface was introduced.

23. **C23.** Run `Agent(code-reviewer)` or `/code-review` (skill `code-review`). Mandatory per `CLAUDE.md`. Look for neighboring breakage: call sites you didn't notice, shared state you mutated, error paths you silenced.
24. **C24.** Run the language-specific reviewer in parallel with C23:
    - Go: `/go-review` (skill `go-review`)
    - Python: `/python-review` (skill `python-review`)
    - Database or schema changes: `Agent(database-reviewer)`
25. **C25.** If the bug is security-relevant (auth, input handling, secrets, injection, deserialization, crypto, session, rate limit), run `Agent(security-reviewer)` or skill `security-review`. A bug-fix patch that accidentally opens new attack surface is the classic regression trap.
26. **C26.** If the bug is user-facing, run `/e2e` (skill `e2e`, agent `e2e-runner`). Prefers Vercel Agent Browser, falls back to Playwright. A unit test alone does not protect against re-regressions in the UI layer.
27. **C27.** If the build is red, run `/build-fix` (skill `build-fix`, agent `build-error-resolver`) or `/go-build` for Go projects. Minimum-diff only — do not let the build fixer broaden the change.
28. **C28.** Run `/refactor-clean` (skill `refactor-clean`, agent `refactor-cleaner`) to sweep dead code the fix may have created. Unused imports, dead branches, and stale comments all count.

**Parallelization:** C23 + C24 + C25 are independent — launch them in a single message as parallel tool calls. C26–C28 depend on their results, so run them sequentially after the reviewers return.

### Phase 7 — Persist Knowledge (C29–C35)

Non-negotiable. The memory step is what prevents the same class of bug from recurring. Skipping C32 is the single biggest reason bugs come back in Chris's workflow.

29. **C29.** Run `/caveman-commit` (skill `caveman:caveman-commit`). Use a `fix:` type commit and make the description root-cause-oriented, not symptom-oriented. Good: `fix: prevent race in cache warmer when two workers init same key`. Bad: `fix: test failure`.
30. **C30.** Run `gh pr create` with a PR body containing: (a) exact repro steps, (b) root cause in one paragraph, (c) why the minimal fix works, (d) link to the locked test from C11, (e) any follow-up refactoring deferred from C14.
31. **C31.** Run `/checkpoint` (skill `checkpoint`) to snapshot diff + coverage for this fix. This gives you a rollback point and a measurable delta for the learning loop.
32. **C32.** **MANDATORY:** Call `mem_save` with `type: bugfix`. Use this structure:
    ```
    What:     <one-sentence symptom>
    Why:      <root cause in plain English>
    Where:    <file:line or symbol>
    Learned:  <the class of bug — generalized, not specific to this fix>
    ```
    Topic key format: `<project>/bugfix/<category>` (e.g., `obsidiantool/bugfix/cache-race`). This is the engram PROACTIVE SAVE RULE — `mem_save` on every fix is not optional. It is the entire point of why engram exists.
33. **C33.** Run `/vault-session` (skill `vault-session`) to write a Brain session note at `~/Desktop/Brain/sessions/YYYY-MM-DD-<slug>.md`. Required frontmatter fields: `type`, `cssclasses`, `status`, `source`, `project`, `started_at`, `aliases`. Use `[[wikilink]]` to the commit SHA and PR.
34. **C34.** Run `/learn-eval` (skill `learn-eval`) to evaluate the session for extractable instincts. If the bug class is stable (same shape seen twice or more), consider `/evolve --generate` in a follow-up session to promote the instinct into a skill.
35. **C35.** **MANDATORY:** Call `mem_session_summary` before saying "done". This is the engram end-of-session rule and applies to every session without exception.

---

## Why this order

- **C2–C3 reproduce first is non-negotiable.** A fix applied to an unreproduced bug is a guess, and guessed fixes don't survive contact with production. Every skipped reproduction adds a 30% chance of shipping a patch that addresses a symptom next to the real defect.
- **C4 drift detection before investigation.** The overwhelming majority of bugs correlate with code that changed in the last week. Running `mcp__gitnexus__detect_changes` before reading any file narrows the search space to a handful of commits instead of the full repo.
- **C7 parallel Explore over sequential.** Three explorers with distinct angles beat one sequential pass both in wall time and in coverage. Sequential exploration biases toward the first hypothesis; parallel exploration forces cross-checking.
- **C11 failing test before the fix is the load-bearing step.** Skipping it produces fixes that compile and look right but don't address the real defect. The RED test is your oracle — without it, GREEN is meaningless.
- **C14 minimal diff is a discipline, not a preference.** Bug-fix PRs that also refactor get rejected in code review because the fix and the refactor share the same blast radius and can't be bisected. Keep them separate.
- **C16 verify before review.** `/verify` is cheap and catches 80% of regressions. Running expensive reviewers before `/verify` wastes their output if the build is broken.
- **C18 Codex rescue as escape hatch, not first resort.** Claude Code has a documented tendency to loop on hard bugs. GPT-5.4 provides an independent reasoning lens that breaks the loop — but it costs tokens and wall time, so you trigger it only after two failed iterations, not the first hiccup.
- **C32 mem_save with type: bugfix is the whole point of the pipeline.** Without persisted bug-class memory, you pay the debugging cost twice when the same class of defect recurs. The engram PROACTIVE SAVE RULE exists for exactly this.

## Execution notes

**Parallelization:**
- Phase 2 investigators (C7): up to 3 parallel `Agent(Explore)` calls in a single message. Distinct angles per explorer — do not give them overlapping prompts.
- Phase 6 reviewers (C23–C25): code-reviewer + language-reviewer + security-reviewer in a single message. They are independent and their outputs compose cleanly.
- Everything else is sequential because each step depends on the previous result (reproduce → investigate → test → fix → verify → persist). Do not parallelize the core spine.

**Model selection (per `performance.md`):**
- **Sonnet 4.6** — main driver for Phases 1–4 and 6. Best coding model, default for debug work. Use this for the core investigate-test-fix-verify loop; it has the right tradeoff between speed and reasoning for tight iteration.
- **Haiku 4.5** — worker agents inside `/e2e`, `/refactor-clean`, and parallel Explorers in C7. Cheap and fast. Ideal for high-frequency lightweight tasks where you are running the same kind of query across many files.
- **Opus 4.6** — only if `Agent(architect)` is invoked in C10 for structural smell analysis. Do not use Opus as the main driver for debug — it is slower than Sonnet for tight iteration loops and its depth is wasted on mechanical verification.
- **GPT-5.4 via Codex** — exclusive to Phase 5 rescue. Independent reasoning lens; the whole point of the escape hatch is to break Claude's loop. Do not invoke Codex for routine bugs — it costs tokens and wall time better spent on Sonnet iteration.

**Session hygiene:**
- Run `mem_context` at the start of this workflow (not listed as a numbered step because SessionStart auto-loads it) to see what bugs you have touched recently. This often surfaces related fixes from prior sessions.
- Keep `$ERROR_TEXT` from C3 pinned in context through the whole pipeline. Do not let it get compacted out.
- If `/caveman full` makes the output so terse that you lose a critical stack frame, drop intensity to `normal` for the affected section. The token savings are not worth a misdiagnosis.
- If the repo is not yet indexed by gitnexus, run `/update-codemaps` before C5. The impact query in C5 returns nothing useful against an unindexed repo.

**Caveman intensity:**
- Default `full` throughout the pipeline.
- Drop to `normal` automatically for security warnings in C25, destructive ops (force push, reset), and any multi-step confirmation where fragment order could mislead.
- Never use `ultra` for fix work — you need the context, not maximum compression.

---

## Codex rescue protocol

Dedicated procedure for Phase 5. Follow this exactly — the cost of getting it wrong is applying an unreviewed GPT-5.4 patch that breaks something unrelated.

1. **When to trigger.** You have looped C14–C16 more than **twice** on the same symptom, OR the test from C11 is passing but the original repro still fails (meaning your test didn't lock the real bug), OR your hypothesis from Phase 2 is no longer consistent with the behavior. Do not trigger on the first hiccup — Codex rescue is the escape hatch, not the first resort.

2. **How to trigger.** Run `/codex:rescue` (skill `codex:rescue`, agent `codex-rescue`). The prompt you pass must contain:
   - **Problem:** verbatim `$ERROR_TEXT` from C3.
   - **Hypothesis:** your current Phase 2 hypothesis, even if you now think it's wrong.
   - **Tried:** bulleted list of every fix attempt and why each failed. Codex will re-tread your ground without this.
   - **Constraints:** any invariants (e.g., "public API of `FooService` must not change"). The `codex:gpt-5-4-prompting` skill documents best-practice prompt shape for GPT-5.4.

3. **How to monitor.** Run `/codex:status` periodically. Do not poll faster than once per minute. If you need to wait longer than 5 minutes, do other work (read Phase 6 prep material) rather than idle.

4. **How to retrieve.** Once status shows complete, run `/codex:result <job-id>`. The `codex:codex-result-handling` skill parses the output into verdict, findings, proposed patches, and next steps.

5. **How to cancel.** Run `/codex:cancel` if: the job is stuck, you found the bug independently during the wait, or the repro has changed and the rescue context is stale. Unfinished Codex jobs cost tokens.

6. **CRITICAL — never auto-apply Codex fixes.** The codex plugin's rules explicitly forbid it. The review protocol is:
   - Read the full `/codex:result` output end to end.
   - For each proposed patch, ask: does this address the RED test from C11? Does it mutate anything beyond the minimal fix scope?
   - Run `/codex:adversarial-review` on the proposed fix. GPT-5.4 will attack its own earlier suggestion and often surface regressions.
   - Ask the user via `AskUserQuestion`: "Codex proposed fixes for issues A, B, C — which do you want me to apply?" Let the user choose. Never select all.
   - Apply only the user-selected hunks. Re-run C15 (the locked test) after each applied hunk. Do not batch-apply.

---

## Hard gates (stop and ask user)

- **Before C14** — After the test is RED in C13 but before applying any fix, confirm with the user: "The failing test is `<test name>` and it fails with `<message>`. This matches the original repro. Proceed with fix?" This catches cases where you tested the wrong seam.
- **Before C18** — Before invoking Codex rescue, confirm: "Claude Code has looped on this bug `<N>` times without convergence. I want to hand it to Codex GPT-5.4 for an independent diagnostic. OK to proceed?" Rescue is a token-spending commitment.
- **Before applying any Codex hunk** — Ask the user to select which issues to fix from the `/codex:result` output. Do not apply everything automatically.
- **Before C29 (commit)** — Confirm: "Fix is green, reviewers passed, coverage holds. Ready to commit as `fix: <message>`?" This catches accidental unrelated changes in the diff.
- **Before merging** — If the PR touches security, auth, data layer, or deployment config, require `/codex:adversarial-review` output in the PR conversation before merge.
- **Any destructive git op** — Never run `git reset --hard`, `git push --force`, or branch deletion without explicit user confirmation. Caveman drops to normal for these regardless of intensity policy.

---

## Success criteria

A `/debug-test` run is complete only when all of the following are true:

- The bug was reproduced before any code change was written (C2–C3 logged verbatim).
- A test existed that was **RED for the right reason** before the fix landed (C11–C13).
- The same test turned GREEN after the minimal fix (C15).
- `/verify` passed cleanly with no unrelated failures (C16).
- `/test-coverage` shows the new test counted and the module still meets the 80% threshold (C17).
- All reviewers (code-reviewer, language-specific, security-reviewer if applicable) returned without CRITICAL or HIGH findings (C23–C25).
- The commit diff contains **only** the minimal fix and the new test. No drive-by refactors, no formatting churn, no unrelated file touches.
- `mem_save` with `type: bugfix` persisted with a generalized lesson, not a specific fix description (C32).
- A Brain session note was written with the required frontmatter (C33).
- `mem_session_summary` was called before declaring the session done (C35).

If any criterion fails, the fix is not done — return to the phase that produced the failing criterion and iterate. Never ship a fix that skipped C11 or C32.

---

## Anti-patterns (do not do these)

- **"I know what the bug is, I'll just fix it."** No test, no proof, no memory. This is the single most common way the same bug comes back in three weeks. Always lock with C11.
- **Refactoring during a fix.** You will be tempted. Resist. A mixed fix+refactor diff cannot be reviewed, bisected, or reverted cleanly. Deferred refactor goes in the PR description under "follow-ups," not in the fix commit.
- **Grinding Opus in a loop.** If you have iterated C14–C16 twice without convergence, Claude is not going to converge on iteration three by thinking harder. Trigger Phase 5 and hand it to Codex. The escape hatch exists — use it.
- **Auto-applying Codex output.** The codex plugin's rules forbid it. Rescue suggestions must be reviewed, run through `/codex:adversarial-review`, and filtered through explicit user selection. Blind application is how rescue patches introduce new bugs.
- **Skipping `mem_save` because "this bug was obvious."** Obvious bugs recur the most often because nobody thinks to write them down. Save every fix. The topic key format makes it cheap.
- **Writing the fix before reading the impact graph.** `mcp__gitnexus__impact` costs one call. Skipping it is how "small" bugfixes break three unrelated call sites.
- **Quoting the error approximately.** Paraphrased errors lose diagnostic fidelity. The caveman rule is verbatim quoting — copy the exact bytes, including whitespace and punctuation, and keep them in `$ERROR_TEXT` through the whole pipeline.
- **Marking the session done before `mem_session_summary`.** This is the engram MANDATORY end-of-session rule. There are no exceptions.

---

## Related commands and skills

- **Upstream:** `/one-to-n` (if the bug originated in a feature you just shipped, consider returning to that workflow's Phase 8 regression step).
- **Parallel tools:** `/orchestrate` for feature work, `/zero-to-one` for greenfield. Neither replaces `/debug-test` — they serve different work types.
- **Memory:** `mem_search` (lookup), `mem_save` with `type: bugfix` (persist), `mem_session_summary` (close). All three are required per the engram instructions at the top of this workflow.
- **Codex rescue:** `/codex:rescue`, `/codex:status`, `/codex:result`, `/codex:cancel`, `/codex:adversarial-review`. Five-out-of-seven Codex commands live in this workflow — it is the most Codex-heavy pipeline Chris runs.
- **Verification:** `/verify`, `/test-coverage`, `/e2e`, `/build-fix`, `/refactor-clean`. Staged cheap-to-expensive per `performance.md`.
- **Review agents:** `code-reviewer`, `security-reviewer`, `database-reviewer`, `go-reviewer`, `python-reviewer`, `architect` (structural smell only), `build-error-resolver`, `refactor-cleaner`, `e2e-runner`, `tdd-guide`, `codex-rescue`.

---

## One-line summary

Reproduce → investigate → lock with a failing test → fix minimally → verify → (Codex rescue if stuck) → harden → persist. Pattern used: **Boy Scout rule inverted** — leave the fix diff smaller than the refactor you were tempted to do, and trust the memory step to compound learning across future runs.
