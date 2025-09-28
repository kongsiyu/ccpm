#!/bin/bash

echo "Initializing..."
echo ""
echo ""

echo " ██████╗ ██████╗██████╗ ███╗   ███╗"
echo "██╔════╝██╔════╝██╔══██╗████╗ ████║"
echo "██║     ██║     ██████╔╝██╔████╔██║"
echo "╚██████╗╚██████╗██║     ██║ ╚═╝ ██║"
echo " ╚═════╝ ╚═════╝╚═╝     ╚═╝     ╚═╝"

echo "┌─────────────────────────────────┐"
echo "│ Claude Code Project Management  │"
echo "│ by https://x.com/aroussi        │"
echo "└─────────────────────────────────┘"
echo "https://github.com/automazeio/ccpm"
echo ""
echo ""

echo "🚀 Initializing Claude Code PM System"
echo "======================================"
echo ""

# Check for required tools
echo "🔍 Checking dependencies..."

# Check gh CLI
if command -v gh &> /dev/null; then
  echo "  ✅ GitHub CLI (gh) installed"
else
  echo "  ❌ GitHub CLI (gh) not found"
  echo ""
  echo "  Installing gh..."
  if command -v brew &> /dev/null; then
    brew install gh
  elif command -v apt-get &> /dev/null; then
    sudo apt-get update && sudo apt-get install gh
  else
    echo "  Please install GitHub CLI manually: https://cli.github.com/"
    exit 1
  fi
fi

# Check gh auth status
echo ""
echo "🔐 Checking GitHub authentication..."
if gh auth status &> /dev/null; then
  echo "  ✅ GitHub authenticated"
else
  echo "  ⚠️ GitHub not authenticated"
  echo "  Running: gh auth login"
  gh auth login
fi

# Check for gh-sub-issue extension
echo ""
echo "📦 Checking gh extensions..."
if gh extension list | grep -q "yahsan2/gh-sub-issue"; then
  echo "  ✅ gh-sub-issue extension installed"
else
  echo "  📥 Installing gh-sub-issue extension..."
  gh extension install yahsan2/gh-sub-issue
fi

# Create directory structure
echo ""
echo "📁 Creating directory structure..."
mkdir -p .claude/prds
mkdir -p .claude/epics
mkdir -p .claude/rules
mkdir -p .claude/agents
mkdir -p .claude/scripts/pm
echo "  ✅ Directories created"

