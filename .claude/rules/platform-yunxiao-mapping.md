# 云效数据映射规则模板

云效平台与GitHub/本地系统的数据映射规则模板和转换函数。

## 概述

此规则文件提供了云效平台与其他系统（主要是GitHub）之间的数据映射模板，包括字段映射、数据类型转换、状态映射等标准化转换规则。

## 基础映射配置

### 平台映射配置文件
```yaml
# platform-mapping.yml - 平台间映射配置
mappings:
  # GitHub到云效的映射
  github_to_yunxiao:
    issue_types:
      issue: "任务"
      enhancement: "需求"
      bug: "缺陷"
      documentation: "任务"
      question: "任务"

    states:
      open: "待处理"
      closed: "已完成"
      # 自定义状态映射
      "in progress": "进行中"
      "in review": "待验收"
      "blocked": "已暂停"

    priorities:
      low: "低"
      medium: "中"
      high: "高"
      critical: "紧急"

    labels:
      # 标签映射规则
      frontend: "前端"
      backend: "后端"
      api: "接口"
      ui: "界面"
      performance: "性能"
      security: "安全"

  # 云效到GitHub的映射
  yunxiao_to_github:
    workitem_types:
      "任务": "issue"
      "需求": "enhancement"
      "缺陷": "bug"
      "子任务": "issue"

    states:
      "待处理": "open"
      "进行中": "open"
      "待验收": "open"
      "已完成": "closed"
      "已关闭": "closed"

    priorities:
      "低": "low"
      "中": "medium"
      "高": "high"
      "紧急": "critical"
```

## 数据转换函数

### GitHub Issue到云效工作项
```bash
# 将GitHub Issue转换为云效工作项格式
convert_github_issue_to_yunxiao() {
  local issue_json="$1"
  local mapping_file="${2:-.claude/rules/platform-mapping.yml}"

  # 提取GitHub Issue字段
  local title=$(echo "$issue_json" | jq -r '.title')
  local body=$(echo "$issue_json" | jq -r '.body // ""')
  local state=$(echo "$issue_json" | jq -r '.state')
  local labels=$(echo "$issue_json" | jq -r '.labels[].name' | tr '\n' ',' | sed 's/,$//')
  local assignee=$(echo "$issue_json" | jq -r '.assignee.login // ""')
  local issue_number=$(echo "$issue_json" | jq -r '.number')
  local github_url=$(echo "$issue_json" | jq -r '.html_url')

  # 映射工作项类型
  local workitem_type="任务"  # 默认类型
  if echo "$labels" | grep -q "enhancement"; then
    workitem_type="需求"
  elif echo "$labels" | grep -q "bug"; then
    workitem_type="缺陷"
  fi

  # 映射状态
  local yunxiao_status
  case "$state" in
    "open") yunxiao_status="待处理" ;;
    "closed") yunxiao_status="已完成" ;;
    *) yunxiao_status="待处理" ;;
  esac

  # 转换标签
  local yunxiao_labels=$(convert_github_labels_to_yunxiao "$labels")

  # 构建描述（包含来源信息）
  local yunxiao_description=$(cat <<EOF
## 原始描述
$body

## 同步信息
- 来源: GitHub Issue #$issue_number
- 原始链接: $github_url
- 同步时间: $(date '+%Y-%m-%d %H:%M:%S')
- 标签映射: $labels → $yunxiao_labels
EOF
)

  # 构建云效工作项JSON
  local yunxiao_workitem=$(cat <<EOF
{
  "title": "$title [GitHub #$issue_number]",
  "workitem_type": "$workitem_type",
  "description": $(echo "$yunxiao_description" | jq -Rs .),
  "status": "$yunxiao_status",
  "priority": "中",
  "assignee": "$assignee",
  "labels": $(echo "$yunxiao_labels" | tr ',' '\n' | jq -R . | jq -s .),
  "custom_fields": {
    "github_issue_number": "$issue_number",
    "github_url": "$github_url",
    "sync_source": "github",
    "original_labels": $(echo "$labels" | tr ',' '\n' | jq -R . | jq -s .)
  }
}
EOF
)

  echo "$yunxiao_workitem"
}

# 转换GitHub标签到云效标签
convert_github_labels_to_yunxiao() {
  local github_labels="$1"
  local yunxiao_labels=""

  # 分割标签并逐个转换
  IFS=',' read -ra labels_array <<< "$github_labels"
  for label in "${labels_array[@]}"; do
    local trimmed_label=$(echo "$label" | xargs)  # 去除首尾空格
    local yunxiao_label

    case "$trimmed_label" in
      "frontend") yunxiao_label="前端" ;;
      "backend") yunxiao_label="后端" ;;
      "api") yunxiao_label="接口" ;;
      "ui") yunxiao_label="界面" ;;
      "performance") yunxiao_label="性能" ;;
      "security") yunxiao_label="安全" ;;
      "bug") yunxiao_label="缺陷" ;;
      "enhancement") yunxiao_label="功能增强" ;;
      "documentation") yunxiao_label="文档" ;;
      *) yunxiao_label="$trimmed_label" ;;  # 保持原标签
    esac

    if [ -n "$yunxiao_labels" ]; then
      yunxiao_labels="$yunxiao_labels,$yunxiao_label"
    else
      yunxiao_labels="$yunxiao_label"
    fi
  done

  # 添加同步标识标签
  if [ -n "$yunxiao_labels" ]; then
    yunxiao_labels="$yunxiao_labels,github-sync"
  else
    yunxiao_labels="github-sync"
  fi

  echo "$yunxiao_labels"
}
```

