# 云效API调用和数据处理规则

云效平台API接口调用规范、数据处理和错误处理的专用规则。

## 概述

此规则文件定义了与阿里云云效平台API交互的标准化方法，包括认证、请求格式、响应处理、错误重试等核心功能。

## API基础配置

### 端点配置
```bash
# 云效API基础配置
YUNXIAO_API_BASE="https://devops.aliyun.com/api/v4"
YUNXIAO_API_VERSION="v4"

# 通用端点模板
get_api_endpoint() {
  local resource="$1"
  local project_id="$2"
  local resource_id="${3:-}"

  case "$resource" in
    "projects")
      echo "$YUNXIAO_API_BASE/projects"
      ;;
    "project")
      echo "$YUNXIAO_API_BASE/projects/$project_id"
      ;;
    "workitems")
      echo "$YUNXIAO_API_BASE/projects/$project_id/workitems"
      ;;
    "workitem")
      echo "$YUNXIAO_API_BASE/projects/$project_id/workitems/$resource_id"
      ;;
    "users")
      echo "$YUNXIAO_API_BASE/projects/$project_id/users"
      ;;
    *)
      echo "错误: 未知的资源类型 '$resource'" >&2
      return 1
      ;;
  esac
}
```

### 认证处理
```bash
# 检查认证令牌
check_yunxiao_auth() {
  if [ -z "$YUNXIAO_ACCESS_TOKEN" ]; then
    echo "错误: 未设置云效访问令牌"
    echo "请设置环境变量: export YUNXIAO_ACCESS_TOKEN='your_token'"
    return 1
  fi

  # 验证令牌有效性
  local response=$(curl -s -w "%{http_code}" \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    "$YUNXIAO_API_BASE/user")

  local status_code=$(echo "$response" | tail -n1)
  if [ "$status_code" != "200" ]; then
    echo "错误: 云效访问令牌无效或已过期"
    return 1
  fi

  return 0
}

# 获取认证请求头
get_auth_headers() {
  cat <<EOF
Authorization: Bearer $YUNXIAO_ACCESS_TOKEN
Content-Type: application/json
Accept: application/json
User-Agent: CCPM-Yunxiao-Client/1.0
EOF
}
```

## HTTP请求封装

### 通用请求函数
```bash
# 通用API请求函数
yunxiao_api_request() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local headers_file="/tmp/yunxiao_headers_$$"

  # 准备请求头
  get_auth_headers > "$headers_file"

  # 构建curl命令
  local curl_cmd="curl -s -X $method"

  # 添加请求头
  while IFS= read -r header; do
    curl_cmd+=" -H \"$header\""
  done < "$headers_file"

  # 添加数据（如果有）
  if [ -n "$data" ]; then
    curl_cmd+=" -d '$data'"
  fi

  # 添加响应状态码
  curl_cmd+=" -w \"\\n%{http_code}\""

  # 添加端点
  curl_cmd+=" \"$endpoint\""

  # 执行请求
  local response
  response=$(eval "$curl_cmd")

  # 清理临时文件
  rm -f "$headers_file"

  echo "$response"
}

# GET请求
yunxiao_get() {
  local endpoint="$1"
  yunxiao_api_request "GET" "$endpoint"
}

# POST请求
yunxiao_post() {
  local endpoint="$1"
  local data="$2"
  yunxiao_api_request "POST" "$endpoint" "$data"
}

# PUT请求
yunxiao_put() {
  local endpoint="$1"
  local data="$2"
  yunxiao_api_request "PUT" "$endpoint" "$data"
}

# DELETE请求
yunxiao_delete() {
  local endpoint="$1"
  yunxiao_api_request "DELETE" "$endpoint"
}
```

