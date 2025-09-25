#!/bin/bash
# Preflight checks before starting an epic

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

# 1. Verify epic exists
if ! test -f ".claude/epics/$ARGUMENTS/epic.md"; then
  echo "❌ Epic not found. Run: /pm:prd-parse $ARGUMENTS"
  exit 1
fi

# 2. Check GitHub sync (look for github: field)
if ! grep -q "^github:" ".claude/epics/$ARGUMENTS/epic.md"; then
  echo "❌ Epic not synced. Run: /pm:epic-sync $ARGUMENTS first"
  exit 1
fi

# 3. Check for branch
if ! git branch -a | grep -q "epic/$ARGUMENTS"; then
  echo "ℹ️ Branch epic/$ARGUMENTS does not exist - will be created"
fi

# 4. Check for uncommitted changes
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ You have uncommitted changes. Please commit or stash them before starting an epic."
  exit 1
fi

echo "✅ Preflight checks passed for epic: $ARGUMENTS"