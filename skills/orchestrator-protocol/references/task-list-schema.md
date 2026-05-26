# Task-List Coordination Schema

Defines the extended task schema and coordination semantics for task-list-based orchestration. Tasks are the primary coordination mechanism: the orchestrator assigns work by updating task fields; agents read their assigned task, execute, and write results back. This replaces ephemeral SendMessage-based assignment with durable, inspectable task state.

---

## Schema

All fields are top-level properties on the task object. No nesting.

| Field | Type | Purpose | Mutability |
|-------|------|---------|------------|
| `title` | string | Short description of the work unit | Set at creation; not updated |
| `status` | enum | Lifecycle state: `pending` \| `in_progress` \| `completed` | Orchestrator sets `in_progress` on assignment; agent sets `completed` on finish; orchestrator resets to `pending` on retry |
| `owner` | string \| null | Agent name currently responsible; `null` when unassigned | Orchestrator writes on assignment; reset to `null` on retry |
| `pipeline_run_id` | string | Stable identifier grouping all tasks for one `/implement` invocation (e.g. `issue-0092-20260525T143000`) | Set at creation; never changed |
| `worktree_path` | string | Absolute path to the git worktree the agent must operate in | Set at creation; never changed |
| `role` | enum | Agent role for this task: `researcher` \| `editor` \| `reviewer` | Set at creation; never changed |
| `phase` | enum | Work phase: `research` \| `implement` \| `review` \| `fix` \| `commit` | Set at creation; never changed |
| `iteration` | integer | Fix-loop counter; `0` for non-fix phases; `1`+ for successive fix rounds | Set at creation; never changed |
| `result_status` | enum \| null | Outcome written by agent: `success` \| `failure` \| `escalation`; `null` until completed | Agent writes once on completion; not modified after |
| `result_type` | enum \| null | Names the result block that follows: `Task Brief` \| `Changeset Summary` \| `Review Findings` \| `Commit Completion` \| `Failure Report` \| `NEEDS_ESCALATION`; `null` until completed | Agent writes once on completion; not modified after |
| `result_block` | string \| null | Full text of the result block returned by the agent; `null` until completed | Agent writes once on completion; not modified after |
| `claimed_at` | ISO 8601 timestamp \| null | When the agent was assigned (`status` set to `in_progress`); `null` until assigned | Orchestrator writes on assignment; reset to `null` on retry |
| `completed_at` | ISO 8601 timestamp \| null | When the agent wrote results (`status` set to `completed`); `null` until done | Agent writes once on completion; not modified after |
| `archived` | boolean | Set `true` by the orchestrator after the full pipeline run completes; filters task-list queries to exclude finished runs from active views | Orchestrator writes once after pipeline completion; never reset |

### Field classification

**Coordination fields** (drive orchestrator logic): `status`, `owner`, `claimed_at`, `completed_at`, `result_status`, `result_type`, `result_block`.

**Context fields** (provide working context to the agent): `worktree_path`, `role`, `phase`, `iteration`.

**Lifecycle / diagnostics fields** (pipeline completion and filtering): `archived`.

**Audit / grouping fields** (for inspection, dashboard, and manual resume): `pipeline_run_id`.

All fields are flat — no nested objects. This keeps TaskCreate/TaskUpdate calls straightforward and avoids schema fragmentation across task types.

---

## Task Lifecycle

```
pending  →  in_progress  →  completed
```

A task is created with `status=pending` and `owner=null`. When the orchestrator assigns it, `owner` and `claimed_at` are set and `status` advances to `in_progress`. When the agent finishes, result fields are written and `status` advances to `completed`.

