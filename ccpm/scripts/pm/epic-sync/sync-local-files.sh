#!/bin/bash
# Update local files from GitHub data
set -e

EPIC_NAME="$1"

if [ -z "$EPIC_NAME" ]; then
  echo "Usage: $0 <epic_name>"
  exit 1
fi

echo "📥 Syncing local files from GitHub..."

# Update local files from GitHub data
grep "^update_local:" /tmp/epic-sync/sync-actions.txt 2>/dev/null | while IFS=: read action item_type issue_num; do
  echo "📥 Updating local $item_type from GitHub issue #$issue_num..."
  
  if [ "$item_type" = "epic" ]; then
    # Update epic.md from GitHub issue
    gh issue view "$issue_num" --json title,body,updatedAt > /tmp/epic-sync/current-issue.json
    
    gh_title=$(jq -r '.title' /tmp/epic-sync/current-issue.json)
    gh_body=$(jq -r '.body' /tmp/epic-sync/current-issue.json)
    gh_updated=$(jq -r '.updatedAt' /tmp/epic-sync/current-issue.json)
    
    # Read current frontmatter
    epic_file=".claude/epics/$EPIC_NAME/epic.md"
    
    # Update frontmatter timestamp and keep body from GitHub
    sed -i.bak "/^updated:/c\\updated: $gh_updated" "$epic_file"
    
    # Replace body content (preserve frontmatter)
    awk '
      BEGIN { in_frontmatter = 0; frontmatter_count = 0 }
      /^---$/ { 
        frontmatter_count++
        print
        if (frontmatter_count == 2) in_frontmatter = 0
        else in_frontmatter = 1
        next
      }
      in_frontmatter { print }
      !in_frontmatter && frontmatter_count < 2 { print }
      !in_frontmatter && frontmatter_count >= 2 { exit }
    ' "$epic_file" > /tmp/epic-sync/new-epic.md
    
    echo "" >> /tmp/epic-sync/new-epic.md
    echo "$gh_body" >> /tmp/epic-sync/new-epic.md
    
    mv /tmp/epic-sync/new-epic.md "$epic_file"
    rm "${epic_file}.bak"
    
    echo "✅ Updated epic.md from GitHub"
    
  elif [ "$item_type" = "task" ]; then
    # Update task file from GitHub issue
    gh issue view "$issue_num" --json title,body,state,updatedAt > /tmp/epic-sync/current-issue.json
    
    gh_title=$(jq -r '.title' /tmp/epic-sync/current-issue.json)
    gh_body=$(jq -r '.body' /tmp/epic-sync/current-issue.json)
    gh_state=$(jq -r '.state' /tmp/epic-sync/current-issue.json)
    gh_updated=$(jq -r '.updatedAt' /tmp/epic-sync/current-issue.json)
    
    # Convert GitHub state to local status
    if [ "$gh_state" = "closed" ]; then
      local_status="closed"
    else
      local_status="open"
    fi
    
    # Find or create task file
    task_file=".claude/epics/$EPIC_NAME/${issue_num}.md"
    
    if [ -f "$task_file" ]; then
      # Update existing file
      sed -i.bak "/^name:/c\\name: $gh_title" "$task_file"
      sed -i.bak "/^status:/c\\status: $local_status" "$task_file"
      sed -i.bak "/^updated:/c\\updated: $gh_updated" "$task_file"
      
      # Update body content (preserve frontmatter)
      awk '
        BEGIN { in_frontmatter = 0; frontmatter_count = 0 }
        /^---$/ { 
          frontmatter_count++
          print
          if (frontmatter_count == 2) in_frontmatter = 0
          else in_frontmatter = 1
          next
        }
        in_frontmatter { print }
        !in_frontmatter && frontmatter_count < 2 { print }
        !in_frontmatter && frontmatter_count >= 2 { exit }
      ' "$task_file" > /tmp/epic-sync/new-task.md
      
      echo "" >> /tmp/epic-sync/new-task.md
      echo "$gh_body" >> /tmp/epic-sync/new-task.md
      
      mv /tmp/epic-sync/new-task.md "$task_file"
      rm "${task_file}.bak"
    fi
    
    echo "✅ Updated task ${issue_num}.md from GitHub"
  fi
done

# Create local files from GitHub issues that don't exist locally
grep "^create_local:" /tmp/epic-sync/sync-actions.txt 2>/dev/null | while IFS=: read action item_type issue_num; do
  echo "📁 Creating local $item_type file from GitHub issue #$issue_num..."
  
  if [ "$item_type" = "task" ]; then
    gh issue view "$issue_num" --json title,body,state,updatedAt,labels > /tmp/epic-sync/current-issue.json
    
    gh_title=$(jq -r '.title' /tmp/epic-sync/current-issue.json)
    gh_body=$(jq -r '.body' /tmp/epic-sync/current-issue.json)
    gh_state=$(jq -r '.state' /tmp/epic-sync/current-issue.json)
    gh_updated=$(jq -r '.updatedAt' /tmp/epic-sync/current-issue.json)
    
    # Convert GitHub state to local status
    if [ "$gh_state" = "closed" ]; then
      local_status="closed"
    else
      local_status="open"
    fi
    
    # Create new task file
    task_file=".claude/epics/$EPIC_NAME/${issue_num}.md"
    current_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    
    cat > "$task_file" << EOF
---
name: $gh_title
status: $local_status
parallel: false
depends_on: []
conflicts_with: []
github: https://github.com/$repo/issues/$issue_num
created: $current_date
updated: $gh_updated
---

$gh_body
EOF
    
    echo "✅ Created task file: ${issue_num}.md"
  fi
done

exit 0