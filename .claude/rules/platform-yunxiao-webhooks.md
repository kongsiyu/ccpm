# 云效Webhook集成规则

云效平台Webhook事件处理和集成规则，实现工作项状态自动同步。

## 概述

此规则文件定义了云效平台Webhook事件的处理机制，包括事件订阅、接收、解析和响应处理，实现与本地CCPM系统的实时同步。

## Webhook配置

### 支持的事件类型
```yaml
supported_events:
  workitem:
    - workitem.created    # 工作项创建
    - workitem.updated    # 工作项更新
    - workitem.deleted    # 工作项删除
    - workitem.assigned   # 工作项分配
    - workitem.status_changed  # 状态变更

  project:
    - project.updated     # 项目信息更新
    - project.member_added    # 成员添加
    - project.member_removed  # 成员移除

  system:
    - system.maintenance  # 系统维护通知
```

### Webhook端点配置
```bash
# Webhook服务配置
WEBHOOK_PORT="${YUNXIAO_WEBHOOK_PORT:-8080}"
WEBHOOK_PATH="${YUNXIAO_WEBHOOK_PATH:-/yunxiao/webhook}"
WEBHOOK_SECRET="${YUNXIAO_WEBHOOK_SECRET:-}"

# 获取Webhook URL
get_webhook_url() {
  local external_host="${YUNXIAO_WEBHOOK_HOST:-localhost}"
  echo "http://$external_host:$WEBHOOK_PORT$WEBHOOK_PATH"
}
```

## Webhook服务器

### 简单HTTP服务器
```bash
# 启动Webhook接收服务器
start_webhook_server() {
  local port="$WEBHOOK_PORT"
  local log_file="/tmp/yunxiao_webhook.log"

  echo "启动云效Webhook服务器，端口: $port"
  echo "日志文件: $log_file"

  # 使用Python创建简单HTTP服务器
  python3 -c "
import http.server
import socketserver
import json
import urllib.parse
import hashlib
import hmac
import os
from datetime import datetime

class YunxiaoWebhookHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path != '$WEBHOOK_PATH':
            self.send_response(404)
            self.end_headers()
            return

        # 读取请求体
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        # 验证签名（如果配置了密钥）
        if '$WEBHOOK_SECRET':
            signature = self.headers.get('X-Yunxiao-Signature', '')
            if not self.verify_signature(post_data, signature):
                self.send_response(401)
                self.end_headers()
                return

        # 解析事件数据
        try:
            event_data = json.loads(post_data.decode('utf-8'))
            self.process_webhook_event(event_data)

            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'status': 'success'}).encode())

        except Exception as e:
            print(f'Webhook处理错误: {e}')
            self.send_response(500)
            self.end_headers()

    def verify_signature(self, payload, signature):
        if not signature.startswith('sha256='):
            return False

        expected_signature = 'sha256=' + hmac.new(
            '$WEBHOOK_SECRET'.encode(),
            payload,
            hashlib.sha256
        ).hexdigest()

        return hmac.compare_digest(signature, expected_signature)

    def process_webhook_event(self, event_data):
        timestamp = datetime.now().isoformat()
        log_entry = f'[{timestamp}] {json.dumps(event_data)}\n'

        # 写入日志文件
        with open('$log_file', 'a') as f:
            f.write(log_entry)

        # 调用事件处理器
        os.system(f'bash -c \"handle_webhook_event \'{json.dumps(event_data)}\'\"')

    def log_message(self, format, *args):
        pass  # 禁用默认日志

with socketserver.TCPServer(('', $port), YunxiaoWebhookHandler) as httpd:
    print(f'云效Webhook服务器运行在端口 {$port}')
    httpd.serve_forever()
" &

  local server_pid=$!
  echo "$server_pid" > "/tmp/yunxiao_webhook.pid"
  echo "Webhook服务器已启动，PID: $server_pid"
}

# 停止Webhook服务器
stop_webhook_server() {
  local pid_file="/tmp/yunxiao_webhook.pid"

  if [ -f "$pid_file" ]; then
    local pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "Webhook服务器已停止，PID: $pid"
    fi
    rm -f "$pid_file"
  else
    echo "Webhook服务器未运行"
  fi
}
```

## 事件处理器

