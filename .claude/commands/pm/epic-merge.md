---
allowed-tools: Bash, Read, Write
---

# Epic Merge

Merge completed epic from worktree back to main branch.

## Usage
```
/pm:epic-merge <epic_name>
```

## Quick Check

1. **Verify worktree exists:**
   ```bash
   git worktree list | grep "epic-$ARGUMENTS" || echo "❌ No worktree for epic: $ARGUMENTS"
   ```

2. **Check for active agents:**
   Read `.claude/epics/$ARGUMENTS/execution-status.md`
   If active agents exist: "⚠️ Active agents detected. Stop them first with: /pm:epic-stop $ARGUMENTS"

## Instructions

### 1. Pre-Merge Validation

Navigate to worktree and check status:
```bash
!bash ccpm/scripts/pm/epic-merge/validate-worktree.sh "$ARGUMENTS"
```

### 2. Run Tests (Optional but Recommended)

```bash
!bash ccpm/scripts/pm/epic-merge/run-tests.sh
```

### 3. Update Epic Documentation

Get current datetime: `date -u +"%Y-%m-%dT%H:%M:%SZ"`

Update `.claude/epics/$ARGUMENTS/epic.md`:
- Set status to "completed"
- Update completion date
- Add final summary

### 4. Attempt Merge

```bash
!bash ccpm/scripts/pm/epic-merge/execute-merge.sh "$ARGUMENTS"
```

### 5. Handle Merge Conflicts

If merge fails with conflicts:
```bash
!bash ccpm/scripts/pm/epic-merge/handle-conflicts.sh "$ARGUMENTS"
```

### 6. Post-Merge Cleanup

If merge succeeds:
```bash
!bash ccpm/scripts/pm/epic-merge/cleanup-worktree.sh "$ARGUMENTS"
```

### 7. Update GitHub Issues

Close related issues:
```bash
!bash ccpm/scripts/pm/epic-merge/close-github-issues.sh "$ARGUMENTS"
```

### 8. Final Output

```
✅ Epic Merged Successfully: $ARGUMENTS

Summary:
  Branch: epic/$ARGUMENTS → main
  Commits merged: {count}
  Files changed: {count}
  Issues closed: {count}
  
Cleanup completed:
  ✓ Worktree removed
  ✓ Branch deleted
  ✓ Epic archived
  ✓ GitHub issues closed
  
Next steps:
  - Deploy changes if needed
  - Start new epic: /pm:prd-new {feature}
  - View completed work: git log --oneline -20
```

## Conflict Resolution Help

If conflicts need resolution:
```
The epic branch has conflicts with main.

This typically happens when:
- Main has changed since epic started
- Multiple epics modified same files
- Dependencies were updated

To resolve:
1. Open conflicted files
2. Look for <<<<<<< markers
3. Choose correct version or combine
4. Remove conflict markers
5. git add {resolved files}
6. git commit
7. git push

Or abort and try later:
  git merge --abort
```

## Important Notes

- Always check for uncommitted changes first
- Run tests before merging when possible
- Use --no-ff to preserve epic history
- Archive epic data instead of deleting
- Close GitHub issues to maintain sync