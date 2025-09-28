# 云效平台数据映射规则

基于MCP工具调用的云效平台与GitHub/CCPM系统间的数据映射和转换规则。

## 概述

此规则文件定义了云效平台适配器框架的核心数据映射规则，通过MCP工具调用实现GitHub Issue、Epic与云效WorkItem之间的双向数据转换。规则基于前置检查机制，确保数据一致性和转换准确性。

## 核心映射原则

### 数据映射策略
1. **保留原始信息**: 转换时保留来源系统的原始数据和链接
2. **双向映射**: 支持GitHub → 云效和云效 → GitHub的双向转换
3. **MCP工具驱动**: 所有数据操作通过MCP工具调用实现
4. **错误容忍**: 映射失败时提供清晰的错误信息和恢复建议

### 字段映射优先级
```yaml
mapping_priority:
  # 优先级: 必需 > 重要 > 可选
  required:  # 必需字段，映射失败则终止
    - title
    - description
    - type/state
  important: # 重要字段，映射失败则警告
    - assignee
    - priority
    - labels
  optional:  # 可选字段，映射失败则忽略
    - created_at
    - updated_at
    - custom_fields
```

## Epic到云效WorkItem映射

### Epic字段映射规则
```yaml
epic_to_yunxiao_mapping:
  # Epic frontmatter字段 → 云效WorkItem字段
  title: "title"
  description: "description"  # 从Epic内容生成
  status: "status"
  priority: "priority"
  assignee: "assignee"
  estimated_hours: "custom_fields.estimated_hours"
  actual_hours: "custom_fields.actual_hours"
  tags: "labels"
  github: "custom_fields.github_url"

  # Epic状态映射
  status_mapping:
    pending: "待处理"
    in_progress: "进行中"
    completed: "已完成"
    blocked: "已暂停"

  # Epic优先级映射
  priority_mapping:
    low: "低"
    medium: "中"
    high: "高"
    urgent: "紧急"

  # 工作项类型
  workitem_type: "需求"  # Epic对应云效的需求类型
```

### Epic转换MCP调用规则
```markdown
## Epic创建到云效WorkItem

### MCP工具调用序列
1. **数据预处理**:
   ```bash
   # 读取Epic文件内容
   epic_content=$(cat epic_file_path)
   epic_frontmatter=$(extract_frontmatter "$epic_content")
   epic_description=$(extract_content "$epic_content")
   ```

2. **数据转换**:
   ```bash
   # 应用映射规则
   yunxiao_data=$(convert_epic_to_yunxiao "$epic_frontmatter" "$epic_description")
   ```

3. **MCP工具调用**:
   ```bash
   # 调用MCP工具创建WorkItem
   mcp_call "alibabacloud_devops_create_workitem" \
     --project-id "$PROJECT_ID" \
     --workitem-type "需求" \
     --data "$yunxiao_data"
   ```

4. **结果处理**:
   ```bash
   # 更新Epic frontmatter
   update_epic_frontmatter "$epic_file" \
     --yunxiao-id "$workitem_id" \
     --yunxiao-url "$workitem_url" \
     --sync-time "$(date -Iseconds)"
   ```
```

### Epic更新同步规则
```markdown
## Epic状态同步

### 状态检查和同步
1. **本地状态读取**:
   ```bash
   local_status=$(yq eval '.status' "$epic_file")
   local_updated=$(yq eval '.updated' "$epic_file")
   ```

2. **云效状态获取**:
   ```bash
   yunxiao_id=$(yq eval '.yunxiao.id' "$epic_file")
   mcp_result=$(mcp_call "alibabacloud_devops_get_workitem" \
     --project-id "$PROJECT_ID" \
     --workitem-id "$yunxiao_id")
   yunxiao_status=$(echo "$mcp_result" | jq -r '.status')
   yunxiao_updated=$(echo "$mcp_result" | jq -r '.updated_at')
   ```

3. **冲突检测和解决**:
   ```bash
   if [ "$local_updated" != "$yunxiao_updated" ]; then
     # 使用最后修改时间优先原则
     if [[ "$local_updated" > "$yunxiao_updated" ]]; then
       # 本地更新，同步到云效
       sync_epic_to_yunxiao "$epic_file"
     else
       # 云效更新，同步到本地
       sync_yunxiao_to_epic "$epic_file" "$mcp_result"
     fi
   fi
   ```
```

## Issue到云效WorkItem映射

