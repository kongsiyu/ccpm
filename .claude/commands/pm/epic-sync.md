---
allowed-tools: Bash, Read, Write, LS, Task
---

# Epic Sync 2.0 - Bidirectional Sync

Smart bidirectional epic sync that maintains perfect consistency between local files and GitHub issues.

## Usage
```
/pm:epic-sync2 <epic_name>
```

## Overview

This command implements a bidirectional sync that:
- **Pulls from GitHub**: Fetches all epic/task issues and compares with local files
- **Uses timestamps**: `updated` dates determine source of truth (local vs remote)
- **Updates locally**: When GitHub issue is newer, updates local .md file
- **Updates GitHub**: When local is newer, updates GitHub issue content and status
- **Creates missing items**: GitHub issues → local files, or local files → GitHub issues
- **Progress reporting**: Posts progress comments to GitHub issues
- **Auto-closes**: Closes GitHub issues when locally marked as completed

## Platform Detection and Routing

```bash
# Load platform detection library
source ".claude/lib/platform-detection.sh"

# Perform smart platform detection
if ! smart_platform_detection; then
    echo "❌ 平台配置检测失败，请检查配置"
    exit 1
fi

# Route to platform-specific implementation
platform=$(get_platform_type)
echo "🔄 检测到平台: $platform，正在路由到对应的epic-sync实现..."

case "$platform" in
    "yunxiao")
        # Route to Yunxiao epic-sync directory scripts
        echo "🚀 路由到云效平台的epic-sync实现"
        route_to_platform_script_dir "epic-sync" "sync-main.sh" "$@"
        ;;
    "github")
        echo "✅ 使用GitHub平台的epic-sync实现"
        # Continue with current GitHub implementation below
        ;;
    *)
        echo "❌ 不支持的平台类型: $platform"
        exit 1
        ;;
esac
```

## Quick Check

```bash
# Verify epic exists
test -f .claude/epics/$ARGUMENTS/epic.md || echo "❌ Epic not found. Run: /pm:prd-parse $ARGUMENTS"
```

## Instructions

### 0. Repository Protection Check

```bash
# Check if remote origin is the CCPM template repository
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$remote_url" == *"automazeio/ccpm"* ]] || [[ "$remote_url" == *"automazeio/ccpm.git"* ]]; then
  echo "❌ ERROR: You're trying to sync with the CCPM template repository!"
  echo "This repository is a template - you should NOT create issues here."
  echo ""
  echo "Please fork this repository or create your own project repository."
  exit 1
fi
```

### 1. Initialize Sync Environment

```bash
echo "🔄 Starting bidirectional epic sync for: $ARGUMENTS"

# Get repository information
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
REPO=$(echo "$remote_url" | sed 's|.*github.com[:/]||' | sed 's|\.git$||')
[ -z "$REPO" ] && REPO="user/repo"
echo "📍 Repository: $REPO"

# Verify GitHub CLI authentication
if ! gh auth status &>/dev/null; then
  echo "❌ GitHub CLI not authenticated. Run: gh auth login"
  exit 1
fi

# Check for sub-issue extension
if gh extension list 2>/dev/null | grep -q "yahsan2/gh-sub-issue"; then
  use_subissues=true
  echo "🔧 Sub-issue extension available"
else
  use_subissues=false
  echo "⚠️  Sub-issue extension not installed - using fallback mode"
fi
```

### 2. Fetch All GitHub Issues for Epic

Execute the GitHub issues fetcher:

```bash
!bash ccpm/scripts/pm/epic-sync/fetch-github-issues.sh $ARGUMENTS "$REPO"
```

### 3. Build Local File Inventory

Build inventory of all local files with metadata:

```bash
!bash ccpm/scripts/pm/epic-sync/build-local-inventory.sh $ARGUMENTS
```

### 4. Compare and Plan Sync Actions

Analyze differences and plan sync actions:

```bash
!bash ccpm/scripts/pm/epic-sync/plan-sync-actions.sh $ARGUMENTS
```

### 5. Execute Sync Actions - Update Local Files

Update local files from GitHub data:

```bash
!bash ccpm/scripts/pm/epic-sync/sync-local-files.sh $ARGUMENTS
```

### 6. Execute Sync Actions - Update GitHub Issues

Update GitHub issues from local data:

```bash
!bash ccpm/scripts/pm/epic-sync/sync-github-issues.sh $ARGUMENTS "$REPO" "$use_subissues"
```

### 7. Post Progress Reports and Manage Issue States

Post progress comments and manage issue states:

```bash
!bash ccpm/scripts/pm/epic-sync/post-progress-reports.sh $ARGUMENTS
```

