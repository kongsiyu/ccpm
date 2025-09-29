#!/bin/bash
# Compare local and GitHub data to plan sync actions
set -e

EPIC_NAME="$1"

if [ -z "$EPIC_NAME" ]; then
  echo "Usage: $0 <epic_name>"
  exit 1
fi

echo "🔍 Analyzing sync requirements..."

# Get epic number from previous step
epic_number=$(cat /tmp/epic-sync/epic-number.txt 2>/dev/null || true)

# Clear sync actions file
> /tmp/epic-sync/sync-actions.txt

# Process epic sync
if [ -n "$epic_number" ] && [ -f /tmp/epic-sync/epic-issue.json ]; then
  # Epic exists on both sides - compare timestamps
  gh_updated=$(jq -r '.updatedAt' /tmp/epic-sync/epic-issue.json)
  local_updated=$(grep '^epic:' /tmp/epic-sync/local-files.txt | cut -d: -f4)
  
  # Convert ISO timestamps to seconds (cross-platform)
  gh_timestamp=$(date -d "$gh_updated" "+%s" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$gh_updated" "+%s" 2>/dev/null || echo "0")
  local_timestamp=$(date -d "$local_updated" "+%s" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$local_updated" "+%s" 2>/dev/null || echo "0")
  
  if [ "$gh_timestamp" -gt "$local_timestamp" ]; then
    echo "update_local:epic:$epic_number" >> /tmp/epic-sync/sync-actions.txt
    echo "📥 Epic: GitHub newer → update local"
  elif [ "$local_timestamp" -gt "$gh_timestamp" ]; then
    echo "update_github:epic:$epic_number" >> /tmp/epic-sync/sync-actions.txt
    echo "📤 Epic: Local newer → update GitHub"
  else
    echo "✅ Epic: Already in sync"
  fi
elif [ -n "$epic_number" ]; then
  # Epic exists on GitHub but not locally (shouldn't happen, but handle it)
  echo "create_local:epic:$epic_number" >> /tmp/epic-sync/sync-actions.txt
  echo "📥 Epic: Create local from GitHub"
elif grep -q '^epic:' /tmp/epic-sync/local-files.txt; then
  # Epic exists locally but not on GitHub
  echo "create_github:epic:0" >> /tmp/epic-sync/sync-actions.txt
  echo "📤 Epic: Create on GitHub"
fi

# Process task sync
echo "🔍 Analyzing task sync requirements..."

# Check each GitHub task issue
if [ -s /tmp/epic-sync/task-issues.json ]; then
  jq -r '.[] | "\(.number):\(.updatedAt)"' /tmp/epic-sync/task-issues.json | while IFS=: read gh_issue gh_updated; do
    # Find corresponding local file
    local_line=$(grep ":$gh_issue$" /tmp/epic-sync/local-files.txt || true)
    
    if [ -n "$local_line" ]; then
      # Exists on both sides - compare timestamps
      local_updated=$(echo "$local_line" | cut -d: -f4)
      local_status=$(echo "$local_line" | cut -d: -f5)
      
      # Convert ISO timestamps to seconds (cross-platform)
      gh_timestamp=$(date -d "$gh_updated" "+%s" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$gh_updated" "+%s" 2>/dev/null || echo "0")
      local_timestamp=$(date -d "$local_updated" "+%s" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$local_updated" "+%s" 2>/dev/null || echo "0")
      
      if [ "$gh_timestamp" -gt "$local_timestamp" ]; then
        echo "update_local:task:$gh_issue" >> /tmp/epic-sync/sync-actions.txt
      elif [ "$local_timestamp" -gt "$gh_timestamp" ]; then
        echo "update_github:task:$gh_issue:$local_status" >> /tmp/epic-sync/sync-actions.txt
      fi
      
      # Always check if we need to post progress or close issue
      echo "check_status:task:$gh_issue:$local_status" >> /tmp/epic-sync/sync-actions.txt
    else
      # Exists on GitHub but not locally
      echo "create_local:task:$gh_issue" >> /tmp/epic-sync/sync-actions.txt
    fi
  done
fi

# Check each local task file
grep '^task:' /tmp/epic-sync/local-files.txt 2>/dev/null | while IFS=: read file_type file_id file_path local_updated local_status github_issue; do
  if [ -z "$github_issue" ] || ! jq -e ".[] | select(.number == $github_issue)" /tmp/epic-sync/task-issues.json >/dev/null 2>&1; then
    # Exists locally but not on GitHub (or GitHub issue doesn't exist anymore)
    echo "create_github:task:$file_id:$local_status" >> /tmp/epic-sync/sync-actions.txt
  fi
done

# Show sync plan
echo ""
echo "📋 Sync Plan:"
if [ -s /tmp/epic-sync/sync-actions.txt ]; then
  update_local_count=$(grep -c "^update_local:" /tmp/epic-sync/sync-actions.txt || echo 0)
  update_github_count=$(grep -c "^update_github:" /tmp/epic-sync/sync-actions.txt || echo 0)
  create_local_count=$(grep -c "^create_local:" /tmp/epic-sync/sync-actions.txt || echo 0)
  create_github_count=$(grep -c "^create_github:" /tmp/epic-sync/sync-actions.txt || echo 0)
  status_check_count=$(grep -c "^check_status:" /tmp/epic-sync/sync-actions.txt || echo 0)
  
  echo "  📥 Update local files: $update_local_count"
  echo "  📤 Update GitHub issues: $update_github_count"
  echo "  📁 Create local files: $create_local_count"
  echo "  🆕 Create GitHub issues: $create_github_count"
  echo "  ✅ Status/progress checks: $status_check_count"
else
  echo "  ✅ Everything already in sync!"
fi

exit 0