### 主事件处理函数
```bash
# 处理Webhook事件
handle_webhook_event() {
  local event_json="$1"
  local event_type=$(echo "$event_json" | jq -r '.event_type')
  local event_source=$(echo "$event_json" | jq -r '.source // "yunxiao"')

  echo "处理事件: $event_type (来源: $event_source)"

  case "$event_type" in
    "workitem.created")
      handle_workitem_created "$event_json"
      ;;
    "workitem.updated")
      handle_workitem_updated "$event_json"
      ;;
    "workitem.deleted")
      handle_workitem_deleted "$event_json"
      ;;
    "workitem.status_changed")
      handle_workitem_status_changed "$event_json"
      ;;
    "workitem.assigned")
      handle_workitem_assigned "$event_json"
      ;;
    *)
      echo "未知事件类型: $event_type"
      ;;
  esac
}

# 工作项创建事件
handle_workitem_created() {
  local event_json="$1"
  local workitem=$(echo "$event_json" | jq '.data.workitem')

  local workitem_id=$(echo "$workitem" | jq -r '.id')
  local title=$(echo "$workitem" | jq -r '.title')
  local type=$(echo "$workitem" | jq -r '.workitem_type')

  echo "新工作项创建: [$type] $title (ID: $workitem_id)"

  # 更新本地缓存
  update_local_workitem_cache "$workitem_id" "$workitem"

  # 触发本地同步
  trigger_local_sync "workitem_created" "$workitem_id"
}

# 工作项更新事件
handle_workitem_updated() {
  local event_json="$1"
  local workitem=$(echo "$event_json" | jq '.data.workitem')
  local changes=$(echo "$event_json" | jq '.data.changes // {}')

  local workitem_id=$(echo "$workitem" | jq -r '.id')
  local title=$(echo "$workitem" | jq -r '.title')

  echo "工作项更新: $title (ID: $workitem_id)"

  # 显示变更详情
  echo "变更字段:"
  echo "$changes" | jq -r 'to_entries[] | "  \(.key): \(.value.old) → \(.value.new)"'

  # 更新本地缓存
  update_local_workitem_cache "$workitem_id" "$workitem"

  # 触发本地同步
  trigger_local_sync "workitem_updated" "$workitem_id"
}

# 工作项删除事件
handle_workitem_deleted() {
  local event_json="$1"
  local workitem_id=$(echo "$event_json" | jq -r '.data.workitem_id')

  echo "工作项删除: ID $workitem_id"

  # 从本地缓存移除
  remove_local_workitem_cache "$workitem_id"

  # 触发本地同步
  trigger_local_sync "workitem_deleted" "$workitem_id"
}

# 工作项状态变更事件
handle_workitem_status_changed() {
  local event_json="$1"
  local workitem_id=$(echo "$event_json" | jq -r '.data.workitem_id')
  local old_status=$(echo "$event_json" | jq -r '.data.old_status')
  local new_status=$(echo "$event_json" | jq -r '.data.new_status')

  echo "工作项状态变更: ID $workitem_id, $old_status → $new_status"

  # 更新本地状态
  update_local_workitem_status "$workitem_id" "$new_status"

  # 触发本地同步
  trigger_local_sync "status_changed" "$workitem_id"
}

# 工作项分配事件
handle_workitem_assigned() {
  local event_json="$1"
  local workitem_id=$(echo "$event_json" | jq -r '.data.workitem_id')
  local assignee=$(echo "$event_json" | jq -r '.data.assignee')
  local old_assignee=$(echo "$event_json" | jq -r '.data.old_assignee // "无"')

  echo "工作项分配变更: ID $workitem_id, $old_assignee → $assignee"

  # 更新本地分配信息
  update_local_workitem_assignee "$workitem_id" "$assignee"

  # 触发本地同步
  trigger_local_sync "assignee_changed" "$workitem_id"
}
```

## 本地缓存管理

