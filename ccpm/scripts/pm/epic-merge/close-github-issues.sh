#!/bin/bash
# Close related GitHub issues

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

# Extract epic issue number
epic_github_line=$(grep 'github:' ".claude/epics/archived/$ARGUMENTS/epic.md" 2>/dev/null || true)
if [ -n "$epic_github_line" ]; then
  epic_issue=$(echo "$epic_github_line" | grep -oE '[0-9]+$' || true)
else
  epic_issue=""
fi

# Close epic issue
if [ -n "$epic_issue" ]; then
  gh issue close "$epic_issue" -c "Epic completed and merged to main"
  echo "✅ Closed epic issue #$epic_issue"
fi

# Close task issues
for task_file in ".claude/epics/archived/$ARGUMENTS"/[0-9]*.md; do
  [ -f "$task_file" ] || continue
  # Extract task issue number
  task_github_line=$(grep 'github:' "$task_file" 2>/dev/null || true)
  if [ -n "$task_github_line" ]; then
    issue_num=$(echo "$task_github_line" | grep -oE '[0-9]+$' || true)
  else
    issue_num=""
  fi
  if [ -n "$issue_num" ]; then
    gh issue close "$issue_num" -c "Completed in epic merge"
    echo "✅ Closed task issue #$issue_num"
  fi
done