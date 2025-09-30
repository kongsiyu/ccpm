#!/bin/bash
# Create worktree and update mappings
set -e

EPIC_NAME="$1"

if [ -z "$EPIC_NAME" ]; then
  echo "Usage: $0 <epic_name>"
  exit 1
fi

echo "🌳 Ensuring worktree exists..."

# Check if worktree already exists
if git worktree list | grep -q "epic-$EPIC_NAME"; then
  echo "📁 Worktree already exists: ../epic-$EPIC_NAME"
else
  # Create worktree for epic
  git checkout main 2>/dev/null
  git pull origin main 2>/dev/null
  git worktree add "../epic-$EPIC_NAME" -b "epic/$EPIC_NAME" 2>/dev/null
  echo "✅ Created worktree: ../epic-$EPIC_NAME"
fi

# Update mapping file
echo "📋 Updating GitHub mapping file..."
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
epic_number=$(cat /tmp/epic-sync/epic-number.txt 2>/dev/null || echo "TBD")
progress=$(cat /tmp/epic-sync/progress.txt 2>/dev/null || echo "0")
total_tasks=$(cat /tmp/epic-sync/total-tasks.txt 2>/dev/null || echo "0")
closed_tasks=$(cat /tmp/epic-sync/closed-tasks.txt 2>/dev/null || echo "0")

cat > ".claude/epics/$EPIC_NAME/github-mapping.md" << EOF
# GitHub Issue Mapping - Epic: $EPIC_NAME

## Epic
- Epic: #${epic_number} - https://github.com/${repo}/issues/${epic_number}

## Tasks
EOF

for task_file in ".claude/epics/$EPIC_NAME"/[0-9]*.md; do
  [ -f "$task_file" ] || continue
  
  task_num=$(basename "$task_file" .md)
  task_name=$(grep '^name:' "$task_file" | sed 's/^name: *//')
  task_status=$(grep '^status:' "$task_file" | sed 's/^status: *//')
  
  if [ "$task_status" = "closed" ]; then
    status_icon="✅"
  else
    status_icon="⬜"
  fi
  
  echo "- $status_icon #${task_num} - $task_name - https://github.com/${repo}/issues/${task_num}" >> ".claude/epics/$EPIC_NAME/github-mapping.md"
done

cat >> ".claude/epics/$EPIC_NAME/github-mapping.md" << EOF

---
**Last Sync:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")  
**Progress:** $closed_tasks/$total_tasks tasks completed ($progress%)  
**Sync Mode:** Bidirectional (GitHub ↔ Local)
EOF

echo "✅ Updated GitHub mapping file"

exit 0