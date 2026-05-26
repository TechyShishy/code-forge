---
name: load-task
description: "Selects the next workable issue from the project backlog and produces a Task Brief for use by /implement."
allowed-tools:
  - TeamCreate
  - Agent
  - SendMessage
  - TaskCreate
  - TaskUpdate
  - TaskGet
  - Skill(code-forge:orchestrator-protocol)
  - Read(~/**/.claude/skills/researcher-protocol/references/task-brief.md)
  - Read(~/.claude/plugins/**/skills/researcher-protocol/references/task-brief.md)
  - Bash(git rev-parse --show-toplevel)
---

# Load Task from Backlog

Selects the next workable issue from the project backlog and produces a Task Brief for use by `/implement`. Uses a persistent code-forge:researcher-agent teammate to investigate the backlog, rank candidates, and return a structured brief.

Reference: [code-forge:orchestrator-protocol](../orchestrator-protocol/SKILL.md) · [code-forge:researcher-protocol](../researcher-protocol/SKILL.md) · [task-brief-format](../researcher-protocol/references/task-brief.md)

---

## Step 0 — Load code-forge:orchestrator-protocol

Load `/code-forge:orchestrator-protocol` now. It defines the message formats, result blocks, and brief contract used in the steps below. Do not proceed until it is loaded.

---

## Step 1 — Determine Repository Root

Compute the repository root:

```bash
git rev-parse --show-toplevel || pwd
```

Store this as `<REPO_ROOT>`.

---

## Step 2 — Create Pipeline Team, Spawn Researcher, and Assign Task

1. Create an empty named team, catching any failure:

   ```
   try:
     TeamCreate(name: "pipeline-team")
   catch error where error.message contains "Already leading team 'pipeline-team'"
                  or error.message contains "Team 'pipeline-team' already exists at":
     emit the pipeline-team-exists error block from code-forge:orchestrator-protocol/references/error-messages.md verbatim
     stop — do not spawn agents or proceed further
   ```

2. Spawn the researcher into it:

   ```
   Agent(
     subagent_type: "code-forge:researcher-agent",
     name: "researcher",
     team_name: "pipeline-team"
   )
   ```

   Store `RESEARCHER_NAME = "researcher"`. Use this name in all subsequent `SendMessage` and `TaskUpdate` calls. Team member names persist across idle/resume cycles — do not convert to UUIDs.

3. Compute a pipeline run ID using the format `load-task-<YYYYMMDDTHHmmss>` (e.g., `load-task-20260525T143000`). Store as `PIPELINE_RUN_ID`.

4. Create the researcher task via TaskCreate:

   ```
   TaskCreate(
     title           = "Select and research next backlog issue",
     description     = "goal: Select the best workable issue from the project backlog and produce a Task Brief\nrepo_root: <REPO_ROOT>\nuser_args: <arguments from user invocation, or empty string>\ncontext_overrides: <optional overlay instructions, or empty string>",
     status          = "pending",
     owner           = null,
     pipeline_run_id = "<PIPELINE_RUN_ID>",
     worktree_path   = "",
     role            = "researcher",
     phase           = "research",
     iteration       = 0,
     result_status   = null,
     result_type     = null,
     result_block    = null,
     claimed_at      = null,
     completed_at    = null,
     archived        = false
   )
   ```

   Store the returned task ID as `RESEARCHER_TASK_ID`.

5. Assign the task to the researcher via TaskUpdate (this wakes the agent):

   ```
   TaskUpdate(
     task_id    = <RESEARCHER_TASK_ID>,
     owner      = "researcher",
     status     = "in_progress",
     claimed_at = "<ISO 8601 timestamp>"
   )
   ```

The researcher automatically loads the `code-forge:researcher-protocol` skill, which contains the complete research workflow (backlog scanning, scoring, selection, research).

---

## Step 3 — Wait for Task Completion and Validate Brief

The orchestrator goes idle after assigning the task. When the researcher completes it, a task completion notification arrives in the orchestrator's mailbox, waking it to read the result.

Once awakened:
- Read `task.result_block` to obtain the Task Brief text.
- If `task.result_status == "failure"`, surface `task.result_block` as a Failure Report verbatim and stop.
- If `task.result_status == "escalation"`, surface `task.result_block` as NEEDS_ESCALATION verbatim and stop.

After receiving the Task Brief, validate required fields per the brief contract in code-forge:orchestrator-protocol.

If any required field is missing, surface the partial brief to the user with a note identifying the gaps. Do not emit an incomplete brief.

---

## Step 4 — Emit Result

Following the `/orchestrate` result contract and the dispatcher routing table in code-forge:orchestrator-protocol, emit the Task Brief(s) verbatim to the user without reformatting or summary.

End with:

> Run `/implement` to plan and implement this task.

The `pipeline-team` persists for use by `/implement` — editor and reviewer will be spawned into it just-in-time when `/implement` runs.