### Issue字段映射规则
```yaml
issue_to_yunxiao_mapping:
  # GitHub Issue字段 → 云效WorkItem字段
  title: "title"
  body: "description"
  state: "status"
  assignees: "assignee"
  labels: "labels"
  milestone: "custom_fields.milestone"
  number: "custom_fields.github_issue_number"
  html_url: "custom_fields.github_url"

  # Issue状态映射
  status_mapping:
    open: "待处理"
    closed: "已完成"
    # 扩展状态（通过标签识别）
    "in progress": "进行中"
    "in review": "待验收"

  # Issue标签到工作项类型映射
  type_mapping:
    bug: "缺陷"
    enhancement: "需求"
    task: "任务"
    subtask: "子任务"
    default: "任务"

  # Issue优先级映射（从标签推断）
  priority_mapping:
    "priority:low": "低"
    "priority:medium": "中"
    "priority:high": "高"
    "priority:urgent": "紧急"
    default: "中"
```

### Issue转换MCP调用规则
```markdown
## GitHub Issue创建到云效WorkItem

### MCP工具调用序列
1. **Issue数据获取**:
   ```bash
   # 通过GitHub API获取Issue详情
   issue_data=$(gh api repos/$REPO_OWNER/$REPO_NAME/issues/$ISSUE_NUMBER)
   ```

2. **数据转换和验证**:
   ```bash
   # 验证Issue数据完整性
   validate_github_issue_data "$issue_data"

   # 转换为云效格式
   yunxiao_data=$(convert_github_issue_to_yunxiao "$issue_data")
   ```

3. **MCP工具调用**:
   ```bash
   # 创建云效WorkItem
   mcp_result=$(mcp_call "alibabacloud_devops_create_workitem" \
     --project-id "$PROJECT_ID" \
     --data "$yunxiao_data")

   workitem_id=$(echo "$mcp_result" | jq -r '.id')
   workitem_url=$(echo "$mcp_result" | jq -r '.url')
   ```

4. **关联关系建立**:
   ```bash
   # 在GitHub Issue添加评论记录云效关联
   gh api repos/$REPO_OWNER/$REPO_NAME/issues/$ISSUE_NUMBER/comments \
     --field body="🔗 已关联云效工作项: $workitem_url"

   # 添加标签标识
   gh api repos/$REPO_OWNER/$REPO_NAME/issues/$ISSUE_NUMBER/labels \
     --field labels='["yunxiao-sync"]'
   ```
```

### Issue批量同步规则
```markdown
## 批量Issue同步

### 批量同步MCP调用
1. **Issue列表获取**:
   ```bash
   # 获取需要同步的Issues
   issues_data=$(gh api repos/$REPO_OWNER/$REPO_NAME/issues \
     --field state=open \
     --field labels="!yunxiao-sync")
   ```

2. **批量转换和创建**:
   ```bash
   echo "$issues_data" | jq -c '.[]' | while read -r issue; do
     issue_number=$(echo "$issue" | jq -r '.number')
     echo "同步Issue #$issue_number..."

     # 转换数据
     yunxiao_data=$(convert_github_issue_to_yunxiao "$issue")

     # MCP创建WorkItem
     mcp_result=$(mcp_call "alibabacloud_devops_create_workitem" \
       --project-id "$PROJECT_ID" \
       --data "$yunxiao_data")

     if [ $? -eq 0 ]; then
       echo "  ✓ 创建成功: $(echo "$mcp_result" | jq -r '.id')"
       # 标记已同步
       gh api repos/$REPO_OWNER/$REPO_NAME/issues/$issue_number/labels \
         --field labels='["yunxiao-sync"]'
     else
       echo "  ✗ 创建失败: $issue_number"
     fi
   done
   ```
```

## 数据转换函数库

