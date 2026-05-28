# Task-List Coordination Schema

Defines the extended task schema and coordination semantics for task-list-based orchestration. Tasks are the primary coordination mechanism: the orchestrator assigns work by updating task fields; agents read their assigned task, execute, and write results back. This replaces ephemeral SendMessage-based assignment with durable, inspectable task state.

---

## Schema

Tasks have two categories of fields: **core fields** (managed by the task system directly) and **metadata fields** (arbitrary key-value pairs stored in the `metadata` object).

### Core fields

| Field | Type | Purpose | Set by |
|-------|------|---------|--------|
| `subject` | string | Short description of the work unit | TaskCreate — required |
| `description` | string | Full task context, assignment envelope, and brief | TaskCreate — optional |
| `status` | enum | Lifecycle state: `pending` \| `in_progress` \| `completed` | TaskUpdate only — never set at creation |
| `owner` | string \| null | Agent name currently responsible; `null` when unassigned | TaskUpdate only — never set at creation |

Tasks are always created with `status: pending` and no owner. The orchestrator sets `status` and `owner` via TaskUpdate after creation.

### Metadata fields

All pipeline-specific fields are stored in the `metadata` object on the task. These are written via `TaskCreate(metadata: {...})` or `TaskUpdate(metadata: {...})`.

| Field | Type | Purpose | Mutability |
|-------|------|---------|------------|
| `pipeline_run_id` | string | Stable identifier grouping all tasks for one pipeline invocation (e.g. `implement-0092-20260525T143000`) | Set at creation; never changed |
| `worktree_path` | string | Absolute path to the git worktree the agent must operate in | Set at creation; never changed |
| `role` | enum | Agent role for this task: `researcher` \| `editor` \| `reviewer` \| `team-lead` | Set at creation; never changed |
| `phase` | enum | Work phase: `research` \| `implement` \| `review` \| `fix` \| `commit` \| `orchestration` | Set at creation; never changed |
| `iteration` | integer | Fix-loop counter; `0` for non-fix phases; `1`+ for successive fix rounds | Set at creation; never changed |
| `result_status` | enum \| null | Outcome written by agent: `success` \| `failure` \| `escalation`; `null` until completed | Agent writes once on completion |
| `result_type` | enum \| null | Names the result block: `Task Brief` \| `Changeset Summary` \| `Review Findings` \| `Commit Completion` \| `Failure Report` \| `NEEDS_ESCALATION`; `null` until completed | Agent writes once on completion |
| `result_block` | string \| null | Full text of the result block returned by the agent; `null` until completed | Agent writes once on completion |
| `claimed_at` | ISO 8601 timestamp \| null | When the agent was assigned; `null` until assigned | Orchestrator writes on assignment |
| `completed_at` | ISO 8601 timestamp \| null | When the agent wrote results; `null` until done | Agent writes once on completion |
| `archived` | boolean | Set `true` by the orchestrator after the full pipeline run completes | Orchestrator writes once after pipeline completion |

### Field classification

**Coordination fields** (drive orchestrator logic): `status`, `owner`, `metadata.claimed_at`, `metadata.completed_at`, `metadata.result_status`, `metadata.result_type`, `metadata.result_block`.

**Context fields** (provide working context to the agent): `metadata.worktree_path`, `metadata.role`, `metadata.phase`, `metadata.iteration`.

**Lifecycle / diagnostics fields**: `metadata.archived`.

**Audit / grouping fields**: `metadata.pipeline_run_id`.

---

## Task Lifecycle

```
pending  →  in_progress  →  completed
```

A task is created with `status: pending` and no owner. The orchestrator assigns it via TaskUpdate (setting `owner`, `status`, and `metadata.claimed_at`). When the agent finishes, result metadata fields are written and `status` advances to `completed`.

TaskList returns all tasks regardless of status or metadata values. Filtering to find tasks for a specific pipeline run or agent role is done client-side by inspecting `metadata.pipeline_run_id`, `metadata.role`, etc.

