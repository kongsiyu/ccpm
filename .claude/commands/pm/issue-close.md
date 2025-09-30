---
allowed-tools: Bash
---

# Issue Close

Mark an issue as complete and close it on GitHub.

## Usage
```
/pm:issue-close <issue_number> [completion_notes]
```

## Instructions

Close the issue using the issue management script:

```bash
# Extract issue number and completion notes from arguments
issue_number=$(echo "$ARGUMENTS" | awk '{print $1}')
completion_notes=$(echo "$ARGUMENTS" | cut -d' ' -f2-)

# Close the issue
bash ccpm/scripts/pm/close-issue.sh close "$issue_number" "$completion_notes"
```

The script will:
1. Find the local task file (supports both naming conventions)
2. Update local task status to closed with timestamp
3. Update progress file if it exists (set completion to 100%)
4. Close the GitHub issue with completion comment
5. Update epic task list on GitHub (check off the completed task)
6. Recalculate and update epic progress
7. Show completion summary with next steps

## Important Notes

- Automatically handles both old and new task file naming conventions
- Updates all related progress tracking files
- Maintains synchronization between local and GitHub state
- Provides clear feedback on what was updated