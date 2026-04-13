---
description: Run standalone research pipeline — discover, analyze, synthesize into a research bundle for /zero-to-one
argument-hint: [project-name] [optional: domain keywords or one-line description]
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill, WebFetch, WebSearch, Task, TaskCreate, TaskUpdate, AskUserQuestion
---

# /research — Standalone Research Pipeline

## Workflow Initialization

Before starting Phase 1:
1. Read `workflow/state-machines/research.json` to load the state machine
2. Create a Task for each state via TaskCreate (subject: step ID + name)
3. Write initial state to `~/.claude/sessions/workflow-state.json` via workflow-runner
4. Update Task R1 to `in_progress`

After completing each step:
- Update the Task to `completed`
- Update `workflow-state.json` with the new current state
- Update the next Task to `in_progress`

## Purpose

Produces a research bundle at `~/.claude/sessions/research-bundle-{$1}.json` that feeds directly into `/zero-to-one` (at step A3.5, conditionally skipping A4–A8). Two tracks run in parallel:

- **Technical track** — OmegaWiki-inspired knowledge graph: papers, concepts, tools, skeletons, gaps, decision points, and their typed relationships
- **Market/resource track** — extends the `market-research` skill: competitors, pricing signals, existing libraries, community health, paid API options

Run this before `/zero-to-one` when the domain is unfamiliar, the tech landscape is crowded, or the user wants a thorough prior-art sweep before committing to a stack.

## Prerequisites

- MCPs reachable: `engram`, `exa-web-search`, `context7`, `github` (`gh auth status` passes)
- Brain vault present at `~/Desktop/Brain` (for `/vault-find` and final bundle note)
- Caveman full active via SessionStart hook

## Clarification Gates (MANDATORY)

Use `AskUserQuestion` with labeled options. Batch up to 3 per call. Never infer from `$2` — ask. If unresponsive, output `[BLOCKED: awaiting <decision>]` and stop.

### Phase 0 — Intake (before Phase 1)

- **Research focus** — A: understand the problem space / B: find skeleton to fork / C: competitive landscape / D: all three
- **Domain keywords** — exact terms to anchor every search (e.g. "vector database", "stream processing", "OCR layout extraction"). Required if `$2` is absent.
- **Depth** — A: quick sweep (≤30 min) / B: standard (≤1 hr) / C: deep dive (≤2 hr). Affects number of parallel branches and paper ingest volume.
- **Known prior art** — list anything the user already knows to avoid (URLs, repo names, tool names). Feed into gap analysis.
- **Paid API budget** — A: none (public sources only) / B: low (exa paid tier) / C: open (any MCP source). Governs which exa endpoints are called.

## Arguments

- `$1` — project name (required). Used for bundle filename, session slug, vault note.
- `$2` — domain keywords (optional). Comma-separated terms that seed all discovery queries.

If `$1` is missing, stop immediately and ask via `AskUserQuestion` before proceeding.

## Pipeline

### Phase 0 — Intake (R0–R0.5)

- **R0** — Run `AskUserQuestion` with the five Phase 0 gates above (batched into two calls of ≤3 each).
- **R0.5** — `/caveman full` + `/sessions` — open or resume session named `$1`. Call `mcp__engram__mem_context` to hydrate prior decisions about this domain.

### Phase 1 — Context Load (R1–R4)

Read-only. No writes until Phase 4.

- **R1** — `mcp__engram__mem_search "$2"` — cross-project episodic hits for domain keywords. Collect `type: architecture`, `type: learning`, `type: decision` entries.
- **R2** — `/vault-find "$2"` — surface Brain notes already written about this domain. Record wikilinks for bundle back-linking.
- **R3** — `context7` MCP — resolve domain library names to canonical doc URLs. Produces a "known documentation set" that anchors Phase 2 searches.
- **R4** — Load `market-research` skill. This activates market/resource track framing for subsequent queries.

### Phase 2 — Discovery (R5–R7) — parallel fork R5a–R5d

Fire R5a–R5d as a single parallel batch. R6 and R7 depend on their output.

- **R5a** — `mcp__exa-web-search` (technical) — state-of-the-art papers, benchmarks, engineering post-mortems for `$2`. Target: 10–20 sources.
- **R5b** — `gh search repos "$2"` + `gh search code "$2"` — skeleton discovery ranked by stars, last-commit recency, license, and structural fit. Capture 5–8 candidates.
- **R5c** — `mcp__exa-web-search` (market) — competitors, pricing pages, community health signals (Discord size, GitHub issues volume, Stack Overflow activity). Uses `market-research` skill framing.
- **R5d** — `WebSearch` — recent news, release announcements, deprecation notices for the domain (last 12 months). Catches fast-moving ecosystem changes that exa's index may lag on.
- **R6** — `context7` MCP — pull live docs for the 2–3 strongest skeleton candidates found in R5b. Do not guess doc URLs.
- **R7** — `mcp__engram__mem_save` (milestone: discovery complete). Topic key: `$1/research/discovery`. Type: `discovery`. Save the raw candidate list before synthesis so it survives compaction.

