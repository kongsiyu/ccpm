#!/bin/bash
# Post formatted update comment to GitHub issue

ARGUMENTS="$1"
TEMP_FILE="$2"

if [ -z "$ARGUMENTS" ] || [ -z "$TEMP_FILE" ]; then
  echo "❌ Error: Issue number and temp file path required"
  echo "Usage: $0 <issue_number> <temp_comment_file>"
  exit 1
fi

if [ ! -f "$TEMP_FILE" ]; then
  echo "❌ Error: Comment file not found: $TEMP_FILE"
  exit 1
fi

# Check comment size (GitHub limit: 65,536 characters)
comment_size=$(wc -c < "$TEMP_FILE")
if [ "$comment_size" -gt 65536 ]; then
  echo "⚠️ Comment exceeds GitHub limit (${comment_size} chars > 65,536)"
  echo "Consider splitting into multiple comments or summarizing"
  # Proceed anyway - let GitHub handle the truncation
fi

# Post comment using GitHub CLI
if gh issue comment "$ARGUMENTS" --body-file "$TEMP_FILE"; then
  echo "✅ Comment posted successfully to issue #$ARGUMENTS"
  # Clean up temp file
  rm -f "$TEMP_FILE"
else
  echo "❌ Failed to post comment to issue #$ARGUMENTS"
  echo "Comment saved in: $TEMP_FILE"
  exit 1
fi