### Epic数据转换函数
```bash
# Epic frontmatter转换为云效WorkItem数据
convert_epic_to_yunxiao() {
  local epic_frontmatter="$1"
  local epic_description="$2"

  # 提取Epic字段
  local title=$(echo "$epic_frontmatter" | yq eval '.title' -)
  local status=$(echo "$epic_frontmatter" | yq eval '.status // "pending"' -)
  local priority=$(echo "$epic_frontmatter" | yq eval '.priority // "medium"' -)
  local assignee=$(echo "$epic_frontmatter" | yq eval '.assignee // ""' -)
  local estimated_hours=$(echo "$epic_frontmatter" | yq eval '.estimated_hours // 0' -)
  local github_url=$(echo "$epic_frontmatter" | yq eval '.github // ""' -)

  # 映射状态
  local yunxiao_status
  case "$status" in
    "pending") yunxiao_status="待处理" ;;
    "in_progress") yunxiao_status="进行中" ;;
    "completed") yunxiao_status="已完成" ;;
    "blocked") yunxiao_status="已暂停" ;;
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

  # 构建云效WorkItem数据
  local yunxiao_data=$(cat <<EOF
{
  "title": "$title",
  "workitem_type": "需求",
  "description": $(echo "$epic_description" | jq -Rs .),
  "status": "$yunxiao_status",
  "priority": "$yunxiao_priority",
  "assignee": "$assignee",
  "custom_fields": {
    "estimated_hours": $estimated_hours,
    "github_url": "$github_url",
    "sync_source": "ccpm_epic",
    "sync_time": "$(date -Iseconds)"
  },
  "labels": ["ccpm-epic", "github-sync"]
}
EOF
)

  echo "$yunxiao_data"
}

# GitHub Issue转换为云效WorkItem数据
convert_github_issue_to_yunxiao() {
  local issue_data="$1"

  # 提取Issue字段
  local title=$(echo "$issue_data" | jq -r '.title')
  local body=$(echo "$issue_data" | jq -r '.body // ""')
  local state=$(echo "$issue_data" | jq -r '.state')
  local number=$(echo "$issue_data" | jq -r '.number')
  local html_url=$(echo "$issue_data" | jq -r '.html_url')
  local assignee=$(echo "$issue_data" | jq -r '.assignee.login // ""')
  local labels=$(echo "$issue_data" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')

  # 推断工作项类型
  local workitem_type="任务"
  if echo "$labels" | grep -q "bug"; then
    workitem_type="缺陷"
  elif echo "$labels" | grep -q "enhancement"; then
    workitem_type="需求"
  elif echo "$labels" | grep -q "subtask"; then
    workitem_type="子任务"
  fi

  # 映射状态
  local yunxiao_status
  case "$state" in
    "open") yunxiao_status="待处理" ;;
    "closed") yunxiao_status="已完成" ;;
    *) yunxiao_status="待处理" ;;
  esac

  # 推断优先级
  local yunxiao_priority="中"
  if echo "$labels" | grep -q "priority:low"; then
    yunxiao_priority="低"
  elif echo "$labels" | grep -q "priority:high"; then
    yunxiao_priority="高"
  elif echo "$labels" | grep -q "priority:urgent"; then
    yunxiao_priority="紧急"
  fi

  # 构建描述（包含原始信息）
  local yunxiao_description=$(cat <<EOF
## GitHub Issue #$number

$body

---
**同步信息**
- 来源: GitHub Issue #$number
- 原始链接: $html_url
- 同步时间: $(date '+%Y-%m-%d %H:%M:%S')
- 原始标签: $labels
EOF
)

  # 构建云效WorkItem数据
  local yunxiao_data=$(cat <<EOF
{
  "title": "$title [GitHub #$number]",
  "workitem_type": "$workitem_type",
  "description": $(echo "$yunxiao_description" | jq -Rs .),
  "status": "$yunxiao_status",
  "priority": "$yunxiao_priority",
  "assignee": "$assignee",
  "custom_fields": {
    "github_issue_number": "$number",
    "github_url": "$html_url",
    "sync_source": "github_issue",
    "sync_time": "$(date -Iseconds)",
    "original_labels": $(echo "$labels" | tr ',' '\n' | jq -R . | jq -s .)
  },
  "labels": ["github-sync", "github-issue"]
}
EOF
)

  echo "$yunxiao_data"
}

# 云效WorkItem转换为GitHub Issue数据
convert_yunxiao_to_github_issue() {
  local workitem_data="$1"

  # 提取WorkItem字段
  local title=$(echo "$workitem_data" | jq -r '.title')
  local description=$(echo "$workitem_data" | jq -r '.description // ""')
  local status=$(echo "$workitem_data" | jq -r '.status')
  local workitem_type=$(echo "$workitem_data" | jq -r '.workitem_type')
  local priority=$(echo "$workitem_data" | jq -r '.priority // "中"')
  local assignee=$(echo "$workitem_data" | jq -r '.assignee // ""')
  local workitem_id=$(echo "$workitem_data" | jq -r '.id')
  local workitem_url=$(echo "$workitem_data" | jq -r '.url // ""')

  # 映射GitHub状态
  local github_state
  case "$status" in
    "待处理"|"进行中"|"待验收") github_state="open" ;;
    "已完成"|"已关闭") github_state="closed" ;;
    *) github_state="open" ;;
  esac

  # 构建GitHub标签
  local github_labels=()

  # 根据工作项类型添加标签
  case "$workitem_type" in
    "需求") github_labels+=("enhancement") ;;
    "缺陷") github_labels+=("bug") ;;
    "子任务") github_labels+=("subtask") ;;
  esac

  # 根据优先级添加标签
  case "$priority" in
    "紧急") github_labels+=("priority:urgent") ;;
    "高") github_labels+=("priority:high") ;;
    "低") github_labels+=("priority:low") ;;
  esac

  # 添加同步标识
  github_labels+=("yunxiao-sync")

  # 构建GitHub Issue描述
  local github_description=$(cat <<EOF
## 云效工作项 #$workitem_id

$description

---
**同步信息**
- 来源: 云效工作项 #$workitem_id
- 工作项类型: $workitem_type
- 优先级: $priority
- 原始状态: $status
- 同步时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)

  if [ -n "$workitem_url" ] && [ "$workitem_url" != "null" ]; then
    github_description+="\n- 原始链接: $workitem_url"
  fi

  # 构建GitHub Issue数据
  local github_issue=$(cat <<EOF
{
  "title": "$title [云效 #$workitem_id]",
  "body": $(echo "$github_description" | jq -Rs .),
  "state": "$github_state",
  "labels": $(printf '%s\n' "${github_labels[@]}" | jq -R . | jq -s .),
  "assignee": "$assignee"
}
EOF
)

  echo "$github_issue"
}
```

