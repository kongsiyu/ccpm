# 云效工作项操作规则

云效平台工作项的创建、更新、查询和管理操作专用规则。

## 概述

此规则文件专门定义云效平台工作项的各类操作规则，包括工作项生命周期管理、字段操作、关联关系处理等。

## 工作项操作规则

### 创建工作项
```bash
create_yunxiao_workitem() {
  local title="$1"
  local type="$2"  # 任务|需求|缺陷|子任务
  local description="$3"
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  # 构建API请求数据
  local payload=$(cat <<EOF
{
  "title": "$title",
  "workitem_type": "$type",
  "description": "$description",
  "project_id": "$project_id",
  "status": "待处理",
  "priority": "中"
}
EOF
)

  # 发送创建请求
  local response=$(curl -s -X POST \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://devops.aliyun.com/api/v4/projects/$project_id/workitems")

  echo "$response"
}
```

### 更新工作项状态
```bash
update_workitem_status() {
  local workitem_id="$1"
  local new_status="$2"
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  local payload=$(cat <<EOF
{
  "status": "$new_status"
}
EOF
)

  curl -s -X PUT \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://devops.aliyun.com/api/v4/projects/$project_id/workitems/$workitem_id"
}
```

### 查询工作项
```bash
get_workitem() {
  local workitem_id="$1"
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  curl -s -X GET \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    "https://devops.aliyun.com/api/v4/projects/$project_id/workitems/$workitem_id"
}
```

## 字段映射和验证

### 工作项类型验证
```bash
validate_workitem_type() {
  local type="$1"
  case "$type" in
    "任务"|"需求"|"缺陷"|"子任务")
      return 0
      ;;
    *)
      echo "错误: 无效的工作项类型 '$type'"
      echo "支持的类型: 任务, 需求, 缺陷, 子任务"
      return 1
      ;;
  esac
}
```

### 状态验证
```bash
validate_workitem_status() {
  local status="$1"
  case "$status" in
    "待处理"|"进行中"|"待验收"|"已完成"|"已关闭")
      return 0
      ;;
    *)
      echo "错误: 无效的工作项状态 '$status'"
      echo "支持的状态: 待处理, 进行中, 待验收, 已完成, 已关闭"
      return 1
      ;;
  esac
}
```

### 优先级验证
```bash
validate_workitem_priority() {
  local priority="$1"
  case "$priority" in
    "低"|"中"|"高"|"紧急")
      return 0
      ;;
    *)
      echo "错误: 无效的优先级 '$priority'"
      echo "支持的优先级: 低, 中, 高, 紧急"
      return 1
      ;;
  esac
}
```

## 批量操作

### 批量创建工作项
```bash
batch_create_workitems() {
  local input_file="$1"  # JSON文件包含工作项列表

  while IFS= read -r line; do
    local title=$(echo "$line" | jq -r '.title')
    local type=$(echo "$line" | jq -r '.type')
    local description=$(echo "$line" | jq -r '.description')

    echo "创建工作项: $title"
    create_yunxiao_workitem "$title" "$type" "$description"

    # 避免API限流
    sleep 1
  done < <(jq -c '.[]' "$input_file")
}
```

### 批量更新状态
```bash
batch_update_status() {
  local workitem_ids=("$@")
  local new_status="$1"
  shift

  for id in "${workitem_ids[@]}"; do
    echo "更新工作项 $id 状态为: $new_status"
    update_workitem_status "$id" "$new_status"
    sleep 0.5
  done
}
```

## 关联关系管理

### 设置父子关系
```bash
set_workitem_parent() {
  local child_id="$1"
  local parent_id="$2"
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  local payload=$(cat <<EOF
{
  "parent_id": "$parent_id"
}
EOF
)

  curl -s -X PUT \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://devops.aliyun.com/api/v4/projects/$project_id/workitems/$child_id/parent"
}
```