### 缓存操作函数
```bash
# 缓存目录配置
CACHE_DIR="$HOME/.ccpm/cache/yunxiao"
WORKITEM_CACHE_DIR="$CACHE_DIR/workitems"

# 初始化缓存目录
init_cache_directories() {
  mkdir -p "$WORKITEM_CACHE_DIR"
  mkdir -p "$CACHE_DIR/sync_events"
  mkdir -p "$CACHE_DIR/webhooks"
}

# 更新工作项缓存
update_local_workitem_cache() {
  local workitem_id="$1"
  local workitem_data="$2"
  local cache_file="$WORKITEM_CACHE_DIR/$workitem_id.json"

  init_cache_directories

  # 添加时间戳
  local cached_data=$(echo "$workitem_data" | jq ". + {\"cached_at\": \"$(date -Iseconds)\"}")

  echo "$cached_data" > "$cache_file"
  echo "工作项缓存已更新: $cache_file"
}

# 获取工作项缓存
get_local_workitem_cache() {
  local workitem_id="$1"
  local cache_file="$WORKITEM_CACHE_DIR/$workitem_id.json"

  if [ -f "$cache_file" ]; then
    cat "$cache_file"
  else
    echo "null"
  fi
}

# 移除工作项缓存
remove_local_workitem_cache() {
  local workitem_id="$1"
  local cache_file="$WORKITEM_CACHE_DIR/$workitem_id.json"

  if [ -f "$cache_file" ]; then
    rm "$cache_file"
    echo "工作项缓存已移除: $workitem_id"
  fi
}

# 更新工作项状态
update_local_workitem_status() {
  local workitem_id="$1"
  local new_status="$2"
  local cache_file="$WORKITEM_CACHE_DIR/$workitem_id.json"

  if [ -f "$cache_file" ]; then
    local updated_data=$(cat "$cache_file" | jq ".status = \"$new_status\" | .updated_at = \"$(date -Iseconds)\"")
    echo "$updated_data" > "$cache_file"
    echo "工作项状态缓存已更新: $workitem_id → $new_status"
  fi
}

# 更新工作项分配
update_local_workitem_assignee() {
  local workitem_id="$1"
  local assignee="$2"
  local cache_file="$WORKITEM_CACHE_DIR/$workitem_id.json"

  if [ -f "$cache_file" ]; then
    local updated_data=$(cat "$cache_file" | jq ".assignee = \"$assignee\" | .updated_at = \"$(date -Iseconds)\"")
    echo "$updated_data" > "$cache_file"
    echo "工作项分配缓存已更新: $workitem_id → $assignee"
  fi
}
```

## 同步触发器

### 本地同步触发
```bash
# 触发本地同步操作
trigger_local_sync() {
  local sync_type="$1"
  local workitem_id="$2"
  local sync_event_file="$CACHE_DIR/sync_events/$(date +%s)_${sync_type}_${workitem_id}.json"

  init_cache_directories

  # 创建同步事件记录
  local sync_event=$(cat <<EOF
{
  "sync_type": "$sync_type",
  "workitem_id": "$workitem_id",
  "timestamp": "$(date -Iseconds)",
  "processed": false
}
EOF
)

  echo "$sync_event" > "$sync_event_file"
  echo "同步事件已创建: $sync_event_file"

  # 如果配置了自动同步，立即处理
  if [ "${YUNXIAO_AUTO_SYNC:-false}" = "true" ]; then
    process_sync_event "$sync_event_file"
  fi
}

# 处理同步事件
process_sync_event() {
  local event_file="$1"
  local event_data=$(cat "$event_file")

  local sync_type=$(echo "$event_data" | jq -r '.sync_type')
  local workitem_id=$(echo "$event_data" | jq -r '.workitem_id')

  echo "处理同步事件: $sync_type for $workitem_id"

  case "$sync_type" in
    "workitem_created"|"workitem_updated")
      sync_workitem_to_local "$workitem_id"
      ;;
    "workitem_deleted")
      remove_local_workitem_references "$workitem_id"
      ;;
    "status_changed"|"assignee_changed")
      update_local_workitem_references "$workitem_id"
      ;;
  esac

  # 标记事件为已处理
  local processed_event=$(echo "$event_data" | jq '.processed = true | .processed_at = "'$(date -Iseconds)'"')
  echo "$processed_event" > "$event_file"
}

# 批量处理待同步事件
process_pending_sync_events() {
  local event_files=($(find "$CACHE_DIR/sync_events" -name "*.json" -type f))

  if [ ${#event_files[@]} -eq 0 ]; then
    echo "没有待处理的同步事件"
    return 0
  fi

  echo "发现 ${#event_files[@]} 个待处理同步事件"

  for event_file in "${event_files[@]}"; do
    local processed=$(cat "$event_file" | jq -r '.processed')

    if [ "$processed" = "false" ]; then
      process_sync_event "$event_file"
    fi
  done

  echo "所有同步事件处理完成"
}
```

## Webhook注册和管理

