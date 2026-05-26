# Researcher Protocol — Failure Handling (Historical Reference)

> **Note:** This document describes failure handling for the legacy ASSIGN_RESEARCH envelope and TASK_FAILED format. These were used during the transition to task-list-only coordination.
>
> **Current approach:** Agents now use the RESULT envelope and task result fields (task.result_block, task.result_status) for all responses, including failures. See code-forge:researcher-protocol/SKILL.md for current response formats.
>
> This section is retained for reference during the transition period.

---

# Researcher Protocol — Failure Handling

## When to use TASK_FAILED

Use `TASK_FAILED` only when research cannot be attempted at all:

- No backlog exists (no open GitHub issues, no local issue files, no inline TODOs found)
- Repository is inaccessible (`git remote get-url origin` fails and no local fallback is usable)
- The task envelope (from task.description) is malformed (missing required fields)

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

Write this to the task result fields via TaskUpdate. This format is historical; new implementations should use the RESULT envelope instead (see code-forge:researcher-protocol/SKILL.md).
