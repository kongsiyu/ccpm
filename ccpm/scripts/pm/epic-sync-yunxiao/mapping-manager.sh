#!/bin/bash

# Epic-Yunxiao Mapping Manager
# 映射关系管理器，负责维护本地Epic文件与云效工作项之间的映射关系

# 获取脚本目录并引入依赖库
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$LIB_DIR/frontmatter.sh"
source "$LIB_DIR/datetime.sh"

# =============================================================================
# 常量定义
# =============================================================================

# 映射文件路径
readonly MAPPING_FILE=".claude/sync-status/yunxiao-mappings.json"
readonly MAPPING_BACKUP_DIR=".claude/sync-status/mapping-backups"
readonly MAPPING_TEMPLATE="$SCRIPT_DIR/templates/mapping-config.json"

# 映射类型
readonly MAPPING_TYPE_EPIC_TO_REQUIREMENT="epic_to_requirement"
readonly MAPPING_TYPE_TASK_TO_TASK="task_to_task"
readonly MAPPING_TYPE_ISSUE_TO_BUG="issue_to_bug"

# 同步方向
readonly SYNC_DIRECTION_BIDIRECTIONAL="bidirectional"
readonly SYNC_DIRECTION_PUSH_ONLY="push_only"
readonly SYNC_DIRECTION_PULL_ONLY="pull_only"

# =============================================================================
# 映射管理器初始化
# =============================================================================

# 初始化映射管理器
# Usage: init_mapping_manager
# Returns: 0 on success, 1 on failure
init_mapping_manager() {
    log_yunxiao_debug "初始化映射管理器"

    # 创建必要的目录
    mkdir -p "$(dirname "$MAPPING_FILE")"
    mkdir -p "$MAPPING_BACKUP_DIR"

    # 如果映射文件不存在，创建空的映射文件
    if [ ! -f "$MAPPING_FILE" ]; then
        create_empty_mapping_file
    fi

    # 验证映射文件格式
    validate_mapping_file || return 1

    # 清理过期的备份文件
    cleanup_old_backups

    log_yunxiao_debug "映射管理器初始化完成"
    return 0
}

# 创建空的映射文件
# Usage: create_empty_mapping_file
create_empty_mapping_file() {
    log_yunxiao_debug "创建空的映射配置文件"

    local default_config
    default_config=$(cat << 'EOF'
{
  "mappings": {},
  "config": {
    "auto_create_missing": true,
    "conflict_resolution": "manual",
    "sync_frequency": "hourly",
    "last_sync": null,
    "version": "1.0"
  },
  "metadata": {
    "created": null,
    "updated": null,
    "total_mappings": 0
  }
}
EOF
    )

    local current_time
    current_time=$(get_current_timestamp)

    # 使用jq更新时间戳
    echo "$default_config" | jq \
        --arg created "$current_time" \
        --arg updated "$current_time" \
        '.metadata.created = $created | .metadata.updated = $updated' \
        > "$MAPPING_FILE"

    log_yunxiao_success "映射配置文件已创建: $MAPPING_FILE"
}

# 验证映射文件格式
# Usage: validate_mapping_file
# Returns: 0 if valid, 1 if invalid
validate_mapping_file() {
    if [ ! -f "$MAPPING_FILE" ]; then
        log_yunxiao_error "映射文件不存在: $MAPPING_FILE"
        return 1
    fi

    # 验证JSON格式
    if ! jq empty "$MAPPING_FILE" >/dev/null 2>&1; then
        log_yunxiao_error "映射文件JSON格式无效: $MAPPING_FILE"
        return 1
    fi

    # 验证必要的字段
    local required_fields=("mappings" "config" "metadata")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$MAPPING_FILE" >/dev/null 2>&1; then
            log_yunxiao_error "映射文件缺少必要字段: $field"
            return 1
        fi
    done

    log_yunxiao_debug "映射文件格式验证通过"
    return 0
}

# =============================================================================
# 映射CRUD操作
# =============================================================================

