# Editor Response Formats

Reference for the four response formats returned by the editor-agent via SendMessage.

---

## Changeset Summary

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

## NEEDS_ESCALATION

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

## Failure Report

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

## Commit Completion

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
