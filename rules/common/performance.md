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

- **Code review (<5 files changed):** Route to Haiku 4.5. Pattern-matching and style enforcement don't need Sonnet depth.
- **Code review (>5 files or cross-module):** Keep Sonnet 4.6. Architectural implications require deeper reasoning.
- **Security review:** Always Sonnet 4.6. Security analysis requires contextual reasoning about attack surfaces.
- **Language-specific review:** Haiku 4.5. Idiomatic checks are well-scoped.
- **Architecture review:** Opus 4.6. Structural decisions deserve deepest reasoning.

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
