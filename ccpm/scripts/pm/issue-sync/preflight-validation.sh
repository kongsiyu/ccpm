#!/bin/bash
# Preflight validation for issue sync

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Issue number required"
  exit 1
fi

# 1. GitHub Authentication
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ GitHub CLI not authenticated. Run: gh auth login"
  exit 1
fi

# 2. Issue Validation
if ! gh issue view "$ARGUMENTS" --json state >/dev/null 2>&1; then
  echo "❌ Issue #$ARGUMENTS not found"
  exit 1
fi

# Check issue state
issue_state=$(gh issue view "$ARGUMENTS" --json state --jq '.state')
if [ "$issue_state" = "CLOSED" ]; then
  echo "⚠️ Issue is closed but work incomplete"
fi

# 3. Local Updates Check
epic_found=""
for epic_dir in .claude/epics/*/; do
  if [ -d "${epic_dir}updates/$ARGUMENTS/" ]; then
    epic_found=$(basename "$epic_dir")
    break
  fi
done

if [ -z "$epic_found" ]; then
  echo "❌ No local updates found for issue #$ARGUMENTS. Run: /pm:issue-start $ARGUMENTS"
  exit 1
fi

if [ ! -f ".claude/epics/$epic_found/updates/$ARGUMENTS/progress.md" ]; then
  echo "❌ No progress tracking found. Initialize with: /pm:issue-start $ARGUMENTS"
  exit 1
fi

echo "✅ Preflight validation passed for issue #$ARGUMENTS"
echo "Epic: $epic_found"