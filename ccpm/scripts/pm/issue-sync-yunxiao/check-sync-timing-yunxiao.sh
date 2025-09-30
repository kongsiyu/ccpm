#!/bin/bash
# Check last sync timing to prevent excessive yunxiao syncing

# 获取脚本目录并引入依赖
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/datetime.sh"

ARGUMENTS="$1"
FORCE_SYNC="${2:-false}"

if [ -z "$ARGUMENTS" ]; then
  echo "❌ Error: Issue number required"
  exit 1
fi

# 查找包含此issue的epic
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

progress_file=".claude/epics/$epic_found/updates/$ARGUMENTS/progress.md"

if [ ! -f "$progress_file" ]; then
  echo "ℹ️  未找到之前的同步记录 - 执行首次同步"
  exit 0
fi

# 从frontmatter提取last_sync时间戳
last_sync=$(grep '^last_sync:' "$progress_file" | head -1 | cut -d: -f2- | sed 's/^ *//')

if [ -z "$last_sync" ] || [ "$last_sync" = "null" ]; then
  echo "ℹ️  未找到上次同步时间戳 - 允许同步"
  exit 0
fi

# 计算时间差 (基本检查 - 5分钟 = 300秒，对于云效API可能需要更长间隔)
current_time=$(date -u +%s)

# 尝试解析last_sync时间戳
last_sync_time=0
if command -v gdate >/dev/null 2>&1; then
  # macOS with GNU coreutils
  last_sync_time=$(gdate -d "$last_sync" +%s 2>/dev/null || echo "0")
else
  # Linux date
  last_sync_time=$(date -d "$last_sync" +%s 2>/dev/null || echo "0")
fi

# 如果时间解析失败，允许同步
if [ "$last_sync_time" -eq 0 ]; then
  echo "⚠️  无法解析上次同步时间，允许同步"
  exit 0
fi

time_diff=$((current_time - last_sync_time))

# 云效同步最小间隔设置为10分钟（600秒），避免API限流
MIN_SYNC_INTERVAL=600

if [ "$time_diff" -lt $MIN_SYNC_INTERVAL ]; then
  minutes_ago=$((time_diff / 60))
  echo "⚠️  最近在 $minutes_ago 分钟前进行过云效同步"

  # 检查是否强制同步
  if [ "$FORCE_SYNC" = "true" ] || [ "$FORCE_SYNC" = "1" ]; then
    echo "🔄 强制同步模式，跳过时间检查"
    exit 0
  fi

  # 在自动化上下文中，建议稍后重试
  remaining_time=$((MIN_SYNC_INTERVAL - time_diff))
  remaining_minutes=$((remaining_time / 60))

  echo "建议等待 $remaining_minutes 分钟后再次同步，或使用 --force 参数强制同步"
  echo "云效API有访问频率限制，频繁同步可能导致失败"

  # 返回特殊退出码，表示需要等待
  exit 2
fi

# 检查是否存在云效工作项关联
if grep -q "yunxiao_workitem:" "$progress_file"; then
  yunxiao_workitem_id=$(grep "yunxiao_workitem:" "$progress_file" | head -1 | cut -d: -f2- | sed 's/^ *//')
  if [ -n "$yunxiao_workitem_id" ]; then
    echo "✅ 云效工作项 #$yunxiao_workitem_id 同步时机检查通过"
  fi
else
  echo "ℹ️  未找到云效工作项关联，将创建新工作项"
fi

echo "✅ 云效同步时机检查通过"
echo "距离上次同步: $((time_diff / 60)) 分钟"