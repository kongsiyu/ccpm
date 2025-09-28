# 云效平台Issue同步规则

基于MCP工具调用的GitHub Issue与云效平台WorkItem双向同步的完整操作规则。

## 概述

此规则文件定义了GitHub Issue与云效WorkItem之间的双向同步规则，支持单个Issue同步、批量同步和实时状态监控。通过MCP工具调用实现，避免直接API集成，提供统一的Issue管理接口。

## Issue同步流程规则

### GitHub Issue到云效WorkItem同步

将GitHub Issue创建为云效WorkItem的完整流程：

```bash
# GitHub Issue创建到云效同步
github_issue_to_yunxiao_sync() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_number="$3"

  echo "开始GitHub Issue #$issue_number 到云效同步..."

  # 前置检查
  local platform=$(yq eval '.platform.type' .claude/ccpm.config 2>/dev/null || echo "github")
  if [ "$platform" != "yunxiao" ]; then
    echo "提示: 当前平台为 $platform，跳过云效同步"
    return 0
  fi

  # 1. 获取GitHub Issue数据
  echo "获取GitHub Issue数据..."
  local issue_data=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number)

  if [ $? -ne 0 ]; then
    echo "错误: 无法获取GitHub Issue #$issue_number"
    return 1
  fi

  # 2. 检查是否已同步
  local labels=$(echo "$issue_data" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
  if echo "$labels" | grep -q "yunxiao-sync"; then
    echo "Issue #$issue_number 已标记为已同步，跳过重复同步"
    return 0
  fi

  # 3. 验证Issue数据
  if ! validate_github_issue_data "$issue_data"; then
    echo "错误: GitHub Issue数据验证失败"
    return 1
  fi

  # 4. 转换为云效格式
  echo "转换Issue数据为云效WorkItem格式..."
  local yunxiao_data=$(convert_github_issue_to_yunxiao "$issue_data")

  # 5. 验证转换结果
  if ! validate_yunxiao_workitem_data "$yunxiao_data"; then
    echo "错误: 云效WorkItem数据验证失败"
    return 1
  fi

  # 6. MCP工具调用创建WorkItem
  echo "通过MCP工具创建云效WorkItem..."
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local mcp_result=$(mcp_call "alibabacloud_devops_create_workitem" \
    --project-id "$project_id" \
    --data "$yunxiao_data")

  if [ $? -eq 0 ]; then
    local workitem_id=$(echo "$mcp_result" | jq -r '.id')
    local workitem_url=$(echo "$mcp_result" | jq -r '.url // ""')

    echo "✓ Issue同步成功，云效WorkItem ID: $workitem_id"

    # 7. 在GitHub Issue添加关联评论
    local comment_body="🔗 **已关联云效工作项**

- **WorkItem ID**: $workitem_id
- **WorkItem URL**: $workitem_url
- **同步时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **同步方向**: GitHub → 云效

此Issue已自动同步到云效平台，后续状态变更将双向同步。"

    gh api repos/$repo_owner/$repo_name/issues/$issue_number/comments \
      --field body="$comment_body"

    # 8. 添加同步标签
    gh api repos/$repo_owner/$repo_name/issues/$issue_number/labels \
      --field labels='["yunxiao-sync"]'

    echo "✓ GitHub Issue已标记为已同步"
    return 0
  else
    echo "✗ Issue同步失败，MCP调用返回错误"
    return 1
  fi
}
```

### 云效WorkItem到GitHub Issue同步

将云效WorkItem创建为GitHub Issue的流程：