# Copy scripts if in main repo
if [ -d "scripts/pm" ] && [ ! "$(pwd)" = *"/.claude"* ]; then
  echo ""
  echo "📝 Copying PM scripts..."
  cp -r scripts/pm/* .claude/scripts/pm/
  chmod +x .claude/scripts/pm/*.sh
  echo "  ✅ Scripts copied and made executable"
fi

# Check for git
echo ""
echo "🔗 Checking Git configuration..."
if git rev-parse --git-dir > /dev/null 2>&1; then
  echo "  ✅ Git repository detected"

  # Check remote
  if git remote -v | grep -q origin; then
    remote_url=$(git remote get-url origin)
    echo "  ✅ Remote configured: $remote_url"
    
    # Check if remote is the CCPM template repository
    if [[ "$remote_url" == *"automazeio/ccpm"* ]] || [[ "$remote_url" == *"automazeio/ccpm.git"* ]]; then
      echo ""
      echo "  ⚠️ WARNING: Your remote origin points to the CCPM template repository!"
      echo "  This means any issues you create will go to the template repo, not your project."
      echo ""
      echo "  To fix this:"
      echo "  1. Fork the repository or create your own on GitHub"
      echo "  2. Update your remote:"
      echo "     git remote set-url origin https://github.com/YOUR_USERNAME/YOUR_REPO.git"
      echo ""
    else
      # Create GitHub labels if this is a GitHub repository
      if gh repo view &> /dev/null; then
        echo ""
        echo "🏷️ Creating GitHub labels..."
        
        # Create base labels with improved error handling
        epic_created=false
        task_created=false
        
        if gh label create "epic" --color "0E8A16" --description "Epic issue containing multiple related tasks" --force 2>/dev/null; then
          epic_created=true
        elif gh label list 2>/dev/null | grep -q "^epic"; then
          epic_created=true  # Label already exists
        fi
        
        if gh label create "task" --color "1D76DB" --description "Individual task within an epic" --force 2>/dev/null; then
          task_created=true
        elif gh label list 2>/dev/null | grep -q "^task"; then
          task_created=true  # Label already exists
        fi
        
        # Report results
        if $epic_created && $task_created; then
          echo "  ✅ GitHub labels created (epic, task)"
        elif $epic_created || $task_created; then
          echo "  ⚠️ Some GitHub labels created (epic: $epic_created, task: $task_created)"
        else
          echo "  ❌ Could not create GitHub labels (check repository permissions)"
        fi
      else
        echo "  ℹ️ Not a GitHub repository - skipping label creation"
      fi
    fi
  else
    echo "  ⚠️ No remote configured"
    echo "  Add with: git remote add origin <url>"
  fi
else
  echo "  ⚠️ Not a git repository"
  echo "  Initialize with: git init"
fi

# Create CLAUDE.md if it doesn't exist
if [ ! -f "CLAUDE.md" ]; then
  echo ""
  echo "📄 Creating CLAUDE.md..."
  cat > CLAUDE.md << 'EOF'
# CLAUDE.md

> Think carefully and implement the most concise solution that changes as little code as possible.

## Project-Specific Instructions

Add your project-specific instructions here.

## Testing

Always run tests before committing:
- `npm test` or equivalent for your stack

## Code Style

Follow existing patterns in the codebase.
EOF
  echo "  ✅ CLAUDE.md created"
fi

# Platform Configuration
echo ""
echo "🎯 Platform Configuration"
echo "=========================="
echo ""

# Check for existing configuration
YAML_CONFIG=".claude/ccpm.yaml"
LEGACY_CONFIG=".claude/ccpm.config"

if [ -f "$YAML_CONFIG" ]; then
  # Read existing platform configuration
  if command -v yq >/dev/null 2>&1; then
    EXISTING_PLATFORM=$(yq eval '.platform.type' "$YAML_CONFIG" 2>/dev/null || echo "github")
    echo "📋 Found existing configuration: $EXISTING_PLATFORM platform"
    echo "   Skipping platform selection - using existing configuration"
    SELECTED_PLATFORM="$EXISTING_PLATFORM"
  else
    # Fallback: simple parsing without yq
    echo "📋 Found existing YAML configuration (parsing without yq)"
    EXISTING_PLATFORM=$(grep -A 2 "^platform:" "$YAML_CONFIG" | grep "type:" | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
    if [ -z "$EXISTING_PLATFORM" ]; then
      EXISTING_PLATFORM="github"
    fi
    echo "   Detected platform: $EXISTING_PLATFORM"
    echo "   Note: Install yq for full YAML support: https://github.com/mikefarah/yq#install"
    SELECTED_PLATFORM="$EXISTING_PLATFORM"
  fi
else
  # Platform selection for new projects
  echo "🔧 Choose your project management platform:"
  echo ""
  echo "  1) GitHub (Default) - Use GitHub Issues and Projects"
  echo "  2) Alibaba Cloud DevOps (云效) - Use 云效工作项管理"
  echo "  3) Both platforms (Hybrid) - Support both GitHub and 云效"
  echo ""

  # Default to GitHub for non-interactive environments
  if [ -t 0 ]; then
    read -p "Select platform [1]: " platform_choice
  else
    platform_choice="1"
    echo "Non-interactive mode: defaulting to GitHub"
  fi

  case "${platform_choice:-1}" in
    2)
      SELECTED_PLATFORM="yunxiao"
      echo "✅ Selected: Alibaba Cloud DevOps (云效)"
      ;;
    3)
      SELECTED_PLATFORM="github"
      HYBRID_MODE="true"
      echo "✅ Selected: Hybrid mode (GitHub + 云效)"
      ;;
    *)
      SELECTED_PLATFORM="github"
      echo "✅ Selected: GitHub (Default)"
      ;;
  esac

  # Create configuration file
  echo ""
  echo "📝 Creating configuration file..."

  if [ "$SELECTED_PLATFORM" = "yunxiao" ] || [ "$HYBRID_MODE" = "true" ]; then
    # Create YAML configuration for 云效 or hybrid mode
    cat > "$YAML_CONFIG" << 'EOF'
# CCPM 平台配置文件
# Cloud Code Project Management - Platform Configuration

# 平台配置 - Platform Configuration
platform:
  type: "github"
  project_id: ""

  # GitHub 配置
  github:
    repository: ""

  # 云效配置
  yunxiao:
    api:
      base_url: "https://devops.aliyun.com"
      version: "v4"
      timeout: 30000
    token_env: "YUNXIAO_ACCESS_TOKEN"
    workitem_types:
      default_task_type: "任务"
      default_epic_type: "需求"
      default_bug_type: "缺陷"

# 同步配置
sync:
  mode: "bidirectional"
  interval: 300
  timeout: 60
  conflict_resolution:
    strategy: "timestamp"

# 功能开关
features:
  verbose_logging: false
  strict_validation: true
  legacy_compatibility: true
  auto_backup: true

# 模板配置
templates:
  task_template: ".claude/templates/task.md"
  epic_template: ".claude/templates/epic.md"

# 路径配置
paths:
  epics_dir: ".claude/epics"
  rules_dir: ".claude/rules"
  logs_dir: ".claude/logs"
  backup_dir: ".claude/backups"

# 元信息
metadata:
  version: "1.0.0"
  created: "$(date -Iseconds)"
  updated: "$(date -Iseconds)"
  description: "CCPM 平台配置"
EOF

    # Update platform type based on selection
    if command -v yq >/dev/null 2>&1; then
      yq eval ".platform.type = \"$SELECTED_PLATFORM\"" -i "$YAML_CONFIG"
      if [ "$HYBRID_MODE" = "true" ]; then
        yq eval '.platform.type = "github"' -i "$YAML_CONFIG"
        yq eval '.features.yunxiao_support = true' -i "$YAML_CONFIG"
      fi
      echo "  ✅ YAML configuration created: $YAML_CONFIG"
    else
      echo "  ⚠️ YAML configuration created but yq not available for updates"
    fi
  else
    # GitHub-only mode - keep existing behavior
    echo "  ✅ Using default GitHub configuration"
  fi

  # Handle 云效 specific setup
  if [ "$SELECTED_PLATFORM" = "yunxiao" ] || [ "$HYBRID_MODE" = "true" ]; then
    echo ""
    echo "🔗 云效平台配置"
    echo "==============="

    # Prompt for project ID
    if [ -t 0 ]; then
      echo ""
      echo "请输入云效项目ID (可在云效项目设置中找到):"
      read -p "Project ID: " YUNXIAO_PROJECT_ID

      if [ -n "$YUNXIAO_PROJECT_ID" ] && command -v yq >/dev/null 2>&1; then
        yq eval ".platform.project_id = \"$YUNXIAO_PROJECT_ID\"" -i "$YAML_CONFIG"
        echo "  ✅ 项目ID已配置: $YUNXIAO_PROJECT_ID"
      fi
    fi

    # Check for access token
    if [ -z "$YUNXIAO_ACCESS_TOKEN" ]; then
      echo ""
      echo "⚠️ 云效访问令牌未配置"
      echo "请设置环境变量: export YUNXIAO_ACCESS_TOKEN='your-token'"
      echo "获取令牌: https://devops.aliyun.com/settings/personalAccessTokens"
    else
      echo "  ✅ 云效访问令牌已配置"
    fi
  fi
fi  # End of new configuration setup

# Platform Connection Validation
echo ""
echo "🔍 Platform Connection Validation"
echo "=================================="

# Determine current platform configuration
if [ -f "$YAML_CONFIG" ]; then
  if command -v yq >/dev/null 2>&1; then
    CURRENT_PLATFORM=$(yq eval '.platform.type' "$YAML_CONFIG" 2>/dev/null || echo "github")
    PROJECT_ID=$(yq eval '.platform.project_id' "$YAML_CONFIG" 2>/dev/null || echo "")
  else
    # Fallback parsing without yq
    CURRENT_PLATFORM=$(grep -A 2 "^platform:" "$YAML_CONFIG" | grep "type:" | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
    PROJECT_ID=$(grep -A 3 "^platform:" "$YAML_CONFIG" | grep "project_id:" | sed 's/.*"\([^"]*\)".*/\1/' | head -1)
    if [ -z "$CURRENT_PLATFORM" ]; then
      CURRENT_PLATFORM="github"
    fi
  fi
