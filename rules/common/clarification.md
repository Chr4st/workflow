# Clarification Gates (Global, Always On)

## Principle

**When in doubt, ASK. Never guess on anything that affects correctness, scope, reversibility, or shared state.** Vagueness leads to wrong implementations. Hand-wavy assumptions cost more to undo than they save to make.

This rule applies to every workflow (0→1, 1→n, debug+test) and every phase within each workflow. It is not optional and does not weaken as sessions get longer.

## Method

Use the `AskUserQuestion` tool with **2–4 labeled options** per question. **Note:** `AskUserQuestion` is a deferred tool — load its schema via `ToolSearch("select:AskUserQuestion")` before first use in a session. Batch up to 3 related questions in a single call. Each question must:

1. Have a short header (the decision area).
2. Have a concrete question — not "is this ok?" or "what do you think?"
3. Offer labeled options (A/B/C/D) with one-line trade-offs each.
4. Include an "Other" option only when the space is genuinely open.

**Never ask open-ended**: "What database should I use?"
**Always ask bounded**: "Persistence layer — A: none (in-memory), B: SQLite (file, single-node), C: Postgres (networked, multi-node). Which fits your target deployment?"

## Hard Rule

**Do not proceed past a gate with an assumption.** If the user is unresponsive, output `[BLOCKED: awaiting <decision>]` and stop. Do not "pick a reasonable default and keep going" unless the user has previously told you which defaults to use in this project.

**Exception**: reversible, local, read-only actions (reading files, listing directories, grep, running tests that don't mutate state) never require clarification. The gate applies to writes, edits, installs, deletes, network calls, and shared-state mutations.

## Default Ask

When no constraint exists for a decision and none is inferable from the repo, ask:
"Do you want to set a constraint here, or should I research the best option and recommend one?"
Options: A) I'll give you a constraint, B) Research and recommend, C) Use the simplest default.

This applies to: architecture choices, naming conventions, file organization, dependency selection, error handling strategy, and any design decision with >1 reasonable approach.

## Universal Triggers (any workflow)

### Hard Gates (never skip, never assume)

These are irreversible, high-blast-radius, or trust-boundary decisions. Always ask via `AskUserQuestion`:

- **Destructive git**: `git reset --hard`, `git push --force`, `git branch -D`, `git checkout -- .`, `git clean -fd`, amending published commits.
- **Schema / config / env changes**: any modification to shared config, migrations, env vars, secrets.
- **Third-party uploads**: pastebins, gists, diagram services, any tool that publishes code externally.
- **Tech stack**: language, framework, runtime, package manager — when not already declared.
- **Installing new dependencies**: confirm each new dep before `npm install` / `pip install` / `cargo add`.
- **Plans touching >3 files**: show plan first, ask approval before editing.
- **Any choice between two non-equivalent approaches**: performance vs simplicity, speed vs correctness, feature A vs feature B.

### Soft Gates (skip if context is unambiguous)

These add friction when the answer is obvious. Apply judgment — ask only when genuinely ambiguous:

- **File paths**: when the user says "the config file" and there's more than one candidate. Skip if there's only one match.
- **Scope creep**: touching files or areas outside the explicit ask. **Exception:** if mentor.md growth-edge monitoring recommends the action (file >150 LOC needing extraction, mutation pattern needing immutable refactor), proceed with the improvement — mention it, but don't gate it.
- **Any ambiguous pronoun**: "it", "this", "the bug", "that function" — only when more than one referent is plausible AND the referent matters for the next action. If context makes the referent obvious, proceed.

## 0→1 Triggers (new projects)

Ask before scaffolding:

- **Target runtime**: Node / Python / Go / Rust / other. No default.
- **Deployment target**: local only / Docker / Vercel / Cloudflare Workers / AWS / Railway / self-hosted. Affects persistence, secrets, build.
- **Package manager**: npm / pnpm / yarn / bun. No silent pick.
- **Persistence**: none / SQLite / Postgres / Redis / file / key-value store.
- **Auth model**: none / API key / OAuth / JWT / session cookie / magic link.
- **Test framework**: when language has multiple (Python: pytest vs unittest; Node: vitest vs jest).
- **License**: MIT / Apache-2.0 / GPL / proprietary.
- **Repo visibility**: public / private.
- **Budget / timebox**: "quick prototype" vs "production-ready" shifts many choices downstream.
- **Skeleton selection**: when 2+ forkable skeletons exist, present them with trade-offs, let user pick.

