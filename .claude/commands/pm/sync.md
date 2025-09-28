---
allowed-tools: Bash, Read, Write, LS
---

# Sync

Full bidirectional sync between local and GitHub.

## Usage
```
/pm:sync [epic_name]
```

If epic_name provided, sync only that epic. Otherwise sync all.

## Platform Detection and Routing

### Step 1: Detect Platform Configuration
```bash
# Initialize platform variables with defaults for backward compatibility
PLATFORM_TYPE="github"
PLATFORM_PROJECT_ID=""

# Method 1: Check for YAML configuration (future format)
if [ -f ".claude/ccpm.config" ] && command -v yq >/dev/null 2>&1; then
  # Try YAML format first
  platform_type_yaml=$(yq eval '.platform.type' .claude/ccpm.config 2>/dev/null)
  if [ "$platform_type_yaml" != "null" ] && [ -n "$platform_type_yaml" ]; then
    PLATFORM_TYPE="$platform_type_yaml"
    PLATFORM_PROJECT_ID=$(yq eval '.platform.project_id' .claude/ccpm.config 2>/dev/null)
  fi
fi

# Method 2: Check for bash configuration (current format)
if [ "$PLATFORM_TYPE" = "github" ] && [ -f ".claude/ccpm.config" ]; then
  # Source the bash configuration if YAML parsing failed or yq not available
  if grep -q "GITHUB_REPO=" .claude/ccpm.config 2>/dev/null; then
    echo "Using existing GitHub configuration from .claude/ccpm.config"
    # Configuration exists but is GitHub-focused, continue with GitHub
  fi
fi

# Method 3: Environment variable override
if [ -n "$CCPM_PLATFORM_TYPE" ]; then
  PLATFORM_TYPE="$CCPM_PLATFORM_TYPE"
fi

if [ -n "$CCPM_PROJECT_ID" ]; then
  PLATFORM_PROJECT_ID="$CCPM_PROJECT_ID"
fi

echo "Detected platform: $PLATFORM_TYPE"
```

### Step 2: Load Platform-specific Rules
```bash
# Load platform-specific sync rules if available
case "$PLATFORM_TYPE" in
  "yunxiao"|"alicloud")
    if [ -f ".claude/rules/platform-yunxiao-sync.md" ]; then
      echo "Loading Yunxiao platform sync rules..."
      # Platform-specific logic will be implemented through rule files
      # This preserves existing GitHub logic while enabling cloud platform support
    else
      echo "Warning: Yunxiao platform selected but rules not found. Falling back to GitHub."
      PLATFORM_TYPE="github"
    fi
    ;;
  "github"|*)
    echo "Using GitHub sync logic (default)"
    ;;
esac
```

### Step 3: Platform-specific Initialization
```bash
# Initialize platform-specific variables and tools
if [ "$PLATFORM_TYPE" = "yunxiao" ] || [ "$PLATFORM_TYPE" = "alicloud" ]; then
  # Yunxiao platform initialization
  if [ -z "$PLATFORM_PROJECT_ID" ]; then
    echo "❌ Error: project_id required for Yunxiao platform"
    echo "Please configure in .claude/ccpm.config:"
    echo "platform:"
    echo "  type: yunxiao"
    echo "  project_id: your-project-id"
    exit 1
  fi

  # Verify Yunxiao CLI tools (when implemented)
  # if ! command -v aliyun >/dev/null 2>&1; then
  #   echo "❌ Error: Aliyun CLI not found. Please install and configure."
  #   exit 1
  # fi

  echo "Initializing Yunxiao sync for project: $PLATFORM_PROJECT_ID"

  # TODO: Load Yunxiao-specific sync logic from rule files
  # For now, show that routing works and fall back to GitHub
  echo "⚠️ Yunxiao sync not yet implemented. Falling back to GitHub for now."
  PLATFORM_TYPE="github"
fi
```

## Instructions

### 1. Pull from GitHub

Get current state of all issues:
```bash
# Get all epic and task issues
gh issue list --label "epic" --limit 1000 --json number,title,state,body,labels,updatedAt
gh issue list --label "task" --limit 1000 --json number,title,state,body,labels,updatedAt
```

### 2. Update Local from GitHub

For each GitHub issue:
- Find corresponding local file by issue number
- Compare states:
  - If GitHub state newer (updatedAt > local updated), update local
  - If GitHub closed but local open, close local
  - If GitHub reopened but local closed, reopen local
- Update frontmatter to match GitHub state

### 3. Push Local to GitHub

For each local task/epic:
- If has GitHub URL but GitHub issue not found, it was deleted - mark local as archived
- If no GitHub URL, create new issue (like epic-sync)
- If local updated > GitHub updatedAt, push changes:
  ```bash
  gh issue edit {number} --body-file {local_file}
  ```

### 4. Handle Conflicts

If both changed (local and GitHub updated since last sync):
- Show both versions
- Ask user: "Local and GitHub both changed. Keep: (local/github/merge)?"
- Apply user's choice

### 5. Update Sync Timestamps

Update all synced files with last_sync timestamp.

### 6. Output

```
🔄 Sync Complete

Pulled from GitHub:
  Updated: {count} files
  Closed: {count} issues
  
Pushed to GitHub:
  Updated: {count} issues
  Created: {count} new issues
  
Conflicts resolved: {count}

Status:
  ✅ All files synced
  {or list any sync failures}
```

## Important Notes

Follow `/rules/github-operations.md` for GitHub commands.
Follow `/rules/frontmatter-operations.md` for local updates.
Always backup before sync in case of issues.