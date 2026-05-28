---
name: describe-task
description: "Creates a Task Brief from a plain-language problem description. Clarifies the problem with the user, researches the codebase for entry points and relevant files, then emits a v1 Task Brief for use by /implement. Companion to /load-task for describing work directly rather than selecting from the backlog."
allowed-tools:
  - TeamCreate
  - Agent
  - TaskCreate
  - TaskUpdate
  - TaskGet
  - Read(~/**/.claude/skills/researcher-protocol/references/task-brief.md)
  - Read(~/.claude/plugins/**/skills/researcher-protocol/references/task-brief.md)
  - Bash(git rev-parse --show-toplevel)
  - AskUserQuestion
---

# Describe Task

Creates a Task Brief from a plain-language problem description instead of selecting from the project backlog. Uses a persistent code-forge:researcher-agent teammate to clarify the problem, research the codebase, and return a structured brief.

Reference: [code-forge:orchestrator-protocol](../orchestrator-protocol/SKILL.md) · [code-forge:researcher-protocol](../researcher-protocol/SKILL.md) · [task-brief-format](../researcher-protocol/references/task-brief.md)

---

## Step 0 — Load code-forge:orchestrator-protocol

Load `/code-forge:orchestrator-protocol` now. It defines the message formats, result blocks, and brief contract used in the steps below. Do not proceed until it is loaded.

---

## Step 1 — Capture the Description

Check the user's invocation arguments. If a description was provided (as a single quoted string or multi-word argument), use it as `<DESCRIPTION>`. If no argument was given, prompt the user:

Use `AskUserQuestion` with a single question:

- **Header:** "Problem description"
- **Question:** "Describe the problem or task you want to work on. Be as specific as you can about what should change and why."
- **Options:** (omit; this is a free-text response)

Capture the user's answer as `<DESCRIPTION>`. Proceed to Step 2.

---

## Step 2 — Clarify the Description

Parse `<DESCRIPTION>` and identify what is `Known` or `Unknown`:

| What to infer | Derived from user answer |
|---|---|
| Change **type** (Bug / Chore / Enhancement) | Is something broken, or is this new/improved/cleaned up? |
| **Done condition** — what the user can observe when it works | "How will you know it's working?" |
| **Starting point hint** — a file, feature name, or module | "Which part of the code is involved, if you know?" |

For each `Unknown`, include the corresponding question in the batch below. Do not proceed to Step 3 while any field is `Unknown`.

**Use `AskUserQuestion` to batch all outstanding clarifications:**

Include these questions as appropriate (omit those where the answer is already clear from the description):

- **Q1 — Nature of the change** (include if type is not clear):
  - Header: "Change type"
  - Question: "What kind of change is this?"
  - Options: 
    - "Something is broken" (→ Bug)
    - "Add or improve something" (→ Enhancement)
    - "Cleanup, refactor, or update" (→ Chore)

- **Q2 — Done condition** (include only if description lacks a concrete outcome):
  - Header: "Success condition"
  - Question: "What should work differently when this is done?"
  - Options: (omit; free-text answer)

- **Q3 — Codebase focus** (include only if description is vague about location):
  - Header: "Codebase area"
  - Question: "Do you know which file, feature, or area of the code is involved?"
  - Options: (omit; free-text, optional)

**Always use `AskUserQuestion` for this step** — even if only one field is unknown. Record all answers.

Synthesize the answers into a `context_overrides` string: comma-separated key=value pairs, e.g., `type=Bug, criteria=Should log retry attempts, area=api/http.go`. Pass this to Step 4 below.

---

## Step 3 — Determine Repository Root

Compute the repository root:

```bash
git rev-parse --show-toplevel || pwd
```

Store this as `<REPO_ROOT>`.

---

## Step 4 — Create Pipeline Team, Spawn Researcher, and Assign Task

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

3. Store `RESEARCHER_NAME = "researcher"`. Use this name in all subsequent `TaskUpdate` calls. Team member names persist across idle/resume cycles — do not convert to UUIDs.

4. Compute a pipeline run ID using the format `describe-task-<YYYYMMDDTHHmmss>` (e.g., `describe-task-20260525T143000`). Store as `PIPELINE_RUN_ID`.

5. Create the sentinel task and assign it to `team-lead` before spawning any agent work. This keeps the task list from being auto-cleared by the UI while the orchestrator is reading back the researcher's result:

   ```
   TaskCreate(
     subject     = "Pipeline orchestration — <PIPELINE_RUN_ID>",
     description = "Held in_progress by the team-lead to prevent UI auto-cleanup of the task list while the orchestrator reads back researcher results.",
     metadata    = {
       pipeline_run_id: "<PIPELINE_RUN_ID>",
       worktree_path:   "",
       role:            "team-lead",
       phase:           "orchestration",
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

   Store the returned task ID as `SENTINEL_TASK_ID`. Then assign it immediately:

   ```
   TaskUpdate(
     taskId   = <SENTINEL_TASK_ID>,
     owner    = "team-lead",
     status   = "in_progress",
     metadata = { claimed_at: "<ISO 8601 timestamp>" }
   )
   ```

6. Create the researcher task via TaskCreate:

   ```
   TaskCreate(
     subject     = "Describe and research task from user description",
     description = "goal: Produce a Task Brief from a user-provided description\nrepo_root: <REPO_ROOT>\ndescription: <full DESCRIPTION text from Step 1>\ncontext_overrides: <key=value pairs from Step 2; omit if empty>\nreturn_format: Task Brief",
     metadata    = {
       pipeline_run_id: "<PIPELINE_RUN_ID>",
       worktree_path:   "",
       role:            "researcher",
       phase:           "research",
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

   Store the returned task ID as `RESEARCHER_TASK_ID`.

7. Assign the task to the researcher via TaskUpdate (this wakes the agent):

   ```
   TaskUpdate(
     taskId   = <RESEARCHER_TASK_ID>,
     owner    = "researcher",
     status   = "in_progress",
     metadata = { claimed_at: "<ISO 8601 timestamp>" }
   )
   ```

The researcher automatically loads the `code-forge:researcher-protocol` skill.

The orchestrator goes idle after assignment. When the researcher completes the task, a task completion notification arrives in the orchestrator's mailbox, waking it to proceed to Step 5.

---

## Step 5 — Validate Brief

Read `task.metadata.result_block` from the completed researcher task to obtain the Task Brief text.
- If `task.metadata.result_status == "failure"`, surface `task.metadata.result_block` as a Failure Report verbatim and stop.
- If `task.metadata.result_status == "escalation"`, surface `task.metadata.result_block` as NEEDS_ESCALATION verbatim and stop.

After receiving the Task Brief, validate required fields per the brief contract in code-forge:orchestrator-protocol.

If any required field is missing, surface the partial brief to the user with a note identifying the gaps. Do not emit an incomplete brief.

---

## Step 6 — Emit Result

Following the `/orchestrate` result contract, emit the Task Brief verbatim to the user without reformatting or summary.

Then complete the sentinel task:

```
TaskUpdate(
  taskId   = <SENTINEL_TASK_ID>,
  status   = "completed",
  metadata = { completed_at: "<ISO 8601 timestamp>" }
)
```

End with:

> Run `/implement` to plan and implement this task.

The `pipeline-team` persists for use by `/implement` — editor and reviewer will be spawned into it just-in-time when `/implement` runs.
