# 云效平台Epic同步规则

基于MCP工具调用的CCPM Epic与云效平台WorkItem同步的完整操作规则。

## 概述

此规则文件定义了Epic生命周期管理的完整流程，包括创建、更新、状态同步和双向数据流管理。通过MCP工具调用实现与云效平台的集成，避免直接API调用，提供统一的操作接口。

## Epic操作流程规则

### Epic创建到云效WorkItem

Epic创建时需要通过MCP工具将Epic信息同步到云效平台：

```bash
# Epic创建同步流程
epic_create_sync() {
  local epic_file="$1"

  # 前置检查
  if ! validate_epic_data "$epic_file"; then
    echo "错误: Epic数据验证失败"
    return 1
  fi

  # 检查平台配置
  local platform=$(yq eval '.platform.type' .claude/ccpm.config 2>/dev/null || echo "github")
  if [ "$platform" != "yunxiao" ]; then
    echo "提示: 当前平台为 $platform，跳过云效同步"
    return 0
  fi

  # 1. 读取Epic数据
  echo "读取Epic文件: $epic_file"
  local epic_frontmatter=$(extract_frontmatter "$epic_file")
  local epic_content=$(extract_content "$epic_file")

  # 2. 转换为云效格式
  echo "转换Epic数据为云效WorkItem格式..."
  local yunxiao_data=$(convert_epic_to_yunxiao "$epic_frontmatter" "$epic_content")

  # 3. 验证转换结果
  if ! validate_yunxiao_workitem_data "$yunxiao_data"; then
    echo "错误: 云效WorkItem数据验证失败"
    return 1
  fi

  # 4. MCP工具调用创建WorkItem
  echo "通过MCP工具创建云效WorkItem..."
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local mcp_result=$(mcp_call "alibabacloud_devops_create_workitem" \
    --project-id "$project_id" \
    --data "$yunxiao_data")

  if [ $? -eq 0 ]; then
    local workitem_id=$(echo "$mcp_result" | jq -r '.id')
    local workitem_url=$(echo "$mcp_result" | jq -r '.url // ""')

    echo "✓ Epic创建成功，云效WorkItem ID: $workitem_id"

    # 5. 更新Epic frontmatter
    update_epic_frontmatter "$epic_file" \
      --yunxiao-id "$workitem_id" \
      --yunxiao-url "$workitem_url" \
      --sync-time "$(date -Iseconds)" \
      --sync-status "synced"

    echo "✓ Epic frontmatter已更新"
    return 0
  else
    echo "✗ Epic创建失败，MCP调用返回错误"
    return 1
  fi
}
```

### Epic更新同步规则

Epic状态或内容更新时的同步处理：

