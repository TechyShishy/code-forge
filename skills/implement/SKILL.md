---
name: implement
description: "Event-driven state machine that coordinates all pipeline phases (implementation, review, fix cycles, commit) via task-list assignment. Validates brief sufficiency, enters a worktree, spawns editor and reviewer agents, and drives state transitions on task completion. Handles stall detection, team cleanup, and worktree lifecycle on all exit paths. Use after /load-task."
disable-model-invocation: true
allowed-tools:
  - EnterWorktree
  - ExitWorktree
  - Agent
  - AskUserQuestion
  - Bash(git rev-parse --show-toplevel)
  - Read
  - Write
  - TaskCreate
  - TaskUpdate
  - TaskGet
  - TaskList
  - TeamDelete
  - Bash(npm test)
  - Bash(npm run *)
  - Bash(pytest)
  - Bash(cargo test)
  - Bash(make test)
---

# Implement Issue

Event-driven state machine for end-to-end implementation. Reads a Task Brief, enters a worktree, then drives implementation → review → fix cycles → commit via task-list assignment. Transitions fire exclusively on task completion notifications delivered to the orchestrator's mailbox.

<rules>
- **No approval pause.** Invoking this skill is the user's approval to proceed.
- **Sufficiency first.** Validate the brief before entering the worktree (Step 1); if insufficient, bail out and direct the user back to `/load-task`.
- **Trust the brief.** File-path or assumption staleness surfaces during implementation when the editor attempts edits.
- **Worktree second.** Enter the worktree after sufficiency check passes (Step 2), before spawning any subagent.
- **Just-in-time team.** `pipeline-team` was created by `/load-task`. Step 3 spawns editor and reviewer into it. If the team was not created upstream, `Agent` will error — surface the error and stop.
- **Task-list primary.** All phase coordination uses TaskCreate + TaskUpdate(owner) for assignment. The orchestrator goes idle after each assignment and is awakened exclusively by task completion notifications in its mailbox.
- **TeamDelete on every exit.** Call TeamDelete on all exit paths: success, failure, escalation, and abort. <!-- FIXME(0086): TeamDelete integration pending issue 0086 — call TeamDelete(name="pipeline-team") here once available -->
- **Archive on completion.** After all phases complete (or on abort), call TaskUpdate(archived=true) for every task belonging to PIPELINE_RUN_ID.
- **Scope only.** Implement what the issue asks; do not add features or refactors beyond the brief.
- **Test before committing.** The implementation phase must run tests and verify acceptance criteria before returning a Changeset Summary.
</rules>

## State Machine

States in order: `waiting_for_research` → `waiting_for_implementation` → `waiting_for_review` → `waiting_for_commit` → `done`

Each state creates one or more tasks, assigns them to team members, and goes idle. Transitions fire exclusively when a task completion notification arrives in the orchestrator's mailbox.

## Contents