## 数据验证规则

### Epic数据验证
```bash
# 验证Epic frontmatter数据
validate_epic_data() {
  local epic_file="$1"
  local errors=()

  # 检查文件存在
  if [ ! -f "$epic_file" ]; then
    errors+=("Epic文件不存在: $epic_file")
    echo "Epic数据验证失败:"
    printf '  - %s\n' "${errors[@]}"
    return 1
  fi

  # 提取frontmatter
  local frontmatter=$(extract_frontmatter "$epic_file")

  # 检查必需字段
  local title=$(echo "$frontmatter" | yq eval '.title // ""' -)
  if [ -z "$title" ]; then
    errors+=("缺少必需字段: title")
  fi

  local status=$(echo "$frontmatter" | yq eval '.status // ""' -)
  if [ -n "$status" ]; then
    case "$status" in
      "pending"|"in_progress"|"completed"|"blocked") ;;
      *) errors+=("无效的状态值: $status") ;;
    esac
  fi

  local priority=$(echo "$frontmatter" | yq eval '.priority // ""' -)
  if [ -n "$priority" ]; then
    case "$priority" in
      "low"|"medium"|"high"|"urgent") ;;
      *) errors+=("无效的优先级: $priority") ;;
    esac
  fi

  # 输出验证结果
  if [ ${#errors[@]} -eq 0 ]; then
    echo "Epic数据验证通过"
    return 0
  else
    echo "Epic数据验证失败:"
    printf '  - %s\n' "${errors[@]}"
    return 1
  fi
}

# 验证GitHub Issue数据
validate_github_issue_data() {
  local issue_data="$1"
  local errors=()

  # 检查必需字段
  local title=$(echo "$issue_data" | jq -r '.title // ""')
  if [ -z "$title" ]; then
    errors+=("缺少必需字段: title")
  fi

  local number=$(echo "$issue_data" | jq -r '.number // ""')
  if [ -z "$number" ] || [ "$number" = "null" ]; then
    errors+=("缺少必需字段: number")
  fi

  local html_url=$(echo "$issue_data" | jq -r '.html_url // ""')
  if [ -z "$html_url" ] || [ "$html_url" = "null" ]; then
    errors+=("缺少必需字段: html_url")
  fi

  # 检查字段格式
  local state=$(echo "$issue_data" | jq -r '.state // ""')
  if [ -n "$state" ] && [[ "$state" != "open" && "$state" != "closed" ]]; then
    errors+=("无效的状态值: $state")
  fi

  # 输出验证结果
  if [ ${#errors[@]} -eq 0 ]; then
    echo "GitHub Issue数据验证通过"
    return 0
  else
    echo "GitHub Issue数据验证失败:"
    printf '  - %s\n' "${errors[@]}"
    return 1
  fi
}

# 验证云效WorkItem数据
validate_yunxiao_workitem_data() {
  local workitem_data="$1"
  local errors=()

  # 检查必需字段
  local title=$(echo "$workitem_data" | jq -r '.title // ""')
  if [ -z "$title" ]; then
    errors+=("缺少必需字段: title")
  fi

  local workitem_type=$(echo "$workitem_data" | jq -r '.workitem_type // ""')
  if [ -z "$workitem_type" ]; then
    errors+=("缺少必需字段: workitem_type")
  fi

  # 验证工作项类型
  case "$workitem_type" in
    "任务"|"需求"|"缺陷"|"子任务") ;;
    *) errors+=("无效的工作项类型: $workitem_type") ;;
  esac

  # 验证状态
  local status=$(echo "$workitem_data" | jq -r '.status // ""')
  if [ -n "$status" ]; then
    case "$status" in
      "待处理"|"进行中"|"待验收"|"已完成"|"已关闭") ;;
      *) errors+=("无效的状态: $status") ;;
    esac
  fi

  # 验证优先级
  local priority=$(echo "$workitem_data" | jq -r '.priority // ""')
  if [ -n "$priority" ]; then
    case "$priority" in
      "低"|"中"|"高"|"紧急") ;;
      *) errors+=("无效的优先级: $priority") ;;
    esac
  fi

  # 输出验证结果
  if [ ${#errors[@]} -eq 0 ]; then
    echo "云效WorkItem数据验证通过"
    return 0
  else
    echo "云效WorkItem数据验证失败:"
    printf '  - %s\n' "${errors[@]}"
    return 1
  fi
}
```