```bash
# 云效WorkItem到GitHub Issue同步
yunxiao_workitem_to_github_sync() {
  local project_id="$1"
  local workitem_id="$2"
  local repo_owner="$3"
  local repo_name="$4"

  echo "开始云效WorkItem $workitem_id 到GitHub同步..."

  # 1. 获取云效WorkItem数据
  echo "获取云效WorkItem数据..."
  local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
    --project-id "$project_id" \
    --workitem-id "$workitem_id")

  if [ $? -ne 0 ]; then
    echo "错误: 无法获取云效WorkItem $workitem_id"
    return 1
  fi

  # 2. 检查是否已同步
  local custom_fields=$(echo "$workitem_data" | jq -r '.custom_fields // {}')
  local github_issue_number=$(echo "$custom_fields" | jq -r '.github_issue_number // ""')

  if [ -n "$github_issue_number" ] && [ "$github_issue_number" != "null" ]; then
    echo "WorkItem $workitem_id 已关联GitHub Issue #$github_issue_number，跳过重复同步"
    return 0
  fi

  # 3. 验证WorkItem数据
  if ! validate_yunxiao_workitem_data "$workitem_data"; then
    echo "错误: 云效WorkItem数据验证失败"
    return 1
  fi

  # 4. 转换为GitHub Issue格式
  echo "转换WorkItem数据为GitHub Issue格式..."
  local github_issue_data=$(convert_yunxiao_to_github_issue "$workitem_data")

  # 5. 创建GitHub Issue
  echo "创建GitHub Issue..."
  local issue_result=$(gh api repos/$repo_owner/$repo_name/issues \
    --method POST \
    --input <(echo "$github_issue_data"))

  if [ $? -eq 0 ]; then
    local github_issue_number=$(echo "$issue_result" | jq -r '.number')
    local github_issue_url=$(echo "$issue_result" | jq -r '.html_url')

    echo "✓ GitHub Issue创建成功，Issue #$github_issue_number"

    # 6. 更新云效WorkItem关联信息
    local update_data=$(cat <<EOF
{
  "custom_fields": {
    "github_issue_number": "$github_issue_number",
    "github_url": "$github_issue_url",
    "sync_source": "yunxiao_to_github",
    "sync_time": "$(date -Iseconds)"
  }
}
EOF
)

    mcp_call "alibabacloud_devops_update_workitem" \
      --project-id "$project_id" \
      --workitem-id "$workitem_id" \
      --data "$update_data"

    echo "✓ 云效WorkItem关联信息已更新"
    return 0
  else
    echo "✗ GitHub Issue创建失败"
    return 1
  fi
}
```

### Issue状态双向同步

处理Issue状态变更的双向同步：