### 云效工作项到GitHub Issue
```bash
# 将云效工作项转换为GitHub Issue格式
convert_yunxiao_workitem_to_github() {
  local workitem_json="$1"

  # 提取云效工作项字段
  local title=$(echo "$workitem_json" | jq -r '.title')
  local description=$(echo "$workitem_json" | jq -r '.description // ""')
  local status=$(echo "$workitem_json" | jq -r '.status')
  local workitem_type=$(echo "$workitem_json" | jq -r '.workitem_type')
  local priority=$(echo "$workitem_json" | jq -r '.priority // "中"')
  local assignee=$(echo "$workitem_json" | jq -r '.assignee // ""')
  local workitem_id=$(echo "$workitem_json" | jq -r '.id')
  local yunxiao_url=$(echo "$workitem_json" | jq -r '.url // ""')

  # 映射到GitHub状态
  local github_state
  case "$status" in
    "待处理"|"进行中"|"待验收") github_state="open" ;;
    "已完成"|"已关闭") github_state="closed" ;;
    *) github_state="open" ;;
  esac

  # 映射标签
  local github_labels=()

  # 根据工作项类型添加标签
  case "$workitem_type" in
    "需求") github_labels+=("enhancement") ;;
    "缺陷") github_labels+=("bug") ;;
    "任务") ;;  # 不添加特殊标签
    "子任务") github_labels+=("subtask") ;;
  esac

  # 根据优先级添加标签
  case "$priority" in
    "紧急") github_labels+=("priority:critical") ;;
    "高") github_labels+=("priority:high") ;;
    "中") github_labels+=("priority:medium") ;;
    "低") github_labels+=("priority:low") ;;
  esac

  # 添加同步标识
  github_labels+=("yunxiao-sync")

  # 构建GitHub Issue描述
  local github_description=$(cat <<EOF
## 工作项描述
$description

## 同步信息
- 来源: 云效工作项 #$workitem_id
- 工作项类型: $workitem_type
- 优先级: $priority
- 原始状态: $status
- 同步时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF
)

  # 如果有云效链接，添加到描述中
  if [ -n "$yunxiao_url" ] && [ "$yunxiao_url" != "null" ]; then
    github_description+="\n- 原始链接: $yunxiao_url"
  fi

  # 构建GitHub Issue JSON
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

## 字段映射规则

### 标准字段映射表
```bash
# 定义字段映射关系
declare -A FIELD_MAPPING_GITHUB_TO_YUNXIAO=(
  ["title"]="title"
  ["body"]="description"
  ["state"]="status"
  ["labels"]="labels"
  ["assignee"]="assignee"
  ["milestone"]="milestone"
  ["created_at"]="created_at"
  ["updated_at"]="updated_at"
  ["number"]="github_issue_number"
  ["html_url"]="github_url"
)

declare -A FIELD_MAPPING_YUNXIAO_TO_GITHUB=(
  ["title"]="title"
  ["description"]="body"
  ["status"]="state"
  ["labels"]="labels"
  ["assignee"]="assignee"
  ["created_at"]="created_at"
  ["updated_at"]="updated_at"
  ["id"]="yunxiao_workitem_id"
  ["url"]="yunxiao_url"
)

