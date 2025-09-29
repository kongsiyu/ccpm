#!/bin/bash
# Build local file inventory with metadata
set -e

EPIC_NAME="$1"

if [ -z "$EPIC_NAME" ]; then
  echo "Usage: $0 <epic_name>"
  exit 1
fi

echo "📁 Building local file inventory..."

# Create/clear local files list
> /tmp/epic-sync/local-files.txt

# List all local files with metadata
for file_path in ".claude/epics/$EPIC_NAME"/*.md; do
  [ -f "$file_path" ] || continue
  
  filename=$(basename "$file_path")
  if [ "$filename" = "epic.md" ]; then
    file_type="epic"
    file_id="epic"
  elif [[ "$filename" =~ ^[0-9]+\.md$ ]]; then
    file_type="task"
    file_id=$(basename "$filename" .md)
  else
    continue  # Skip other files
  fi
  
  # Extract metadata from frontmatter
  updated_date=$(grep '^updated:' "$file_path" | sed 's/^updated: *//' || echo "1970-01-01T00:00:00Z")
  status=$(grep '^status:' "$file_path" | sed 's/^status: *//' || echo "open")
  github_url=$(grep '^github:' "$file_path" | sed 's/^github: *//' || true)
  
  if [ -n "$github_url" ]; then
    github_issue=$(echo "$github_url" | grep -oE '[0-9]+$' || true)
  else
    github_issue=""
  fi
  
  echo "$file_type:$file_id:$file_path:$updated_date:$status:$github_issue" >> /tmp/epic-sync/local-files.txt
done

local_file_count=$(wc -l < /tmp/epic-sync/local-files.txt)
echo "📊 Found $local_file_count local files"

exit 0