```bash
# Issue状态双向同步
issue_status_bidirectional_sync() {
  local sync_direction="$1"  # github_to_yunxiao 或 yunxiao_to_github
  local repo_owner="$2"
  local repo_name="$3"
  local issue_number="$4"
  local workitem_id="${5:-}"

  case "$sync_direction" in
    "github_to_yunxiao")
      sync_github_issue_status_to_yunxiao "$repo_owner" "$repo_name" "$issue_number"
      ;;
    "yunxiao_to_github")
      sync_yunxiao_status_to_github_issue "$repo_owner" "$repo_name" "$issue_number" "$workitem_id"
      ;;
    "auto")
      auto_detect_and_sync_issue_status "$repo_owner" "$repo_name" "$issue_number"
      ;;
    *)
      echo "错误: 未知的同步方向: $sync_direction"
      return 1
      ;;
  esac
}

# GitHub Issue状态同步到云效
sync_github_issue_status_to_yunxiao() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_number="$3"

  echo "同步GitHub Issue #$issue_number 状态到云效..."

  # 获取GitHub Issue当前状态
  local issue_data=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number)
  local github_state=$(echo "$issue_data" | jq -r '.state')
  local github_updated=$(echo "$issue_data" | jq -r '.updated_at')

  # 查找关联的云效WorkItem
  local workitem_id=$(get_workitem_id_from_github_issue "$repo_owner" "$repo_name" "$issue_number")

  if [ -z "$workitem_id" ]; then
    echo "GitHub Issue #$issue_number 未关联云效WorkItem，跳过状态同步"
    return 0
  fi

  # 映射GitHub状态到云效状态
  local yunxiao_status
  case "$github_state" in
    "open") yunxiao_status="待处理" ;;
    "closed") yunxiao_status="已完成" ;;
    *) yunxiao_status="待处理" ;;
  esac

  # 检查是否有进度标签（扩展状态）
  local labels=$(echo "$issue_data" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
  if echo "$labels" | grep -q "in progress"; then
    yunxiao_status="进行中"
  elif echo "$labels" | grep -q "in review"; then
    yunxiao_status="待验收"
  fi

  # 更新云效WorkItem状态
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local update_data=$(cat <<EOF
{
  "status": "$yunxiao_status",
  "custom_fields": {
    "github_sync_time": "$github_updated",
    "sync_source": "github_status_update"
  }
}
EOF
)

  local mcp_result=$(mcp_call "alibabacloud_devops_update_workitem" \
    --project-id "$project_id" \
    --workitem-id "$workitem_id" \
    --data "$update_data")

  if [ $? -eq 0 ]; then
    echo "✓ GitHub Issue状态已同步到云效 ($github_state → $yunxiao_status)"
  else
    echo "✗ GitHub Issue状态同步失败"
    return 1
  fi
}

# 云效WorkItem状态同步到GitHub Issue
sync_yunxiao_status_to_github_issue() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_number="$3"
  local workitem_id="$4"

  echo "同步云效WorkItem $workitem_id 状态到GitHub Issue #$issue_number..."

  # 获取云效WorkItem当前状态
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
    --project-id "$project_id" \
    --workitem-id "$workitem_id")

  local yunxiao_status=$(echo "$workitem_data" | jq -r '.status')
  local yunxiao_updated=$(echo "$workitem_data" | jq -r '.updated_at')

  # 映射云效状态到GitHub状态和标签
  local github_state="open"
  local status_labels=()

  case "$yunxiao_status" in
    "待处理")
      github_state="open"
      ;;
    "进行中")
      github_state="open"
      status_labels+=("in progress")
      ;;
    "待验收")
      github_state="open"
      status_labels+=("in review")
      ;;
    "已完成"|"已关闭")
      github_state="closed"
      ;;
    *)
      github_state="open"
      ;;
  esac

  # 更新GitHub Issue状态
  gh api repos/$repo_owner/$repo_name/issues/$issue_number \
    --method PATCH \
    --field state="$github_state"

  # 更新状态标签
  if [ ${#status_labels[@]} -gt 0 ]; then
    # 移除旧状态标签
    local current_labels=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number | jq -r '.labels[].name')
    local filtered_labels=$(echo "$current_labels" | grep -v -E "^(in progress|in review)$" | tr '\n' ',' | sed 's/,$//')

    # 添加新状态标签
    local new_labels="$filtered_labels"
    for label in "${status_labels[@]}"; do
      if [ -n "$new_labels" ]; then
        new_labels="$new_labels,$label"
      else
        new_labels="$label"
      fi
    done

    # 应用标签更新
    gh api repos/$repo_owner/$repo_name/issues/$issue_number/labels \
      --method PUT \
      --field labels="$(echo "$new_labels" | tr ',' '\n' | jq -R . | jq -s .)"
  fi

  echo "✓ 云效WorkItem状态已同步到GitHub Issue ($yunxiao_status → $github_state)"

  # 添加同步评论
  local comment_body="🔄 **状态同步更新**

云效WorkItem状态已更新为: **$yunxiao_status**
GitHub Issue状态已同步为: **$github_state**

同步时间: $(date '+%Y-%m-%d %H:%M:%S')"

  gh api repos/$repo_owner/$repo_name/issues/$issue_number/comments \
    --field body="$comment_body"
}

# 自动检测并同步Issue状态
auto_detect_and_sync_issue_status() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_number="$3"

  echo "自动检测Issue #$issue_number 同步状态..."

  # 获取GitHub Issue数据
  local issue_data=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number)
  local github_updated=$(echo "$issue_data" | jq -r '.updated_at')

  # 查找关联的云效WorkItem
  local workitem_id=$(get_workitem_id_from_github_issue "$repo_owner" "$repo_name" "$issue_number")

  if [ -z "$workitem_id" ]; then
    echo "Issue #$issue_number 未关联云效WorkItem，无法进行状态同步"
    return 0
  fi

  # 获取云效WorkItem数据
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
    --project-id "$project_id" \
    --workitem-id "$workitem_id")

  local yunxiao_updated=$(echo "$workitem_data" | jq -r '.updated_at')

  # 比较更新时间，确定同步方向
  if [[ "$github_updated" > "$yunxiao_updated" ]]; then
    echo "GitHub更新较新，同步到云效..."
    sync_github_issue_status_to_yunxiao "$repo_owner" "$repo_name" "$issue_number"
  elif [[ "$yunxiao_updated" > "$github_updated" ]]; then
    echo "云效更新较新，同步到GitHub..."
    sync_yunxiao_status_to_github_issue "$repo_owner" "$repo_name" "$issue_number" "$workitem_id"
  else
    echo "两端状态一致，无需同步"
  fi
}
```

