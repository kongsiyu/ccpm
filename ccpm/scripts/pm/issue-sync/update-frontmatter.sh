#!/bin/bash
# Update frontmatter in progress and task files after sync

ARGUMENTS="$1"
COMPLETION="$2"

if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Issue number required"
  exit 1
fi

# Default completion to 0 if not provided
if [ -z "$COMPLETION" ]; then
  COMPLETION="0"
fi

# Find epic containing this issue
epic_found=""
for epic_dir in .claude/epics/*/; do
  if [ -d "${epic_dir}updates/$ARGUMENTS/" ]; then
    epic_found=$(basename "$epic_dir")
    break
  fi
done

if [ -z "$epic_found" ]; then
  echo "❌ No updates directory found for issue #$ARGUMENTS"
  exit 1
fi

# Get current datetime
current_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Update progress.md frontmatter
progress_file=".claude/epics/$epic_found/updates/$ARGUMENTS/progress.md"
if [ -f "$progress_file" ]; then
  # Extract current frontmatter values
  started=$(grep '^started:' "$progress_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  
  # Create updated frontmatter
  {
    echo "---"
    echo "issue: $ARGUMENTS"
    echo "started: $started"
    echo "last_sync: $current_datetime"
    echo "completion: ${COMPLETION}%"
    echo "---"
    # Add content after frontmatter
    sed '1,/^---$/d; 1,/^---$/d' "$progress_file"
  } > "$progress_file.tmp" && mv "$progress_file.tmp" "$progress_file"
  
  echo "✅ Updated progress.md frontmatter"
fi

# Find and update task file frontmatter
task_file=""
for task in ".claude/epics/$epic_found"/[0-9]*.md; do
  if [ -f "$task" ] && grep -q "github.*$ARGUMENTS" "$task"; then
    task_file="$task"
    break
  fi
done

if [ -n "$task_file" ]; then
  # Extract current frontmatter values
  name=$(grep '^name:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  created=$(grep '^created:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  github_url=$(grep '^github:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  
  # Determine status based on completion
  if [ "$COMPLETION" = "100" ]; then
    status="closed"
  else
    status="open"
  fi
  
  # Create updated frontmatter
  {
    echo "---"
    echo "name: $name"
    echo "status: $status"
    echo "created: $created"
    echo "updated: $current_datetime"
    echo "github: $github_url"
    echo "---"
    # Add content after frontmatter
    sed '1,/^---$/d; 1,/^---$/d' "$task_file"
  } > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"
  
  echo "✅ Updated task file frontmatter: $(basename "$task_file")"
fi

echo "✅ Frontmatter updates completed"