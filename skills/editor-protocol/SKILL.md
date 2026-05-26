---
name: editor-protocol
description: Teammate editor protocol — response formats for the code-forge:editor-agent in Agent Teams orchestration
---

## Teammate Editor — Agent Teams Mode

You are an editor teammate executing tasks assigned by the orchestrator. Execute the task fully — read all relevant files before editing, run tests. Respond using one of the formats below.

## Contents

- [RESULT Envelope](#result-envelope-new--preferred) — unified response wrapper (new)
- [Changeset Summary](#changeset-summary-successful-implementation) — successful implementation
- [NEEDS_ESCALATION](#needs_escalation-task-exceeds-safe-scope-after-analysis) — task exceeds scope
- [Failure Report](#failure-report-acceptance-criteria-cannot-be-met) — acceptance criteria unmet
- [Commit Completion](#commit-completion-commit-task-response) — commit task response

---

## Response Formats

If the task cannot be attempted at all (not: criteria unmet — use Failure Report), see [failure.md](references/failure.md).

Full protocol contract: `code-forge:orchestrator-protocol`.

### RESULT Envelope

Wrap every response in the unified RESULT envelope before the result body. The envelope tells the orchestrator dispatcher the outcome without parsing the body.

**Successful implementation (Changeset Summary):**

```
RESULT
task_id: <id>
agent: editor
status: success
result_type: Changeset Summary
```

**Scope escalation (NEEDS_ESCALATION):**

```
RESULT
task_id: <id>
agent: editor
status: escalation
result_type: NEEDS_ESCALATION
```

**Acceptance criteria unmet (Failure Report):**

```
RESULT
task_id: <id>
agent: editor
status: failure
result_type: Failure Report
```

**Commit completion:**

```
RESULT
task_id: commit-main
agent: editor
status: success
result_type: Commit Completion
```

The RESULT header is followed immediately by the result body defined in the sections below.

**Example — successful implementation:**

```
RESULT
task_id: implement-main
agent: editor
status: success
result_type: Changeset Summary

## Changeset Summary

**Issue:** 0079
**Model:** claude-sonnet-4-5
**Worktree path:** /home/user/Code/myproject

### Files changed

| File | Change |
|------|--------|
| skills/editor-protocol/SKILL.md | Added RESULT envelope documentation |

### Test results

No automated tests; manual review of Markdown formatting.

### Proposed commit subject

Define RESULT envelope in editor-protocol

### Issue reference

Closes #0079
```

### TASK_DONE (transition period — still valid)

The legacy format remains accepted by the orchestrator during the transition period (see Issue 0083 for deprecation timeline). Emit TASK_DONE only if your implementation predates RESULT support; new implementations should use the RESULT envelope above.

```
TASK_DONE
task_id: <id>
result_block: <Changeset Summary | NEEDS_ESCALATION | Failure Report | Commit Completion>
```

Followed immediately by the result body block.

---

### Changeset Summary (successful implementation)

```markdown
## Changeset Summary

**Issue:** <issue ID from brief>
**Model:** <your model name as it appears in your system prompt>
**Worktree path:** <worktree path from input>

### Files changed

| File | Change |
|------|--------|
| path/to/file | what changed and why |

### Test results

<test command run and outcome — "All tests pass" or specific counts>

### Proposed commit subject

<imperative sentence, ≤50 chars>

### Proposed commit body (if needed)

<1–2 sentences explaining what changed and why, if non-obvious. Omit if subject is self-explanatory.>

### Issue reference

Fixes #<N>   ← bugs
Closes #<N>  ← features/chores
Fixes TODO-<NNNN>  ← standalone TODOs
```

---

### NEEDS_ESCALATION (task exceeds safe scope after analysis)

```markdown
## NEEDS_ESCALATION

**Issue:** <issue ID from brief>

### Why escalation is needed

<concrete reason the task exceeds scope>

### Files that would need changes

<list of files identified as needing modification>

### Files modified (if any)

<list any files started but that should be reverted>
```

---

### Failure Report (acceptance criteria cannot be met)

```markdown
## Failure Report

**Issue:** <issue ID from brief>
**Phase:** Implementation

### What failed

<description of the failure — test output, unexpected code state, or plan invalidity>

### Files modified (if any)

<list any files partially modified — these may need manual cleanup>

### Recommended next step

<what the user should inspect or fix before re-invoking>
```

---

### Commit Completion (commit task response)

When `task_id` is `commit-main`:

1. Stage exactly the files listed in the Changeset Summary's "Files changed" section
2. Construct the commit message:
   - Subject: the Proposed commit subject (imperative, ≤50 chars)
   - Body: the Proposed commit body (1 blank line after subject; omit if empty)
   - Trailers: `Fixes #N` or `Closes #N`; `Co-authored-by: Claude <model-name> <noreply@anthropic.com>`
   - No Conventional Commits prefixes (no `feat:`, `fix:`, `chore:`, etc.)
3. Call `mcp-human-interface/wait-for-user-interaction` (user must be present for PGP passphrase)
4. Commit using git heredoc pattern
5. Capture the short SHA
6. Cherry-pick to main

Respond with:

```markdown
## Commit Completion

**Issue:** <issue ID from summary>
**Commit SHA:** <short SHA>
**Cherry-pick:** <success / failure>

Details:
- Committed: <subject line>
- Files staged: <list of files>
- Cherry-picked to: main (or reason for failure)
```
