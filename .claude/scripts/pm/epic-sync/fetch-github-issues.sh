#!/bin/bash
# Fetch all GitHub issues for an epic
set -e

EPIC_NAME="$1"
REPO="$2"

if [ -z "$EPIC_NAME" ] || [ -z "$REPO" ]; then
  echo "Usage: $0 <epic_name> <repo>"
  exit 1
fi

echo "📥 Fetching GitHub issues for epic: $EPIC_NAME"

# Create work directory
mkdir -p /tmp/epic-sync
> /tmp/epic-sync/github-issues.json

# Get epic issue if it exists
epic_github_url=$(grep '^github:' ".claude/epics/$EPIC_NAME/epic.md" 2>/dev/null | sed 's/^github: *//' || true)
if [ -n "$epic_github_url" ]; then
  epic_number=$(echo "$epic_github_url" | grep -oE '[0-9]+$')
  echo "📋 Found epic issue: #$epic_number"
  
  # Fetch epic issue data
  if gh issue view "$epic_number" --json number,title,body,state,updatedAt 2>/dev/null; then
    gh issue view "$epic_number" --json number,title,body,state,updatedAt > /tmp/epic-sync/epic-issue.json
    echo "epic:$epic_number" >> /tmp/epic-sync/github-issues.json
    echo "$epic_number" > /tmp/epic-sync/epic-number.txt
  else
    echo "⚠️  Epic issue #$epic_number no longer exists on GitHub"
    echo "" > /tmp/epic-sync/epic-number.txt
  fi
else
  echo "📝 No existing epic issue found"
  echo "" > /tmp/epic-sync/epic-number.txt
fi

# Find all task issues by searching for epic label
echo "🔍 Searching for task issues with label 'epic:$EPIC_NAME'..."
gh issue list --repo "$REPO" --label "epic:$EPIC_NAME" --label "task" --state all --limit 100 \
  --json number,title,body,state,updatedAt > /tmp/epic-sync/task-issues.json

# Extract issue numbers for reference
jq -r '.[].number' /tmp/epic-sync/task-issues.json | while read issue_num; do
  echo "task:$issue_num" >> /tmp/epic-sync/github-issues.json
done

task_issue_count=$(jq length /tmp/epic-sync/task-issues.json)
echo "📊 Found $task_issue_count task issues on GitHub"

exit 0