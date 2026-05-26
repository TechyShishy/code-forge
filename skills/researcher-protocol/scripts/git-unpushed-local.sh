#!/usr/bin/env bash
# Lists unpushed local commits (one-line format)
# Usage: git-unpushed-local.sh [repo-root]
set -euo pipefail
repo="${1:-.}"
branch="$(git -C "$repo" rev-parse --abbrev-ref HEAD)"
git -C "$repo" log "origin/${branch}..HEAD" --oneline