## MCP工具调用标准化

### MCP调用封装函数
```bash
# 标准化MCP工具调用接口
mcp_call() {
  local tool_name="$1"
  shift
  local tool_args=("$@")

  echo "调用MCP工具: $tool_name ${tool_args[*]}" >&2

  # 根据工具类型调用对应的MCP函数
  case "$tool_name" in
    "alibabacloud_devops_create_workitem")
      mcp_create_workitem "${tool_args[@]}"
      ;;
    "alibabacloud_devops_get_workitem")
      mcp_get_workitem "${tool_args[@]}"
      ;;
    "alibabacloud_devops_update_workitem")
      mcp_update_workitem "${tool_args[@]}"
      ;;
    "alibabacloud_devops_search_workitems")
      mcp_search_workitems "${tool_args[@]}"
      ;;
    "alibabacloud_devops_get_project_info")
      mcp_get_project_info "${tool_args[@]}"
      ;;
    *)
      echo "错误: 未知的MCP工具: $tool_name" >&2
      return 1
      ;;
  esac
}

# MCP工具具体实现（示例接口）
mcp_create_workitem() {
  local project_id=""
  local data=""

  # 解析参数
  while [[ $# -gt 0 ]]; do
    case $1 in
      --project-id)
        project_id="$2"
        shift 2
        ;;
      --data)
        data="$2"
        shift 2
        ;;
      *)
        echo "错误: 未知参数 $1" >&2
        return 1
        ;;
    esac
  done

  # 验证必需参数
  if [ -z "$project_id" ] || [ -z "$data" ]; then
    echo "错误: 缺少必需参数" >&2
    return 1
  fi

  # 实际的MCP工具调用（基于MCP协议）
  # 使用Claude Code MCP工具进行API调用
  local mcp_request=$(cat <<EOF
{
  "method": "tools/call",
  "params": {
    "name": "alibabacloud_devops_create_workitem",
    "arguments": {
      "project_id": "$project_id",
      "workitem_data": $data
    }
  }
}
EOF
)

  # 执行MCP调用并处理错误
  local mcp_response
  if mcp_response=$(echo "$mcp_request" | mcp_client_call); then
    # 解析响应
    local success=$(echo "$mcp_response" | jq -r '.result.success // false')
    if [ "$success" = "true" ]; then
      echo "$mcp_response" | jq -r '.result.data'
    else
      local error_msg=$(echo "$mcp_response" | jq -r '.result.error // "未知错误"')
      echo "错误: MCP调用失败 - $error_msg" >&2
      return 1
    fi
  else
    echo "错误: MCP通信失败" >&2
    return 1
  fi
}

mcp_get_workitem() {
  local project_id=""
  local workitem_id=""

  # 解析参数
  while [[ $# -gt 0 ]]; do
    case $1 in
      --project-id)
        project_id="$2"
        shift 2
        ;;
      --workitem-id)
        workitem_id="$2"
        shift 2
        ;;
      *)
        echo "错误: 未知参数 $1" >&2
        return 1
        ;;
    esac
  done

  # 验证必需参数
  if [ -z "$project_id" ] || [ -z "$workitem_id" ]; then
    echo "错误: 缺少必需参数" >&2
    return 1
  fi

  # 实际的MCP工具调用（基于MCP协议）
  local mcp_request=$(cat <<EOF
{
  "method": "tools/call",
  "params": {
    "name": "alibabacloud_devops_get_workitem",
    "arguments": {
      "project_id": "$project_id",
      "workitem_id": "$workitem_id"
    }
  }
}
EOF
)

  # 执行MCP调用并处理错误
  local mcp_response
  if mcp_response=$(echo "$mcp_request" | mcp_client_call); then
    local success=$(echo "$mcp_response" | jq -r '.result.success // false')
    if [ "$success" = "true" ]; then
      echo "$mcp_response" | jq -r '.result.data'
    else
      local error_msg=$(echo "$mcp_response" | jq -r '.result.error // "WorkItem不存在或无访问权限"')
      echo "错误: MCP调用失败 - $error_msg" >&2
      return 1
    fi
  else
    echo "错误: MCP通信失败" >&2
    return 1
  fi
}

mcp_update_workitem() {
  local project_id=""
  local workitem_id=""
  local data=""

  # 解析参数
  while [[ $# -gt 0 ]]; do
    case $1 in
      --project-id)
        project_id="$2"
        shift 2
        ;;
      --workitem-id)
        workitem_id="$2"
        shift 2
        ;;
      --data)
        data="$2"
        shift 2
        ;;
      *)
        echo "错误: 未知参数 $1" >&2
        return 1
        ;;
    esac
  done

  # 验证必需参数
  if [ -z "$project_id" ] || [ -z "$workitem_id" ] || [ -z "$data" ]; then
    echo "错误: 缺少必需参数" >&2
    return 1
  fi

  # 实际的MCP工具调用（基于MCP协议）
  local mcp_request=$(cat <<EOF
{
  "method": "tools/call",
  "params": {
    "name": "alibabacloud_devops_update_workitem",
    "arguments": {
      "project_id": "$project_id",
      "workitem_id": "$workitem_id",
      "update_data": $data
    }
  }
}
EOF
)

  # 执行MCP调用并处理错误
  local mcp_response
  if mcp_response=$(echo "$mcp_request" | mcp_client_call); then
    local success=$(echo "$mcp_response" | jq -r '.result.success // false')
    if [ "$success" = "true" ]; then
      echo "$mcp_response" | jq -r '.result.data'
    else
      local error_msg=$(echo "$mcp_response" | jq -r '.result.error // "WorkItem更新失败"')
      echo "错误: MCP调用失败 - $error_msg" >&2
      return 1
    fi
  else
    echo "错误: MCP通信失败" >&2
    return 1
  fi
}

# MCP工具搜索功能
mcp_search_workitems() {
  local project_id=""
  local query=""
  local status=""
  local assignee=""
  local limit="50"

  # 解析参数
  while [[ $# -gt 0 ]]; do
    case $1 in
      --project-id)
        project_id="$2"
        shift 2
        ;;
      --query)
        query="$2"
        shift 2
        ;;
      --status)
        status="$2"
        shift 2
        ;;
      --assignee)
        assignee="$2"
        shift 2
        ;;
      --limit)
        limit="$2"
        shift 2
        ;;
      *)
        echo "错误: 未知参数 $1" >&2
        return 1
        ;;
    esac
  done

  # 验证必需参数
  if [ -z "$project_id" ]; then
    echo "错误: 缺少必需参数 project_id" >&2
    return 1
  fi

  # 构建搜索条件
  local search_conditions="{}"
  if [ -n "$query" ]; then
    search_conditions=$(echo "$search_conditions" | jq --arg q "$query" '. + {query: $q}')
  fi
  if [ -n "$status" ]; then
    search_conditions=$(echo "$search_conditions" | jq --arg s "$status" '. + {status: $s}')
  fi
  if [ -n "$assignee" ]; then
    search_conditions=$(echo "$search_conditions" | jq --arg a "$assignee" '. + {assignee: $a}')
  fi

  # 实际的MCP工具调用
  local mcp_request=$(cat <<EOF
{
  "method": "tools/call",
  "params": {
    "name": "alibabacloud_devops_search_workitems",
    "arguments": {
      "project_id": "$project_id",
      "search_conditions": $search_conditions,
      "limit": $limit
    }
  }
}
EOF
)

  # 执行MCP调用
  local mcp_response
  if mcp_response=$(echo "$mcp_request" | mcp_client_call); then
    local success=$(echo "$mcp_response" | jq -r '.result.success // false')
    if [ "$success" = "true" ]; then
      echo "$mcp_response" | jq -r '.result.data'
    else
      local error_msg=$(echo "$mcp_response" | jq -r '.result.error // "搜索失败"')
      echo "错误: MCP调用失败 - $error_msg" >&2
      return 1
    fi
  else
    echo "错误: MCP通信失败" >&2
    return 1
  fi
}

# MCP工具项目信息获取
mcp_get_project_info() {
  local project_id=""

  # 解析参数
  while [[ $# -gt 0 ]]; do
    case $1 in
      --project-id)
        project_id="$2"
        shift 2
        ;;
      *)
        echo "错误: 未知参数 $1" >&2
        return 1
        ;;
    esac
  done

  # 验证必需参数
  if [ -z "$project_id" ]; then
    echo "错误: 缺少必需参数 project_id" >&2
    return 1
  fi

  # 实际的MCP工具调用
  local mcp_request=$(cat <<EOF
{
  "method": "tools/call",
  "params": {
    "name": "alibabacloud_devops_get_project_info",
    "arguments": {
      "project_id": "$project_id"
    }
  }
}
EOF
)

  # 执行MCP调用
  local mcp_response
  if mcp_response=$(echo "$mcp_request" | mcp_client_call); then
    local success=$(echo "$mcp_response" | jq -r '.result.success // false')
    if [ "$success" = "true" ]; then
      echo "$mcp_response" | jq -r '.result.data'
    else
      local error_msg=$(echo "$mcp_response" | jq -r '.result.error // "项目信息获取失败"')
      echo "错误: MCP调用失败 - $error_msg" >&2
      return 1
    fi
  else
    echo "错误: MCP通信失败" >&2
    return 1
  fi
}

# MCP客户端调用通用接口
mcp_client_call() {
  # 读取标准输入的MCP请求
  local mcp_request=$(cat)

  # 这里应该是实际的MCP客户端调用
  # 可能通过管道、文件或网络与MCP服务通信
  # 示例实现（实际使用时需要替换为真实的MCP客户端调用）

  # 临时文件方式（示例）
  local temp_request=$(mktemp)
  local temp_response=$(mktemp)

  echo "$mcp_request" > "$temp_request"

  # 调用实际的MCP客户端工具
  # 例如: mcp_client --request "$temp_request" --response "$temp_response"
  # 或者: curl -X POST -d @"$temp_request" http://mcp-server/api/call > "$temp_response"

  # 暂时模拟成功响应（实际使用时需要移除）
  local request_method=$(echo "$mcp_request" | jq -r '.params.name')
  case "$request_method" in
    "alibabacloud_devops_create_workitem")
      cat <<EOF > "$temp_response"
{
  "result": {
    "success": true,
    "data": {
      "id": "workitem_$(date +%s)",
      "url": "https://devops.aliyun.com/workitem/$(date +%s)",
      "status": "待处理",
      "created_at": "$(date -Iseconds)"
    }
  }
}
EOF
      ;;
    "alibabacloud_devops_get_workitem"|"alibabacloud_devops_update_workitem")
      cat <<EOF > "$temp_response"
{
  "result": {
    "success": true,
    "data": {
      "id": "workitem_123",
      "status": "进行中",
      "updated_at": "$(date -Iseconds)",
      "title": "示例工作项",
      "description": "这是一个示例工作项"
    }
  }
}
EOF
      ;;
    "alibabacloud_devops_search_workitems")
      cat <<EOF > "$temp_response"
{
  "result": {
    "success": true,
    "data": {
      "items": [],
      "total": 0,
      "page": 1
    }
  }
}
EOF
      ;;
    "alibabacloud_devops_get_project_info")
      cat <<EOF > "$temp_response"
{
  "result": {
    "success": true,
    "data": {
      "id": "project_123",
      "name": "CCPM项目",
      "status": "active",
      "members_count": 5
    }
  }
}
EOF
      ;;
    *)
      cat <<EOF > "$temp_response"
{
  "result": {
    "success": false,
    "error": "未知的MCP工具: $request_method"
  }
}
EOF
      ;;
  esac

  # 返回响应内容
  cat "$temp_response"

  # 清理临时文件
  rm -f "$temp_request" "$temp_response"
}

# MCP工具重试机制
mcp_call_with_retry() {
  local tool_name="$1"
  shift
  local tool_args=("$@")
  local max_retries=3
  local retry_delay=1
  local attempt=1

  while [ $attempt -le $max_retries ]; do
    echo "MCP调用尝试 $attempt/$max_retries: $tool_name" >&2

    if mcp_call "$tool_name" "${tool_args[@]}"; then
      return 0
    fi

    if [ $attempt -lt $max_retries ]; then
      echo "MCP调用失败，等待 ${retry_delay}s 后重试..." >&2
      sleep $retry_delay
      retry_delay=$((retry_delay * 2))  # 指数退避
    fi

    ((attempt++))
  done

  echo "错误: MCP调用失败，已达到最大重试次数" >&2
  return 1
}
```

