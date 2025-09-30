#!/bin/bash
# Pre-merge validation for epic worktree

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

# Verify worktree exists
if ! git worktree list | grep -q "epic-$ARGUMENTS"; then
  echo "❌ No worktree for epic: $ARGUMENTS"
  exit 1
fi

# Navigate to worktree and check status
cd "../epic-$ARGUMENTS" || exit 1

# Check for uncommitted changes
if [[ $(git status --porcelain) ]]; then
  echo "⚠️ Uncommitted changes in worktree:"
  git status --short
  echo "Commit or stash changes before merging"
  exit 1
fi

# Check branch status
git fetch origin
git status -sb

echo "✅ Worktree validation passed for epic: $ARGUMENTS"