- [Step 0 — Verify code-forge:orchestrator-protocol is loaded](#step-0--verify-orchestrator-protocol-is-loaded)
- [Prerequisite: Task Brief in Context or Task-List](#prerequisite-task-brief-in-context-or-task-list)
- [Step 1 — Validate Brief Sufficiency](#step-1--validate-brief-sufficiency)
- [Step 2 — Enter the Worktree](#step-2--enter-the-worktree)
- [Step 3 — Spawn Editor and Reviewer into Pipeline Team](#step-3--spawn-editor-and-reviewer-into-pipeline-team)
- [Step 4 — Initialize State Machine](#step-4--initialize-state-machine)
- [State: waiting_for_research](#state-waiting_for_research)
- [State: waiting_for_implementation](#state-waiting_for_implementation)
- [State: waiting_for_review](#state-waiting_for_review)
- [State: waiting_for_commit](#state-waiting_for_commit)
- [State: done](#state-done)
- [Team Cleanup](#team-cleanup)

Reference: [code-forge:orchestrator-protocol](../orchestrator-protocol/SKILL.md) · [task-list-schema.md](../orchestrator-protocol/references/task-list-schema.md) · [stall-detection.md](../orchestrator-protocol/references/stall-detection.md) · [error-messages.md](../orchestrator-protocol/references/error-messages.md) · [task-brief.md](references/task-brief.md)

---

## Step 0 — Verify code-forge:orchestrator-protocol is loaded

`code-forge:orchestrator-protocol` must be in context before proceeding. It is loaded automatically by `/load-task` — if you invoked `/implement` without a prior `/load-task` in this session, stop and run `/load-task` first.

If the protocol is not in context, output:

> No code-forge:orchestrator-protocol in context. Run `/load-task` first.

---

## Prerequisite: Task Brief in Context or Task-List

**Division of responsibility:**
- `/load-task` validates that all *required fields* are present in the brief (per the brief contract in code-forge:orchestrator-protocol).
- `/implement` validates that the brief is *sufficient for implementation* — no critical ambiguities, clear entry points, concrete criteria.

If a Task Brief is visible in conversation context (from a prior `/load-task` invocation), use it. Otherwise, call `TaskList()` and find the most recently completed task whose `metadata.role` is `"researcher"` and `metadata.result_status` is `"success"`. Read `task.metadata.result_block` from that entry.

If neither source yields a Task Brief, stop and output the message from [error-messages.md#no-task-brief](../orchestrator-protocol/references/error-messages.md#no-task-brief).

---

## Step 1 — Validate Brief Sufficiency

Check the brief for red flags per [brief-sufficiency.md](references/brief-sufficiency.md).
If 2 or more red flags are present, output the message from [error-messages.md#brief-insufficient](../orchestrator-protocol/references/error-messages.md#brief-insufficient) and stop.

---

## Step 2 — Enter the Worktree

Extract the issue ID from the Task Brief (e.g., `#123` → `issue-0123`, `TODO-456` → `issue-TODO-456`, `0092` → `issue-0092`). Store as `ISSUE_ID`.

Call `EnterWorktree` with `name=issue-<ISSUE_ID>`. Then immediately run `git rev-parse --show-toplevel` to capture the resulting absolute path — store it as `WORKTREE_PATH`. Pass this path explicitly in every phase task's context. Do not rely on working directory inheritance across subagent boundaries (see worktree conventions in code-forge:orchestrator-protocol).

If `EnterWorktree` fails or this is not a git repo, proceed without a worktree, set `WORKTREE_PATH` to the current directory, and note it in the final summary.

---

## Step 3 — Spawn Editor and Reviewer into Pipeline Team

`pipeline-team` must have been created by `/load-task` or `/describe-task` earlier in this session. Spawn editor and reviewer into it:

```
Agent(
  subagent_type: "code-forge:editor-agent",
  name: "editor",
  team_name: "pipeline-team"
)

Agent(
  subagent_type: "code-forge:reviewer-agent",
  name: "reviewer",
  team_name: "pipeline-team"
)
```

If either `Agent` call fails, surface the failure using the message from [error-messages.md#team-coordination-failed](../orchestrator-protocol/references/error-messages.md#team-coordination-failed) and stop. Do not attempt to spawn alternative subagents.

Set the team member names used in all subsequent TaskUpdate calls:

```
EDITOR_NAME   = "editor"
REVIEWER_NAME = "reviewer"
```

These names are stable across idle/resume cycles — do not convert them to UUIDs.

---

## Step 4 — Initialize State Machine

Compute:

```
PIPELINE_RUN_ID = "implement-<ISSUE_ID>-<YYYYMMDDTHHmmss>"
```

For example: `implement-0094-20260525T143000`. This ID groups all tasks created during this `/implement` invocation and is used for archiving.

> **Note on prefix:** The `implement-` prefix is intentional — it distinguishes tasks spawned by `/implement` from tasks spawned by `/load-task` (which uses the `load-task-` prefix). The task-list-schema.md reference example (`issue-0092-...`) shows the issue ID directly; that format is illustrative, not prescriptive. Using a phase prefix makes pipeline_run_id self-describing and avoids collisions when the same issue is re-run across pipeline phases.

Store `CURRENT_STATE = "waiting_for_research"`. Store an empty list `PIPELINE_TASK_IDS = []` — append every `TaskCreate` return value to this list for archiving at the end.

---

## State: waiting_for_research

The researcher task was completed by `/load-task` before `/implement` was invoked. This state reads and validates its result.

**If the Task Brief is already validated in context (from the prerequisite check):** no TaskGet is needed — the Task Brief is already in hand. Transition directly to `waiting_for_implementation`.

**If the Task Brief was read from TaskList in the prerequisite check:** validate it now:
- `task.metadata.result_status` must be `"success"`.
- `task.metadata.result_type` must be `"Task Brief"`.
- `task.metadata.result_block` must be non-empty and pass the brief contract field checks (Issue, Title, Type, Effort, Acceptance criteria, Risks sections).

If validation fails, surface the partial brief with a gap note and stop. Do not proceed to implementation with an incomplete brief.

Transition: set `CURRENT_STATE = "waiting_for_implementation"`.

---

## State: waiting_for_implementation

### Create and assign implementation task

Create the implementation task:

```
TaskCreate(
  subject     = "Implement issue <ISSUE_ID>",
  description = "goal: Implement the changes described in the Task Brief below\n\n<full Task Brief text>",
  metadata    = {
    pipeline_run_id: "<PIPELINE_RUN_ID>",
    worktree_path:   "<WORKTREE_PATH>",
    role:            "editor",
    phase:           "implement",
    iteration:       0,
    result_status:   null,
    result_type:     null,
    result_block:    null,
    claimed_at:      null,
    completed_at:    null,
    archived:        false
  }
)
```

Store the returned ID as `IMPL_TASK_ID`. Append to `PIPELINE_TASK_IDS`.

Assign to the editor:

```
TaskUpdate(
  taskId   = <IMPL_TASK_ID>,
  owner    = <EDITOR_NAME>,
  status   = "in_progress",
  metadata = { claimed_at: "<ISO 8601 timestamp>" }
)
```

### Wait for completion

The orchestrator goes idle. It is awakened when the editor completes the implementation task and a task completion notification arrives in the orchestrator's mailbox. Read the result fields from the completed task:

- `task.metadata.result_status` — `success`, `failure`, or `escalation`
- `task.metadata.result_type` — `Changeset Summary`, `Failure Report`, or `NEEDS_ESCALATION`
- `task.metadata.result_block` — full result text

### Route on result

**`result_status == "escalation"` (NEEDS_ESCALATION):**
- Surface `task.metadata.result_block` verbatim to the user. The task exceeds safe scope.
- Do not proceed to review.
- Call [Team Cleanup](#team-cleanup).
- Stop.
<!-- FIXME(0085): verify escalation handling matches issue 0085 resolution when available -->

**`result_status == "failure"` (Failure Report):**
- Surface `task.metadata.result_block` verbatim per [error-messages.md#implementation-failed](../orchestrator-protocol/references/error-messages.md#implementation-failed) (in code-forge:orchestrator-protocol).
- Call `ExitWorktree(action=keep)`.
- Call [Team Cleanup](#team-cleanup).
- Stop.

**`result_status == "success"` (Changeset Summary):**
- Store `CHANGESET_SUMMARY = task.metadata.result_block`.
- Transition: set `CURRENT_STATE = "waiting_for_review"`.

---

## State: waiting_for_review

**Skip condition:** If the change is a single-line typo fix, whitespace-only change, or one-word rename — skip this state entirely and transition to `waiting_for_commit`.

### Review loop variables

Initialize:

```
REVIEW_ITERATION  = 0
PREV_FINGERPRINTS = []
STALL_COUNT       = 0
GRACE_USED        = false
USER_DIRECTION    = ""
ACTIVE_MUST_FIX   = []
```

### Phase R1 — Dispatch review task

Increment `REVIEW_ITERATION`.

Create the review task:

```
TaskCreate(
  subject     = "Review issue <ISSUE_ID> — iteration <REVIEW_ITERATION>",
  description = "goal: Review the changeset and return severity-tagged findings\n\n<CHANGESET_SUMMARY>",
  metadata    = {
    pipeline_run_id: "<PIPELINE_RUN_ID>",
    worktree_path:   "<WORKTREE_PATH>",
    role:            "reviewer",
    phase:           "review",
    iteration:       <REVIEW_ITERATION>,
    result_status:   null,
    result_type:     null,
    result_block:    null,
    claimed_at:      null,
    completed_at:    null,
    archived:        false
  }
)
```

Store ID as `REVIEW_TASK_ID`. Append to `PIPELINE_TASK_IDS`.

Assign:

```
TaskUpdate(
  taskId   = <REVIEW_TASK_ID>,
  owner    = <REVIEWER_NAME>,
  status   = "in_progress",
  metadata = { claimed_at: "<ISO 8601 timestamp>" }
)
```

For re-reviews (`REVIEW_ITERATION > 1`), note that the reviewer should focus on delta only and reference original MUST FIX findings by fingerprint category.

### Phase R2 — Wait for review completion

The orchestrator goes idle. It is awakened when the reviewer completes the review task and a task completion notification arrives in the orchestrator's mailbox. Read `task.metadata.result_block` as Review Findings. Parse findings into severity buckets (`MUST_FIX`, `SHOULD_FIX`, `CONSIDER`, `GOOD`).

If `REVIEW_ITERATION == 1`: set `ACTIVE_MUST_FIX = <all MUST FIX items from findings>`.
If `REVIEW_ITERATION > 1`: update `ACTIVE_MUST_FIX` to items still present in current findings.

### Phase R3 — Route on severity

**No MUST FIX items remain and no SHOULD FIX:** Proceed to Phase R5 (cleanup and transition to commit).

**SHOULD FIX items present (and no MUST FIX):**

Create a fix task for SHOULD FIX:

```
TaskCreate(
  subject     = "Apply SHOULD FIX findings for issue <ISSUE_ID>",
  description = "goal: Apply SHOULD FIX findings from review\n\n<each SHOULD FIX item as a list>",
  metadata    = {
    pipeline_run_id: "<PIPELINE_RUN_ID>",
    worktree_path:   "<WORKTREE_PATH>",
    role:            "editor",
    phase:           "fix",
    iteration:       <REVIEW_ITERATION>,
    result_status:   null,
    result_type:     null,
    result_block:    null,
    claimed_at:      null,
    completed_at:    null,
    archived:        false
  }
)
```

Append to `PIPELINE_TASK_IDS`. Assign to `EDITOR_NAME`. Go idle; await task completion notification.

Check `task.metadata.result_status`:
- **`failure` or `escalation`:** Surface `task.metadata.result_block` verbatim. Call `ExitWorktree(action=keep)`. Call [Team Cleanup](#team-cleanup). Stop.
- **`success`:** Update `CHANGESET_SUMMARY = task.metadata.result_block`.

No re-review. Proceed to Phase R5.

**MUST FIX items remain:** Execute the MUST FIX fix sub-loop (Phase R4).

### Phase R4 — MUST FIX fix sub-loop

Apply stall fingerprinting per [stall-detection.md](../orchestrator-protocol/references/stall-detection.md) (in code-forge:orchestrator-protocol):

<!-- FIXME(0087): normalized category extraction depends on issue 0087 — the fingerprint tuple
     is (severity, file_path, finding_category). For now, extract file_path and a coarse
     category label by stripping variable names and quoted values from the finding summary.
     Replace with the standardized extractor from issue 0087 when available. -->

Extract fingerprints from `ACTIVE_MUST_FIX`: for each item, produce a normalized tuple `(MUST_FIX, file_path, finding_category)` per stall-detection.md. Store as `CURRENT_FINGERPRINTS`.

Apply stall detection rules from stall-detection.md:

- **First iteration or empty baseline:** treat as progress; set `PREV_FINGERPRINTS = CURRENT_FINGERPRINTS`.
- **Count decreased:** reset `STALL_COUNT = 0`, `GRACE_USED = false`.
- **New fingerprints appeared (subset change):** reset `STALL_COUNT = 0`, `GRACE_USED = false`.
- **Fingerprint set unchanged:** increment `STALL_COUNT`. If `STALL_COUNT >= 2`, invoke the stall handler (see below).
- **Count increased (regression) and `GRACE_USED = false`:** set `GRACE_USED = true`, reset `STALL_COUNT = 0`.
- **Count increased (regression) and `GRACE_USED = true`:** invoke the stall handler immediately.

**Stall handler:** invoke `AskUserQuestion`:

```
The MUST FIX fix loop has stalled — findings have not progressed after 2 consecutive rounds,
or a regression occurred after the grace round was already used.

Active MUST FIX findings:
<list each active MUST FIX item>

How would you like to proceed?
1. Continue — run another fix attempt (may not resolve without new direction)
2. Accept-as-is — exit the review loop; remaining findings noted as accepted risk in commit summary
3. Skip these items — remove from active MUST FIX set and proceed to commit
4. Provide direction — supply guidance to pass to the next fix attempt
```

Handle responses:
- **Continue:** reset `STALL_COUNT = 0`. Proceed to dispatch fix task.
- **Accept-as-is:** exit the loop. Note accepted findings in `CHANGESET_SUMMARY` under `### Accepted risk`. Proceed to Phase R5.
- **Skip:** remove stalled items from `ACTIVE_MUST_FIX`. If empty, proceed to Phase R5. Otherwise reset `STALL_COUNT = 0` and dispatch fix task.
- **Provide direction:** capture text as `USER_DIRECTION`. Reset `STALL_COUNT = 0`. Dispatch fix task.

**Dispatch fix task:**

Create fix task:

```
TaskCreate(
  subject     = "Apply MUST FIX findings for issue <ISSUE_ID> — iteration <REVIEW_ITERATION>",
  description = "goal: Apply MUST FIX findings from review\n<if USER_DIRECTION non-empty: \nuser_direction: <USER_DIRECTION>>\n\n<each active MUST FIX item as a list>",
  metadata    = {
    pipeline_run_id: "<PIPELINE_RUN_ID>",
    worktree_path:   "<WORKTREE_PATH>",
    role:            "editor",
    phase:           "fix",
    iteration:       <REVIEW_ITERATION>,
    result_status:   null,
    result_type:     null,
    result_block:    null,
    claimed_at:      null,
    completed_at:    null,
    archived:        false
  }
)
```

Reset `USER_DIRECTION = ""` after injecting it. Append to `PIPELINE_TASK_IDS`. Assign to `EDITOR_NAME`.

Go idle; await task completion notification.

Check `task.metadata.result_status`:
- **`failure` or `escalation`:** Surface `task.metadata.result_block` verbatim. Call `ExitWorktree(action=keep)`. Call [Team Cleanup](#team-cleanup). Stop.
- **`success`:** Update `CHANGESET_SUMMARY = task.metadata.result_block`.

Set `PREV_FINGERPRINTS = CURRENT_FINGERPRINTS`. Return to Phase R1 (dispatch re-review, increment `REVIEW_ITERATION`).

### Phase R5 — Review cleanup

Transition: set `CURRENT_STATE = "waiting_for_commit"`.

---

## State: waiting_for_commit

### Create and assign commit task

Create the commit task:

```
TaskCreate(
  subject     = "Commit issue <ISSUE_ID>",
  description = "goal: Stage, commit, and cherry-pick the changes from the Changeset Summary\n\n<CHANGESET_SUMMARY>\n\nInstructions:\n- Stage exactly the files listed in the Changeset Summary's 'Files changed' section\n- Construct commit message: subject from 'Proposed commit subject' (imperative, ≤50 chars); body from 'Proposed commit body' (1 blank line after subject; omit if empty); trailers: Fixes/Closes #N from 'Issue reference', Co-authored-by: Claude <model-name> <noreply@anthropic.com>\n- HARD BAN on Conventional Commits format (no feat:, fix:, chore:, etc. prefixes)\n- Before committing, call mcp-human-interface/wait-for-interaction (user must be present for PGP passphrase)\n- Commit using git heredoc pattern\n- Capture the short SHA\n- Cherry-pick the commit to main",
  metadata    = {
    pipeline_run_id: "<PIPELINE_RUN_ID>",
    worktree_path:   "<WORKTREE_PATH>",
    role:            "editor",
    phase:           "commit",
    iteration:       0,
    result_status:   null,
    result_type:     null,
    result_block:    null,
    claimed_at:      null,
    completed_at:    null,
    archived:        false
  }
)
```

Store as `COMMIT_TASK_ID`. Append to `PIPELINE_TASK_IDS`.

Assign to the editor:

```
TaskUpdate(
  taskId   = <COMMIT_TASK_ID>,
  owner    = <EDITOR_NAME>,
  status   = "in_progress",
  metadata = { claimed_at: "<ISO 8601 timestamp>" }
)
```

### Wait for commit completion

The orchestrator goes idle. It is awakened when the editor completes the commit task and a task completion notification arrives in the orchestrator's mailbox.

### Route on result

**`result_status == "failure"`:**
- Surface `task.metadata.result_block` verbatim per [error-messages.md#commit-failed](../orchestrator-protocol/references/error-messages.md#commit-failed) (in code-forge:orchestrator-protocol).
- Call `ExitWorktree(action=keep)`.
- Call [Team Cleanup](#team-cleanup).
- Stop.

**`result_status == "success"`:**
- Store `COMMIT_RESULT = task.metadata.result_block`.
- Extract commit SHA and cherry-pick status from the result.
- Transition: set `CURRENT_STATE = "done"`.

---

## State: done

1. Print the completion summary:

   ~~~markdown
   ## Done: <ISSUE_ID> — <title>

   Commit: <short sha> — <proposed commit subject>
   Cherry-picked to: main

   Changes made:
   - <file>: <what changed>
   - …

   Tests: <passed / updated / added>
   ~~~

2. Call [Team Cleanup](#team-cleanup). Team Cleanup archives all `PIPELINE_TASK_IDS` — do not archive separately here.

3. Prompt the user: "Worktree `issue-<ISSUE_ID>` is ready — keep it (for further work) or remove it?"

5. Call `ExitWorktree` with the action the user specifies (keep or remove) per worktree conventions in code-forge:orchestrator-protocol.

---

## Team Cleanup

Called on all exit paths (success, failure, escalation, and abort).

1. Archive any unarchived pipeline tasks (best-effort — skip if PIPELINE_TASK_IDS is empty or archiving fails):

   For each `task_id` in `PIPELINE_TASK_IDS`:
   ```
   TaskUpdate(taskId = <id>, metadata = { archived: true })
   ```

2. Delete the pipeline team:

   <!-- FIXME(0086): TeamDelete integration pending issue 0086.
        Call TeamDelete(name="pipeline-team") here once the tool is available.
        Until then, log that cleanup is pending and proceed. -->

3. (Cleanup complete — ExitWorktree is called separately by each exit path as needed.)

---

## Supporting files

- Task Brief format: [task-brief.md](references/task-brief.md)
- Brief sufficiency rules: [brief-sufficiency.md](references/brief-sufficiency.md)