# 应用字段映射
apply_field_mapping() {
  local source_json="$1"
  local mapping_direction="$2"  # github_to_yunxiao 或 yunxiao_to_github
  local result_json="{}"

  case "$mapping_direction" in
    "github_to_yunxiao")
      for github_field in "${!FIELD_MAPPING_GITHUB_TO_YUNXIAO[@]}"; do
        local yunxiao_field="${FIELD_MAPPING_GITHUB_TO_YUNXIAO[$github_field]}"
        local value=$(echo "$source_json" | jq -r ".$github_field // null")

        if [ "$value" != "null" ]; then
          result_json=$(echo "$result_json" | jq ". + {\"$yunxiao_field\": $(echo "$value" | jq -R .)}")
        fi
      done
      ;;
    "yunxiao_to_github")
      for yunxiao_field in "${!FIELD_MAPPING_YUNXIAO_TO_GITHUB[@]}"; do
        local github_field="${FIELD_MAPPING_YUNXIAO_TO_GITHUB[$yunxiao_field]}"
        local value=$(echo "$source_json" | jq -r ".$yunxiao_field // null")

        if [ "$value" != "null" ]; then
          result_json=$(echo "$result_json" | jq ". + {\"$github_field\": $(echo "$value" | jq -R .)}")
        fi
      done
      ;;
  esac

  echo "$result_json"
}
```

## 数据验证规则

### 映射数据验证
```bash
# 验证GitHub Issue数据
validate_github_issue_data() {
  local issue_json="$1"
  local errors=()

  # 检查必需字段
  local title=$(echo "$issue_json" | jq -r '.title // ""')
  if [ -z "$title" ]; then
    errors+=("缺少必需字段: title")
  fi

  local number=$(echo "$issue_json" | jq -r '.number // ""')
  if [ -z "$number" ]; then
    errors+=("缺少必需字段: number")
  fi

  # 检查字段格式
  local state=$(echo "$issue_json" | jq -r '.state // ""')
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

# 验证云效工作项数据
validate_yunxiao_workitem_data() {
  local workitem_json="$1"
  local errors=()

  # 检查必需字段
  local title=$(echo "$workitem_json" | jq -r '.title // ""')
  if [ -z "$title" ]; then
    errors+=("缺少必需字段: title")
  fi

  local workitem_type=$(echo "$workitem_json" | jq -r '.workitem_type // ""')
  if [ -z "$workitem_type" ]; then
    errors+=("缺少必需字段: workitem_type")
  fi

  # 验证工作项类型
  case "$workitem_type" in
    "任务"|"需求"|"缺陷"|"子任务") ;;
    *) errors+=("无效的工作项类型: $workitem_type") ;;
  esac

  # 验证状态
  local status=$(echo "$workitem_json" | jq -r '.status // ""')
  if [ -n "$status" ]; then
    case "$status" in
      "待处理"|"进行中"|"待验收"|"已完成"|"已关闭") ;;
      *) errors+=("无效的状态: $status") ;;
    esac
  fi

  # 验证优先级
  local priority=$(echo "$workitem_json" | jq -r '.priority // ""')
  if [ -n "$priority" ]; then
    case "$priority" in
      "低"|"中"|"高"|"紧急") ;;
      *) errors+=("无效的优先级: $priority") ;;
    esac
  fi

  # 输出验证结果
  if [ ${#errors[@]} -eq 0 ]; then
    echo "云效工作项数据验证通过"
    return 0
  else
    echo "云效工作项数据验证失败:"
    printf '  - %s\n' "${errors[@]}"
    return 1
  fi
}
```

## 批量转换工具

### 批量数据转换
```bash
# 批量转换GitHub Issues到云效工作项
batch_convert_github_to_yunxiao() {
  local issues_file="$1"
  local output_file="$2"
  local converted_items="[]"

  echo "开始批量转换GitHub Issues到云效工作项..."

  # 读取并转换每个Issue
  local issue_count=$(cat "$issues_file" | jq length)
  echo "发现 $issue_count 个GitHub Issues"

  for ((i=0; i<issue_count; i++)); do
    local issue=$(cat "$issues_file" | jq ".[$i]")
    local issue_number=$(echo "$issue" | jq -r '.number')

    echo "转换 Issue #$issue_number..."

    # 验证数据
    if validate_github_issue_data "$issue"; then
      # 执行转换
      local converted_item=$(convert_github_issue_to_yunxiao "$issue")
      converted_items=$(echo "$converted_items" | jq ". + [$converted_item]")
      echo "  ✓ 转换成功"
    else
      echo "  ✗ 验证失败，跳过"
    fi
  done

  # 保存结果
  echo "$converted_items" > "$output_file"
  local converted_count=$(echo "$converted_items" | jq length)
  echo "批量转换完成: $converted_count/$issue_count 个项目转换成功"
  echo "结果保存到: $output_file"
}

# 批量转换云效工作项到GitHub Issues
batch_convert_yunxiao_to_github() {
  local workitems_file="$1"
  local output_file="$2"
  local converted_items="[]"

  echo "开始批量转换云效工作项到GitHub Issues..."

  # 读取并转换每个工作项
  local workitem_count=$(cat "$workitems_file" | jq length)
  echo "发现 $workitem_count 个云效工作项"

  for ((i=0; i<workitem_count; i++)); do
    local workitem=$(cat "$workitems_file" | jq ".[$i]")
    local workitem_id=$(echo "$workitem" | jq -r '.id')

    echo "转换工作项 #$workitem_id..."

    # 验证数据
    if validate_yunxiao_workitem_data "$workitem"; then
      # 执行转换
      local converted_item=$(convert_yunxiao_workitem_to_github "$workitem")
      converted_items=$(echo "$converted_items" | jq ". + [$converted_item]")
      echo "  ✓ 转换成功"
    else
      echo "  ✗ 验证失败，跳过"
    fi
  done

  # 保存结果
  echo "$converted_items" > "$output_file"
  local converted_count=$(echo "$converted_items" | jq length)
  echo "批量转换完成: $converted_count/$workitem_count 个项目转换成功"
  echo "结果保存到: $output_file"
}
```

## 映射配置管理

### 自定义映射配置
```bash
# 加载自定义映射配置
load_custom_mapping_config() {
  local config_file="${1:-.claude/platform-mapping.yml}"

  if [ -f "$config_file" ]; then
    echo "加载自定义映射配置: $config_file"
    # 这里可以扩展为更复杂的配置加载逻辑
    return 0
  else
    echo "使用默认映射配置"
    return 1
  fi
}

# 生成映射配置模板
generate_mapping_config_template() {
  local output_file="${1:-.claude/platform-mapping.yml}"

  cat > "$output_file" <<'EOF'
# 平台间数据映射配置文件
# 自定义此文件以调整映射规则

mappings:
  github_to_yunxiao:
    # 自定义Issue类型映射
    issue_types:
      issue: "任务"
      enhancement: "需求"
      bug: "缺陷"
      documentation: "任务"

    # 自定义状态映射
    states:
      open: "待处理"
      closed: "已完成"

    # 自定义优先级映射
    priorities:
      low: "低"
      medium: "中"
      high: "高"
      critical: "紧急"

    # 自定义标签映射
    labels:
      frontend: "前端"
      backend: "后端"
      api: "接口"
      ui: "界面"

  yunxiao_to_github:
    # 反向映射配置
    workitem_types:
      "任务": "issue"
      "需求": "enhancement"
      "缺陷": "bug"

    states:
      "待处理": "open"
      "进行中": "open"
      "已完成": "closed"

    priorities:
      "低": "low"
      "中": "medium"
      "高": "high"
      "紧急": "critical"

# 高级配置选项
advanced:
  # 是否保留原始标签
  preserve_original_labels: true

  # 同步标识标签
  sync_labels:
    github_to_yunxiao: "github-sync"
    yunxiao_to_github: "yunxiao-sync"

  # 描述模板
  description_templates:
    github_to_yunxiao: |
      ## 原始描述
      {original_description}

      ## 同步信息
      - 来源: GitHub Issue #{issue_number}
      - 原始链接: {github_url}
      - 同步时间: {sync_time}

    yunxiao_to_github: |
      ## 工作项描述
      {original_description}

      ## 同步信息
      - 来源: 云效工作项 #{workitem_id}
      - 工作项类型: {workitem_type}
      - 同步时间: {sync_time}
EOF

  echo "映射配置模板已生成: $output_file"
  echo "请根据需要修改配置文件"
}
```

## 使用示例

### 完整的数据映射流程
```bash
#!/bin/bash

# 生成配置模板（首次使用）
if [ ! -f ".claude/platform-mapping.yml" ]; then
  echo "生成映射配置模板..."
  generate_mapping_config_template ".claude/platform-mapping.yml"
fi

# 加载配置
load_custom_mapping_config ".claude/platform-mapping.yml"

# 示例：转换单个GitHub Issue
echo "=== 转换单个GitHub Issue ==="
github_issue='{"number":123,"title":"实现用户登录","body":"添加用户登录功能","state":"open","labels":[{"name":"enhancement"},{"name":"frontend"}],"assignee":{"login":"developer1"},"html_url":"https://github.com/user/repo/issues/123"}'

echo "原始GitHub Issue:"
echo "$github_issue" | jq .

yunxiao_workitem=$(convert_github_issue_to_yunxiao "$github_issue")
echo "转换后的云效工作项:"
echo "$yunxiao_workitem" | jq .

# 示例：批量转换
echo "=== 批量转换GitHub Issues ==="
# 假设有issues.json文件包含GitHub Issues数组
# batch_convert_github_to_yunxiao "issues.json" "yunxiao_workitems.json"

echo "数据映射演示完成"
```

## 版本信息

- **规则版本**: v1.0.0
- **最后更新**: 2025-09-28
- **依赖**: jq, yq
- **相关规则**: platform-yunxiao-sync.md, platform-yunxiao-api.md