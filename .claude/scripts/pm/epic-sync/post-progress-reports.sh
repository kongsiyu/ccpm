#!/bin/bash
# Post progress reports and manage issue states
set -e

EPIC_NAME="$1"

if [ -z "$EPIC_NAME" ]; then
  echo "Usage: $0 <epic_name>"
  exit 1
fi

echo "📊 Posting progress reports and managing issue states..."

# Calculate current epic progress
total_tasks=$(ls ".claude/epics/$EPIC_NAME"/[0-9]*.md 2>/dev/null | wc -l)
closed_tasks=$(grep -l '^status: closed' ".claude/epics/$EPIC_NAME"/[0-9]*.md 2>/dev/null | wc -l)

if [ "$total_tasks" -gt 0 ]; then
  progress=$((closed_tasks * 100 / total_tasks))
else
  progress=0
fi

# Save progress for other scripts
echo "$progress" > /tmp/epic-sync/progress.txt
echo "$total_tasks" > /tmp/epic-sync/total-tasks.txt
echo "$closed_tasks" > /tmp/epic-sync/closed-tasks.txt

# Process status checks and progress updates
grep "^check_status:" /tmp/epic-sync/sync-actions.txt 2>/dev/null | while IFS=: read action item_type issue_num local_status; do
  if [ "$item_type" = "task" ]; then
    # Get current GitHub issue state
    gh_state=$(gh issue view "$issue_num" --json state -q .state)
    
    # Post progress comment
    current_date=$(date -u +"%Y-%m-%d %H:%M UTC")
    
    progress_comment="## 📊 Sync Update - $current_date

**Local Status:** $local_status
**Epic Progress:** $closed_tasks/$total_tasks tasks completed ($progress%)

---
*Updated via epic sync*"
    
    echo "$progress_comment" | gh issue comment "$issue_num" --body-file -
    
    # Manage issue state based on local status
    if [ "$local_status" = "closed" ] && [ "$gh_state" = "open" ]; then
      gh issue close "$issue_num" -c "🎯 Task completed - closing via sync

Epic Progress: $closed_tasks/$total_tasks tasks completed ($progress%)"
      echo "✅ Closed GitHub issue #$issue_num (task completed)"
      
    elif [ "$local_status" = "open" ] && [ "$gh_state" = "closed" ]; then
      gh issue reopen "$issue_num" -c "🔄 Task reopened - syncing status

Epic Progress: $closed_tasks/$total_tasks tasks completed ($progress%)"
      echo "🔄 Reopened GitHub issue #$issue_num (task reopened)"
    else
      echo "📝 Posted progress update to issue #$issue_num"
    fi
  fi
done

# Update epic progress if epic exists
epic_number=$(cat /tmp/epic-sync/epic-number.txt 2>/dev/null || true)
if [ -n "$epic_number" ]; then
  echo "📈 Updating epic progress..."
  
  # Update epic frontmatter
  current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  epic_file=".claude/epics/$EPIC_NAME/epic.md"
  
  sed -i.bak "/^progress:/c\\progress: ${progress}%" "$epic_file"
  sed -i.bak "/^updated:/c\\updated: $current_date" "$epic_file"
  rm "${epic_file}.bak"
  
  # Post epic progress comment
  epic_comment="## 📈 Epic Progress Update - $(date -u +"%Y-%m-%d %H:%M UTC")

**Progress:** $closed_tasks/$total_tasks tasks completed (**$progress%**)

### Task Status:
$(for task_file in ".claude/epics/$EPIC_NAME"/[0-9]*.md; do
  [ -f "$task_file" ] || continue
  task_num=$(basename "$task_file" .md)
  task_name=$(grep '^name:' "$task_file" | sed 's/^name: *//')
  task_status=$(grep '^status:' "$task_file" | sed 's/^status: *//')
  if [ "$task_status" = "closed" ]; then
    echo "- ✅ #$task_num - $task_name"
  else
    echo "- ⬜ #$task_num - $task_name"
  fi
done)

---
*Updated via bidirectional epic sync*"
  
  echo "$epic_comment" | gh issue comment "$epic_number" --body-file -
  echo "📊 Posted epic progress update to issue #$epic_number"
  
  # Close epic if 100% complete
  if [ "$progress" -eq 100 ]; then
    epic_state=$(gh issue view "$epic_number" --json state -q .state)
    if [ "$epic_state" = "open" ]; then
      gh issue close "$epic_number" -c "🎉 Epic completed! All tasks finished.

Final Status: $closed_tasks/$total_tasks tasks completed (100%)"
      echo "🎉 Closed epic issue #$epic_number (100% complete)"
    fi
  fi
fi

exit 0