## Issue批量操作规则

### 批量Issue同步

支持批量GitHub Issue到云效的同步：

```bash
# 批量GitHub Issue同步
batch_github_issues_sync() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_filter="${3:-open}"  # open, closed, all

  echo "=== 批量GitHub Issue同步 ==="
  echo "仓库: $repo_owner/$repo_name"
  echo "过滤条件: $issue_filter"

  # 获取Issues列表（排除已同步的）
  local issues_data
  case "$issue_filter" in
    "open")
      issues_data=$(gh api repos/$repo_owner/$repo_name/issues \
        --field state=open \
        --field labels="!yunxiao-sync" \
        --paginate)
      ;;
    "closed")
      issues_data=$(gh api repos/$repo_owner/$repo_name/issues \
        --field state=closed \
        --field labels="!yunxiao-sync" \
        --paginate)
      ;;
    "all")
      issues_data=$(gh api repos/$repo_owner/$repo_name/issues \
        --field state=all \
        --field labels="!yunxiao-sync" \
        --paginate)
      ;;
  esac

  local issue_count=$(echo "$issues_data" | jq length)
  echo "发现 $issue_count 个未同步Issue"

  if [ "$issue_count" -eq 0 ]; then
    echo "没有需要同步的Issue"
    return 0
  fi

  local success_count=0
  local failed_count=0

  echo "$issues_data" | jq -c '.[]' | while read -r issue; do
    local issue_number=$(echo "$issue" | jq -r '.number')
    local issue_title=$(echo "$issue" | jq -r '.title')

    echo ""
    echo "同步Issue #$issue_number: $issue_title"

    if github_issue_to_yunxiao_sync "$repo_owner" "$repo_name" "$issue_number"; then
      echo "  ✓ 同步成功"
      ((success_count++))
    else
      echo "  ✗ 同步失败"
      ((failed_count++))
    fi

    # 避免API限流
    sleep 2
  done

  echo ""
  echo "=== 批量同步完成 ==="
  echo "成功: $success_count"
  echo "失败: $failed_count"
}

# 批量状态同步
batch_issue_status_sync() {
  local repo_owner="$1"
  local repo_name="$2"

  echo "=== 批量Issue状态同步 ==="

  # 获取已同步的Issues
  local synced_issues=$(gh api repos/$repo_owner/$repo_name/issues \
    --field state=all \
    --field labels="yunxiao-sync" \
    --paginate)

  local issue_count=$(echo "$synced_issues" | jq length)
  echo "发现 $issue_count 个已同步Issue"

  if [ "$issue_count" -eq 0 ]; then
    echo "没有已同步的Issue需要状态同步"
    return 0
  fi

  echo "$synced_issues" | jq -c '.[]' | while read -r issue; do
    local issue_number=$(echo "$issue" | jq -r '.number')
    local issue_title=$(echo "$issue" | jq -r '.title')

    echo ""
    echo "检查Issue #$issue_number 状态同步: $issue_title"

    if auto_detect_and_sync_issue_status "$repo_owner" "$repo_name" "$issue_number"; then
      echo "  ✓ 状态同步完成"
    else
      echo "  ✗ 状态同步失败"
    fi

    # 避免API限流
    sleep 1
  done
}
```

## Issue查询和管理

### Issue关联查询