```bash
# Epic更新同步流程
epic_update_sync() {
  local epic_file="$1"
  local force_sync="${2:-false}"

  # 检查是否已关联云效WorkItem
  local yunxiao_id=$(yq eval '.yunxiao.id // ""' "$epic_file")
  if [ -z "$yunxiao_id" ]; then
    echo "提示: Epic未关联云效WorkItem，执行首次创建同步"
    epic_create_sync "$epic_file"
    return $?
  fi

  echo "开始Epic更新同步，云效WorkItem ID: $yunxiao_id"

  # 1. 获取本地Epic状态
  local local_updated=$(yq eval '.updated // ""' "$epic_file")
  local local_status=$(yq eval '.status // "pending"' "$epic_file")
  local sync_status=$(yq eval '.yunxiao.sync_status // ""' "$epic_file")

  # 2. 获取云效WorkItem当前状态
  echo "获取云效WorkItem当前状态..."
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
    --project-id "$project_id" \
    --workitem-id "$yunxiao_id")

  if [ $? -ne 0 ]; then
    echo "警告: 无法获取云效WorkItem状态，可能已被删除"
    # 清除本地关联信息
    update_epic_frontmatter "$epic_file" \
      --yunxiao-id "" \
      --yunxiao-url "" \
      --sync-status "unsynced"
    return 1
  fi

  local yunxiao_updated=$(echo "$workitem_data" | jq -r '.updated_at // ""')
  local yunxiao_status=$(echo "$workitem_data" | jq -r '.status // ""')

  # 3. 冲突检测和解决
  if [ "$force_sync" = "true" ]; then
    echo "强制同步: 本地 → 云效"
    sync_epic_to_yunxiao "$epic_file" "$yunxiao_id"
  elif [[ "$local_updated" > "$yunxiao_updated" ]]; then
    echo "本地更新较新: 本地 → 云效"
    sync_epic_to_yunxiao "$epic_file" "$yunxiao_id"
  elif [[ "$yunxiao_updated" > "$local_updated" ]]; then
    echo "云效更新较新: 云效 → 本地"
    sync_yunxiao_to_epic "$epic_file" "$workitem_data"
  else
    echo "两端状态一致，无需同步"
    # 更新同步状态
    update_epic_frontmatter "$epic_file" --sync-status "synced"
  fi
}

# 本地Epic同步到云效
sync_epic_to_yunxiao() {
  local epic_file="$1"
  local yunxiao_id="$2"

  echo "同步本地Epic到云效WorkItem..."

  # 转换Epic数据
  local epic_frontmatter=$(extract_frontmatter "$epic_file")
  local epic_content=$(extract_content "$epic_file")
  local update_data=$(convert_epic_update_to_yunxiao "$epic_frontmatter" "$epic_content")

  # MCP更新WorkItem
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local mcp_result=$(mcp_call "alibabacloud_devops_update_workitem" \
    --project-id "$project_id" \
    --workitem-id "$yunxiao_id" \
    --data "$update_data")

  if [ $? -eq 0 ]; then
    echo "✓ Epic同步到云效成功"
    update_epic_frontmatter "$epic_file" \
      --sync-time "$(date -Iseconds)" \
      --sync-status "synced"
    return 0
  else
    echo "✗ Epic同步到云效失败"
    update_epic_frontmatter "$epic_file" --sync-status "error"
    return 1
  fi
}

# 云效WorkItem同步到本地Epic
sync_yunxiao_to_epic() {
  local epic_file="$1"
  local workitem_data="$2"

  echo "同步云效WorkItem到本地Epic..."

  # 提取云效数据
  local yunxiao_status=$(echo "$workitem_data" | jq -r '.status')
  local yunxiao_updated=$(echo "$workitem_data" | jq -r '.updated_at')
  local yunxiao_assignee=$(echo "$workitem_data" | jq -r '.assignee // ""')
  local yunxiao_priority=$(echo "$workitem_data" | jq -r '.priority // ""')

  # 映射云效状态到Epic状态
  local epic_status
  case "$yunxiao_status" in
    "待处理") epic_status="pending" ;;
    "进行中") epic_status="in_progress" ;;
    "已完成") epic_status="completed" ;;
    "已暂停") epic_status="blocked" ;;
    *) epic_status="pending" ;;
  esac

  # 映射优先级
  local epic_priority
  case "$yunxiao_priority" in
    "低") epic_priority="low" ;;
    "中") epic_priority="medium" ;;
    "高") epic_priority="high" ;;
    "紧急") epic_priority="urgent" ;;
    *) epic_priority="medium" ;;
  esac

  # 更新Epic frontmatter
  update_epic_frontmatter "$epic_file" \
    --status "$epic_status" \
    --priority "$epic_priority" \
    --assignee "$yunxiao_assignee" \
    --updated "$yunxiao_updated" \
    --sync-time "$(date -Iseconds)" \
    --sync-status "synced"

  echo "✓ 云效WorkItem同步到Epic成功"
}
```

### Epic状态流转规则

定义Epic状态变化时的同步行为：

```yaml
epic_status_flow:
  # Epic状态 → 云效状态映射
  status_mapping:
    pending: "待处理"
    in_progress: "进行中"
    completed: "已完成"
    blocked: "已暂停"
    cancelled: "已关闭"

  # 状态变更触发同步
  auto_sync_triggers:
    - status_change: true
    - assignee_change: true
    - priority_change: true
    - deadline_change: true

  # 同步冷却时间（避免频繁同步）
  sync_cooldown: 30  # 秒
```