## 辅助工具函数

### Frontmatter处理
```bash
# 提取文件的frontmatter部分
extract_frontmatter() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    echo "错误: 文件不存在 $file_path" >&2
    return 1
  fi

  # 使用sed提取frontmatter (在---之间的部分)
  sed -n '/^---$/,/^---$/p' "$file_path" | sed '1d;$d'
}

# 提取文件的正文内容
extract_content() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    echo "错误: 文件不存在 $file_path" >&2
    return 1
  fi

  # 跳过frontmatter，提取正文
  sed -n '/^---$/,/^---$/d; /^---$/,$p' "$file_path" | sed '/^---$/d'
}

# 更新Epic文件的frontmatter
update_epic_frontmatter() {
  local epic_file="$1"
  shift
  local updates=("$@")

  # 提取当前frontmatter和内容
  local current_frontmatter=$(extract_frontmatter "$epic_file")
  local content=$(extract_content "$epic_file")

  # 应用更新
  local updated_frontmatter="$current_frontmatter"
  for update in "${updates[@]}"; do
    case "$update" in
      --yunxiao-id)
        shift
        local yunxiao_id="$1"
        updated_frontmatter=$(echo "$updated_frontmatter" | yq eval ".yunxiao.id = \"$yunxiao_id\"" -)
        ;;
      --yunxiao-url)
        shift
        local yunxiao_url="$1"
        updated_frontmatter=$(echo "$updated_frontmatter" | yq eval ".yunxiao.url = \"$yunxiao_url\"" -)
        ;;
      --sync-time)
        shift
        local sync_time="$1"
        updated_frontmatter=$(echo "$updated_frontmatter" | yq eval ".yunxiao.sync_time = \"$sync_time\"" -)
        ;;
      --status)
        shift
        local status="$1"
        updated_frontmatter=$(echo "$updated_frontmatter" | yq eval ".status = \"$status\"" -)
        ;;
    esac
    shift
  done

  # 重建文件
  {
    echo "---"
    echo "$updated_frontmatter"
    echo "---"
    echo "$content"
  } > "$epic_file"
}
```