# 创建新的映射关系
# Usage: create_mapping "local_id" "local_path" "yunxiao_workitem_id" "mapping_type" ["sync_direction"] ["sync_fields"]
# Returns: 0 on success, 1 on failure
create_mapping() {
    local local_id="$1"
    local local_path="$2"
    local yunxiao_workitem_id="$3"
    local mapping_type="$4"
    local sync_direction="${5:-$SYNC_DIRECTION_BIDIRECTIONAL}"
    local sync_fields="${6:-status,progress,description,title}"

    if [ -z "$local_id" ] || [ -z "$local_path" ] || [ -z "$yunxiao_workitem_id" ] || [ -z "$mapping_type" ]; then
        log_yunxiao_error "创建映射需要所有必要参数"
        return 1
    fi

    log_yunxiao_info "创建映射关系: $local_id -> $yunxiao_workitem_id"

    # 检查映射是否已存在
    if mapping_exists "$local_id"; then
        log_yunxiao_warning "映射已存在: $local_id"
        return 1
    fi

    # 备份当前映射文件
    backup_mapping_file || return 1

    # 获取当前时间戳
    local current_time
    current_time=$(get_current_timestamp)

    # 构建映射数据
    local mapping_data
    mapping_data=$(jq -n \
        --arg local_id "$local_id" \
        --arg local_path "$local_path" \
        --arg yunxiao_id "$yunxiao_workitem_id" \
        --arg mapping_type "$mapping_type" \
        --arg sync_direction "$sync_direction" \
        --arg sync_fields "$sync_fields" \
        --arg created "$current_time" \
        --arg updated "$current_time" \
        '{
            local_id: $local_id,
            local_path: $local_path,
            yunxiao_workitem_id: $yunxiao_id,
            mapping_type: $mapping_type,
            sync_direction: $sync_direction,
            sync_fields: ($sync_fields | split(",")),
            created: $created,
            last_sync: null,
            sync_count: 0,
            status: "active"
        }')

    # 添加映射到文件
    local temp_file
    temp_file=$(mktemp)

    jq \
        --arg local_id "$local_id" \
        --argjson mapping_data "$mapping_data" \
        --arg updated "$current_time" \
        '.mappings[$local_id] = $mapping_data |
         .metadata.updated = $updated |
         .metadata.total_mappings = (.mappings | length)' \
        "$MAPPING_FILE" > "$temp_file"

    if [ $? -eq 0 ]; then
        mv "$temp_file" "$MAPPING_FILE"
        log_yunxiao_success "映射关系创建成功: $local_id"
        return 0
    else
        rm -f "$temp_file"
        log_yunxiao_error "创建映射关系失败"
        return 1
    fi
}

# 获取映射关系
# Usage: get_mapping "local_id"
# Returns: JSON string or empty if not found
get_mapping() {
    local local_id="$1"

    if [ -z "$local_id" ]; then
        log_yunxiao_error "获取映射需要指定本地ID"
        return 1
    fi

    if [ ! -f "$MAPPING_FILE" ]; then
        return 1
    fi

    jq -r ".mappings[\"$local_id\"] // empty" "$MAPPING_FILE"
}

# 更新映射关系
# Usage: update_mapping "local_id" "field" "value"
# Returns: 0 on success, 1 on failure
update_mapping() {
    local local_id="$1"
    local field="$2"
    local value="$3"

    if [ -z "$local_id" ] || [ -z "$field" ]; then
        log_yunxiao_error "更新映射需要指定本地ID和字段名"
        return 1
    fi

    if ! mapping_exists "$local_id"; then
        log_yunxiao_error "映射不存在: $local_id"
        return 1
    fi

    log_yunxiao_debug "更新映射字段: $local_id.$field = $value"

    # 备份当前映射文件
    backup_mapping_file || return 1

    local current_time
    current_time=$(get_current_timestamp)

    local temp_file
    temp_file=$(mktemp)

    # 更新映射
    jq \
        --arg local_id "$local_id" \
        --arg field "$field" \
        --arg value "$value" \
        --arg updated "$current_time" \
        '.mappings[$local_id][$field] = $value |
         .metadata.updated = $updated' \
        "$MAPPING_FILE" > "$temp_file"

    if [ $? -eq 0 ]; then
        mv "$temp_file" "$MAPPING_FILE"
        log_yunxiao_debug "映射更新成功: $local_id.$field"
        return 0
    else
        rm -f "$temp_file"
        log_yunxiao_error "更新映射失败"
        return 1
    fi
}

