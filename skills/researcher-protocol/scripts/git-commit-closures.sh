#!/usr/bin/env bash
# Scans local (unpushed) commits for closing keywords and emits a parsable list.
# Output format: one entry per line — <short-sha> <issue-ref>
# Usage: git-commit-closures.sh [repo-root]
set -euo pipefail

repo="${1:-.}"
branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0

# Collect full commit messages for unpushed commits
git -C "$repo" log "origin/${branch}..HEAD" --format="%h %s%n%b" 2>/dev/null \
  | awk '
    # Track the current short SHA (appears at start of subject line)
    /^[0-9a-f]{7,}[[:space:]]/ {
      sha = $1
    }
    # Match closing keywords followed by an issue reference
    {
      line = $0
      while (match(line, /[Ff]ix(es|ed)?[[:space:]]+#([0-9]+)|[Cc]los(es|ed)?[[:space:]]+#([0-9]+)|[Rr]esolv(es|ed)?[[:space:]]+#([0-9]+)/)) {
        token = substr(line, RSTART, RLENGTH)
        if (match(token, /#([0-9]+)/)) {
          issue = substr(token, RSTART, RLENGTH)
          print sha " " issue
        }
        line = substr(line, RSTART + RLENGTH)
      }
    }
  '
