# Git Workflow

## Commit Message Format
```
<type>: <description>

<optional body>
```

Types: feat, fix, refactor, docs, test, chore, perf, ci

Note: Attribution disabled globally via ~/.claude/settings.json.

## PR Size Limit (Hard Gate)

Maximum 150 lines of code changes per PR. If staged changes exceed 150 LOC:

1. Stop and ask the user to split into smaller PRs
2. Suggest a split strategy (by feature slice, by layer, by file group)
3. Do not proceed with review until each PR is under 150 LOC

Reviewer effectiveness degrades after 80-100 lines of diff. Smaller PRs get better coverage and fewer shipped bugs.

Exceptions (confirm with user): generated code, bulk renames, initial scaffold.

## Pull Request Workflow

When creating PRs:
1. Analyze full commit history (not just latest commit)
2. Use `git diff [base-branch]...HEAD` to see all changes
3. Draft comprehensive PR summary
4. Include test plan with TODOs
5. Push with `-u` flag if new branch

> For the full development process (planning, TDD, code review) before git operations,
> see [development-workflow.md](./development-workflow.md).