# 删除映射关系
# Usage: delete_mapping "local_id"
# Returns: 0 on success, 1 on failure
delete_mapping() {
    local local_id="$1"

    if [ -z "$local_id" ]; then
        log_yunxiao_error "删除映射需要指定本地ID"
        return 1
    fi

    if ! mapping_exists "$local_id"; then
        log_yunxiao_warning "映射不存在: $local_id"
        return 0
    fi

    log_yunxiao_info "删除映射关系: $local_id"

    # 备份当前映射文件
    backup_mapping_file || return 1

    local current_time
    current_time=$(get_current_timestamp)

    local temp_file
    temp_file=$(mktemp)

    jq \
        --arg local_id "$local_id" \
        --arg updated "$current_time" \
        'del(.mappings[$local_id]) |
         .metadata.updated = $updated |
         .metadata.total_mappings = (.mappings | length)' \
        "$MAPPING_FILE" > "$temp_file"

    if [ $? -eq 0 ]; then
        mv "$temp_file" "$MAPPING_FILE"
        log_yunxiao_success "映射删除成功: $local_id"
        return 0
    else
        rm -f "$temp_file"
        log_yunxiao_error "删除映射失败"
        return 1
    fi
}

# =============================================================================
# 映射查询和匹配
# =============================================================================

# 检查映射是否存在
# Usage: mapping_exists "local_id"
# Returns: 0 if exists, 1 if not
mapping_exists() {
    local local_id="$1"

    if [ -z "$local_id" ] || [ ! -f "$MAPPING_FILE" ]; then
        return 1
    fi

    jq -e ".mappings[\"$local_id\"]" "$MAPPING_FILE" >/dev/null 2>&1
}

# 根据云效工作项ID查找映射
# Usage: find_mapping_by_yunxiao_id "yunxiao_workitem_id"
# Returns: local_id or empty if not found
find_mapping_by_yunxiao_id() {
    local yunxiao_workitem_id="$1"

    if [ -z "$yunxiao_workitem_id" ] || [ ! -f "$MAPPING_FILE" ]; then
        return 1
    fi

    jq -r ".mappings | to_entries[] | select(.value.yunxiao_workitem_id == \"$yunxiao_workitem_id\") | .key" "$MAPPING_FILE"
}

# 获取指定Epic的所有映射
# Usage: get_epic_mappings "epic_name"
# Returns: JSON array of mappings
get_epic_mappings() {
    local epic_name="$1"

    if [ -z "$epic_name" ] || [ ! -f "$MAPPING_FILE" ]; then
        echo "[]"
        return 1
    fi

    jq ".mappings | to_entries[] | select(.value.local_path | startswith(\".claude/epics/$epic_name/\")) | .value" "$MAPPING_FILE"
}

# 列出所有映射
# Usage: list_all_mappings
# Returns: JSON object with all mappings
list_all_mappings() {
    if [ ! -f "$MAPPING_FILE" ]; then
        echo "{}"
        return 1
    fi

    jq '.mappings' "$MAPPING_FILE"
}

# =============================================================================
# 自动映射发现
# =============================================================================

