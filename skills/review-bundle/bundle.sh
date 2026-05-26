#!/usr/bin/env bash
# Generate a pre-computed review context bundle for the reviewer.
# Outputs bundle to stdout. Safe to run in any directory: no-ops cleanly outside git repos.

set -euo pipefail

MAX_FILE_BYTES=10240   # 10KB cap per source file
MAX_DIFF_BYTES=61440   # 60KB cap on staged diff

if ! GIT_DIR=$(git rev-parse --git-dir 2>/dev/null); then
  echo "[review-bundle] Not in a git repo — skipping"
  exit 0
fi

SCRATCH="${GIT_DIR}/claude-scratch"

# ── Collect changed files ────────────────────────────────────────────────────
# Scope cascade: staged → unstaged → unpushed → clean

STAGED_FILES=$(git diff --staged --name-only 2>/dev/null || true)
if [[ -n "$STAGED_FILES" ]]; then
  ALL_CHANGED="$STAGED_FILES"
  DIFF_SOURCE="staged"
else
  HEAD_FILES=$(git diff HEAD --name-only 2>/dev/null || true)
  if [[ -n "$HEAD_FILES" ]]; then
    ALL_CHANGED="$HEAD_FILES"
    DIFF_SOURCE="head"
  else
    BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"
    UNPUSHED=$(git log "origin/${BRANCH}..HEAD" --name-only --pretty=format: 2>/dev/null \
      | sort -u | grep -v '^$' || true)
    if [[ -n "$UNPUSHED" ]]; then
      ALL_CHANGED="$UNPUSHED"
      DIFF_SOURCE="unpushed"
    else
      ALL_CHANGED=""
    fi
  fi
fi

if [[ -z "$ALL_CHANGED" ]]; then
  echo "# Review Bundle"
  echo ""
  echo "_No changed files — working tree and staging area are clean. Nothing to review._"
  exit 0
fi

# ── Test-file resolution ─────────────────────────────────────────────────────
# Port of the resolution logic from post-edit-test-runner.sh

find_ts_test() {
  local dir="$1" name="$2" ext="$3"
  for cand in "${dir}/${name}.spec.${ext}" "${dir}/${name}.test.${ext}"; do
    [[ -f "$cand" ]] && echo "$cand" && return 0
  done
  local pkg="$dir"
  while [[ "$pkg" != "/" && "$pkg" != "." ]]; do
    [[ -f "${pkg}/package.json" ]] && break
    pkg="${pkg%/*}"
  done
  if [[ -f "${pkg}/package.json" ]]; then
    for tests_dir in "${pkg}/src/__tests__" "${pkg}/__tests__"; do
      for cand in \
          "${tests_dir}/${name}.test.${ext}" \
          "${tests_dir}/${name}.unit.test.${ext}" \
          "${tests_dir}/${name}.integration.test.${ext}"; do
        [[ -f "$cand" ]] && echo "$cand" && return 0
      done
    done
  fi
  return 1
}

find_kt_test() {
  local src="$1"
  local test="${src/\/src\/main\//\/src\/test\/}"
  test="${test%.*}Test.${src##*.}"
  [[ -f "$test" ]] && echo "$test" && return 0
  return 1
}

resolve_test_file() {
  local file="$1"
  local ext="${file##*.}"
  local base="${file##*/}"
  local name="${base%.*}"
  local dir="${file%/*}"
  [[ "$dir" == "$file" ]] && dir="."
  case "$ext" in
    ts|tsx|js|jsx|mjs|cjs)
      find_ts_test "$dir" "$name" "$ext" 2>/dev/null || true ;;
    kt|java)
      find_kt_test "$file" 2>/dev/null || true ;;
  esac
}

