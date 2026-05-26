# Brief Sufficiency Red Flags

Used by `/implement` Step 1. If **2 or more** red flags are present, the brief is insufficient: output the message from [error-messages.md](../orchestrator-protocol/references/error-messages.md#brief-insufficient) (in code-forge:orchestrator-protocol) and stop.

---

## Red flag 1 — Unclear entry points

**Description:** The "Relevant files" section is missing, file paths are ambiguous, or there is no clear starting point for implementation.

**Examples:**
- Brief says "update the API handler" but names no file or module
- File paths listed are partial directory names without filenames (e.g., `src/api/` instead of `src/api/handler.ts`)
- Brief references "the existing utility" with no path or identifier

---

## Red flag 2 — Ambiguous acceptance criteria

**Description:** Acceptance criteria use conditional language, have multiple valid interpretations, or lack concrete test cases.

**Examples:**
- "Should work correctly for most inputs" — no definition of "most" or "correctly"
- "Fix the performance issue" — no baseline, no target metric
- "Make the tests pass" when tests don't yet exist and expected behavior isn't specified

---

## Red flag 3 — Unresolved risks

**Description:** The "Risks and unknowns" section flags blockers that are still open — not acknowledged as acceptable risk, not resolved.

**Examples:**
- "Unknown whether library X supports feature Y" — no resolution noted, library is required for the task
- "May require schema migration" — no decision on whether migration is in scope
- Risks section lists open questions that the acceptance criteria depend on

---

## Red flag 4 — Multiple valid approaches without recommendation

**Description:** The brief lists 2 or more distinct implementation strategies without recommending one, leaving the choice to the implementer.

**Examples:**
- "We could either refactor the existing class or introduce a new service layer"
- "Option A: patch the SQL query. Option B: add a caching layer." — no recommendation given
- Acceptance criteria that are compatible with incompatible architectures

---

## Threshold rule

**2 or more** red flags present = insufficient brief. A single red flag may be resolvable during implementation; two or more indicate the brief needs further research before implementation can begin safely.
