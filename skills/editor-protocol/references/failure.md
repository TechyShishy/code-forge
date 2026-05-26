# Editor Protocol — Failure Handling (Historical Reference)

> **Note:** This document describes failure handling for the legacy ASSIGN_EDIT envelope and TASK_FAILED format. These were used during the transition to task-list-only coordination. 
>
> **Current approach:** Agents now use the RESULT envelope and task result fields (task.result_block, task.result_status) for all responses, including failures. See code-forge:editor-protocol/SKILL.md for current response formats.
>
> This section is retained for reference during the transition period.

---

# Editor Protocol — Failure Handling

## When to use TASK_FAILED (historical)

Use `TASK_FAILED` only when the task cannot be attempted at all:

- The worktree path is inaccessible or invalid
- The task envelope (from task.description) is malformed (missing required fields)
- A hard prerequisite blocks any work from starting (e.g., build toolchain missing and required)

## When NOT to use TASK_FAILED

Do not use `TASK_FAILED` when acceptance criteria cannot be met after attempting the work. Use a **Failure Report** instead — the Failure Report format captures partial progress, the nature of the failure, and recommended next steps for the user.

`TASK_FAILED` signals protocol-level failure (cannot start). Failure Report signals implementation failure (started, could not complete).

## TASK_FAILED format

```
TASK_FAILED
task_id: <id>
reason: <short description>
files_modified: <list or "none">
recommended_action: <what orchestrator/user should do>
```

Write this to the task result fields via TaskUpdate. This format is historical; new implementations should use the RESULT envelope instead (see code-forge:editor-protocol/SKILL.md).
