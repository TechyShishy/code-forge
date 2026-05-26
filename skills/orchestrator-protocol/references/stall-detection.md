# Stall Detection

Applies to the MUST FIX fix loop in `/implement` Phase 6.2.

## Fingerprint definition

For each MUST FIX finding, extract a normalized tuple `(severity, file_path, finding_category)`:

- **severity:** always `MUST_FIX`
- **file_path:** file path from the finding, stripped of line numbers (e.g., `src/foo.ts`, not `src/foo.ts:42`)
- **finding_category:** topical label of the finding, stripped of variable names, quoted values, and phrasing variation — keep only the structural category (e.g., "missing null check", "unhandled promise")

The fingerprint set for a round is the sorted list of these tuples. Line numbers, variable names, and exact phrasing are excluded so cosmetic re-phrasings of the same problem map to the same fingerprint.

## Stall detection rules

| Fingerprint set change from previous round | Action |
|--------------------------------------------|--------|
| First iteration (`iteration == 1` or `prev_fingerprints` empty) | Treat as progress; set baseline and continue |
| Count decreased | Continue — progress occurring; reset `stall_count = 0` |
| New fingerprints appeared (subset change) | Continue — progress occurring; reset `stall_count = 0` |
| Fingerprint set unchanged for 2 consecutive rounds | Stall detected — invoke `AskUserQuestion` |
| Count increased (regression) AND `grace_used = false` | Grant grace: set `grace_used = true`, reset `stall_count = 0`; allow one additional round |
| Count increased (regression) AND `grace_used = true` | No grace available — treat as stall immediately |

Grace is one-shot per improvement cycle: once `grace_used` is `true`, it remains `true` until count decreases again, at which point reset `grace_used = false`.

## Loop procedure

Initialize: `iteration = 0`, `prev_fingerprints = []`, `stall_count = 0`, `grace_used = false`, `user_direction = ""`.

**Invariant:** `prev_fingerprints = current_fingerprints` must execute on every iteration before looping back to step 1.

1. Increment `iteration`.
2. Create and assign fix task via TaskCreate + TaskUpdate:
   ```
   TaskCreate(
     title           = "Apply MUST FIX findings for issue <ISSUE_ID> — iteration <REVIEW_ITERATION>",
     description     = "goal: Apply MUST FIX findings from review\nworktree_path: <WORKTREE_PATH>\nrole: editor\nphase: fix\niteration: <iteration>\n<if USER_DIRECTION non-empty: \nuser_direction: <USER_DIRECTION>>\n\n<each active MUST FIX item as a list>",
     status          = "pending",
     owner           = null,
     pipeline_run_id = "<PIPELINE_RUN_ID>",
     worktree_path   = "<WORKTREE_PATH>",
     role            = "editor",
     phase           = "fix",
     iteration       = <iteration>,
     result_status   = null,
     result_type     = null,
     result_block    = null,
     claimed_at      = null,
     completed_at    = null,
     archived        = false
   )
   
   TaskUpdate(
     task_id    = <FIX_TASK_ID>,
     owner      = "editor",
     status     = "in_progress",
     claimed_at = "<ISO 8601 timestamp>"
   )
   ```
   Reset `user_direction = ""` after injecting it. Go idle; await task completion notification.

3. Editor returns Changeset Summary. Update `changeset_summary = task.result_block`.

4. Create and assign review task via TaskCreate + TaskUpdate:
   ```
   TaskCreate(
     title           = "Review issue <ISSUE_ID> — iteration <iteration>",
     description     = "goal: Review the changeset and return severity-tagged findings\nworktree_path: <WORKTREE_PATH>\nrole: reviewer\nphase: review\niteration: <iteration>\n\n<CHANGESET_SUMMARY>",
     status          = "pending",
     owner           = null,
     pipeline_run_id = "<PIPELINE_RUN_ID>",
     worktree_path   = "<WORKTREE_PATH>",
     role            = "reviewer",
     phase           = "review",
     iteration       = <iteration>,
     result_status   = null,
     result_type     = null,
     result_block    = null,
     claimed_at      = null,
     completed_at    = null,
     archived        = false
   )
   
   TaskUpdate(
     task_id    = <REVIEW_TASK_ID>,
     owner      = "reviewer",
     status     = "in_progress",
     claimed_at = "<ISO 8601 timestamp>"
   )
   ```
   Go idle; await task completion notification.

5. Reviewer returns Review Findings. Parse findings into severity buckets.
6. If no MUST FIX items remain, proceed to Phase 6.3.
7. Extract fingerprint set for this round.
8. If `iteration == 1` or `prev_fingerprints` is empty: treat as progress (no baseline yet). Set `prev_fingerprints = current_fingerprints` and skip to step 9.

   Otherwise, compare `current_fingerprints` to `prev_fingerprints`:
   - **Sets identical:** increment `stall_count`. If `stall_count >= 2`, go to **Stall Handler**.
   - **Count increased (regression):**
     - If `grace_used = false`: set `grace_used = true`, reset `stall_count = 0`. Continue.
     - If `grace_used = true`: go to **Stall Handler**.
   - **Count decreased:** reset `stall_count = 0`, `grace_used = false`.
   - **New fingerprints appeared:** reset `stall_count = 0`, `grace_used = false`.
9. Set `prev_fingerprints = current_fingerprints`. Return to step 1.

## Stall handler

When a stall is detected, invoke `AskUserQuestion`:

```
The fix loop has stalled — either the MUST FIX findings have not progressed after 2 consecutive rounds, or a regression occurred after the grace round was already used.

Active MUST FIX findings:

<list each active MUST FIX item>

How would you like to proceed?

1. **Continue** — run another fix attempt (may not resolve without new direction)
2. **Accept-as-is** — exit the review loop; remaining findings will be noted as accepted risk in the commit summary
3. **Skip these items** — remove them from the active MUST FIX set for this session and proceed to commit
4. **Provide direction** — supply guidance that will be passed to the next fix attempt
```

Handle each response:

- **Option 1 (Continue):** Reset `stall_count = 0`. Return to step 1.
- **Option 2 (Accept-as-is):** Exit the loop. Note accepted findings verbatim in the Changeset Summary under `### Accepted risk`. Proceed to Phase 6.3.
- **Option 3 (Skip):** Remove stalled items from the active MUST FIX set. If no MUST FIX items remain, proceed to Phase 6.3. Otherwise reset `stall_count = 0` and return to step 1.
- **Option 4 (Provide direction):** Capture user's text as `user_direction`. Reset `stall_count = 0`. Return to step 1.
