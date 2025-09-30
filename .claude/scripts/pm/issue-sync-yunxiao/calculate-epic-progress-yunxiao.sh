#!/bin/bash
# Calculate and update epic progress based on yunxiao workitem status

# 获取脚本目录并引入依赖
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"
YUNXIAO_DIR="$(dirname "$SCRIPT_DIR")/yunxiao"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$LIB_DIR/frontmatter.sh"
source "$YUNXIAO_DIR/workitem-common.sh"

EPIC_NAME="$1"
if [ -z "$EPIC_NAME" ]; then
  echo "❌ Error: Epic name required"
  exit 1
fi

if [ ! -d ".claude/epics/$EPIC_NAME" ]; then
  echo "❌ Epic目录不存在: $EPIC_NAME"
  exit 1
fi

echo "🔍 计算Epic进度: $EPIC_NAME"

# 统计epic中的任务
total_tasks=0
closed_tasks=0
in_progress_tasks=0
yunxiao_synced_tasks=0

# 收集云效工作项状态信息
declare -A yunxiao_workitem_status

for task_file in ".claude/epics/$EPIC_NAME"/[0-9]*.md; do
  [ -f "$task_file" ] || continue
  total_tasks=$((total_tasks + 1))

  # 检查任务状态
  status=$(grep '^status:' "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  if [ "$status" = "closed" ]; then
    closed_tasks=$((closed_tasks + 1))
  elif [ "$status" = "open" ] && grep -q "in.*progress\|进行中" "$task_file"; then
    in_progress_tasks=$((in_progress_tasks + 1))
  fi

  # 检查是否关联了云效工作项
  if grep -q "yunxiao_workitem:" "$task_file"; then
    yunxiao_workitem_id=$(grep "yunxiao_workitem:" "$task_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
    if [ -n "$yunxiao_workitem_id" ]; then
      yunxiao_synced_tasks=$((yunxiao_synced_tasks + 1))

      # 尝试获取云效工作项的实时状态
      echo "🔍 检查云效工作项 #$yunxiao_workitem_id 状态..."
      if workitem_data=$(yunxiao_retry_call yunxiao_get_workitem "$yunxiao_workitem_id" 2>/dev/null); then
        yunxiao_status=$(get_workitem_field "$workitem_data" "status")
        yunxiao_workitem_status["$yunxiao_workitem_id"]="$yunxiao_status"
        echo "  状态: $yunxiao_status"
      else
        echo "  ⚠️  无法获取状态"
      fi
    fi
  fi
done

if [ $total_tasks -eq 0 ]; then
  echo "ℹ️  Epic中未找到任务: $EPIC_NAME"
  exit 0
fi

# 计算基础进度百分比
basic_progress=$((closed_tasks * 100 / total_tasks))

# 根据云效工作项状态调整进度计算
adjusted_progress=$basic_progress
yunxiao_completed=0
yunxiao_total=0

for yunxiao_id in "${!yunxiao_workitem_status[@]}"; do
  yunxiao_total=$((yunxiao_total + 1))
  status="${yunxiao_workitem_status[$yunxiao_id]}"

  case "$status" in
    "已完成"|"已关闭"|"completed"|"closed")
      yunxiao_completed=$((yunxiao_completed + 1))
      ;;
    "进行中"|"in_progress")
      # 进行中的任务按50%计算
      yunxiao_completed=$((yunxiao_completed + 1))
      ;;
  esac
done

# 如果有云效同步的任务，使用云效状态进行更精确的计算
if [ $yunxiao_total -gt 0 ]; then
  # 云效同步任务的加权进度
  yunxiao_weighted_progress=$((yunxiao_completed * 100 / yunxiao_total))

  # 非云效同步任务的进度
  local_only_tasks=$((total_tasks - yunxiao_synced_tasks))
  if [ $local_only_tasks -gt 0 ]; then
    local_only_closed=$((closed_tasks - yunxiao_completed))
    local_only_progress=$((local_only_closed * 100 / local_only_tasks))

    # 综合计算：云效任务权重70%，本地任务权重30%
    adjusted_progress=$(( (yunxiao_weighted_progress * yunxiao_synced_tasks * 70 + local_only_progress * local_only_tasks * 30) / (total_tasks * 100) ))
  else
    adjusted_progress=$yunxiao_weighted_progress
  fi
fi

# 更新epic frontmatter
epic_file=".claude/epics/$EPIC_NAME/epic.md"
if [ -f "$epic_file" ]; then
  echo "🔄 更新Epic frontmatter..."

  # 提取当前frontmatter值
  name=$(grep '^name:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  status=$(grep '^status:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  created=$(grep '^created:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  prd=$(grep '^prd:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  github_url=$(grep '^github:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  depends_on=$(grep '^depends_on:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  parallel=$(grep '^parallel:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  conflicts_with=$(grep '^conflicts_with:' "$epic_file" | head -1 | cut -d: -f2- | sed 's/^ *//')

  # 根据进度更新状态
  if [ $adjusted_progress -eq 100 ]; then
    status="completed"
  elif [ $adjusted_progress -gt 0 ] || [ $in_progress_tasks -gt 0 ]; then
    status="in-progress"
  fi

  # 获取当前时间
  current_datetime=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # 构建更新的frontmatter
  {
    echo "---"
    echo "name: $name"
    echo "status: $status"
    echo "created: $created"
    echo "updated: $current_datetime"
    echo "progress: ${adjusted_progress}%"
    [ -n "$prd" ] && echo "prd: $prd"
    [ -n "$github_url" ] && echo "github: $github_url"
    [ -n "$depends_on" ] && echo "depends_on: $depends_on"
    [ -n "$parallel" ] && echo "parallel: $parallel"
    [ -n "$conflicts_with" ] && echo "conflicts_with: $conflicts_with"
    echo "yunxiao_synced_tasks: $yunxiao_synced_tasks"
    echo "---"
    # 添加frontmatter后的内容
    sed '1,/^---$/d; 1,/^---$/d' "$epic_file"
  } > "$epic_file.tmp" && mv "$epic_file.tmp" "$epic_file"

  echo "✅ Epic进度更新完成"
else
  echo "⚠️  Epic文件不存在: $epic_file"
fi

# 输出进度总结
echo ""
echo "=== Epic进度报告 ==="
echo "Epic: $EPIC_NAME"
echo "总任务数: $total_tasks"
echo "已完成: $closed_tasks"
echo "进行中: $in_progress_tasks"
echo "云效同步任务: $yunxiao_synced_tasks"
echo "基础进度: ${basic_progress}%"
echo "调整后进度: ${adjusted_progress}%"

if [ $yunxiao_synced_tasks -gt 0 ]; then
  echo ""
  echo "=== 云效工作项状态 ==="
  for yunxiao_id in "${!yunxiao_workitem_status[@]}"; do
    echo "工作项 #$yunxiao_id: ${yunxiao_workitem_status[$yunxiao_id]}"
  done
fi

echo ""
echo "✅ Epic进度计算完成: ${adjusted_progress}%"