### 分页请求处理
```bash
# 处理分页API请求
yunxiao_paginated_request() {
  local endpoint="$1"
  local per_page="${2:-50}"  # 默认每页50条
  local all_results="[]"
  local page=1
  local has_more=true

  while [ "$has_more" = true ]; do
    local paginated_endpoint="${endpoint}?page=$page&per_page=$per_page"
    local response=$(yunxiao_get "$paginated_endpoint")

    # 分离响应体和状态码
    local status_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n -1)

    if [ "$status_code" != "200" ]; then
      echo "分页请求失败，页码: $page，状态码: $status_code" >&2
      return 1
    fi

    # 解析响应数据
    local page_data=$(echo "$body" | jq -r '.data // .workitems // .items // []')
    local total_pages=$(echo "$body" | jq -r '.total_pages // 1')

    # 合并结果
    all_results=$(echo "$all_results" | jq ". + $page_data")

    # 检查是否还有更多页面
    if [ "$page" -ge "$total_pages" ]; then
      has_more=false
    else
      page=$((page + 1))
    fi

    # 避免API限流
    sleep 0.2
  done

  echo "$all_results"
}
```

## 响应处理

### 标准响应解析
```bash
# 解析API响应
parse_yunxiao_response() {
  local response="$1"
  local expected_status="${2:-200}"

  # 分离响应体和状态码
  local status_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | head -n -1)

  # 检查状态码
  if [ "$status_code" != "$expected_status" ]; then
    local error_msg=$(echo "$body" | jq -r '.error.message // .message // "未知错误"')
    echo "API请求失败: HTTP $status_code - $error_msg" >&2
    return 1
  fi

  # 返回响应体
  echo "$body"
}

# 提取特定字段
extract_field() {
  local json_data="$1"
  local field_path="$2"
  local default_value="${3:-null}"

  echo "$json_data" | jq -r "$field_path // \"$default_value\""
}

# 检查操作是否成功
is_operation_successful() {
  local response="$1"
  local status_code=$(echo "$response" | tail -n1)

  case "$status_code" in
    200|201|204)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
```

### 错误处理和重试
```bash
# 指数退避重试机制
retry_with_backoff() {
  local max_attempts="${1:-3}"
  local base_delay="${2:-1}"
  local max_delay="${3:-30}"
  shift 3

  local attempt=1
  local delay="$base_delay"

  while [ $attempt -le $max_attempts ]; do
    echo "尝试第 $attempt 次执行: $*" >&2

    if "$@"; then
      return 0
    fi

    if [ $attempt -eq $max_attempts ]; then
      echo "达到最大重试次数 ($max_attempts)，操作失败" >&2
      return 1
    fi

    echo "等待 $delay 秒后重试..." >&2
    sleep "$delay"

    # 计算下次延迟时间（指数退避）
    delay=$((delay * 2))
    if [ $delay -gt $max_delay ]; then
      delay=$max_delay
    fi

    attempt=$((attempt + 1))
  done
}

# 智能重试（根据错误类型决定是否重试）
smart_retry() {
  local response="$1"
  shift

  local status_code=$(echo "$response" | tail -n1)

  case "$status_code" in
    429|502|503|504)
      # 限流或服务器错误，可以重试
      echo "检测到可重试错误 (HTTP $status_code)，启动重试机制" >&2
      retry_with_backoff 3 2 10 "$@"
      ;;
    401|403)
      # 认证错误，不应重试
      echo "认证错误 (HTTP $status_code)，请检查访问令牌" >&2
      return 1
      ;;
    400|404|422)
      # 客户端错误，不应重试
      echo "请求错误 (HTTP $status_code)，请检查请求参数" >&2
      return 1
      ;;
    *)
      # 未知错误，尝试一次重试
      echo "未知错误 (HTTP $status_code)，尝试重试一次" >&2
      retry_with_backoff 1 1 1 "$@"
      ;;
  esac
}
```

## 数据转换和验证

