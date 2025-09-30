#!/bin/bash
# Post formatted update comment to yunxiao workitem

# 获取脚本目录并引入依赖
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"
YUNXIAO_DIR="$(dirname "$SCRIPT_DIR")/yunxiao"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$YUNXIAO_DIR/workitem-common.sh"

ARGUMENTS="$1"
TEMP_FILE="$2"
YUNXIAO_WORKITEM_ID="$3"

if [ -z "$ARGUMENTS" ] || [ -z "$TEMP_FILE" ]; then
  echo "❌ Error: Issue number and temp file path required"
  echo "Usage: $0 <issue_number> <temp_comment_file> [yunxiao_workitem_id]"
  exit 1
fi

if [ ! -f "$TEMP_FILE" ]; then
  echo "❌ Error: Comment file not found: $TEMP_FILE"
  exit 1
fi

# 检查评论大小 (云效限制可能不同，这里设置为合理限制)
comment_size=$(wc -c < "$TEMP_FILE")
if [ "$comment_size" -gt 32768 ]; then
  echo "⚠️  评论内容过长 (${comment_size} 字符 > 32,768)"
  echo "建议拆分为多条评论或进行摘要"
  # 继续执行，让云效API处理截断
fi

# 如果没有提供云效工作项ID，尝试从本地查找
if [ -z "$YUNXIAO_WORKITEM_ID" ]; then
  echo "🔍 查找关联的云效工作项..."

  # 查找epic
  epic_found=""
  for epic_dir in .claude/epics/*/; do
    if [ -d "${epic_dir}updates/$ARGUMENTS/" ]; then
      epic_found=$(basename "$epic_dir")
      break
    fi
  done

  if [ -n "$epic_found" ]; then
    progress_file=".claude/epics/$epic_found/updates/$ARGUMENTS/progress.md"
    if [ -f "$progress_file" ] && grep -q "yunxiao_workitem:" "$progress_file"; then
      YUNXIAO_WORKITEM_ID=$(grep "yunxiao_workitem:" "$progress_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
    fi
  fi
fi

# 如果仍然没有云效工作项ID，跳过云效评论发布
if [ -z "$YUNXIAO_WORKITEM_ID" ]; then
  echo "ℹ️  未找到关联的云效工作项，跳过云效评论发布"
  echo "✅ 评论保存在: $TEMP_FILE"
  exit 0
fi

echo "🔄 发布评论到云效工作项 #$YUNXIAO_WORKITEM_ID..."

# 读取评论内容
comment_content=$(cat "$TEMP_FILE")

# 添加时间戳和来源标识
current_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
formatted_comment="**GitHub Issue #$ARGUMENTS 同步更新** - $current_datetime

$comment_content

---
*此评论由CCPM自动同步*"

# 构建评论数据 (假设云效API接受这种格式)
comment_json=$(jq -n \
  --arg content "$formatted_comment" \
  --arg created_time "$current_datetime" \
  --arg workitem_id "$YUNXIAO_WORKITEM_ID" \
  '{
    workitem_id: $workitem_id,
    content: $content,
    created_time: $created_time,
    type: "comment"
  }')

# 调用云效MCP服务发布评论
# 注意：这里假设云效库中有add_workitem_comment函数
if yunxiao_call_mcp "add_workitem_comment" "$comment_json"; then
  echo "✅ 评论成功发布到云效工作项 #$YUNXIAO_WORKITEM_ID"

  # 清理临时文件
  rm -f "$TEMP_FILE"

  # 同时发布到GitHub Issue (保持双向同步)
  echo "🔄 同步发布到GitHub Issue #$ARGUMENTS..."
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    if gh issue comment "$ARGUMENTS" --body-file <(echo "**云效工作项同步更新** - $current_datetime

$comment_content

---
*此评论由CCPM自动同步*"); then
      echo "✅ 评论同时发布到GitHub Issue #$ARGUMENTS"
    else
      echo "⚠️  GitHub评论发布失败，但云效评论已成功"
    fi
  else
    echo "ℹ️  GitHub CLI未配置，跳过GitHub评论发布"
  fi

else
  echo "❌ 云效评论发布失败"
  echo "评论保存在: $TEMP_FILE"
  echo "工作项ID: $YUNXIAO_WORKITEM_ID"

  # 如果云效发布失败，至少尝试发布到GitHub
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    echo "🔄 尝试仅发布到GitHub Issue #$ARGUMENTS..."
    if gh issue comment "$ARGUMENTS" --body-file "$TEMP_FILE"; then
      echo "✅ 评论已发布到GitHub Issue #$ARGUMENTS"
      rm -f "$TEMP_FILE"
    fi
  fi

  exit 1
fi