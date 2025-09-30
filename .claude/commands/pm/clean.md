---
allowed-tools: Bash
---

# Clean

Clean up completed work and archive old epics.

## Usage
```
/pm:clean [--dry-run] [--verbose]
```

Options:
- `--dry-run` - Show what would be cleaned without doing it
- `--verbose` - Show detailed output during cleanup

## Instructions

Run the system cleanup script:

```bash
bash ccpm/scripts/pm/clean.sh $ARGUMENTS
```

The cleanup script will:
1. Scan for completed epics (status: completed, all tasks closed, >30 days old)
2. Find stale progress files for closed issues  
3. Identify empty directories
4. Show cleanup plan and ask for confirmation
5. Archive completed epics to `.claude/epics/.archived/`
6. Remove stale files and empty directories
7. Create detailed archive log
8. Report space recovered

## Important Notes

- Always previews changes before making them
- Never deletes PRDs or incomplete work  
- Maintains complete archive log for history
- Can be run safely with `--dry-run` to preview changes