---
name: orchestrator-protocol
description: "Shared protocol reference for the load-task → implement pipeline. Defines team topology, message envelope formats, result block definitions, brief contract, review severity handling, stall detection, worktree conventions, and failure handling. Load before running /load-task or /implement."
user-invocable: false
---

# Orchestrator Protocol — load-task → implement Pipeline

This is a reference spec, not a walkthrough. It defines shared vocabulary for the `/load-task` → `/implement` pipeline. Both skills reference this document rather than repeating these definitions inline.

## Contents

- [Team Topology](#team-topology)
- [Message Envelope Formats](#message-envelope-formats) — TASK_DONE (transition), RESULT (unified)
- [Result Block Definitions](#result-block-definitions)
- [Brief Contract](#brief-contract)
- [Review Severity Handling](#review-severity-handling)
- [Stall Detection](#stall-detection)
- [Worktree Conventions](#worktree-conventions)
- [Failure Handling](#failure-handling)
- [Task-List Coordination Schema](references/task-list-schema.md) — extended task fields, lifecycle, assignment semantics, result capture, stall inspection and recovery

---

## Team Topology

The pipeline uses a single named team, `pipeline-team`, with agents spawned just-in-time as each phase begins.

| Role | Member name | Model | Purpose | Spawned by |
|------|-------------|-------|---------|------------|
| Researcher | `researcher` | Haiku | Backlog research, issue selection, Task Brief production | `/load-task` or `/describe-task` |
| Editor | `editor` | Sonnet | Implementation, file edits, staging, commits | `/implement` Step 3 |
| Reviewer | `reviewer` | Sonnet | Code review, findings by severity | `/implement` Step 3 |

**Just-in-time spawning.** `/load-task` and `/describe-task` call `TeamCreate(name: "pipeline-team")` to create an empty team container, then spawn the researcher via `Agent(subagent_type: "code-forge:researcher-agent", team_name: "pipeline-team")`. `/implement` spawns editor and reviewer into the existing team via two `Agent` calls (no `TeamCreate`) before dispatching work.

SendMessage uses team member names, not UUIDs. Names remain addressable when agents idle and resume.

The orchestrator routes; it does not implement, research, or review.

---

## Message Envelope Formats

All assignment coordination uses the task list (TaskCreate + TaskUpdate). SendMessage is used for result delivery (RESULT). The formats below document the active format and retained historical formats.

### ASSIGN_EDIT (historical — removed)

> **Historical reference only.** This SendMessage envelope was sent by the orchestrator during the backward-compatibility period. It has been removed. Assignment now uses task-list only (TaskCreate + TaskUpdate).

### ASSIGN_REVIEW (historical — removed)

> **Historical reference only.** This SendMessage envelope was sent by the orchestrator during the backward-compatibility period. It has been removed. Assignment now uses task-list only (TaskCreate + TaskUpdate).

### TASK_DONE (historical)

> **Historical reference only.** Superseded by the unified RESULT envelope. Retained for documentation of the transition period.

```
TASK_DONE
task_id: <id>
result_block: <name of the result block in this message>
```

Followed immediately by the result block.

### TASK_FAILED (historical)

> **Historical reference only.** Superseded by the unified RESULT envelope. Retained for documentation of the transition period.

```
TASK_FAILED
task_id: <id>
reason: <short description>
files_modified: <list or "none">
recommended_action: <what the orchestrator or user should do next>
```

### RESULT

Sent by teammate to orchestrator on task completion (success, failure, or escalation). Replaces the role-specific TASK_DONE formats in new implementations; TASK_DONE remains valid during the transition period (see [TASK_DONE](#task_done)).

```
RESULT
task_id: <id>
agent: <researcher | editor | reviewer>
status: <success | failure | escalation>
result_type: <Task Brief | Changeset Summary | Commit Completion | NEEDS_ESCALATION | Failure Report | Review Findings>
```

Followed immediately by the result body block.

**Field descriptions:**

- `task_id`: Echoes the task_id from the originating ASSIGN_* envelope.
- `agent`: Sender's role — `researcher`, `editor`, or `reviewer`.
- `status`: `success` — task completed; `failure` — acceptance criteria cannot be met; `escalation` — task exceeds safe scope.
- `result_type`: Names the result block that follows (see [Result Block Definitions](#result-block-definitions)).

**Dispatcher routing table** (status, result_type) → orchestrator action:

| status | result_type | Orchestrator action |
|--------|-------------|---------------------|
| `success` | `Task Brief` | Validate fields; emit brief to user |
| `success` | `Changeset Summary` | Dispatch `code-forge:reviewer-agent` via task-list assignment |
| `success` | `Commit Completion` | Emit result; call ExitWorktree(action=remove) |
| `success` | `Review Findings` | Parse severity tags; apply [Review Severity Handling](#review-severity-handling) |
| `failure` | `Failure Report` | Emit verbatim; call ExitWorktree(action=keep); stop |
| `escalation` | `NEEDS_ESCALATION` | Surface to user; stop |

Full dispatcher implementation is defined in Issue 0083.

---

## Result Block Definitions

### Task Brief v1

Required fields (validated by `/load-task` before emitting):

- `**Issue:**` — GitHub issue `#N`, `TODO-NNNN`, `TODO@file:line`, `DESCRIBE-<slug>`, or local issue `NNNN` (zero-padded number, no prefix)
- `**Title:**` — issue title, TODO summary, or description
- `**Type:**` — `Bug | Chore | Enhancement`
- `**Effort:**` — `Small | Medium | Large`
- `### Acceptance criteria` — bulleted list of criteria
- `### Risks and unknowns` — section present (may be empty)

Full format defined in [code-forge:researcher-protocol](../researcher-protocol/SKILL.md).

### Changeset Summary

Returned by `code-forge:editor-agent` on successful implementation. Required fields:

- `**Issue:**` — issue ID from brief
- `**Model:**` — editor's model name
- `**Worktree path:**` — absolute worktree path
- `### Files changed` — table of file paths and descriptions
- `### Test results` — test command and outcome
- `### Proposed commit subject` — imperative sentence, ≤50 chars
- `### Issue reference` — `Fixes #N` / `Closes #N` / `Fixes TODO-NNNN`

### Review Findings

Returned by `code-forge:reviewer-agent`. Findings are tagged by severity bracket:

- `[MUST FIX]` — blocking: correctness, safety, or acceptance criteria violations
- `[SHOULD FIX]` — non-blocking: code quality, maintainability, style
- `[CONSIDER]` — optional: suggestions without strong recommendation
- `[GOOD]` — positive findings

Full findings format:

```
FINDINGS: [severity-bracketed findings].
```

### NEEDS_ESCALATION

Returned by `code-forge:editor-agent` when the task exceeds safe scope after analysis. Required fields:

- `**Issue:**` — issue ID
- `### Why escalation is needed` — concrete reason
- `### Files that would need changes` — list
- `### Files modified (if any)` — list or omit

Orchestrator response: surface to user, stop. Do not proceed to review silently.

### Failure Report

Returned by `code-forge:editor-agent` when acceptance criteria cannot be met. Required fields:

- `**Issue:**` — issue ID
- `**Phase:**` — `Implementation`
- `### What failed` — description
- `### Files modified (if any)` — list or omit
- `### Recommended next step` — user-facing guidance

Orchestrator response: emit verbatim, call `ExitWorktree` with `action=keep`, stop.

### Commit Completion

Returned by `code-forge:editor-agent` after staging, committing, and cherry-picking. Required fields:

- `**Issue:**` — issue ID
- `**Commit SHA:**` — short SHA
- `**Cherry-pick:**` — `success` or failure reason
- `Details:` — committed subject, files staged, cherry-pick target

---

## Brief Contract

The brief contract has two checkpoints, each enforced by a different skill.

### Required fields (enforced by `/load-task`)

Before emitting the Task Brief to the user, `/load-task` verifies:

- `**Issue:**` present and non-empty
- `**Title:**` present and non-empty
- `**Type:**` present and one of: Bug, Chore, Enhancement
- `**Effort:**` present and one of: Small, Medium, Large
- `### Acceptance criteria` section present and non-empty
- `### Risks and unknowns` section present

If any field is missing, `/load-task` surfaces the partial brief with a gap note and does not emit it.

### Sufficiency red flags (enforced by `/implement`)

Before entering the worktree, `/implement` validates the brief for implementation sufficiency. The following are red flags:

1. **Unclear entry points** — "Relevant files" section missing, file paths ambiguous, or no clear starting point
2. **Ambiguous acceptance criteria** — criteria use conditional language, have multiple interpretations, or lack concrete test cases
3. **Unresolved risks** — "Risks and unknowns" flags unresolved blockers
4. **Multiple valid approaches** — brief lists 2+ distinct strategies without recommending one

If **2 or more** red flags are present, the brief is insufficient: `/implement` bails out and directs the user back to `/load-task`.

---

## Review Severity Handling

How the orchestrator handles each severity tag from the reviewer:

| Tag | Orchestrator action |
|-----|---------------------|
| `[GOOD]` | No action. Proceed. |
| `[CONSIDER]` | Skip. No dispatch. Proceed. |
| `[SHOULD FIX]` | Dispatch once to `code-forge:editor-agent` via task-list assignment (task: `edit-should-fix`). No re-review after. Proceed to commit. |
| `[MUST FIX]` | Enter the fix loop (see [Stall Detection](#stall-detection)). Loop until no MUST FIX items remain or a stall is detected. |

---

## Stall Detection

Applies to the MUST FIX fix loop (Phase 6.2 of `/implement`).
If MUST FIX items remain unchanged across 2 consecutive fix rounds, a stall is detected.
See [stall-detection.md](references/stall-detection.md) for the fingerprint definition, detection rules, loop procedure, and stall handler.

---

## Worktree Conventions

- **Naming:** `issue-<ID>` format — e.g., `issue-0123` for GitHub issue #123, `issue-TODO-456` for TODO-456, `issue-DESCRIBE-add-retry-logic` for DESCRIBE-<slug>.
- **Team members:** working directory is not inherited across team member boundaries. The orchestrator passes `worktree_path` explicitly in every task envelope; team members must use that path as the base for all file and git operations.
- **Fork subagents:** inherit parent working directory.
- **ExitWorktree semantics:**
  - `action=keep` — preserve worktree for inspection (use on failure or user request).
  - `action=remove` — clean up worktree after successful commit.
  - Prompt user before calling `ExitWorktree` if outcome is ambiguous.

---

## Failure Handling

On any failure response from a teammate, emit verbatim, preserve the worktree, and stop.
See [failure-handling.md](references/failure-handling.md) for per-type handling (Failure Report, NEEDS_ESCALATION, team coordination failure).
