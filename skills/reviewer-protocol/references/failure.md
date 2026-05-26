# Reviewer Protocol — Failure Handling

## When to return failure

Return `status: failure` only when review cannot be performed at all:

- Worktree path is inaccessible (cannot read any files)
- The task description is malformed (missing required fields)
- The Changeset Summary is unparseable and no files can be identified for review

## When NOT to return failure

Do not return failure because the code has severe problems. Even code with many `[MUST FIX]` findings is reviewable — return **Review Findings** with the appropriate severity brackets. The orchestrator's fix loop handles MUST FIX items.

`status: failure` signals protocol-level failure (cannot perform review). Review Findings signals completed review with findings that need action.

## RESULT format — failure case

Sent by the reviewer when a fatal error prevents completion:

```
RESULT
task_id: <id>
agent: reviewer
status: failure
result_type: Failure Report
```

Followed by the Failure Report body:

**Issue:** <if known>
**Phase:** Review

### What failed

<description — e.g., worktree inaccessible, envelope unparseable, changeset summary malformed>

### Recommended next step

<user-facing guidance — e.g., "Verify the worktree path exists and is readable. Run `/implement` again.">

Return this via TaskUpdate to the orchestrator.
