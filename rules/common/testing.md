# Testing Requirements

## Minimum Test Coverage: 80%

Test Types (ALL required):
1. **Unit Tests** - Individual functions, utilities, components
2. **Integration Tests** - API endpoints, database operations
3. **E2E Tests** - Critical user flows (framework chosen per language)
4. **Property-Based Tests** - Invariants for all valid inputs. Use `hypothesis` (Python), `fast-check` (TS/JS), `gopter` (Go), `proptest` (Rust). Required for: data transformations, serialization, validation, math, API contracts. Catches 37.3% more bugs than example-based tests (arXiv:2506.18315).

## Test-Driven Development

MANDATORY workflow:
1. Write test first (RED)
2. Run test - it should FAIL
3. Write minimal implementation (GREEN)
4. Run test - it should PASS
4.5. Write property-based tests for invariants
4.6. Run property tests - fix failures before proceeding
5. Refactor (IMPROVE)
6. Verify coverage (80%+)

## Troubleshooting Test Failures

1. Use **tdd-guide** agent
2. Check test isolation
3. Verify mocks are correct
4. Fix implementation, not tests (unless tests are wrong)

## Agent Support

- **tdd-guide** - Use PROACTIVELY for new features, enforces write-tests-first
