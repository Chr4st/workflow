# Performance Optimization

## Model Selection Strategy

**Haiku 4.5** (handles most coding tasks at ~3x cost savings vs Sonnet):
- Lightweight agents with frequent invocation
- Pair programming and code generation
- Worker agents in multi-agent systems

**Sonnet 4.6** (Best coding model):
- Main development work
- Orchestrating multi-agent workflows
- Complex coding tasks

**Opus 4.6** (Deepest reasoning):
- Complex architectural decisions
- Maximum reasoning requirements
- Research and analysis tasks

## Context Window Management

Avoid last 20% of context window for:
- Large-scale refactoring
- Feature implementation spanning multiple files
- Debugging complex interactions

Lower context sensitivity tasks:
- Single-file edits
- Independent utility creation
- Documentation updates
- Simple bug fixes

## Extended Thinking + Plan Mode

Extended thinking is enabled by default, reserving up to 31,999 tokens for internal reasoning.

Control extended thinking via:
- **Toggle**: Option+T (macOS) / Alt+T (Windows/Linux)
- **Config**: Set `alwaysThinkingEnabled` in `~/.claude/settings.json`
- **Budget cap**: `export MAX_THINKING_TOKENS=10000`
- **Verbose mode**: Ctrl+O to see thinking output

For complex tasks requiring deep reasoning:
1. Ensure extended thinking is enabled (on by default)
2. Enable **Plan Mode** for structured approach
3. Use multiple critique rounds for thorough analysis
4. Use split role sub-agents for diverse perspectives

## Model Routing for Review Agents

### Base routing (default)
- **Code review (<5 files changed):** Haiku 4.5
- **Code review (>=5 files or cross-module):** Sonnet 4.6
- **Security review:** Sonnet 4.6
- **Language-specific review:** Haiku 4.5
- **Database review:** Haiku 4.5
- **Architecture review:** Opus 4.6

### Escalation triggers (override base routing)

After each reviewer completes, scan its output for escalation signals:

1. **Hedging language escalation.** If output contains hedging about correctness or safety ("might be vulnerable", "could cause issues", "unclear whether this is safe", "I'm not sure"), escalate the NEXT reviewer one tier: Haiku → Sonnet → Opus.
2. **Critical finding escalation.** If ANY reviewer finds a CRITICAL-severity issue, escalate ALL remaining reviewers to Sonnet 4.6 minimum.
3. **De-escalation.** If two consecutive reviewers produce zero findings and no hedging, the next reviewer may drop one tier. Do not de-escalate below Haiku.

### Escalation applies to these chains:
- **Workflow A:** A26 (security) → A27 (language) → A28 (database) → A29 (codex)
- **Workflow B:** B32 (security) → B33 (language) → B34 (database) → B35 (codex)
- **Workflow C:** C23 (security) → C24 (code-reviewer) → C25 (language)

## Build Troubleshooting

If build fails:
1. Use **build-error-resolver** agent
2. Analyze error messages
3. Fix incrementally
4. Verify after each fix

## Token Budgets (per-step estimates)

| Step | Est. tokens | Timeout | Notes |
|------|-------------|---------|-------|
| `/multi-plan` | ~8k | 3 min | Multi-model planning |
| `/codex:adversarial-review` | ~5k | 2 min | GPT-5.4 second opinion |
| `/orchestrate feature` | ~12k | 5 min | Sequences 4 agents |
| `/multi-execute` | ~15k | 8 min | Parallel Haiku workers |
| `/verify pre-pr` | varies | 5 min | Build+types+lint+tests |
| `/e2e` | varies | 5 min | Playwright/Browser |
| `/codex:rescue` | ~10k | 5 min | Including Codex job time |

On timeout: skip the step, note it in the PR body, and continue. Do not let runaway steps block the workflow.

## Prompt Cache Discipline

Anthropic's prompt cache (arXiv:2601.06007) yields 78.5% cost reduction on cached prefixes. To maximize cache hits:

1. **Freeze tool definitions across pipeline agents.** Changing the tool set between sequential reviewers invalidates the cache prefix. All reviewers in a chain MUST use the same tool set.
2. **Dynamic content goes in user messages, NEVER in system prompts.** Git status, file contents, diffs, test output belong in user-role messages. System prompts must be static across runs.
3. **Context briefs are user messages.** The computed briefs at A25.5, B21.8, C22.5 are dynamic. Pass them as the first user message to each reviewer agent, not as part of the system prompt.
4. **Batch tool permissions once.** Do not conditionally add/remove tools between agents in the same pipeline.
5. **Order matters.** Place stable content earliest in the system prompt (identity, rules, tool definitions) and volatile content last (in user messages per rule 2).

## Trajectory Hygiene (AgentDiet)

Before passing context to the next agent in a pipeline, compress the trajectory (arXiv:2509.23586, 40-60% input token reduction):

At every context brief point (A25.5, B21.8, C22.5), classify each prior output:

- **KEEP**: Findings, decisions, architecture choices, test results, error messages, security findings. Load-bearing content that must pass through verbatim.
- **SUMMARIZE**: Verbose command output (build logs, grep results, file listings, gitnexus graph dumps) → compress to 1-2 line summary retaining only the conclusion.
- **DROP**: Expired state (old git status before new commits), superseded plans (drafts replaced by approved plan), duplicate information (same finding from multiple tools), file content read but not relevant to review.

Apply this classification BEFORE computing the context brief, not after. Do NOT drop anything from the current phase — only compress outputs from PRIOR phases.

## Telemetry

Install `claude-hud` (jarrodwatts/claude-hud) for real-time visibility into context window fill, tokens consumed per turn, and active agent count. Run `claude plugin install claude-hud@claude-hud` once. No config needed — it reads Claude Code runtime state directly. Use the overlay to detect runaway context consumption before hitting compaction.
