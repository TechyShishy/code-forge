# Researcher Protocol — Failure Handling

## When to use TASK_FAILED

Use `TASK_FAILED` only when research cannot be attempted at all:

- No backlog exists (no open GitHub issues, no local issue files, no inline TODOs found)
- Repository is inaccessible (`git remote get-url origin` fails and no local fallback is usable)
- The `ASSIGN_RESEARCH` envelope is malformed (missing required fields)

## When NOT to use TASK_FAILED

Do not use `TASK_FAILED` for partial results. If research is possible but incomplete, return what you have with gaps explicitly noted in `### Risks and unknowns`. Partial briefs are preferable to failure.

## TASK_FAILED format

```
TASK_FAILED
task_id: <id>
reason: <short description>
files_modified: <list or "none">
recommended_action: <what orchestrator/user should do>
```

Send this via SendMessage to the orchestrator. Do not include a result block.
