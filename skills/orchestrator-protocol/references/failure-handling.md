# Failure Handling

Per-type handling for failure responses from teammates. Message text for user-facing output blocks is defined in [error-messages.md](error-messages.md).

---

## Failure Report received (from code-forge:editor-agent)

**Trigger:** `code-forge:editor-agent` returns a Failure Report instead of a Changeset Summary.

1. Emit the Failure Report verbatim to the user.
2. Call `ExitWorktree` with `action=keep`.
3. Stop and wait for user direction.

Do not attempt to retry or work around the failure.

---

## NEEDS_ESCALATION received (from code-forge:editor-agent)

**Trigger:** `code-forge:editor-agent` returns a NEEDS_ESCALATION block (task exceeds safe scope).

1. Surface to the user — the task exceeds safe scope.
2. Stop. Do not proceed to review silently.

The editor's NEEDS_ESCALATION block contains the scope analysis; emit it verbatim.

---

## Team coordination failure

**Trigger:** Task assignment to `EDITOR_NAME` or `REVIEWER_NAME` fails, agents did not spawn, or coordination times out.

1. Output the team coordination failure block (see [error-messages.md#team-coordination-failed](error-messages.md#team-coordination-failed)).
2. Call `ExitWorktree` with `action=keep`.
3. Stop and wait for user direction.

Do not attempt to spawn alternative subagents or cold-spawn fallbacks.
