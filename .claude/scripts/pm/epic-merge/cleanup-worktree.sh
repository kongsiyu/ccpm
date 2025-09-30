#!/bin/bash
# Post-merge cleanup operations

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

# Push to remote
git push origin main

# Clean up worktree
git worktree remove "../epic-$ARGUMENTS"
echo "✅ Worktree removed: ../epic-$ARGUMENTS"

# Delete branch
git branch -d "epic/$ARGUMENTS"
git push origin --delete "epic/$ARGUMENTS" 2>/dev/null || true

# Archive epic locally
mkdir -p .claude/epics/archived/
mv ".claude/epics/$ARGUMENTS" ".claude/epics/archived/"
echo "✅ Epic archived: .claude/epics/archived/$ARGUMENTS"