else
  CURRENT_PLATFORM="github"
  PROJECT_ID=""
fi

# Validate GitHub connection
echo ""
echo "📊 GitHub 连接状态:"
if command -v gh >/dev/null 2>&1; then
  if gh auth status >/dev/null 2>&1; then
    gh_user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
    echo "  ✅ GitHub 已认证 (用户: $gh_user)"
    GITHUB_STATUS="✅ 可用"
  else
    echo "  ❌ GitHub 未认证"
    GITHUB_STATUS="❌ 需要认证"
  fi
else
  echo "  ❌ GitHub CLI 未安装"
  GITHUB_STATUS="❌ 未安装"
fi

# Validate 云效 connection if configured
if [ "$CURRENT_PLATFORM" = "yunxiao" ] || [ -f "$YAML_CONFIG" ]; then
  echo ""
  echo "📊 云效连接状态:"

  if [ -z "$YUNXIAO_ACCESS_TOKEN" ]; then
    echo "  ❌ 访问令牌未配置"
    YUNXIAO_STATUS="❌ 令牌缺失"
  elif [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
    echo "  ⚠️ 项目ID未配置"
    YUNXIAO_STATUS="⚠️ 项目ID缺失"
  else
    # Test connection (simplified check)
    if curl -s --max-time 5 -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
       "https://devops.aliyun.com/api/v4/projects/$PROJECT_ID" >/dev/null 2>&1; then
      echo "  ✅ 云效连接正常 (项目: $PROJECT_ID)"
      YUNXIAO_STATUS="✅ 可用"
    else
      echo "  ❌ 云效连接失败 - 请检查令牌和项目ID"
      YUNXIAO_STATUS="❌ 连接失败"
    fi
  fi
else
  YUNXIAO_STATUS="⚪ 未配置"
fi

# Generate Initialization Report
echo ""
echo "📋 Initialization Report"
echo "========================"
echo ""
echo "🎯 配置摘要:"
echo "   平台类型: $CURRENT_PLATFORM"
echo "   配置文件: $([ -f "$YAML_CONFIG" ] && echo "ccpm.yaml" || echo "legacy")"
echo "   项目标识: ${PROJECT_ID:-$(git remote get-url origin 2>/dev/null | sed -E 's#.*github\.com[/:]([^/]+/[^/]+).*#\1#' | sed 's#\.git$##' || echo 'unknown')}"
echo ""
echo "🔗 平台状态:"
echo "   GitHub:   $GITHUB_STATUS"
echo "   云效:     $YUNXIAO_STATUS"
echo ""
echo "📁 目录结构:"
ls -la .claude/ 2>/dev/null | grep -E "^d" | awk '{print "   " $9}' | grep -v "^\.$" | sort
echo ""

# Next Steps based on configuration
echo "🎯 下一步操作:"

if [ "$CURRENT_PLATFORM" = "github" ]; then
  if [[ "$GITHUB_STATUS" == *"✅"* ]]; then
    echo "  1. 创建第一个PRD: /pm:prd-new <feature-name>"
    echo "  2. 查看帮助: /pm:help"
    echo "  3. 检查状态: /pm:status"
  else
    echo "  1. 配置GitHub认证: gh auth login"
    echo "  2. 重新运行初始化: /pm:init"
  fi
elif [ "$CURRENT_PLATFORM" = "yunxiao" ]; then
  if [[ "$YUNXIAO_STATUS" == *"✅"* ]]; then
    echo "  1. 同步云效工作项: /pm:sync"
    echo "  2. 创建新任务: /pm:task-new"
    echo "  3. 查看项目状态: /pm:status"
  else
    echo "  1. 配置云效访问令牌: export YUNXIAO_ACCESS_TOKEN='your-token'"
    echo "  2. 配置项目ID: yq eval '.platform.project_id = \"your-project-id\"' -i .claude/ccpm.yaml"
    echo "  3. 重新运行初始化: /pm:init"
  fi
fi

echo ""
echo "📚 文档和资源:"
echo "  - 配置指南: .claude/rules/platform-config.md"
echo "  - 项目文档: README.md"
echo "  - 云效集成: https://devops.aliyun.com"
echo ""

# Summary
echo "✅ Initialization Complete!"
echo "=========================="

exit 0