### 云效平台Webhook注册
```bash
# 注册Webhook
register_yunxiao_webhook() {
  local webhook_url="$1"
  local events=("${@:2}")
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  # 构建事件列表
  local events_json=$(printf '%s\n' "${events[@]}" | jq -R . | jq -s .)

  # 构建注册数据
  local webhook_data=$(cat <<EOF
{
  "url": "$webhook_url",
  "events": $events_json,
  "active": true,
  "secret": "$WEBHOOK_SECRET"
}
EOF
)

  # 发送注册请求
  local endpoint="https://devops.aliyun.com/api/v4/projects/$project_id/webhooks"
  local response=$(yunxiao_post "$endpoint" "$webhook_data")

  if is_operation_successful "$response"; then
    local webhook_id=$(parse_yunxiao_response "$response" 201 | jq -r '.webhook.id')
    echo "Webhook注册成功，ID: $webhook_id"
    echo "$webhook_id" > "$CACHE_DIR/webhook_id"
    return 0
  else
    echo "Webhook注册失败"
    return 1
  fi
}

# 注销Webhook
unregister_yunxiao_webhook() {
  local webhook_id_file="$CACHE_DIR/webhook_id"

  if [ ! -f "$webhook_id_file" ]; then
    echo "未找到Webhook ID"
    return 1
  fi

  local webhook_id=$(cat "$webhook_id_file")
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local endpoint="https://devops.aliyun.com/api/v4/projects/$project_id/webhooks/$webhook_id"

  local response=$(yunxiao_delete "$endpoint")

  if is_operation_successful "$response"; then
    echo "Webhook注销成功，ID: $webhook_id"
    rm -f "$webhook_id_file"
    return 0
  else
    echo "Webhook注销失败"
    return 1
  fi
}

# 更新Webhook配置
update_yunxiao_webhook() {
  local webhook_url="$1"
  local events=("${@:2}")
  local webhook_id_file="$CACHE_DIR/webhook_id"

  if [ ! -f "$webhook_id_file" ]; then
    echo "未找到Webhook ID，请先注册Webhook"
    return 1
  fi

  local webhook_id=$(cat "$webhook_id_file")
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)

  # 构建更新数据
  local events_json=$(printf '%s\n' "${events[@]}" | jq -R . | jq -s .)
  local update_data=$(cat <<EOF
{
  "url": "$webhook_url",
  "events": $events_json,
  "active": true
}
EOF
)

  local endpoint="https://devops.aliyun.com/api/v4/projects/$project_id/webhooks/$webhook_id"
  local response=$(yunxiao_put "$endpoint" "$update_data")

  if is_operation_successful "$response"; then
    echo "Webhook配置更新成功"
    return 0
  else
    echo "Webhook配置更新失败"
    return 1
  fi
}
```

## 使用示例

### 完整的Webhook集成流程
```bash
#!/bin/bash

# 初始化
init_cache_directories

# 检查配置
if [ -z "$YUNXIAO_WEBHOOK_SECRET" ]; then
  echo "警告: 未设置Webhook密钥，建议设置以提高安全性"
fi

# 启动Webhook服务器
echo "启动Webhook服务器..."
start_webhook_server

# 获取Webhook URL
webhook_url=$(get_webhook_url)
echo "Webhook URL: $webhook_url"

# 注册Webhook
echo "注册云效Webhook..."
webhook_events=(
  "workitem.created"
  "workitem.updated"
  "workitem.deleted"
  "workitem.status_changed"
  "workitem.assigned"
)

if register_yunxiao_webhook "$webhook_url" "${webhook_events[@]}"; then
  echo "Webhook集成配置完成"
else
  echo "Webhook注册失败，停止服务器"
  stop_webhook_server
  exit 1
fi

# 启动同步事件处理器
echo "启动同步事件处理器..."
while true; do
  process_pending_sync_events
  sleep 30  # 每30秒检查一次
done &

sync_processor_pid=$!
echo "$sync_processor_pid" > "/tmp/yunxiao_sync_processor.pid"

echo "云效Webhook集成已启动"
echo "- Webhook服务器: $(cat /tmp/yunxiao_webhook.pid)"
echo "- 同步处理器: $sync_processor_pid"
echo "使用 'stop_yunxiao_webhook_integration' 停止服务"

# 等待中断信号
trap 'stop_yunxiao_webhook_integration' INT TERM
wait
```

### 停止Webhook集成
```bash
stop_yunxiao_webhook_integration() {
  echo "停止云效Webhook集成..."

  # 注销Webhook
  unregister_yunxiao_webhook

  # 停止同步处理器
  if [ -f "/tmp/yunxiao_sync_processor.pid" ]; then
    local pid=$(cat "/tmp/yunxiao_sync_processor.pid")
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "同步处理器已停止"
    fi
    rm -f "/tmp/yunxiao_sync_processor.pid"
  fi

  # 停止Webhook服务器
  stop_webhook_server

  echo "云效Webhook集成已完全停止"
}
```

## 版本信息

- **规则版本**: v1.0.0
- **最后更新**: 2025-09-28
- **依赖**: python3, jq, curl
- **相关规则**: platform-yunxiao-sync.md, platform-yunxiao-api.md