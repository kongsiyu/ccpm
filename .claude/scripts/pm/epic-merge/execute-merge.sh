#!/bin/bash
# Execute the epic merge operation

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

# Return to main repository (assume we're in a worktree)
cd "$(git rev-parse --show-superproject-working-tree)" || cd "../$(basename "$(pwd)" | sed 's/^epic-//')" || exit 1

# Ensure main is up to date
git checkout main
git pull origin main

# Generate feature list
feature_list=""
if [ -d ".claude/epics/$ARGUMENTS" ]; then
  cd ".claude/epics/$ARGUMENTS" || exit 1
  for task_file in [0-9]*.md; do
    [ -f "$task_file" ] || continue
    task_name=$(grep '^name:' "$task_file" | cut -d: -f2 | sed 's/^ *//')
    feature_list="$feature_list\n- $task_name"
  done
  cd - > /dev/null
fi

# Extract epic issue number
epic_issue=""
epic_github_line=$(grep 'github:' ".claude/epics/$ARGUMENTS/epic.md" 2>/dev/null || true)
if [ -n "$epic_github_line" ]; then
  epic_issue=$(echo "$epic_github_line" | grep -oE '[0-9]+' || true)
fi

# Build commit message
commit_message="Merge epic: $ARGUMENTS

Completed features:$feature_list"

if [ -n "$epic_issue" ]; then
  commit_message="$commit_message

Closes epic #$epic_issue"
fi

# Attempt merge
echo "Merging epic/$ARGUMENTS to main..."
git merge "epic/$ARGUMENTS" --no-ff -m "$commit_message"

if [ $? -eq 0 ]; then
  echo "✅ Merge completed successfully"
else
  echo "❌ Merge failed - conflicts detected"
  exit 1
fi