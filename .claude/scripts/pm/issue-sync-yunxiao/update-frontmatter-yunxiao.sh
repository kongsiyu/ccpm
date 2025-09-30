#!/bin/bash
# Update frontmatter in progress and task files after yunxiao sync

# 获取脚本目录并引入依赖
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"
YUNXIAO_DIR="$(dirname "$SCRIPT_DIR")/yunxiao"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$LIB_DIR/frontmatter.sh"
source "$YUNXIAO_DIR/workitem-common.sh"

ARGUMENTS="$1"
COMPLETION="$2"
YUNXIAO_WORKITEM_ID="$3"

if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Issue number required"
  exit 1
fi

# 默认完成度为0
if [ -z "$COMPLETION" ]; then
  COMPLETION="0"
fi

# 查找epic包含此issue
epic_found=""
for epic_dir in .claude/epics/*/; do
  if [ -d "${epic_dir}updates/$ARGUMENTS/" ]; then
    epic_found=$(basename "$epic_dir")
    break
  fi
done

if [ -z "$epic_found" ]; then
  echo "❌ 未找到Issue #$ARGUMENTS的更新目录"
  exit 1
fi

# 获取当前时间
current_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 更新progress.md的frontmatter
progress_file=".claude/epics/$epic_found/updates/$ARGUMENTS/progress.md"
if [ -f "$progress_file" ]; then
  echo "🔄 更新progress.md frontmatter..."

  # 提取当前frontmatter值
  started=$(grep '^started:' "$progress_file" | head -1 | cut -d: -f2- | sed 's/^ *//')

  # 构建更新的frontmatter
  {
    echo "---"
    echo "issue: $ARGUMENTS"
    echo "started: $started"
    echo "last_sync: $current_datetime"
    echo "completion: ${COMPLETION}%"
    # 如果提供了云效工作项ID，添加到frontmatter
    if [ -n "$YUNXIAO_WORKITEM_ID" ]; then
      echo "yunxiao_workitem: $YUNXIAO_WORKITEM_ID"
    fi
    echo "---"
    # 添加frontmatter后的内容
    sed '1,/^---$/d; 1,/^---$/d' "$progress_file"
  } > "$progress_file.tmp" && mv "$progress_file.tmp" "$progress_file"

  echo "✅ 更新了progress.md frontmatter"
fi

# 查找并更新任务文件frontmatter
task_file=""
for task in ".claude/epics/$epic_found"/[0-9]*.md; do
  if [ -f "$task" ] && grep -q "github.*$ARGUMENTS" "$task"; then
    task_file="$task"
    break
  fi
done

if [ -n "$task_file" ]; then
  echo "🔄 更新任务文件frontmatter..."

  # 提取当前frontmatter值
  name=$(grep '^name:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  created=$(grep '^created:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  github_url=$(grep '^github:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  depends_on=$(grep '^depends_on:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  parallel=$(grep '^parallel:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  conflicts_with=$(grep '^conflicts_with:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')

  # 根据完成度确定状态
  if [ "$COMPLETION" = "100" ]; then
    status="closed"
  else
    status="open"
  fi

  # 构建更新的frontmatter
  {
    echo "---"
    echo "name: $name"
    echo "status: $status"
    echo "created: $created"
    echo "updated: $current_datetime"
    echo "github: $github_url"
    [ -n "$depends_on" ] && echo "depends_on: $depends_on"
    [ -n "$parallel" ] && echo "parallel: $parallel"
    [ -n "$conflicts_with" ] && echo "conflicts_with: $conflicts_with"
    # 如果提供了云效工作项ID，添加到frontmatter
    if [ -n "$YUNXIAO_WORKITEM_ID" ]; then
      echo "yunxiao_workitem: $YUNXIAO_WORKITEM_ID"
    fi
    echo "---"
    # 添加frontmatter后的内容
    sed '1,/^---$/d; 1,/^---$/d' "$task_file"
  } > "$task_file.tmp" && mv "$task_file.tmp" "$task_file"

  echo "✅ 更新了任务文件frontmatter: $(basename "$task_file")"
fi

# 如果有云效工作项ID，同步工作项状态到云效
if [ -n "$YUNXIAO_WORKITEM_ID" ]; then
  echo "🔄 同步状态到云效工作项 #$YUNXIAO_WORKITEM_ID..."

  # 根据完成度映射云效状态
  yunxiao_status=""
  case "$COMPLETION" in
    "0")
      yunxiao_status="新建"
      ;;
    "100")
      yunxiao_status="已完成"
      ;;
    *)
      yunxiao_status="进行中"
      ;;
  esac

  # 构建更新数据
  updates_json=$(jq -n \
    --arg status "$yunxiao_status" \
    --arg updated_time "$current_datetime" \
    '{
      status: $status,
      updated_time: $updated_time
    }')

  # 调用云效API更新工作项
  if yunxiao_retry_call yunxiao_update_workitem "$YUNXIAO_WORKITEM_ID" "$updates_json"; then
    echo "✅ 云效工作项状态同步成功"
  else
    echo "⚠️  云效工作项状态同步失败，但本地更新已完成"
  fi
fi

echo "✅ Frontmatter更新完成"
echo "Issue: #$ARGUMENTS"
echo "完成度: ${COMPLETION}%"
if [ -n "$YUNXIAO_WORKITEM_ID" ]; then
  echo "云效工作项: #$YUNXIAO_WORKITEM_ID"
fi