### 关联相关工作项
```bash
link_workitems() {
  local from_id="$1"
  local to_id="$2"
  local relation_type="$3"  # relates_to|blocks|blocked_by
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  local payload=$(cat <<EOF
{
  "target_workitem_id": "$to_id",
  "relation_type": "$relation_type"
}
EOF
)

  curl -s -X POST \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "https://devops.aliyun.com/api/v4/projects/$project_id/workitems/$from_id/relations"
}
```

## 高级查询

### 按条件查询工作项
```bash
query_workitems() {
  local status="$1"
  local assignee="$2"
  local workitem_type="$3"
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  local query_params=""

  [ -n "$status" ] && query_params+="&status=$status"
  [ -n "$assignee" ] && query_params+="&assignee=$assignee"
  [ -n "$workitem_type" ] && query_params+="&workitem_type=$workitem_type"

  curl -s -X GET \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    "https://devops.aliyun.com/api/v4/projects/$project_id/workitems?${query_params#&}"
}
```

### 获取工作项历史
```bash
get_workitem_history() {
  local workitem_id="$1"
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  curl -s -X GET \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    "https://devops.aliyun.com/api/v4/projects/$project_id/workitems/$workitem_id/history"
}
```

## 错误处理

### API响应处理
```bash
handle_api_response() {
  local response="$1"
  local operation="$2"

  # 检查是否有错误信息
  local error_message=$(echo "$response" | jq -r '.error.message // empty')
  if [ -n "$error_message" ]; then
    echo "操作失败 ($operation): $error_message"
    return 1
  fi

  # 检查HTTP状态码
  local status_code=$(echo "$response" | jq -r '.status_code // 200')
  if [ "$status_code" -ge 400 ]; then
    echo "HTTP错误 ($operation): 状态码 $status_code"
    return 1
  fi

  echo "操作成功 ($operation)"
  return 0
}
```

### 重试机制
```bash
retry_api_call() {
  local max_attempts=3
  local delay=1
  local attempt=1

  while [ $attempt -le $max_attempts ]; do
    echo "尝试第 $attempt 次..."

    if "$@"; then
      return 0
    fi

    if [ $attempt -eq $max_attempts ]; then
      echo "达到最大重试次数，操作失败"
      return 1
    fi

    echo "等待 $delay 秒后重试..."
    sleep $delay
    delay=$((delay * 2))  # 指数退避
    attempt=$((attempt + 1))
  done
}
```

## 数据导出和导入

### 导出工作项数据
```bash
export_workitems() {
  local output_file="$1"
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  echo "导出工作项数据到: $output_file"

  curl -s -X GET \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    "https://devops.aliyun.com/api/v4/projects/$project_id/workitems?per_page=100" \
    | jq '.workitems' > "$output_file"

  echo "导出完成"
}
```

### 导入工作项数据
```bash
import_workitems() {
  local input_file="$1"

  if [ ! -f "$input_file" ]; then
    echo "错误: 文件 $input_file 不存在"
    return 1
  fi

  echo "从 $input_file 导入工作项数据"
  batch_create_workitems "$input_file"
  echo "导入完成"
}
```

## 使用示例

### 完整的工作项创建流程
```bash
# 验证输入参数
validate_workitem_type "任务" || exit 1
validate_workitem_status "待处理" || exit 1
validate_workitem_priority "高" || exit 1

# 创建工作项
response=$(create_yunxiao_workitem "实现用户登录功能" "任务" "用户可以通过用户名和密码登录系统")

# 处理响应
if handle_api_response "$response" "创建工作项"; then
  workitem_id=$(echo "$response" | jq -r '.workitem.id')
  echo "工作项已创建，ID: $workitem_id"
else
  echo "工作项创建失败"
  exit 1
fi
```

## 版本信息

- **规则版本**: v1.0.0
- **最后更新**: 2025-09-28
- **依赖规则**: platform-yunxiao-sync.md