### JSON数据构建
```bash
# 构建工作项JSON数据
build_workitem_json() {
  local title="$1"
  local type="$2"
  local description="$3"
  local assignee="${4:-}"
  local priority="${5:-中}"
  local status="${6:-待处理}"

  local json_data=$(cat <<EOF
{
  "title": $(echo "$title" | jq -R .),
  "workitem_type": $(echo "$type" | jq -R .),
  "description": $(echo "$description" | jq -R .),
  "priority": $(echo "$priority" | jq -R .),
  "status": $(echo "$status" | jq -R .)
EOF
)

  # 添加可选字段
  if [ -n "$assignee" ]; then
    json_data+=", \"assignee\": $(echo "$assignee" | jq -R .)"
  fi

  json_data+="}"
  echo "$json_data"
}

# 构建更新数据JSON
build_update_json() {
  local updates=("$@")
  local json_data="{"
  local first=true

  for update in "${updates[@]}"; do
    local key=$(echo "$update" | cut -d'=' -f1)
    local value=$(echo "$update" | cut -d'=' -f2-)

    if [ "$first" = true ]; then
      first=false
    else
      json_data+=", "
    fi

    json_data+="\"$key\": $(echo "$value" | jq -R .)"
  done

  json_data+="}"
  echo "$json_data"
}
```

### 数据验证
```bash
# 验证JSON格式
validate_json() {
  local json_data="$1"

  if ! echo "$json_data" | jq . >/dev/null 2>&1; then
    echo "错误: 无效的JSON格式" >&2
    return 1
  fi

  return 0
}

# 验证必需字段
validate_required_fields() {
  local json_data="$1"
  shift
  local required_fields=("$@")

  for field in "${required_fields[@]}"; do
    local value=$(echo "$json_data" | jq -r ".$field // empty")
    if [ -z "$value" ]; then
      echo "错误: 缺少必需字段 '$field'" >&2
      return 1
    fi
  done

  return 0
}
```

## 缓存和性能优化

### 响应缓存
```bash
# 缓存API响应
cache_response() {
  local cache_key="$1"
  local response="$2"
  local cache_dir="/tmp/yunxiao_cache"
  local cache_file="$cache_dir/${cache_key}.json"

  mkdir -p "$cache_dir"
  echo "$response" > "$cache_file"

  # 设置缓存过期时间（5分钟）
  touch -d "+5 minutes" "$cache_file"
}

# 获取缓存响应
get_cached_response() {
  local cache_key="$1"
  local cache_dir="/tmp/yunxiao_cache"
  local cache_file="$cache_dir/${cache_key}.json"

  if [ -f "$cache_file" ] && [ "$cache_file" -nt "$(date -d '-5 minutes' '+%Y%m%d%H%M%S')" ]; then
    cat "$cache_file"
    return 0
  fi

  return 1
}

# 带缓存的API请求
cached_yunxiao_request() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  # 生成缓存键
  local cache_key=$(echo "${method}_${endpoint}_${data}" | md5sum | cut -d' ' -f1)

  # 对于GET请求，尝试使用缓存
  if [ "$method" = "GET" ]; then
    local cached_response
    if cached_response=$(get_cached_response "$cache_key"); then
      echo "使用缓存响应" >&2
      echo "$cached_response"
      return 0
    fi
  fi

  # 执行实际请求
  local response=$(yunxiao_api_request "$method" "$endpoint" "$data")

  # 缓存成功的GET响应
  if [ "$method" = "GET" ] && is_operation_successful "$response"; then
    cache_response "$cache_key" "$response"
  fi

  echo "$response"
}
```

### 批量操作优化
```bash
# 批量API请求（并行处理）
batch_api_requests() {
  local max_parallel="${1:-5}"  # 最大并行数
  local requests_file="$2"      # 包含请求信息的文件
  shift 2

  local pids=()
  local results_dir="/tmp/yunxiao_batch_$$"
  mkdir -p "$results_dir"

  local line_num=0
  while IFS= read -r request_line; do
    # 如果达到最大并行数，等待一个进程完成
    if [ ${#pids[@]} -ge $max_parallel ]; then
      wait "${pids[0]}"
      pids=("${pids[@]:1}")  # 移除第一个PID
    fi

    # 解析请求信息
    local method=$(echo "$request_line" | jq -r '.method')
    local endpoint=$(echo "$request_line" | jq -r '.endpoint')
    local data=$(echo "$request_line" | jq -r '.data // empty')

    # 启动后台进程
    (
      local result=$(yunxiao_api_request "$method" "$endpoint" "$data")
      echo "$result" > "$results_dir/result_$line_num"
    ) &

    pids+=($!)
    line_num=$((line_num + 1))

    # 控制请求频率
    sleep 0.1
  done < "$requests_file"

  # 等待所有进程完成
  for pid in "${pids[@]}"; do
    wait "$pid"
  done

  # 收集结果
  for ((i=0; i<line_num; i++)); do
    if [ -f "$results_dir/result_$i" ]; then
      echo "=== 请求 $i 结果 ==="
      cat "$results_dir/result_$i"
      echo
    fi
  done

  # 清理临时文件
  rm -rf "$results_dir"
}
```

