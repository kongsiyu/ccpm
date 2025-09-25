#!/bin/bash
# Calculate and update epic progress based on completed tasks

EPIC_NAME="$1"
if [ -z "$EPIC_NAME" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

if [ ! -d ".claude/epics/$EPIC_NAME" ]; then
  echo "❌ Epic directory not found: $EPIC_NAME"
  exit 1
fi

# Count total tasks in epic directory
total_tasks=0
closed_tasks=0

for task_file in ".claude/epics/$EPIC_NAME"/[0-9]*.md; do
  [ -f "$task_file" ] || continue
  total_tasks=$((total_tasks + 1))
  
  # Check if task is closed
  status=$(grep '^status:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  if [ "$status" = "closed" ]; then
    closed_tasks=$((closed_tasks + 1))
  fi
done

if [ $total_tasks -eq 0 ]; then
  echo "ℹ️ No tasks found in epic: $EPIC_NAME"
  exit 0
fi

# Calculate progress percentage
progress=$((closed_tasks * 100 / total_tasks))

# Update epic frontmatter
epic_file=".claude/epics/$EPIC_NAME/epic.md"
if [ -f "$epic_file" ]; then
  # Extract current frontmatter values
  name=$(grep '^name:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  status=$(grep '^status:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  created=$(grep '^created:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  prd=$(grep '^prd:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  github_url=$(grep '^github:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  
  # Update status based on progress
  if [ $progress -eq 100 ]; then
    status="completed"
  elif [ $progress -gt 0 ]; then
    status="in-progress"
  fi
  
  # Create updated frontmatter
  {
    echo "---"
    echo "name: $name"
    echo "status: $status"
    echo "created: $created"
    echo "progress: ${progress}%"
    [ -n "$prd" ] && echo "prd: $prd"
    [ -n "$github_url" ] && echo "github: $github_url"
    echo "---"
    # Add content after frontmatter
    sed '1,/^---$/d; 1,/^---$/d' "$epic_file"
  } > "$epic_file.tmp" && mv "$epic_file.tmp" "$epic_file"
  
  echo "✅ Epic progress updated: $progress% ($closed_tasks/$total_tasks tasks completed)"
else
  echo "⚠️ Epic file not found: $epic_file"
fi