### 8. Create Worktree and Update Mappings

Ensure worktree exists and update mapping file:

```bash
!bash ccpm/scripts/pm/epic-sync/worktree-and-mappings.sh $ARGUMENTS
```

### 9. Cleanup and Summary

```bash
# Get final stats from temp files
epic_number=$(cat /tmp/epic-sync/epic-number.txt 2>/dev/null || echo "TBD")
progress=$(cat /tmp/epic-sync/progress.txt 2>/dev/null || echo "0")
total_tasks=$(cat /tmp/epic-sync/total-tasks.txt 2>/dev/null || echo "0")
closed_tasks=$(cat /tmp/epic-sync/closed-tasks.txt 2>/dev/null || echo "0")
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)

echo ""
echo "🎯 Bidirectional Epic Sync Complete: $ARGUMENTS"
echo "=================================================="
echo ""
echo "📊 **Final Status:**"
echo "   Epic: #${epic_number} ($progress% complete)"
echo "   Tasks: $closed_tasks completed / $total_tasks total"
echo ""
echo "🔄 **Sync Summary:**"
if [ -s /tmp/epic-sync/sync-actions.txt ]; then
  updated_local=$(grep -c "^update_local:" /tmp/epic-sync/sync-actions.txt || echo 0)
  updated_github=$(grep -c "^update_github:" /tmp/epic-sync/sync-actions.txt || echo 0)
  created_local=$(grep -c "^create_local:" /tmp/epic-sync/sync-actions.txt || echo 0)
  created_github=$(grep -c "^create_github:" /tmp/epic-sync/sync-actions.txt || echo 0)
  
  echo "   📥 Local files updated: $updated_local"
  echo "   📤 GitHub issues updated: $updated_github"  
  echo "   📁 Local files created: $created_local"
  echo "   🆕 GitHub issues created: $created_github"
else
  echo "   ✅ Everything was already in perfect sync!"
fi

echo ""
echo "🔗 **Links:**"
echo "   Epic: https://github.com/${repo}/issues/${epic_number}"
echo "   Mapping: .claude/epics/$ARGUMENTS/github-mapping.md"
echo "   Worktree: ../epic-$ARGUMENTS"
echo ""
echo "🚀 **Next Steps:**"
echo "   • Start development: /pm:epic-start $ARGUMENTS"
echo "   • Work on specific task: /pm:issue-start <issue_number>"
echo "   • Check progress: cat .claude/epics/$ARGUMENTS/github-mapping.md"

# Cleanup temp files
rm -rf /tmp/epic-sync/

echo ""
echo "✨ Bidirectional sync completed successfully!"
```

## Key Features

### 🔄 **Bidirectional Sync**
- **GitHub → Local**: Updates local .md files when GitHub issues are newer
- **Local → GitHub**: Updates GitHub issues when local files are newer  
- **Timestamp-based**: Uses `updated` fields to determine source of truth

### 🆕 **Orphan Handling**
- **Missing Local**: Creates local .md files from GitHub issues
- **Missing GitHub**: Creates GitHub issues from local .md files
- **Smart Detection**: Handles deleted/missing issues gracefully

### 📊 **Progress Management**
- **Auto-close**: Closes GitHub issues when locally marked as completed
- **Progress comments**: Posts regular sync updates to all issues
- **Epic tracking**: Updates epic progress based on task completion

### 🔧 **Advanced Features**
- **Sub-issue support**: Uses gh-sub-issue extension when available
- **Status sync**: Keeps GitHub issue state in sync with local status
- **File renaming**: Renames local files to match GitHub issue numbers
- **Worktree management**: Creates/maintains development worktrees

### ⚙️ **Modular Architecture**
- **Focused Scripts**: Each sync step is a separate, testable script
- **Reusable Components**: Scripts can be used independently or by other commands
- **Clear Separation**: Logic flow in markdown, implementation in scripts
- **Easy Maintenance**: Scripts have proper syntax highlighting and debugging

## Script Components

The sync process is powered by these modular scripts:

- **`fetch-github-issues.sh`** - Fetches all GitHub issues for the epic
- **`build-local-inventory.sh`** - Builds inventory of local files with metadata
- **`plan-sync-actions.sh`** - Compares timestamps and plans sync actions
- **`sync-local-files.sh`** - Updates local files from GitHub data
- **`sync-github-issues.sh`** - Updates GitHub issues from local data  
- **`post-progress-reports.sh`** - Posts progress comments and manages issue states
- **`worktree-and-mappings.sh`** - Creates worktrees and updates mapping files

This replaces both `epic-sync.md` and `epic-refresh.md` with a single, comprehensive bidirectional sync command.