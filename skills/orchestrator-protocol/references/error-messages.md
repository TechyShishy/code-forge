# Error Messages & Output Blocks

User-facing output blocks for error and failure cases in the `/implement` skill. Each section below provides the exact text or template to surface when the corresponding condition is triggered.

---

## no-task-brief

**Trigger:** Prerequisite check; no Task Brief is visible in conversation context.

**Surface:**

> No task brief in context. Run `/load-task` first to select and research an issue, then invoke `/implement`.

---

## brief-insufficient

**Trigger:** Step 1; the Task Brief has 2 or more red flags (unclear entry points, ambiguous acceptance criteria, unresolved risks, or multiple valid approaches without recommendation).

**Surface:**

~~~markdown
## Brief is insufficient for implementation

The Task Brief needs clarification before proceeding:

**Issues identified:**
- <specific red flag(s)>

**What to do:**
1. Run `/load-task` again and ask the researcher to:
   - Clarify <missing detail>
   - Resolve <unresolved question>
   - Narrow scope to a single approach
2. Once you have a refined brief, run `/implement` again.

[Current brief attached for reference]
~~~

**Customization:** Fill in the bulleted items with specific red flags identified during sufficiency validation (e.g., "Unclear which files contain the API contract", "Acceptance criteria use conditional language without test cases").

---

## implementation-failed

**Trigger:** Step 5; the code-forge:editor-agent returns a Failure Report instead of a Changeset Summary.

**Surface:**

1. Output the Failure Report verbatim to the user.
2. Call `ExitWorktree` with action=keep (preserve state for inspection).
3. Print the stop message:

> Implementation failed — see the Failure Report above. Inspect the worktree, fix the issue, then re-invoke `/implement`.

---

## team-coordination-failed

**Trigger:** Phase 6.4; SendMessage to editor or reviewer agent fails, agents did not spawn at Step 3, or team coordination times out.

**Surface:**

~~~markdown
## Team Coordination Failed

The review/fix phase encountered a failure in agent communication or team setup.

**What happened:**
- <specific failure: SendMessage timeout, agent spawn failure, response parsing error, etc.>

**Current state:**
- Worktree: `issue-<ID>` (preserved for inspection)
- Changeset Summary: [attached below]

**Next steps:**
1. Inspect the worktree and changeset to understand what was implemented.
2. Run manual tests if needed to verify the changes.
3. Decide whether to commit or fix further:
   - **To commit as-is:** run `/implement` again (the commit phase will complete).
   - **To fix issues first:** make manual edits in the worktree, then run `/implement` again.
   - **To abandon:** call `ExitWorktree` with action=remove.

[Changeset Summary attached]
~~~

**Customization:** Fill in the `What happened:` bullet with the specific failure detail (e.g., "SendMessage to EDITOR_NAME timed out after 30s", "REVIEWER_NAME spawn failed: insufficient resources"), and fill the `<ID>` placeholder with the actual issue ID from the brief.

After printing: Call `ExitWorktree` with action=keep (preserve state). Stop and wait for user direction.

---

## commit-failed

**Trigger:** Step 7; the code-forge:editor-agent returns a Failure Report instead of a Commit Completion response.

**Surface:**

1. Output the Failure Report verbatim to the user.
2. Call `ExitWorktree` with action=keep (preserve state for inspection).
3. Stop and wait for user direction.

**Message:**
> Commit failed — see the Failure Report above. Inspect the worktree, fix the issue, then re-invoke `/implement`.

---

## pipeline-team-exists

**Trigger:** Step 4 of `/describe-task` or Step 2 of `/load-task`; `TeamCreate(name: "pipeline-team")` fails with one of these errors:
- "Already leading team 'pipeline-team'..." (same session that created the team)
- "Team 'pipeline-team' already exists at /home/techyshishy/.claude/teams/pipeline-team/config.json..." (different session)

**Surface:**

~~~markdown
## Session Already in Progress

A `describe-task` or `load-task` session is already active elsewhere.

**What happened:**
The skills use a shared team called `pipeline-team` to coordinate agents. You cannot create a new session while another one is in progress.

**Your options:**

1. **Complete the existing session:** Return to your other terminal and run `/implement` to finish the current task.
2. **Abandon the existing session:** If the other session is stale or no longer needed, clean it up with `TeamDelete` in that session, then try again here.

**Why this matters:** Running multiple sessions simultaneously on the same task can cause conflicts in team coordination and agent spawning.
~~~

**Customization:** No customization needed; the message is generic for both error variants and both `/describe-task` and `/load-task`.