### Phase 3 — Analysis (R8–R10.5) — parallel fork R8a–R8b

- **R8a** — `Agent(research-synthesizer)` — takes R5a–R6 outputs. Structures them into a typed knowledge graph (entities + relationships per schema below). Outputs: top-3 recommended approaches with trade-offs, skeleton ranking, tech stack recommendation, risk register, open questions.
- **R8b** — `Agent(research-critic)` — runs in parallel with R8a against the same raw inputs. Checks for cherry-picked evidence, missing alternatives, unrealistic risk assessments, unsupported novelty claims. Produces severity-rated critique ending with `[CONFIDENCE: HIGH/MEDIUM/LOW]`.
- **R9** — Merge R8a + R8b. If critic returns `[CONFIDENCE: LOW]` or any CRITICAL finding, escalate: re-run `research-synthesizer` with critic findings injected as constraints. Stop and show merged findings to user before R10.
- **R10** — `AskUserQuestion` — resolve open questions from R8a. Present top-3 approaches with trade-offs; ask user to confirm or redirect before bundle is written.
- **R10.5** — `mcp__engram__mem_save` (milestone: synthesis approved). Topic key: `$1/research/synthesis-approved`. Type: `decision`.

### Phase 4 — Bundle + Persist (R11–R15)

- **R11** — Write research bundle to `~/.claude/sessions/research-bundle-{$1}.json` (schema below). This is the primary output of the workflow.
- **R12** — `/vault-session` — write Brain session note at `~/Desktop/Brain/sessions/YYYY-MM-DD-$1-research.md` with required frontmatter. Back-link to R2 vault hits.
- **R13** — `mcp__engram__mem_save` (structured ADR). Fields: What / Why / Where / Learned. Topic key: `$1/research/bundle`. Type: `architecture`.
- **R14** — `/learn-eval` — extract instincts from the session (patterns in the evidence, surprising gaps, recurring skeleton shape).
- **R15** — `mcp__engram__mem_session_summary` — MANDATORY. Never say "done" before this runs.

## Knowledge Graph Schema

**Entity types**: `paper`, `concept`, `topic`, `tool`, `skeleton`, `claim`, `gap`, `market_data`, `decision_point`

**Relationship types**: `extends`, `contradicts`, `supports`, `implements`, `competes_with`, `depends_on`, `supersedes`, `costs`, `integrates_with`

Each entity carries: `id`, `type`, `label`, `source_url`, `confidence` (HIGH/MEDIUM/LOW), `date`.
Each relationship carries: `from`, `to`, `type`, `evidence`, `confidence`.

## Research Bundle Format

Output at `~/.claude/sessions/research-bundle-{$1}.json`:

```json
{
  "project": "$1",
  "generated_at": "<ISO timestamp>",
  "domain_keywords": ["..."],
  "knowledge_graph": { "entities": [...], "relationships": [...] },
  "top_approaches": [
    { "rank": 1, "label": "...", "rationale": "...", "trade_offs": "...", "skeleton_url": "..." }
  ],
  "skeleton_candidates": [
    { "rank": 1, "repo": "...", "stars": 0, "last_commit": "...", "license": "...", "fit_score": "HIGH|MEDIUM|LOW" }
  ],
  "tech_stack_recommendation": { "runtime": "...", "persistence": "...", "framework": "..." },
  "risk_register": [
    { "risk": "...", "severity": "CRITICAL|HIGH|MEDIUM|LOW", "mitigation": "..." }
  ],
  "open_questions": ["..."],
  "critic_findings": [
    { "severity": "...", "finding": "..." }
  ],
  "vault_backlinks": ["[[...]]"],
  "sources": ["..."]
}
```

## Integration with /zero-to-one

When `/zero-to-one` starts, at step **A3.5** (after `mem_context`), check for `~/.claude/sessions/research-bundle-{$1}.json`:

- **Bundle present and fresh (< 7 days)** — load it, inject knowledge graph and top-3 approaches into Phase 2 context, skip A4–A8 (research already done). Confirm skip with user via `AskUserQuestion`.
- **Bundle present but stale (≥ 7 days)** — ask user: A: use as-is / B: re-run `/research $1` / C: skip and run A4–A8 inline.
- **Bundle absent** — proceed with A4–A8 as normal.

The bundle's `skeleton_candidates` feeds directly into A14's skeleton selection gate. The `risk_register` feeds the A13 adversarial review context so Codex focuses on novel risks rather than re-deriving known ones.