```bash
# 根据GitHub Issue查找关联的云效WorkItem ID
get_workitem_id_from_github_issue() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_number="$3"

  # 从Issue评论中查找WorkItem ID
  local comments=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number/comments)
  local workitem_id=$(echo "$comments" | jq -r '.[] | select(.body | contains("WorkItem ID")) | .body' | grep -o "WorkItem ID.*: [0-9]\+" | head -1 | grep -o "[0-9]\+$")

  echo "$workitem_id"
}

# 根据云效WorkItem查找关联的GitHub Issue
get_github_issue_from_workitem() {
  local project_id="$1"
  local workitem_id="$2"

  # 获取WorkItem数据
  local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
    --project-id "$project_id" \
    --workitem-id "$workitem_id")

  # 从custom_fields中提取GitHub Issue信息
  local github_issue_number=$(echo "$workitem_data" | jq -r '.custom_fields.github_issue_number // ""')
  local github_url=$(echo "$workitem_data" | jq -r '.custom_fields.github_url // ""')

  if [ -n "$github_issue_number" ] && [ "$github_issue_number" != "null" ]; then
    echo "$github_issue_number"
  else
    echo ""
  fi
}

# 检查Issue同步状态
check_issue_sync_status() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_number="$3"

  echo "=== Issue同步状态检查 ==="
  echo "仓库: $repo_owner/$repo_name"
  echo "Issue: #$issue_number"

  # 获取GitHub Issue信息
  local issue_data=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number)
  local issue_title=$(echo "$issue_data" | jq -r '.title')
  local issue_state=$(echo "$issue_data" | jq -r '.state')
  local issue_updated=$(echo "$issue_data" | jq -r '.updated_at')
  local labels=$(echo "$issue_data" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')

  echo "Issue标题: $issue_title"
  echo "Issue状态: $issue_state"
  echo "最后更新: $issue_updated"
  echo "标签: $labels"

  # 检查是否已同步
  if echo "$labels" | grep -q "yunxiao-sync"; then
    echo "同步状态: 已同步"

    # 查找关联的WorkItem
    local workitem_id=$(get_workitem_id_from_github_issue "$repo_owner" "$repo_name" "$issue_number")

    if [ -n "$workitem_id" ]; then
      echo "关联WorkItem ID: $workitem_id"

      # 获取WorkItem状态
      local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
      local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
        --project-id "$project_id" \
        --workitem-id "$workitem_id" 2>/dev/null)

      if [ $? -eq 0 ]; then
        local workitem_status=$(echo "$workitem_data" | jq -r '.status')
        local workitem_updated=$(echo "$workitem_data" | jq -r '.updated_at')
        echo "WorkItem状态: $workitem_status"
        echo "WorkItem更新时间: $workitem_updated"

        # 检查同步一致性
        if [[ "$issue_updated" > "$workitem_updated" ]]; then
          echo "⚠️  GitHub更新较新，建议同步到云效"
        elif [[ "$workitem_updated" > "$issue_updated" ]]; then
          echo "⚠️  云效更新较新，建议同步到GitHub"
        else
          echo "✓ 两端状态一致"
        fi
      else
        echo "❌ 无法获取WorkItem状态（可能已删除）"
      fi
    else
      echo "⚠️  未找到关联的WorkItem ID"
    fi
  else
    echo "同步状态: 未同步"
  fi
}
```

## Issue同步命令集成

### 命令行接口规范

Issue同步功能的统一命令接口：

