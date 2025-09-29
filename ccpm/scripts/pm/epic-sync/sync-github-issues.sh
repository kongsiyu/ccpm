#!/bin/bash
# Update GitHub issues from local data
set -e

EPIC_NAME="$1"
REPO="$2"
USE_SUBISSUES="$3"

if [ -z "$EPIC_NAME" ] || [ -z "$REPO" ]; then
  echo "Usage: $0 <epic_name> <repo> [use_subissues]"
  exit 1
fi

echo "📤 Syncing GitHub issues from local data..."

# Get epic number from previous steps
epic_number=$(cat /tmp/epic-sync/epic-number.txt 2>/dev/null || true)

# Update GitHub issues from local data
grep "^update_github:" /tmp/epic-sync/sync-actions.txt 2>/dev/null | while IFS=: read action item_type issue_num local_status; do
  echo "📤 Updating GitHub issue #$issue_num from local $item_type..."
  
  if [ "$item_type" = "epic" ]; then
    # Update epic issue from epic.md
    epic_file=".claude/epics/$EPIC_NAME/epic.md"
    
    # Extract title and body (strip frontmatter)
    epic_title="Epic: $EPIC_NAME"
    sed '1,/^---$/d; 1,/^---$/d' "$epic_file" > /tmp/epic-sync/epic-body.md
    
    # Update GitHub issue
    gh issue edit "$issue_num" \
      --title "$epic_title" \
      --body-file /tmp/epic-sync/epic-body.md
    
    echo "✅ Updated GitHub epic issue #$issue_num"
    
  elif [ "$item_type" = "task" ]; then
    # Update task issue from task file
    task_file=".claude/epics/$EPIC_NAME/${issue_num}.md"
    
    if [ -f "$task_file" ]; then
      task_title=$(grep '^name:' "$task_file" | sed 's/^name: *//')
      
      # Strip frontmatter for body
      sed '1,/^---$/d; 1,/^---$/d' "$task_file" > /tmp/epic-sync/task-body.md
      
      # Update GitHub issue content
      gh issue edit "$issue_num" \
        --title "$task_title" \
        --body-file /tmp/epic-sync/task-body.md
      
      echo "✅ Updated GitHub task issue #$issue_num"
    fi
  fi
done

# Create GitHub issues from local files that don't have issues
grep "^create_github:" /tmp/epic-sync/sync-actions.txt 2>/dev/null | while IFS=: read action item_type file_id local_status; do
  echo "🆕 Creating GitHub issue from local $item_type..."
  
  if [ "$item_type" = "epic" ]; then
    # Create epic issue from epic.md
    epic_file=".claude/epics/$EPIC_NAME/epic.md"
    epic_title="Epic: $EPIC_NAME"
    
    # Strip frontmatter for body
    sed '1,/^---$/d; 1,/^---$/d' "$epic_file" > /tmp/epic-sync/epic-body.md
    
    # Determine epic type from content
    if grep -qi "bug\\|fix\\|issue\\|problem\\|error" /tmp/epic-sync/epic-body.md; then
      epic_type="bug"
    else
      epic_type="feature"
    fi
    
    # Create epic issue
    new_epic_number=$(gh issue create \
      --repo "$REPO" \
      --title "$epic_title" \
      --body-file /tmp/epic-sync/epic-body.md \
      --label "epic,epic:$EPIC_NAME,$epic_type" \
      --json number -q .number)
    
    # Update epic.md with GitHub URL
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    epic_url="https://github.com/$repo/issues/$new_epic_number"
    current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    sed -i.bak "/^github:/c\\github: $epic_url" "$epic_file"
    sed -i.bak "/^updated:/c\\updated: $current_date" "$epic_file"
    rm "${epic_file}.bak"
    
    # Update epic number for later scripts
    echo "$new_epic_number" > /tmp/epic-sync/epic-number.txt
    
    echo "✅ Created GitHub epic issue #$new_epic_number"
    
  elif [ "$item_type" = "task" ]; then
    # Create task issue from task file
    task_file=".claude/epics/$EPIC_NAME/${file_id}.md"
    
    if [ -f "$task_file" ]; then
      task_title=$(grep '^name:' "$task_file" | sed 's/^name: *//')
      task_status=$(grep '^status:' "$task_file" | sed 's/^status: *//')
      
      # Strip frontmatter for body
      sed '1,/^---$/d; 1,/^---$/d' "$task_file" > /tmp/epic-sync/task-body.md
      
      # Get current epic number
      current_epic_number=$(cat /tmp/epic-sync/epic-number.txt 2>/dev/null || true)
      
      # Create task issue (with sub-issue support if available)
      if [ "$USE_SUBISSUES" = "true" ] && [ -n "$current_epic_number" ]; then
        task_number=$(gh sub-issue create \
          --parent "$current_epic_number" \
          --title "$task_title" \
          --body-file /tmp/epic-sync/task-body.md \
          --label "task,epic:$EPIC_NAME" \
          --json number -q .number)
      else
        task_number=$(gh issue create \
          --repo "$REPO" \
          --title "$task_title" \
          --body-file /tmp/epic-sync/task-body.md \
          --label "task,epic:$EPIC_NAME" \
          --json number -q .number)
      fi
      
      # Update task file with GitHub URL and rename if needed
      repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
      task_url="https://github.com/$repo/issues/$task_number"
      current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
      
      # Create new filename based on issue number
      new_task_file=".claude/epics/$EPIC_NAME/${task_number}.md"
      
      # Update frontmatter
      sed "/^github:/c\\github: $task_url" "$task_file" | \
      sed "/^updated:/c\\updated: $current_date" > "$new_task_file"
      
      # Remove old file if different name
      [ "$task_file" != "$new_task_file" ] && rm "$task_file"
      
      # Close issue immediately if status is closed
      if [ "$task_status" = "closed" ]; then
        gh issue close "$task_number" -c "Task completed - closed during sync"
      fi
      
      echo "✅ Created GitHub task issue #$task_number (renamed to $(basename "$new_task_file"))"
    fi
  fi
done

exit 0