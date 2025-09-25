---
allowed-tools: Bash
---

# Epic Close

Mark an epic as complete when all tasks are done.

## Usage
```
/pm:epic-close <epic_name> [--archive]
```

Options:
- `--archive` - Automatically archive epic after closing

## Instructions

Close the epic using the epic management script:

```bash
bash ccpm/scripts/pm/close-epic.sh close $ARGUMENTS
```

The script will:
1. Verify all tasks in the epic are closed (exits with error if not)
2. Update epic status to completed with 100% progress and completion timestamp
3. Update linked PRD status to complete (if referenced)
4. Close the epic issue on GitHub with completion comment
5. Calculate and display epic duration
6. Offer to archive the completed epic (or auto-archive with --archive flag)
7. Create detailed archive summary if archived

## Alternative: Reopen Epic

To reopen a closed epic for additional work:

```bash
bash ccpm/scripts/pm/close-epic.sh reopen $ARGUMENTS
```

## Important Notes

- Only closes epics when all tasks are complete
- Automatically updates linked PRD status  
- Preserves all data when archiving
- Creates detailed completion and archive logs
- Can unarchive and reopen epics if needed