is_test_file() {
  local f="$1"
  case "$f" in
    *.spec.ts|*.spec.tsx|*.spec.js|*.spec.jsx) return 0 ;;
    *.test.ts|*.test.tsx|*.test.js|*.test.jsx) return 0 ;;
    *Test.kt|*Test.java|*Spec.kt|*Spec.java)  return 0 ;;
    */__tests__/*)                              return 0 ;;
  esac
  return 1
}

# ── Write bundle ─────────────────────────────────────────────────────────────

FILE_COUNT=$(echo "$ALL_CHANGED" | wc -l | tr -d ' ')

{
  echo "# Review Bundle"
  echo "Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  echo "Changed files: ${FILE_COUNT}"
  echo ""

  # ── Git context ──────────────────────────────────────────────────────────

  echo "## Git Context"
  echo ""

  echo "### Recent commits"
  echo '```'
  git log --oneline -5 2>/dev/null || echo "(no commits)"
  echo '```'
  echo ""

  echo "### Status"
  echo '```'
  git status --short 2>/dev/null || echo "(unavailable)"
  echo '```'
  echo ""

  case "$DIFF_SOURCE" in
    staged)
      DIFF=$(git diff --staged 2>/dev/null || true)
      echo "### Staged diff"
      ;;
    head)
      DIFF=$(git diff HEAD 2>/dev/null || true)
      echo "### Unstaged diff"
      ;;
    unpushed)
      BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")"
      DIFF=$(git diff "origin/${BRANCH}..HEAD" 2>/dev/null || true)
      echo "### Unpushed commits diff"
      ;;
  esac

  if [[ -z "$DIFF" ]]; then
    echo "_No changes in diff._"
  else
    DIFF_SIZE=${#DIFF}
    echo '```diff'
    if [[ $DIFF_SIZE -gt $MAX_DIFF_BYTES ]]; then
      printf '%s' "$DIFF" | head -c "$MAX_DIFF_BYTES"
      echo ""
      echo '```'
      echo ""
      echo "_[Diff truncated at 60KB — $((DIFF_SIZE / 1024))KB total]_"
    else
      printf '%s' "$DIFF"
      echo '```'
    fi
  fi
  echo ""

  # ── Changed file contents ─────────────────────────────────────────────────

  echo "## Changed Files (full content)"
  echo ""

  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    echo "### \`${file}\`"
    if [[ ! -f "$file" ]]; then
      echo "_[File deleted or not found]_"
      echo ""
      continue
    fi
    FILE_SIZE=$(wc -c < "$file" 2>/dev/null || echo 0)
    echo '```'
    if [[ $FILE_SIZE -gt $MAX_FILE_BYTES ]]; then
      head -c "$MAX_FILE_BYTES" "$file"
      echo ""
      echo '```'
      echo "_[Truncated at 10KB — $((FILE_SIZE / 1024))KB total]_"
    else
      cat "$file"
      echo '```'
    fi
    echo ""
  done <<< "$ALL_CHANGED"

  # ── Test counterparts ─────────────────────────────────────────────────────

  echo "## Test Counterparts"
  echo ""

  TEST_FILES_FOUND=0

  while IFS= read -r file; do
    [[ -z "$file" || ! -f "$file" ]] && continue
    is_test_file "$file" && continue   # skip test files themselves

    TEST_FILE=$(resolve_test_file "$file")
    [[ -z "$TEST_FILE" || ! -f "$TEST_FILE" ]] && continue

    TEST_FILES_FOUND=1
    echo "### \`${TEST_FILE}\` (counterpart for \`${file}\`)"
    TEST_SIZE=$(wc -c < "$TEST_FILE" 2>/dev/null || echo 0)
    echo '```'
    if [[ $TEST_SIZE -gt $MAX_FILE_BYTES ]]; then
      head -c "$MAX_FILE_BYTES" "$TEST_FILE"
      echo ""
      echo '```'
      echo "_[Truncated at 10KB — $((TEST_SIZE / 1024))KB total]_"
    else
      cat "$TEST_FILE"
      echo '```'
    fi
    echo ""
  done <<< "$ALL_CHANGED"

  if [[ $TEST_FILES_FOUND -eq 0 ]]; then
    echo "_No test counterparts found for changed source files._"
    echo ""
  fi

  # ── Hook outputs ─────────────────────────────────────────────────────────

  if [[ -f "${SCRATCH}/test-results.md" ]]; then
    echo "## Test Results (from post-edit hook)"
    echo ""
    cat "${SCRATCH}/test-results.md"
    echo ""
  fi

  if [[ -f "${SCRATCH}/git-context.md" ]]; then
    echo "## Git Context Supplement (from SessionStart hook)"
    echo ""
    cat "${SCRATCH}/git-context.md"
    echo ""
  fi

}