## 监控和日志

### API调用日志
```bash
# 记录API调用日志
log_api_call() {
  local method="$1"
  local endpoint="$2"
  local status_code="$3"
  local duration="$4"
  local log_file="${YUNXIAO_LOG_FILE:-/tmp/yunxiao_api.log}"

  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local log_entry="[$timestamp] $method $endpoint - HTTP $status_code - ${duration}ms"

  echo "$log_entry" >> "$log_file"
}

# 带日志的API请求
logged_yunxiao_request() {
  local start_time=$(date +%s%3N)
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local response=$(yunxiao_api_request "$method" "$endpoint" "$data")
  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))

  local status_code=$(echo "$response" | tail -n1)
  log_api_call "$method" "$endpoint" "$status_code" "$duration"

  echo "$response"
}
```

### 性能监控
```bash
# 获取API性能统计
get_api_performance_stats() {
  local log_file="${YUNXIAO_LOG_FILE:-/tmp/yunxiao_api.log}"

  if [ ! -f "$log_file" ]; then
    echo "日志文件不存在: $log_file"
    return 1
  fi

  echo "=== 云效API性能统计 ==="
  echo "总请求数: $(wc -l < "$log_file")"
  echo "成功请求数: $(grep -c "HTTP 2[0-9][0-9]" "$log_file")"
  echo "失败请求数: $(grep -c "HTTP [45][0-9][0-9]" "$log_file")"
  echo

  echo "=== 响应时间统计 ==="
  awk -F' - ' '{print $3}' "$log_file" | sed 's/ms$//' | sort -n | awk '
    BEGIN { sum = 0; count = 0 }
    {
      durations[count] = $1
      sum += $1
      count++
    }
    END {
      if (count > 0) {
        print "平均响应时间: " sum/count "ms"
        print "最小响应时间: " durations[0] "ms"
        print "最大响应时间: " durations[count-1] "ms"

        # 计算中位数
        if (count % 2 == 1) {
          median = durations[int(count/2)]
        } else {
          median = (durations[count/2-1] + durations[count/2]) / 2
        }
        print "中位数响应时间: " median "ms"
      }
    }'
}
```

## 使用示例

### 完整的API调用流程
```bash
#!/bin/bash

# 检查认证
if ! check_yunxiao_auth; then
  exit 1
fi

# 获取项目ID
project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

# 创建工作项
echo "创建新工作项..."
workitem_data=$(build_workitem_json "测试API集成" "任务" "验证云效API集成功能")

endpoint=$(get_api_endpoint "workitems" "$project_id")
response=$(logged_yunxiao_request "POST" "$endpoint" "$workitem_data")

if is_operation_successful "$response"; then
  workitem_id=$(parse_yunxiao_response "$response" 201 | jq -r '.workitem.id')
  echo "工作项创建成功，ID: $workitem_id"
else
  echo "工作项创建失败"
  exit 1
fi

# 更新工作项状态
echo "更新工作项状态..."
update_data='{"status": "进行中"}'

endpoint=$(get_api_endpoint "workitem" "$project_id" "$workitem_id")
response=$(logged_yunxiao_request "PUT" "$endpoint" "$update_data")

if is_operation_successful "$response"; then
  echo "工作项状态更新成功"
else
  echo "工作项状态更新失败"
fi

# 显示性能统计
get_api_performance_stats
```

## 版本信息

- **规则版本**: v1.0.0
- **支持的API版本**: v4
- **最后更新**: 2025-09-28
- **依赖**: jq, curl, md5sum