Transitions are one-directional under normal operation. The only reversal is stall recovery, which resets a stalled `in_progress` task back to `pending` (see [Stall Recovery](#stall-recovery)).

---

## Assignment Semantics

The orchestrator assigns a task by calling:

```
TaskUpdate(
  taskId     = <task_id>,
  owner      = <agent_name>,
  status     = "in_progress",
  metadata   = { claimed_at: <ISO 8601 timestamp> }
)
```

`TaskUpdate` delivers a mailbox notification to the named owner. This notification wakes the agent, which then reads the task to obtain its working context (`worktree_path`, `role`, `phase`, `iteration`, and the full brief in the task description).

The agent does not need a separate `CLAIM` round-trip. Assignment is atomic: setting `owner`, `status`, and `metadata.claimed_at` in a single `TaskUpdate` call prevents double-assignment.

---

## Result Capture

When the agent completes work (success, failure, or escalation), it writes results back to the task in a single call:

```
TaskUpdate(
  taskId   = <task_id>,
  status   = "completed",
  metadata = {
    result_status: <"success" | "failure" | "escalation">,
    result_type:   <result block name>,
    result_block:  <full text of the result block>,
    completed_at:  <ISO 8601 timestamp>
  }
)
```

The orchestrator reads these metadata fields to route next steps without requiring a SendMessage from the agent. The agent may also send a SendMessage notification to the orchestrator after updating the task, but the task record is the authoritative result — not the message.

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

There is no automatic timeout clock. Stall detection is manual: inspect `metadata.claimed_at` and `metadata.completed_at` to determine whether a task is still making progress.

**Operational guidance:** if `now − metadata.claimed_at > 1 hour` and `metadata.completed_at` is still `null`, consider the task stalled and inspect before continuing.

To inspect a potentially stalled task, review the task fields:

- `metadata.phase` and `metadata.role` — what kind of work was assigned
- `metadata.claimed_at` — when work began
- `metadata.worktree_path` — check for uncommitted file changes or partial edits
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
  taskId   = <task_id>,
  owner    = null,
  status   = "pending",
  metadata = { claimed_at: null }
)
```

Then re-assign using the normal assignment semantics above. This resets the task to a clean assignable state. The `metadata.result_status`, `metadata.result_type`, and `metadata.result_block` fields remain `null` from initial creation and do not need clearing.

If the worktree may be in a partially modified state, the orchestrator should note this in the new assignment context so the agent can inspect before proceeding.

---

## TaskCreate / TaskUpdate Integration

TaskCreate accepts `subject`, `description`, and `metadata`. It does not accept `status` or `owner` — tasks are always created with `status: pending` and no owner.

TaskUpdate and TaskGet use `taskId` (camelCase) to identify the task.

TaskList returns all tasks; filter client-side by inspecting `metadata` fields.

### Creating a task

```
TaskCreate(
  subject     = "<brief description>",
  description = "<full context, assignment envelope, and brief>",
  metadata    = {
    pipeline_run_id: "<run_id>",
    worktree_path:   "<absolute_path>",
    role:            "<researcher | editor | reviewer | team-lead>",
    phase:           "<research | implement | review | fix | commit | orchestration>",
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

### Assigning a task

```
TaskUpdate(
  taskId   = <task_id>,
  owner    = "<agent_name>",
  status   = "in_progress",
  metadata = { claimed_at: "<ISO 8601 timestamp>" }
)
```

### Recording a result

```
TaskUpdate(
  taskId   = <task_id>,
  status   = "completed",
  metadata = {
    result_status: "<success | failure | escalation>",
    result_type:   "<result block name>",
    result_block:  "<full result text>",
    completed_at:  "<ISO 8601 timestamp>"
  }
)
```

### Resetting for retry

```
TaskUpdate(
  taskId   = <task_id>,
  owner    = null,
  status   = "pending",
  metadata = { claimed_at: null }
)
```

### Archiving after pipeline completion

Called by the orchestrator on all tasks for a `pipeline_run_id` once the full run is done (success or failure):

```
TaskUpdate(
  taskId   = <task_id>,
  metadata = { archived: true }
)
```

Archived tasks remain readable for audit and manual resume.
