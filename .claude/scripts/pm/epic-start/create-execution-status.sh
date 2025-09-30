#!/bin/bash
# Create or update execution status file

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

# Get current datetime
DATETIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create execution status file
cat > ".claude/epics/$ARGUMENTS/execution-status.md" << EOF
---
started: $DATETIME
branch: epic/$ARGUMENTS
---

# Execution Status

## Active Agents
(Agents will be added here as they launch)

## Queued Issues
(Issues waiting for dependencies will be listed here)

## Completed
(Completed work will be tracked here)
EOF

echo "✅ Created execution status file: .claude/epics/$ARGUMENTS/execution-status.md"