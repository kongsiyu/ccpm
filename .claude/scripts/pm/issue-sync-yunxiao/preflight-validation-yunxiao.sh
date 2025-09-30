#!/bin/bash
# Preflight validation for yunxiao issue sync

# 获取脚本目录并引入依赖
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"
YUNXIAO_DIR="$(dirname "$SCRIPT_DIR")/yunxiao"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$YUNXIAO_DIR/workitem-common.sh"

ARGUMENTS="$1"
if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Issue number required"
  exit 1
fi

# 1. 云效环境验证
echo "🔍 验证云效环境..."

# 检查云效配置
if ! validate_yunxiao_config; then
  echo "❌ 云效配置无效，请检查 .ccpm-config.yaml 中的配置"
  exit 1
fi

# 检查MCP服务状态
if ! check_yunxiao_mcp_service; then
  echo "❌ 云效MCP服务不可用，请确保服务正常运行"
  exit 1
fi

# 2. GitHub Issue验证
echo "🔍 验证GitHub Issue..."

# GitHub Authentication
if ! gh auth status >/dev/null 2>&1; then
  echo "❌ GitHub CLI未认证，请运行: gh auth login"
  exit 1
fi

# Issue存在性验证
if ! gh issue view "$ARGUMENTS" --json state >/dev/null 2>&1; then
  echo "❌ Issue #$ARGUMENTS 不存在"
  exit 1
fi

# 检查issue状态
issue_state=$(gh issue view "$ARGUMENTS" --json state --jq '.state')
if [ "$issue_state" = "CLOSED" ]; then
  echo "⚠️  Issue已关闭但工作未完成"
fi

# 3. 本地更新检查
echo "🔍 检查本地更新..."

epic_found=""
for epic_dir in .claude/epics/*/; do
  if [ -d "${epic_dir}updates/$ARGUMENTS/" ]; then
    epic_found=$(basename "$epic_dir")
    break
  fi
done

if [ -z "$epic_found" ]; then
  echo "❌ 未找到Issue #$ARGUMENTS的本地更新，请运行: /pm:issue-start $ARGUMENTS"
  exit 1
fi

if [ ! -f ".claude/epics/$epic_found/updates/$ARGUMENTS/progress.md" ]; then
  echo "❌ 未找到进度跟踪文件，请使用以下命令初始化: /pm:issue-start $ARGUMENTS"
  exit 1
fi

# 4. 云效工作项关联检查
echo "🔍 检查云效工作项关联..."

progress_file=".claude/epics/$epic_found/updates/$ARGUMENTS/progress.md"
yunxiao_workitem_id=""

# 从progress.md中提取云效工作项ID
if grep -q "yunxiao_workitem:" "$progress_file"; then
  yunxiao_workitem_id=$(grep "yunxiao_workitem:" "$progress_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
fi

# 如果存在工作项ID，验证其有效性
if [ -n "$yunxiao_workitem_id" ]; then
  echo "🔍 验证云效工作项 #$yunxiao_workitem_id..."
  if ! yunxiao_retry_call yunxiao_get_workitem "$yunxiao_workitem_id" >/dev/null 2>&1; then
    echo "⚠️  云效工作项 #$yunxiao_workitem_id 可能已不存在或无法访问"
  else
    echo "✅ 云效工作项 #$yunxiao_workitem_id 验证通过"
  fi
else
  echo "ℹ️  未找到关联的云效工作项，同步时将创建新工作项"
fi

# 5. 依赖检查
echo "🔍 检查依赖..."

# 检查工作项操作依赖
if ! check_workitem_dependencies; then
  echo "❌ 工作项依赖检查失败"
  exit 1
fi

# 检查必需的命令
require_commands "jq" "gh" "date" "grep" "sed"

echo "✅ 云效Issue同步预检验证通过"
echo "Issue: #$ARGUMENTS"
echo "Epic: $epic_found"
if [ -n "$yunxiao_workitem_id" ]; then
  echo "关联的云效工作项: #$yunxiao_workitem_id"
fi