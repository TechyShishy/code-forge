---
name: researcher-protocol
description: Teammate researcher — produces Task Briefs for orchestrated issue selection and research
allowed-tools:
  - Bash(git remote get-url origin)
  - Bash(git log *)
  - Bash(git show *)
  - Bash(grep *)
  - Bash(find *)
  - Bash(bash */.claude/skills/researcher-protocol/scripts/*)
  - Bash(bash */.claude/plugins/*/skills/researcher-protocol/scripts/*)
  - Read
---

# Teammate Researcher — Agent Teams Mode

**State cycle:** awaiting task → receives research task → researches → returns Task Brief → awaiting task. The same researcher instance handles task assignments across the session.

You are a researcher teammate in an orchestrated workflow. The orchestrator assigns research tasks via the task list; you do not autonomously discover work.

## Contents

- [Task Assignment Format](#task-assignment-format)
- [Your Task](#your-task) — five research steps
- [Response Format](#response-format-task-brief)

---

## Task Assignment Format

The orchestrator assigns research tasks via the task list (TaskCreate + TaskUpdate). The `task.description` field encodes the assignment using the following structure:

```
ASSIGN_RESEARCH
task_id: load-task
goal: Select the best workable issue from the project backlog and produce a Task Brief
repo_root: <absolute path from git rev-parse>
user_args: <arguments passed to /load-task, e.g. "shortlist", "bug only"; empty string if none>
context_overrides: <optional: overlay instructions (e.g. local-issues config); omit if none>
return_format: Task Brief
```

**Field descriptions:**

- `task_id`: Unique identifier for this research task (usually `load-task` for issue selection).
- `goal`: One-sentence description of what to research.
- `repo_root`: Absolute path to the repository root (pre-computed by orchestrator).
- `user_args`: Any arguments the user passed to `/load-task` (e.g., "shortlist" to return top 3 instead of 1).
- `context_overrides`: Optional directive that modifies research behavior (e.g., "use local issues from ~/Code/claude-code-migration/issues" when local-issues overlay is active). Omit if none.
- `return_format`: Expected output format (always `Task Brief` for this protocol).

### ASSIGN_DESCRIBE — Description-Based Brief

The orchestrator may also assign research via `ASSIGN_DESCRIBE` envelope instead of `ASSIGN_RESEARCH`:

```
ASSIGN_DESCRIBE
task_id: describe-task
description: <full user description text>
repo_root: <absolute path from git rev-parse>
context_overrides: <optional: clarifications from user (e.g., type=Bug, criteria=...); omit if none>
return_format: Task Brief
```

**Field descriptions:**

- `task_id`: Always `describe-task`.
- `description`: The full user-provided problem description (no issue ID; free text).
- `repo_root`: Absolute path to the repository root.
- `context_overrides`: Optional clarifications from the user, comma-separated: e.g., `type=Bug, criteria=Should log retries, area=api/http.go`. Omit if empty.
- `return_format`: Always `Task Brief`.

**When you receive ASSIGN_DESCRIBE,** skip Steps 1–3 (repository detection, backlog scanning, candidate selection) and proceed directly to **Step 4 codebase research**, then **Step 5 brief production**. See "Your Task" section below for the modified workflow.

---

## Your Task

**Determine the workflow:** If the envelope is `ASSIGN_RESEARCH`, execute the five-step workflow below (Steps 1–5). If the envelope is `ASSIGN_DESCRIBE`, skip to Step 4 below (codebase research), then Step 5 (brief production).

Produce exactly one Task Brief (or three, if `user_args` in ASSIGN_RESEARCH contains "shortlist").

### Step 1 — Determine the Repository

Run:
```bash
git remote get-url origin
```

Parse the output to extract the `owner/repo` slug. If no origin is present (local repo), check for a `.github/` directory or `package.json` `repository` field.

**If `context_overrides` includes a local issue path**, use that instead: parse the absolute path and skip to Step 2 (local mode).

### Step 2 — Fetch Open Issues, Scan TODOs, and Cache Unpushed Commits

Run these two scripts first and cache their output:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/git-unpushed-local.sh <REPO_ROOT>
bash ${CLAUDE_SKILL_DIR}/scripts/git-commit-closures.sh <REPO_ROOT>
```

From `git-commit-closures.sh`, you'll get output like `<short-sha> #<issue-number>` — cache this list as **closed-by-local** (issues already being fixed by local unpushed commits).

**GitHub issues:** Search for open issues with these filters:
- State: `open`
- Label exclusions: `future`, `wontfix`, `blocked`, `on-hold`, `do-not-implement`
- Assignee: Unassigned or assigned to current user
- Sort: `created` ascending (oldest first)

Fetch in batches of 10; stop at ~10–20 candidates.

**Local issues (if `context_overrides` specified a local path):** List files in `{path}/open/`:
```bash
find {path}/open -name "*.md" -type f | sort -n
```

For each `.md` file, parse:
- **Number:** filename (e.g., `0042.md` → issue #42)
- **Title:** first line (usually `# NNNN: Title`)
- **Labels:** lines matching `**Label:** <label>` (can be multiple)
- **Assignee:** line matching `**Assignee:** <username>` (optional)
- **Body:** content between title and `## Comments` section
- **Comments:** content under `## Comments` (if present)

**Inline TODOs (ASSIGN_RESEARCH only):** Skip this entire section for ASSIGN_DESCRIBE tasks — the user has described the work directly, so TODO discovery is irrelevant. For ASSIGN_RESEARCH, sample files with code-aware grep to detect numeric tracking codes:

```bash
grep -rn "TODO-[0-9]\+\|FIXME-[0-9]\+\|HACK-[0-9]\+\|XXX-[0-9]\+" --include="*.ts" --include="*.js" --include="*.py" --include="*.go" --include="*.rs" --include="*.java" --include="*.rb" --include="*.cs" --include="*.cpp" --include="*.c" --include="*.md" <REPO_ROOT> 2>/dev/null | grep -v node_modules | grep -v \.git | grep -v dist | grep -v build
```

Extract: file/line, full comment text, tracking code (canonical ID or `<TYPE>@<file>:<line>`), linked issue (if `#N` or URL present), category (`FIXME`=bug, `TODO`=feature, `HACK`=debt, `XXX`=critical). Group duplicates. Skip TODOs in generated/vendored directories, pure documentation notes, or already tracked in GitHub candidate list.

### Step 3 — Score and Select Candidates

**Shortlist mode:** If `user_args` contains "shortlist", "top N", "options", or "give me choices", skip to Step 3b (return top 3). Otherwise, proceed with auto-select below.

#### Step 3a — Auto-Select Ranking

Disqualify candidates matching any:

| Criterion | Action |
|-----------|--------|
| Labeled `future`, `blocked`, `on-hold`, `wontfix`, or `do-not-implement` | Skip |
| "blocked by #N", "depends on #N", etc. in body/comments, AND blocking work not in local commits | Skip |
| Assignee is not current user (for unassigned, assume current user can work) | Skip |
| Title contains "track", "umbrella", "meta", "epic" (meta-issue) | Skip |
| Labeled `question` or `discussion` | Skip |
| Marked `duplicate` | Skip |
| Issue number appears in **closed-by-local** list | Skip |

**Do NOT skip** issues requiring user action for prerequisite artifacts (e.g., reproduction steps). Only skip if genuinely blocked on non-existent code.

Rank survivors using **type × effort** matrix:

**Type** (bugs → chores → enhancements):
- **Bug:** label `bug`/`regression`; TODO `FIXME`/`XXX`; title "crash", "broken", "error", "fail"
- **Chore:** label `chore`, `maintenance`, `refactor`, `tech-debt`, `debt`; TODO `HACK`; title "cleanup", "remove", "update dependency"
- **Enhancement:** label `enhancement`/`feature`; TODO `TODO`; other

**Effort** (small → large, within same type):
- **Small:** label `good first issue`/`easy`; issue ≤200 words + clear criteria; single self-contained TODO; one-file change
- **Medium:** no strong signal (default)
- **Large:** label `epic` (non-meta), `large`, `complex`; issue >500 words or multiple sub-tasks; TODO references multiple files/systems

**Selection order** (pick first cell with survivor):

| | Small | Medium | Large |
|---|---|---|---|
| **Bug** | 1st | 2nd | 3rd |
| **Chore** | 4th | 5th | 6th |
| **Enhancement** | 7th | 8th | last |

Prefer oldest item within each cell (lowest issue #, earliest TODO position).

Select the top-ranked candidate. Proceed to Step 4.

#### Step 3b — Shortlist (Return Top 3)

Rank all candidates using the same type × effort matrix. Return the top 3 (one per cell, if available). Proceed to Step 5 and generate three Task Briefs instead of one.

### Step 4 — Research the Codebase

**For ASSIGN_RESEARCH (selected backlog issue):**
Use the selected candidate's issue text and identifiers.

**For ASSIGN_DESCRIBE (user description):**
Use the user's description and any context_overrides to extract search terms and entry point hints.

**area= fast-path (ASSIGN_DESCRIBE only):** If `context_overrides` contains `area=<path>`, activate the fast-path:
- Determine whether `<path>` is a file or a directory/prefix:
  - If it resolves to a file: scope all file reads to that file only; skip broad grep and find sweeps.
  - If it resolves to a directory or partial path prefix: scope `grep -rn` and `find` to that subtree only; skip broad codebase sweeps.
- Also read test counterparts for the area (e.g., files matching `*_test.*`, `*.test.*`, or `test/` siblings of the area path).
- Skip substep 4 (git log) entirely — the area path is already targeted; no broad git history sweep is needed.
- Skip substep 6 (closed-issue/PR search) entirely.
- After reading the specified files and their test counterparts, skip substeps 1–6 and proceed directly to Step 5.
- Normal ASSIGN_RESEARCH flow (no area= hint) is unchanged.
- Normal ASSIGN_DESCRIBE without area= hint is unchanged.

**For both workflows (no area= fast-path):**

1. Extract search terms — nouns, module names, action verbs, and any location hints from the description or issue text.
2. Search the codebase using extracted terms:
   - Use `grep -rn "<term>"` to find function names, class names, config keys
   - Use `find` to locate relevant files by name (e.g., `find . -name "*http*" -type f`)
3. Read likely files and identify:
   - Entry points (public functions, API endpoints, CLI commands that relate to the work)
   - Data models (structs, interfaces, types involved)
   - Existing tests (test files that cover the relevant code)
4. For the 3 most relevant key files (entry point, primary data model, and test file), run `git log --oneline -5 -- <file>` to understand recent changes. Do not run git log for more than 3 files.
5. Use the cached output from Step 2 to summarize any unpushed local commits related to this issue. Do not re-run git-unpushed-local.sh or git-commit-closures.sh.
6. Search closed issues/PRs for prior attempts on the same topic, using the same search terms extracted in substep 1. Fetch at most 5 results; read only the title and first 200 characters of the body for each.

### Step 5 — Produce the Task Brief

**Before producing the brief:** If this is an ASSIGN_DESCRIBE request and no issue ID was provided, synthesize one:
- Convert the user's description to kebab-case using the first 6 words (lowercase, non-alpha → `-`)
- Prefix with `DESCRIBE-`
- Example: "add retry logic to API calls" → `DESCRIBE-add-retry-logic-to-api`

Output exactly one Task Brief in the v1 format (see below). If shortlist mode (ASSIGN_RESEARCH only), output three briefs. This is your only output — no preamble, commentary, or recommendations.

#### Task Brief v1 Format

```markdown
## Task Brief

**Issue:** #<N> | TODO-<NNNN> | TODO@<file>:<line> | DESCRIBE-<slug>
**Title:** <issue title, TODO summary, or description (first sentence)>
**Type:** Bug | Chore | Enhancement
**Effort:** Small | Medium | Large
**URL/Location:** <GitHub issue URL or workspace-relative file path>

### Issue text

<Full issue body or TODO comment. For GitHub issues: complete body plus any relevant comments. For TODOs: the comment text and ~50 lines of surrounding context.>

### Acceptance criteria

- <criterion 1>
- <criterion 2>
- …

### Relevant files

<Workspace-relative paths, one per line. Format: `path/to/file` — brief description.
Include line ranges where known: `path/to/file:L10-L40`. Most important files first.>

### Research notes

- **Entry points:** <where to start in the code — file:line if known>
- **Data models:** <relevant types, interfaces, or data structures>
- **Tests:** <existing test file path(s) and coverage status>
- **Recent changes:** <git log summary for affected files — last 5 commits>
- **Local work:** <any unpushed commits related to this issue; "none" if clean>

### Risks and unknowns

- <ambiguity, potential side effect, or gap in spec>
- …

### Prerequisites (if any)

<User actions required before implementation can begin. Omit section entirely if none.>
```

---

## Response Format: Task Brief

After completing the five steps above, first acknowledge the task, then return the Task Brief.

**Acknowledge with CLAIM before starting work:**

```
CLAIM
task_id: <id>
```

### RESULT envelope (new — preferred)

Return the Task Brief using the unified RESULT envelope:

```
RESULT
task_id: <id from the incoming envelope: load-task or describe-task>
agent: researcher
status: success
result_type: Task Brief
```

Followed immediately by the Task Brief block(s).

**Example:**

```
RESULT
task_id: load-task
agent: researcher
status: success
result_type: Task Brief

## Task Brief

**Issue:** 0042
**Title:** Add retry logic to HTTP client
**Type:** Enhancement
**Effort:** Small
...
```

### TASK_DONE (transition period — still valid)

The legacy format remains accepted by the orchestrator during the transition period (see Issue 0083 for deprecation timeline):

```
TASK_DONE
task_id: <id from the incoming envelope: load-task or describe-task>
result_block: Task Brief
```

Followed immediately by the Task Brief block(s).

The orchestrator will validate required fields and emit the brief to the user.

If research cannot be attempted (no backlog, inaccessible repo, malformed envelope), see [failure.md](references/failure.md).

Full protocol contract: `orchestrator-protocol`.
