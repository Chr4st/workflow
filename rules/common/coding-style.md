# Coding Style

## Immutability (CRITICAL)

ALWAYS create new objects, NEVER mutate existing ones:

```
// Pseudocode
WRONG:  modify(original, field, value) → changes original in-place
CORRECT: update(original, field, value) → returns new copy with change
```

Rationale: Immutable data prevents hidden side effects, makes debugging easier, and enables safe concurrency.

## File Organization

MANY SMALL FILES > FEW LARGE FILES:
- High cohesion, low coupling
- 150 lines max
- Extract utilities from large modules
- Organize by feature/domain, not by type

## Structured Reasoning Before Implementation

Before writing any non-trivial implementation (>10 lines), decompose logic into:

1. **Sequential** — what steps execute in order?
2. **Branch** — what conditions determine different paths?
3. **Loop** — what repeats, and what terminates it?

Write this decomposition as a brief plan (3-5 lines), then implement from it. Yields +13.79% correctness, -36% code smells (ACM TOSEM 2025).

Skip for trivial code (config, imports, type definitions, single-expression functions).

## Error Handling

ALWAYS handle errors comprehensively:
- Handle errors explicitly at every level
- Provide user-friendly error messages in UI-facing code
- Log detailed error context on the server side
- Never silently swallow errors

## Input Validation

ALWAYS validate at system boundaries:
- Validate all user input before processing
- Use schema-based validation where available
- Fail fast with clear error messages
- Never trust external data (API responses, user input, file content)

## Code Quality Checklist

Before marking work complete:
- [ ] Code is readable and well-named
- [ ] Functions are small (<50 lines)
- [ ] Files are focused (<150 lines)
- [ ] No deep nesting (>4 levels)
- [ ] Proper error handling
- [ ] No hardcoded values (use constants or config)
- [ ] No mutation (immutable patterns used)
