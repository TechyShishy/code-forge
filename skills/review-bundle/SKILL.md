---
name: review-bundle
description: Generate a pre-computed review context bundle containing all changed files, test counterparts, and hook outputs. Invoke before the reviewer to eliminate discovery tool calls.
---

Generate the review bundle now:

```!
~/.claude/skills/review-bundle/bundle.sh
```

Bundle contents:

```!
cat "$(git rev-parse --git-dir 2>/dev/null)/claude-scratch/review-bundle.md" 2>/dev/null \
  || echo "[review-bundle] Bundle unavailable — not in a git repo or bundle generation failed"
```
