#!/bin/bash
# Check and ensure analysis files exist for issues

ARGUMENTS="$1"
ISSUE="$2"

if [ -z "$ARGUMENTS" ] || [ -z "$ISSUE" ]; then
  echo "❌ Error: Epic name and issue number required"
  echo "Usage: $0 <epic_name> <issue_number>"
  exit 1
fi

# Check for analysis
if ! test -f ".claude/epics/$ARGUMENTS/${ISSUE}-analysis.md"; then
  echo "⚠️ Analysis missing for issue #${ISSUE}"
  echo "Analysis needed before launching agents. Consider running analysis task first."
  exit 1
else
  echo "✅ Analysis found for issue #${ISSUE}"
fi