## Epic数据转换专用函数

### Epic转换函数增强

基于platform-yunxiao-data-mapping.md的函数，增加Epic专用优化：

```bash
# Epic更新数据转换（仅包含变更字段）
convert_epic_update_to_yunxiao() {
  local epic_frontmatter="$1"
  local epic_content="$2"

  # 提取可能变更的字段
  local title=$(echo "$epic_frontmatter" | yq eval '.title // ""' -)
  local status=$(echo "$epic_frontmatter" | yq eval '.status // "pending"' -)
  local priority=$(echo "$epic_frontmatter" | yq eval '.priority // "medium"' -)
  local assignee=$(echo "$epic_frontmatter" | yq eval '.assignee // ""' -)
  local estimated_hours=$(echo "$epic_frontmatter" | yq eval '.estimated_hours // 0' -)
  local actual_hours=$(echo "$epic_frontmatter" | yq eval '.actual_hours // 0' -)

  # 映射状态
  local yunxiao_status
  case "$status" in
    "pending") yunxiao_status="待处理" ;;
    "in_progress") yunxiao_status="进行中" ;;
    "completed") yunxiao_status="已完成" ;;
    "blocked") yunxiao_status="已暂停" ;;
    "cancelled") yunxiao_status="已关闭" ;;
    *) yunxiao_status="待处理" ;;
  esac

  # 映射优先级
  local yunxiao_priority
  case "$priority" in
    "low") yunxiao_priority="低" ;;
    "medium") yunxiao_priority="中" ;;
    "high") yunxiao_priority="高" ;;
    "urgent") yunxiao_priority="紧急" ;;
    *) yunxiao_priority="中" ;;
  esac

  # 构建更新数据（仅包含变更字段）
  local update_data=$(cat <<EOF
{
  "title": "$title",
  "description": $(echo "$epic_content" | jq -Rs .),
  "status": "$yunxiao_status",
  "priority": "$yunxiao_priority",
  "assignee": "$assignee",
  "custom_fields": {
    "estimated_hours": $estimated_hours,
    "actual_hours": $actual_hours,
    "sync_source": "ccpm_epic_update",
    "sync_time": "$(date -Iseconds)"
  }
}
EOF
)

  echo "$update_data"
}

# Epic状态变更历史记录
log_epic_status_change() {
  local epic_file="$1"
  local old_status="$2"
  local new_status="$3"
  local yunxiao_id="$4"

  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local log_entry="[$timestamp] Epic状态变更: $old_status → $new_status (云效ID: $yunxiao_id)"

  # 添加到Epic文件注释或日志
  echo "<!-- $log_entry -->" >> "$epic_file"

  # 可选：记录到专用日志文件
  echo "$log_entry" >> ".claude/logs/epic-sync.log"
}
```

## Epic同步命令集成

### 命令行接口规范

Epic同步功能应集成到CCPM命令系统中：