# 自动发现并创建映射关系
# Usage: auto_discover_mappings "epic_name"
# Returns: 0 on success, 1 on failure
auto_discover_mappings() {
    local epic_name="$1"

    log_yunxiao_info "自动发现映射关系: $epic_name"

    # 检查配置是否允许自动创建映射
    local auto_create
    auto_create=$(jq -r '.config.auto_create_missing // true' "$MAPPING_FILE")

    if [ "$auto_create" != "true" ]; then
        log_yunxiao_info "自动创建映射已禁用"
        return 0
    fi

    local epic_dir=".claude/epics/$epic_name"
    local epic_file="$epic_dir/epic.md"

    # 检查Epic文件是否存在
    if [ ! -f "$epic_file" ]; then
        log_yunxiao_warning "Epic文件不存在: $epic_file"
        return 1
    fi

    # 为Epic本身创建映射（如果还没有）
    discover_epic_mapping "$epic_name" "$epic_file"

    # 为Epic下的任务创建映射
    find "$epic_dir" -name "*.md" -type f ! -name "epic.md" | while read -r task_file; do
        discover_task_mapping "$epic_name" "$task_file"
    done

    log_yunxiao_success "自动映射发现完成: $epic_name"
    return 0
}

# 发现Epic映射
# Usage: discover_epic_mapping "epic_name" "epic_file"
discover_epic_mapping() {
    local epic_name="$1"
    local epic_file="$2"
    local local_id="epic:$epic_name"

    # 检查是否已有映射
    if mapping_exists "$local_id"; then
        log_yunxiao_debug "Epic映射已存在: $local_id"
        return 0
    fi

    # 检查frontmatter中是否有yunxiao_id
    local yunxiao_id
    yunxiao_id=$(get_frontmatter_field "$epic_file" "yunxiao_id")

    if [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
        # 找到了yunxiao_id，创建映射
        create_mapping \
            "$local_id" \
            "$epic_file" \
            "$yunxiao_id" \
            "$MAPPING_TYPE_EPIC_TO_REQUIREMENT" \
            "$SYNC_DIRECTION_BIDIRECTIONAL" \
            "title,description,status,progress"

        log_yunxiao_info "发现Epic映射: $local_id -> $yunxiao_id"
    else
        log_yunxiao_debug "Epic未发现云效ID: $epic_file"
    fi
}

# 发现任务映射
# Usage: discover_task_mapping "epic_name" "task_file"
discover_task_mapping() {
    local epic_name="$1"
    local task_file="$2"
    local task_id
    task_id=$(basename "$task_file" .md)
    local local_id="task:$epic_name/$task_id"

    # 检查是否已有映射
    if mapping_exists "$local_id"; then
        log_yunxiao_debug "任务映射已存在: $local_id"
        return 0
    fi

    # 检查frontmatter中是否有yunxiao_id
    local yunxiao_id
    yunxiao_id=$(get_frontmatter_field "$task_file" "yunxiao_id")

    if [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
        # 找到了yunxiao_id，创建映射
        create_mapping \
            "$local_id" \
            "$task_file" \
            "$yunxiao_id" \
            "$MAPPING_TYPE_TASK_TO_TASK" \
            "$SYNC_DIRECTION_BIDIRECTIONAL" \
            "title,description,status,assignee"

        log_yunxiao_info "发现任务映射: $local_id -> $yunxiao_id"
    else
        log_yunxiao_debug "任务未发现云效ID: $task_file"
    fi
}

# =============================================================================
# 映射同步状态管理
# =============================================================================

# 更新映射的最后同步时间
# Usage: update_mapping_sync_time "local_id"
update_mapping_sync_time() {
    local local_id="$1"
    local current_time
    current_time=$(get_current_timestamp)

    update_mapping "$local_id" "last_sync" "$current_time" && \
    increment_sync_count "$local_id"
}

# 增加同步计数
# Usage: increment_sync_count "local_id"
increment_sync_count() {
    local local_id="$1"

    if ! mapping_exists "$local_id"; then
        return 1
    fi

    local current_count
    current_count=$(jq -r ".mappings[\"$local_id\"].sync_count // 0" "$MAPPING_FILE")
    local new_count=$((current_count + 1))

    update_mapping "$local_id" "sync_count" "$new_count"
}

# 标记映射为非活跃状态
# Usage: deactivate_mapping "local_id"
deactivate_mapping() {
    local local_id="$1"
    update_mapping "$local_id" "status" "inactive"
}

# 重新激活映射
# Usage: activate_mapping "local_id"
activate_mapping() {
    local local_id="$1"
    update_mapping "$local_id" "status" "active"
}

# =============================================================================
# 映射文件备份和恢复
# =============================================================================

# 备份映射文件
# Usage: backup_mapping_file
backup_mapping_file() {
    if [ ! -f "$MAPPING_FILE" ]; then
        return 0
    fi

    local backup_name
    backup_name="mappings-$(date +%Y%m%d-%H%M%S).json"
    local backup_path="$MAPPING_BACKUP_DIR/$backup_name"

    cp "$MAPPING_FILE" "$backup_path" && \
    log_yunxiao_debug "映射文件已备份: $backup_name"
}

# 清理过期备份
# Usage: cleanup_old_backups
cleanup_old_backups() {
    if [ ! -d "$MAPPING_BACKUP_DIR" ]; then
        return 0
    fi

    # 保留最近7天的备份
    find "$MAPPING_BACKUP_DIR" -name "mappings-*.json" -type f -mtime +7 -delete 2>/dev/null || true
    log_yunxiao_debug "清理过期映射备份完成"
}

# 恢复映射文件
# Usage: restore_mapping_file "backup_name"
restore_mapping_file() {
    local backup_name="$1"
    local backup_path="$MAPPING_BACKUP_DIR/$backup_name"

    if [ ! -f "$backup_path" ]; then
        log_yunxiao_error "备份文件不存在: $backup_name"
        return 1
    fi

    # 先备份当前文件
    backup_mapping_file

    # 恢复备份文件
    cp "$backup_path" "$MAPPING_FILE" && \
    log_yunxiao_success "映射文件已恢复: $backup_name"
}

# =============================================================================
# 工具函数
# =============================================================================

# 获取当前时间戳
# Usage: get_current_timestamp
get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 加载映射配置
# Usage: load_mapping_configuration
load_mapping_configuration() {
    log_yunxiao_debug "加载映射配置"

    # 确保映射管理器已初始化
    init_mapping_manager || return 1

    # 自动发现新的映射关系
    # 注意：这里可以根据需要启用或禁用
    # auto_discover_mappings

    log_yunxiao_debug "映射配置加载完成"
    return 0
}

# 更新映射后的处理
# Usage: update_mapping_after_sync "epic_name"
update_mapping_after_sync() {
    local epic_name="$1"

    log_yunxiao_debug "更新同步后的映射状态: $epic_name"

    # 获取Epic的所有映射并更新同步时间
    get_epic_mappings "$epic_name" | jq -r '.local_id' | while read -r local_id; do
        if [ -n "$local_id" ] && [ "$local_id" != "null" ]; then
            update_mapping_sync_time "$local_id"
        fi
    done

    log_yunxiao_debug "映射状态更新完成"
    return 0
}

# =============================================================================
# 主程序入口（用于测试）
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # 如果脚本被直接执行，提供一些测试功能
    case "${1:-help}" in
        "init")
            init_mapping_manager
            ;;
        "create")
            create_mapping "$2" "$3" "$4" "$5" "$6" "$7"
            ;;
        "get")
            get_mapping "$2"
            ;;
        "update")
            update_mapping "$2" "$3" "$4"
            ;;
        "delete")
            delete_mapping "$2"
            ;;
        "list")
            list_all_mappings
            ;;
        "discover")
            auto_discover_mappings "$2"
            ;;
        "help"|*)
            cat << EOF
映射管理器测试工具

用法: $0 <命令> [参数...]

命令:
  init                           初始化映射管理器
  create <id> <path> <yunxiao_id> <type> [direction] [fields]  创建映射
  get <id>                       获取映射
  update <id> <field> <value>    更新映射字段
  delete <id>                    删除映射
  list                           列出所有映射
  discover <epic_name>           自动发现Epic的映射关系
  help                           显示此帮助信息
EOF
            ;;
    esac
fi