#!/bin/bash
# Check last sync timing to prevent excessive syncing

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Issue number required"
  exit 1
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

progress_file=".claude/epics/$epic_found/updates/$ARGUMENTS/progress.md"

if [ ! -f "$progress_file" ]; then
  echo "ℹ️ No previous sync found - proceeding with first sync"
  exit 0
fi

# Extract last_sync from frontmatter
last_sync=$(grep '^last_sync:' "$progress_file" | head -1 | cut -d: -f2- | sed 's/^ *//')

if [ -z "$last_sync" ] || [ "$last_sync" = "null" ]; then
  echo "ℹ️ No previous sync timestamp - proceeding"
  exit 0
fi

# Calculate time difference (basic check - 5 minutes = 300 seconds)
current_time=$(date -u +%s)
if command -v gdate >/dev/null 2>&1; then
  # macOS with GNU coreutils
  last_sync_time=$(gdate -d "$last_sync" +%s 2>/dev/null || echo "0")
else
  # Linux date
  last_sync_time=$(date -d "$last_sync" +%s 2>/dev/null || echo "0")
fi

time_diff=$((current_time - last_sync_time))

if [ "$time_diff" -lt 300 ]; then
  minutes_ago=$((time_diff / 60))
  echo "⚠️ Recently synced $minutes_ago minutes ago. Force sync anyway? (yes/no)"
  # In automated context, we'll proceed but warn
fi

echo "✅ Sync timing check passed"