```bash
# Epic同步命令接口
ccpm_epic_sync() {
  local command="$1"
  local epic_file="$2"
  local options=("${@:3}")

  case "$command" in
    "create")
      echo "创建Epic并同步到云效..."
      epic_create_sync "$epic_file"
      ;;
    "update")
      echo "更新Epic同步..."
      epic_update_sync "$epic_file"
      ;;
    "force-sync")
      echo "强制同步Epic到云效..."
      epic_update_sync "$epic_file" "true"
      ;;
    "status")
      echo "检查Epic同步状态..."
      check_epic_sync_status "$epic_file"
      ;;
    "unlink")
      echo "取消Epic与云效的关联..."
      unlink_epic_from_yunxiao "$epic_file"
      ;;
    *)
      echo "错误: 未知的Epic同步命令: $command"
      echo "可用命令: create, update, force-sync, status, unlink"
      return 1
      ;;
  esac
}

# Epic同步状态检查
check_epic_sync_status() {
  local epic_file="$1"

  if [ ! -f "$epic_file" ]; then
    echo "错误: Epic文件不存在: $epic_file"
    return 1
  fi

  local title=$(yq eval '.title // "未命名Epic"' "$epic_file")
  local yunxiao_id=$(yq eval '.yunxiao.id // ""' "$epic_file")
  local sync_status=$(yq eval '.yunxiao.sync_status // "unsynced"' "$epic_file")
  local sync_time=$(yq eval '.yunxiao.sync_time // ""' "$epic_file")

  echo "=== Epic同步状态 ==="
  echo "Epic标题: $title"
  echo "Epic文件: $epic_file"

  if [ -n "$yunxiao_id" ]; then
    echo "云效WorkItem ID: $yunxiao_id"
    echo "同步状态: $sync_status"
    echo "最后同步时间: $sync_time"

    # 检查云效端状态
    local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
    local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
      --project-id "$project_id" \
      --workitem-id "$yunxiao_id" 2>/dev/null)

    if [ $? -eq 0 ]; then
      local yunxiao_status=$(echo "$workitem_data" | jq -r '.status')
      local yunxiao_updated=$(echo "$workitem_data" | jq -r '.updated_at')
      echo "云效端状态: $yunxiao_status"
      echo "云效端更新时间: $yunxiao_updated"
    else
      echo "警告: 无法获取云效端状态（可能已删除）"
    fi
  else
    echo "同步状态: 未关联云效WorkItem"
  fi
}

# 取消Epic与云效的关联
unlink_epic_from_yunxiao() {
  local epic_file="$1"

  local yunxiao_id=$(yq eval '.yunxiao.id // ""' "$epic_file")
  if [ -z "$yunxiao_id" ]; then
    echo "Epic未关联云效WorkItem，无需取消关联"
    return 0
  fi

  echo "取消Epic与云效WorkItem ($yunxiao_id) 的关联..."

  # 清除关联信息
  update_epic_frontmatter "$epic_file" \
    --yunxiao-id "" \
    --yunxiao-url "" \
    --sync-status "unsynced" \
    --sync-time ""

  echo "✓ Epic关联已清除"
  echo "注意: 云效端WorkItem不会被删除，需要手动处理"
}
```

## Epic批量操作规则

### 批量Epic同步

支持对多个Epic进行批量同步操作：

```bash
# 批量Epic同步
batch_epic_sync() {
  local epic_dir="$1"
  local operation="${2:-update}"

  echo "=== 批量Epic同步 ==="
  echo "Epic目录: $epic_dir"
  echo "操作类型: $operation"

  # 查找所有Epic文件
  local epic_files=($(find "$epic_dir" -name "*.md" -type f))
  local total_count=${#epic_files[@]}

  if [ $total_count -eq 0 ]; then
    echo "未找到Epic文件"
    return 0
  fi

  echo "发现 $total_count 个Epic文件"

  local success_count=0
  local failed_count=0

  for epic_file in "${epic_files[@]}"; do
    echo ""
    echo "处理Epic: $epic_file"

    case "$operation" in
      "create")
        if epic_create_sync "$epic_file"; then
          ((success_count++))
        else
          ((failed_count++))
        fi
        ;;
      "update")
        if epic_update_sync "$epic_file"; then
          ((success_count++))
        else
          ((failed_count++))
        fi
        ;;
      "status")
        check_epic_sync_status "$epic_file"
        ;;
    esac

    # 避免API限流
    sleep 1
  done

  echo ""
  echo "=== 批量同步完成 ==="
  echo "总计: $total_count"
  echo "成功: $success_count"
  echo "失败: $failed_count"
}
```

## 错误处理和恢复

### Epic同步错误处理