Transitions are one-directional under normal operation. The only reversal is stall recovery, which resets a stalled `in_progress` task back to `pending` (see [Stall Recovery](#stall-recovery)).

---

## Assignment Semantics

The orchestrator assigns a task by calling:

```
TaskUpdate(
  owner      = <agent_name>,
  status     = "in_progress",
  claimed_at = <ISO 8601 timestamp>
)
```

`TaskUpdate` delivers a mailbox notification to the named owner. This notification wakes the agent, which then reads the task to obtain its working context (`worktree_path`, `role`, `phase`, `iteration`, and the full brief in the task title or a linked document).

The agent does not need a separate `CLAIM` round-trip. Assignment is atomic: setting `owner`, `status`, and `claimed_at` in a single `TaskUpdate` call prevents double-assignment.

---

## Result Capture

When the agent completes work (success, failure, or escalation), it writes results back to the task in a single call:

```
TaskUpdate(
  status       = "completed",
  result_status = <"success" | "failure" | "escalation">,
  result_type   = <result block name>,
  result_block  = <full text of the result block>,
  completed_at  = <ISO 8601 timestamp>
)
```

The orchestrator reads these fields to route next steps without requiring a SendMessage from the agent. The agent may also send a SendMessage notification to the orchestrator after updating the task, but the task record is the authoritative result — not the message.

### Result type to result_status mapping

| `result_type` | `result_status` |
|---------------|-----------------|
| `Task Brief` | `success` |
| `Changeset Summary` | `success` |
| `Review Findings` | `success` |
| `Commit Completion` | `success` |
| `Failure Report` | `failure` |
| `NEEDS_ESCALATION` | `escalation` |

---

## Stall Inspection

There is no automatic timeout clock. Stall detection is manual: inspect `claimed_at` and `completed_at` to determine whether a task is still making progress.

**Operational guidance:** if `now − claimed_at > 1 hour` and `completed_at` is still `null`, consider the task stalled and inspect before continuing.

To inspect a potentially stalled task, review the task fields:

- `phase` and `role` — what kind of work was assigned
- `claimed_at` — when work began
- `worktree_path` — check for uncommitted file changes or partial edits
- `owner` — which agent was assigned (check agent state if still active)

After inspection, choose one of:

1. **Retry** — reset the task and re-assign (see [Stall Recovery](#stall-recovery))
2. **Continue waiting** — agent is still making progress; check again later
3. **Abort** — stop the pipeline; call `ExitWorktree(action=keep)` to preserve state

---

## Stall Recovery

On a retry decision:

```
TaskUpdate(
  owner      = null,
  status     = "pending",
  claimed_at = null
)
```

Then re-assign using the normal assignment semantics above. This resets the task to a clean assignable state. The `result_status`, `result_type`, and `result_block` fields remain `null` from initial creation and do not need clearing.

If the worktree may be in a partially modified state, the orchestrator should note this in the new assignment context so the agent can inspect before proceeding.

---

## TaskCreate / TaskUpdate Integration

All schema fields are supported as top-level parameters in `TaskCreate` and `TaskUpdate`. No field requires a nested object or separate task type.

### Creating a task

```
TaskCreate(
  title           = "<brief description>",
  status          = "pending",
  owner           = null,
  pipeline_run_id = "<run_id>",
  worktree_path   = "<absolute_path>",
  role            = "<researcher | editor | reviewer>",
  phase           = "<research | implement | review | fix | commit>",
  iteration       = 0,
  result_status   = null,
  result_type     = null,
  result_block    = null,
  claimed_at      = null,
  completed_at    = null,
  archived        = false
)
```

### Assigning a task

```
TaskUpdate(
  owner      = "<agent_name>",
  status     = "in_progress",
  claimed_at = "<ISO 8601 timestamp>"
)
```

### Recording a result

```
TaskUpdate(
  status        = "completed",
  result_status = "<success | failure | escalation>",
  result_type   = "<result block name>",
  result_block  = "<full result text>",
  completed_at  = "<ISO 8601 timestamp>"
)
```

### Resetting for retry

```
TaskUpdate(
  owner      = null,
  status     = "pending",
  claimed_at = null
)
```

### Archiving after pipeline completion

Called by the orchestrator on all tasks for a `pipeline_run_id` once the full run is done (success or failure):

```
TaskUpdate(
  archived = true
)
```

Archived tasks are excluded from active task-list views. They remain readable for audit and manual resume.