```bash
# Issue同步命令接口
ccpm_issue_sync() {
  local command="$1"
  local repo_owner="$2"
  local repo_name="$3"
  local issue_number="${4:-}"
  local options=("${@:5}")

  case "$command" in
    "sync")
      if [ -z "$issue_number" ]; then
        echo "错误: Issue号码是必需的"
        return 1
      fi
      echo "同步单个Issue到云效..."
      github_issue_to_yunxiao_sync "$repo_owner" "$repo_name" "$issue_number"
      ;;
    "batch-sync")
      local filter="${options[0]:-open}"
      echo "批量同步Issues到云效..."
      batch_github_issues_sync "$repo_owner" "$repo_name" "$filter"
      ;;
    "status-sync")
      if [ -z "$issue_number" ]; then
        echo "批量状态同步..."
        batch_issue_status_sync "$repo_owner" "$repo_name"
      else
        echo "同步单个Issue状态..."
        auto_detect_and_sync_issue_status "$repo_owner" "$repo_name" "$issue_number"
      fi
      ;;
    "status")
      if [ -z "$issue_number" ]; then
        echo "错误: Issue号码是必需的"
        return 1
      fi
      check_issue_sync_status "$repo_owner" "$repo_name" "$issue_number"
      ;;
    "unlink")
      if [ -z "$issue_number" ]; then
        echo "错误: Issue号码是必需的"
        return 1
      fi
      echo "取消Issue与云效的关联..."
      unlink_issue_from_yunxiao "$repo_owner" "$repo_name" "$issue_number"
      ;;
    *)
      echo "错误: 未知的Issue同步命令: $command"
      echo "可用命令: sync, batch-sync, status-sync, status, unlink"
      return 1
      ;;
  esac
}

# 取消Issue与云效的关联
unlink_issue_from_yunxiao() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_number="$3"

  echo "取消Issue #$issue_number 与云效的关联..."

  # 查找关联的WorkItem
  local workitem_id=$(get_workitem_id_from_github_issue "$repo_owner" "$repo_name" "$issue_number")

  if [ -n "$workitem_id" ]; then
    echo "发现关联的WorkItem ID: $workitem_id"

    # 清除WorkItem中的GitHub关联信息
    local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
    local update_data=$(cat <<EOF
{
  "custom_fields": {
    "github_issue_number": null,
    "github_url": null,
    "sync_source": "unlinked",
    "sync_time": "$(date -Iseconds)"
  }
}
EOF
)

    mcp_call "alibabacloud_devops_update_workitem" \
      --project-id "$project_id" \
      --workitem-id "$workitem_id" \
      --data "$update_data"

    echo "✓ 云效WorkItem关联信息已清除"
  fi

  # 移除GitHub Issue的同步标签
  local current_labels=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number | jq -r '.labels[].name')
  local filtered_labels=$(echo "$current_labels" | grep -v "yunxiao-sync" | tr '\n' ',' | sed 's/,$//')

  gh api repos/$repo_owner/$repo_name/issues/$issue_number/labels \
    --method PUT \
    --field labels="$(echo "$filtered_labels" | tr ',' '\n' | jq -R . | jq -s .)"

  # 添加取消关联的评论
  local comment_body="🔗 **取消云效关联**

此Issue与云效WorkItem的关联已被取消。

- **取消时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **WorkItem ID**: $workitem_id (如果存在)

后续修改将不再自动同步到云效平台。"

  gh api repos/$repo_owner/$repo_name/issues/$issue_number/comments \
    --field body="$comment_body"

  echo "✓ Issue关联已清除"
}
```

## 错误处理和恢复

### Issue同步错误处理