```bash
# Epic同步错误恢复
recover_epic_sync() {
  local epic_file="$1"

  echo "开始Epic同步错误恢复..."

  # 检查Epic文件状态
  local sync_status=$(yq eval '.yunxiao.sync_status // ""' "$epic_file")

  case "$sync_status" in
    "error")
      echo "检测到同步错误状态，尝试重新同步..."
      epic_update_sync "$epic_file"
      ;;
    "unsynced")
      echo "Epic未同步，尝试创建同步..."
      epic_create_sync "$epic_file"
      ;;
    "synced")
      echo "Epic状态正常，检查云效端一致性..."
      epic_update_sync "$epic_file"
      ;;
    *)
      echo "未知同步状态，重置为未同步..."
      update_epic_frontmatter "$epic_file" --sync-status "unsynced"
      epic_create_sync "$epic_file"
      ;;
  esac
}

# 云效连接检查
check_yunxiao_connectivity() {
  echo "检查云效平台连接..."

  # 测试项目访问
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local project_info=$(mcp_call "alibabacloud_devops_get_project_info" \
    --project-id "$project_id" 2>/dev/null)

  if [ $? -eq 0 ]; then
    echo "✓ 云效平台连接正常"
    return 0
  else
    echo "✗ 云效平台连接失败"
    echo "请检查:"
    echo "1. 网络连接是否正常"
    echo "2. MCP工具配置是否正确"
    echo "3. 访问令牌是否有效"
    echo "4. 项目ID是否正确"
    return 1
  fi
}
```

## 使用示例

### 完整Epic同步工作流示例

```bash
#!/bin/bash

# Epic同步工作流示例
epic_sync_workflow_example() {
  local epic_file=".claude/epics/pm-tool-alibabacloud-devops/epic.md"

  echo "=== Epic同步工作流示例 ==="

  # 1. 检查云效连接
  if ! check_yunxiao_connectivity; then
    echo "云效连接失败，终止同步"
    return 1
  fi

  # 2. 检查Epic文件
  if [ ! -f "$epic_file" ]; then
    echo "Epic文件不存在: $epic_file"
    return 1
  fi

  # 3. 检查当前同步状态
  echo ""
  check_epic_sync_status "$epic_file"

  # 4. 执行同步操作
  echo ""
  echo "开始Epic同步..."

  local yunxiao_id=$(yq eval '.yunxiao.id // ""' "$epic_file")
  if [ -z "$yunxiao_id" ]; then
    echo "首次同步，创建云效WorkItem..."
    epic_create_sync "$epic_file"
  else
    echo "更新同步..."
    epic_update_sync "$epic_file"
  fi

  # 5. 验证同步结果
  echo ""
  echo "同步后状态:"
  check_epic_sync_status "$epic_file"
}

# 运行示例
# epic_sync_workflow_example
```

## 配置要求

### Epic同步所需配置

```yaml
# .claude/ccpm.config 中的云效平台配置
platform:
  type: "yunxiao"
  project_id: "your_project_id"
  base_url: "https://devops.aliyun.com"
  api_version: "v4"

# 环境变量要求
# YUNXIAO_ACCESS_TOKEN: 云效访问令牌
```

### frontmatter扩展字段

Epic文件需要支持云效同步相关字段：

```yaml
---
title: "Epic标题"
status: "in_progress"
priority: "high"
assignee: "user@example.com"
estimated_hours: 40
actual_hours: 15

# 云效同步字段
yunxiao:
  id: "workitem_12345"
  url: "https://devops.aliyun.com/workitem/12345"
  sync_status: "synced"  # synced, unsynced, error
  sync_time: "2025-09-28T10:30:00Z"
---
```

## 版本信息

- **规则版本**: v1.0.0
- **支持的Epic格式**: CCPM Epic frontmatter
- **支持的云效API**: v4
- **最后更新**: 2025-09-28
- **依赖规则**: platform-yunxiao-data-mapping.md, platform-yunxiao-sync.md
- **依赖工具**: yq, jq, MCP alibabacloud_devops_* 工具套件

## 相关规则引用

- `.claude/rules/platform-yunxiao-data-mapping.md` - 数据转换函数库
- `.claude/rules/platform-yunxiao-sync.md` - 基础同步规则
- `.claude/rules/platform-config.md` - 平台配置规则
- `.claude/rules/frontmatter-operations.md` - frontmatter操作规则