## 使用示例

### 完整Epic同步示例
```bash
#!/bin/bash

# Epic到云效同步示例
sync_epic_to_yunxiao_example() {
  local epic_file=".claude/epics/pm-tool-alibabacloud-devops/epic.md"

  echo "=== Epic到云效同步示例 ==="

  # 1. 验证Epic数据
  if ! validate_epic_data "$epic_file"; then
    echo "Epic数据验证失败，终止同步"
    return 1
  fi

  # 2. 转换数据
  local epic_frontmatter=$(extract_frontmatter "$epic_file")
  local epic_content=$(extract_content "$epic_file")
  local yunxiao_data=$(convert_epic_to_yunxiao "$epic_frontmatter" "$epic_content")

  echo "转换后的云效数据:"
  echo "$yunxiao_data" | jq .

  # 3. MCP创建WorkItem
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local mcp_result=$(mcp_call "alibabacloud_devops_create_workitem" \
    --project-id "$project_id" \
    --data "$yunxiao_data")

  if [ $? -eq 0 ]; then
    local workitem_id=$(echo "$mcp_result" | jq -r '.id')
    local workitem_url=$(echo "$mcp_result" | jq -r '.url')

    echo "✓ Epic同步成功"
    echo "  云效WorkItem ID: $workitem_id"
    echo "  云效WorkItem URL: $workitem_url"

    # 4. 更新Epic frontmatter
    update_epic_frontmatter "$epic_file" \
      --yunxiao-id "$workitem_id" \
      --yunxiao-url "$workitem_url" \
      --sync-time "$(date -Iseconds)"

    echo "✓ Epic frontmatter已更新"
  else
    echo "✗ Epic同步失败"
    return 1
  fi
}

# GitHub Issue同步示例
sync_github_issue_example() {
  local repo_owner="kongsiyu"
  local repo_name="ccpm"
  local issue_number="3"

  echo "=== GitHub Issue同步示例 ==="

  # 1. 获取Issue数据
  local issue_data=$(gh api repos/$repo_owner/$repo_name/issues/$issue_number)

  # 2. 验证数据
  if ! validate_github_issue_data "$issue_data"; then
    echo "GitHub Issue数据验证失败，终止同步"
    return 1
  fi

  # 3. 转换数据
  local yunxiao_data=$(convert_github_issue_to_yunxiao "$issue_data")

  echo "转换后的云效数据:"
  echo "$yunxiao_data" | jq .

  # 4. MCP创建WorkItem
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local mcp_result=$(mcp_call "alibabacloud_devops_create_workitem" \
    --project-id "$project_id" \
    --data "$yunxiao_data")

  if [ $? -eq 0 ]; then
    local workitem_id=$(echo "$mcp_result" | jq -r '.id')
    local workitem_url=$(echo "$mcp_result" | jq -r '.url')

    echo "✓ GitHub Issue同步成功"
    echo "  云效WorkItem ID: $workitem_id"
    echo "  云效WorkItem URL: $workitem_url"

    # 5. 在GitHub添加关联评论
    gh api repos/$repo_owner/$repo_name/issues/$issue_number/comments \
      --field body="🔗 已关联云效工作项: $workitem_url"

    # 6. 添加同步标签
    gh api repos/$repo_owner/$repo_name/issues/$issue_number/labels \
      --field labels='["yunxiao-sync"]'

    echo "✓ GitHub Issue已标记为已同步"
  else
    echo "✗ GitHub Issue同步失败"
    return 1
  fi
}

# 运行示例
# sync_epic_to_yunxiao_example
# sync_github_issue_example
```

## 版本信息

- **规则版本**: v1.0.0
- **最后更新**: 2025-09-28
- **依赖**: yq, jq, gh
- **相关规则**: platform-yunxiao-sync.md, platform-yunxiao-epic-sync.md, platform-yunxiao-issue-sync.md
- **MCP工具要求**: alibabacloud_devops_* 工具套件