```bash
# Issue同步错误恢复
recover_issue_sync() {
  local repo_owner="$1"
  local repo_name="$2"
  local issue_number="$3"

  echo "开始Issue #$issue_number 同步错误恢复..."

  # 检查Issue是否存在
  local issue_data=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number 2>/dev/null)
  if [ $? -ne 0 ]; then
    echo "错误: Issue #$issue_number 不存在"
    return 1
  fi

  # 检查同步状态
  local labels=$(echo "$issue_data" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')

  if echo "$labels" | grep -q "yunxiao-sync"; then
    echo "Issue已标记为已同步，检查云效端状态..."

    local workitem_id=$(get_workitem_id_from_github_issue "$repo_owner" "$repo_name" "$issue_number")

    if [ -n "$workitem_id" ]; then
      # 验证WorkItem是否存在
      local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
      local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
        --project-id "$project_id" \
        --workitem-id "$workitem_id" 2>/dev/null)

      if [ $? -eq 0 ]; then
        echo "云效WorkItem存在，尝试状态同步..."
        auto_detect_and_sync_issue_status "$repo_owner" "$repo_name" "$issue_number"
      else
        echo "云效WorkItem不存在，重新创建同步..."
        # 移除同步标签并重新同步
        unlink_issue_from_yunxiao "$repo_owner" "$repo_name" "$issue_number"
        github_issue_to_yunxiao_sync "$repo_owner" "$repo_name" "$issue_number"
      fi
    else
      echo "未找到关联的WorkItem，重新创建同步..."
      unlink_issue_from_yunxiao "$repo_owner" "$repo_name" "$issue_number"
      github_issue_to_yunxiao_sync "$repo_owner" "$repo_name" "$issue_number"
    fi
  else
    echo "Issue未同步，尝试创建同步..."
    github_issue_to_yunxiao_sync "$repo_owner" "$repo_name" "$issue_number"
  fi
}

# 修复损坏的Issue同步关系
repair_broken_issue_sync() {
  local repo_owner="$1"
  local repo_name="$2"

  echo "=== 修复损坏的Issue同步关系 ==="

  # 获取所有标记为已同步的Issues
  local synced_issues=$(gh api repos/$repo_owner/$repo_name/issues \
    --field state=all \
    --field labels="yunxiao-sync" \
    --paginate)

  echo "检查$(echo "$synced_issues" | jq length)个已同步Issue..."

  echo "$synced_issues" | jq -c '.[]' | while read -r issue; do
    local issue_number=$(echo "$issue" | jq -r '.number')
    local issue_title=$(echo "$issue" | jq -r '.title')

    echo ""
    echo "检查Issue #$issue_number: $issue_title"

    local workitem_id=$(get_workitem_id_from_github_issue "$repo_owner" "$repo_name" "$issue_number")

    if [ -z "$workitem_id" ]; then
      echo "  ⚠️  未找到WorkItem ID，尝试修复..."
      recover_issue_sync "$repo_owner" "$repo_name" "$issue_number"
    else
      # 验证WorkItem是否存在
      local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
      local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
        --project-id "$project_id" \
        --workitem-id "$workitem_id" 2>/dev/null)

      if [ $? -eq 0 ]; then
        echo "  ✓ 同步关系正常"
      else
        echo "  ⚠️  WorkItem不存在，尝试修复..."
        recover_issue_sync "$repo_owner" "$repo_name" "$issue_number"
      fi
    fi

    sleep 1
  done

  echo ""
  echo "Issue同步关系修复完成"
}
```

## 使用示例

### 完整Issue同步工作流示例

```bash
#!/bin/bash

# Issue同步工作流示例
issue_sync_workflow_example() {
  local repo_owner="kongsiyu"
  local repo_name="ccpm"

  echo "=== Issue同步工作流示例 ==="

  # 1. 检查云效连接
  if ! check_yunxiao_connectivity; then
    echo "云效连接失败，终止同步"
    return 1
  fi

  # 2. 同步特定Issue
  local issue_number="3"
  echo ""
  echo "同步单个Issue #$issue_number..."
  github_issue_to_yunxiao_sync "$repo_owner" "$repo_name" "$issue_number"

  # 3. 检查同步状态
  echo ""
  echo "检查同步状态..."
  check_issue_sync_status "$repo_owner" "$repo_name" "$issue_number"

  # 4. 批量同步开放Issues
  echo ""
  echo "批量同步开放Issues..."
  batch_github_issues_sync "$repo_owner" "$repo_name" "open"

  # 5. 批量状态同步
  echo ""
  echo "批量状态同步..."
  batch_issue_status_sync "$repo_owner" "$repo_name"
}

# 运行示例
# issue_sync_workflow_example
```

## 配置要求

### Issue同步所需配置

与Epic同步相同的配置要求，确保云效平台配置正确。

### GitHub CLI配置

需要配置GitHub CLI工具：

```bash
# GitHub CLI认证
gh auth login

# 验证认证状态
gh auth status
```

## 版本信息

- **规则版本**: v1.0.0
- **支持的GitHub API**: v4
- **支持的云效API**: v4
- **最后更新**: 2025-09-28
- **依赖规则**: platform-yunxiao-data-mapping.md, platform-yunxiao-sync.md
- **依赖工具**: gh, yq, jq, MCP alibabacloud_devops_* 工具套件

## 相关规则引用

- `.claude/rules/platform-yunxiao-data-mapping.md` - 数据转换函数库
- `.claude/rules/platform-yunxiao-epic-sync.md` - Epic同步规则
- `.claude/rules/platform-yunxiao-sync.md` - 基础同步规则
- `.claude/rules/github-operations.md` - GitHub操作规则