## 1→n Triggers (features in existing codebases)

Ask before editing:

- **Scope boundary**: this file only / this module / this feature / this end-to-end flow.
- **Backwards compatibility required**: yes / no. Critical for public APIs and DB schemas.
- **Migration strategy**: online (zero downtime) / offline (maintenance window) / N/A (no schema change).
- **Feature flag**: yes / no. Affects rollout and revert strategy.
- **Deprecation window**: if removing code, how long to leave deprecated shims in place.
- **Tests allowed to change**: none / existing / new only. Prevents accidental test-weakening.
- **PR split strategy**: single PR / stacked PRs / branch series.
- **Merge target**: main / release / feature branch.
- **Rollback plan**: if blast radius from gitnexus impact exceeds N call sites, confirm the plan before proceeding.
- **Blast radius threshold**: ask user what N is for this repo (default: >10 call sites = stop and confirm).

## Debug+Test Triggers

Ask before investigating:

- **Reproduction confirmed**: yes / no. **Block until yes.** Never debug a bug the user hasn't reproduced in their environment.
- **Fix scope**: fix this specific bug / fix + prevent class of bug / fix + refactor surrounding area.
- **Prod incident**: yes / no. Changes urgency, blast radius tolerance, and rollback posture.
- **Rollback acceptable**: yes / no. Sometimes the right answer is rollback, not forward fix.
- **Tests allowed to change**: none / only broken test / new tests added / refactor existing. Prevents silently loosening guarantees.
- **Root cause ownership**: our code / upstream dependency / framework / infra. Affects whether fix lives here.
- **Post-mortem required**: yes / no. Some bugs need write-ups, not just fixes.
- **Codex rescue authorization**: before invoking `/codex:rescue` on a stuck loop, confirm user wants second opinion rather than different approach here.

## How to Batch

Batch related questions. Example good batch (3 questions in one `AskUserQuestion` call):

```
[
  { header: "Runtime", question: "Target runtime for this project?", options: [...node/python/go/rust] },
  { header: "Persistence", question: "Data storage layer?", options: [...none/sqlite/postgres/redis] },
  { header: "Auth", question: "Auth model?", options: [...none/api-key/oauth/jwt] }
]
```

Bad batch (too many, unrelated):
```
[ runtime, persistence, auth, license, repo-visibility, test-framework, ci-provider ]
```

Limit: 3 questions per call. If more are needed, do a second call after the first batch is answered.

## What NOT to Ask

- Don't ask for approval of read-only exploration ("should I grep for X?") — just do it.
- Don't ask the same question twice in a session after it's been answered.
- Don't ask about information you could derive from the repo state (package.json, lockfile, existing config).
- Don't ask to confirm something the user already said in the current turn.
- Don't ask multiple variations of the same question to hedge — pick your best phrasing.

## Anti-Patterns (never do these)

- "Looks good, should I proceed?" → ask a specific decision instead.
- "I'll use Postgres unless you object." → silent default is an assumption. Ask.
- "I assume you want X." → stop, ask.
- Narrating a choice in prose instead of calling `AskUserQuestion`.
- Listing options in a bullet list without actually invoking the tool — the user can't click bullets.
- Asking for approval at the end of a response after already acting — backwards. Ask first, act second.
- "Any changes before I start?" — too vague. Ask specific decisions.

## Enforcement Ladder

When a gate is hit:

1. **Ask** via `AskUserQuestion` with labeled options.
2. If user answers → proceed with that answer locked in.
3. If user gives an unexpected answer → clarify with one follow-up, then proceed.
4. If user unresponsive → output `[BLOCKED: awaiting <decision>]` and stop. Do not guess.
5. If user says "you decide" → pick the safest option (reversible, well-scoped, idiomatic) and say which one you picked and why in one line.

## Override

User can disable the gate for a specific session by saying: "skip clarifications for this task" or "use defaults". If they do, record what defaults you picked in one line so they can verify at the end.

## Integration with workflows

Every workflow command (`/zero-to-one`, `/one-to-n`, `/debug-test`) has its own "Clarification Gates" section that lists phase-specific triggers. Those are additive to the universal triggers in this file. When both apply, both must be answered before proceeding.
