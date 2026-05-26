# Editor Protocol — Failure Handling

## When to use TASK_FAILED

Use `TASK_FAILED` only when the task cannot be attempted at all:

- The worktree path is inaccessible or invalid
- The `ASSIGN_EDIT` envelope is malformed (missing required fields)
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

Send this via SendMessage to the orchestrator. Do not include a result block.
