#!/bin/bash

# Local to Remote Sync
# 本地到云效同步模块，将本地Epic和任务的变更推送到云效工作项

# 获取脚本目录并引入依赖库
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$LIB_DIR/frontmatter.sh"
source "$LIB_DIR/datetime.sh"

# 引入云效CRUD脚本
YUNXIAO_SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")/yunxiao"
source "$YUNXIAO_SCRIPTS_DIR/workitem-common.sh"

# =============================================================================
# 常量定义
# =============================================================================

# 同步状态
readonly SYNC_STATUS_CREATED="created"
readonly SYNC_STATUS_UPDATED="updated"
readonly SYNC_STATUS_SKIPPED="skipped"
readonly SYNC_STATUS_FAILED="failed"

# 字段映射
declare -A EPIC_FIELD_MAPPING=(
    ["name"]="title"
    ["description"]="description"
    ["status"]="status"
    ["created"]="created_time"
    ["updated"]="updated_time"
)

declare -A TASK_FIELD_MAPPING=(
    ["name"]="title"
    ["description"]="description"
    ["status"]="status"
    ["assignee"]="assignee"
    ["created"]="created_time"
    ["updated"]="updated_time"
)

# 状态映射（本地状态 -> 云效状态）
declare -A STATUS_MAPPING=(
    ["open"]="新建"
    ["in_progress"]="进行中"
    ["completed"]="已完成"
    ["closed"]="已关闭"
    ["paused"]="暂停"
    ["cancelled"]="已取消"
)

# =============================================================================
# 主要同步函数
# =============================================================================

# 本地到远程同步入口函数
# Usage: sync_local_to_remote "sync_mode" "epic_name"
# Returns: 0 on success, 1 on failure
sync_local_to_remote() {
    local sync_mode="$1"
    local epic_name="$2"

    log_yunxiao_info "开始本地到云效同步: mode=$sync_mode, epic=$epic_name"

    # 初始化同步上下文
    init_local_sync_context || return 1

    local sync_result=0

    # 根据是否指定Epic名称决定同步范围
    if [ -n "$epic_name" ]; then
        # 同步指定Epic
        sync_single_epic_to_remote "$sync_mode" "$epic_name" || sync_result=1
    else
        # 同步所有Epic
        sync_all_epics_to_remote "$sync_mode" || sync_result=1
    fi

    # 清理同步上下文
    cleanup_local_sync_context

    if [ $sync_result -eq 0 ]; then
        log_yunxiao_success "本地到云效同步完成"
    else
        log_yunxiao_error "本地到云效同步失败"
    fi

    return $sync_result
}

# 同步单个Epic到远程
# Usage: sync_single_epic_to_remote "sync_mode" "epic_name"
sync_single_epic_to_remote() {
    local sync_mode="$1"
    local epic_name="$2"

    log_yunxiao_info "同步Epic到云效: $epic_name"

    local epic_dir=".claude/epics/$epic_name"
    local epic_file="$epic_dir/epic.md"

    # 检查Epic文件是否存在
    if [ ! -f "$epic_file" ]; then
        log_yunxiao_error "Epic文件不存在: $epic_file"
        return 1
    fi

    # 同步Epic本身
    sync_epic_file_to_remote "$epic_file" "$sync_mode" || return 1

    # 同步Epic下的任务
    find "$epic_dir" -name "*.md" -type f ! -name "epic.md" | while read -r task_file; do
        sync_task_file_to_remote "$task_file" "$sync_mode" "$epic_name" || return 1
    done

    log_yunxiao_success "Epic同步完成: $epic_name"
    return 0
}

# 同步所有Epic到远程
# Usage: sync_all_epics_to_remote "sync_mode"
sync_all_epics_to_remote() {
    local sync_mode="$1"

    log_yunxiao_info "同步所有Epic到云效"

    local epic_count=0
    local success_count=0

    # 遍历所有Epic目录
    find .claude/epics -name "epic.md" -type f | while read -r epic_file; do
        local epic_dir
        epic_dir=$(dirname "$epic_file")
        local epic_name
        epic_name=$(basename "$epic_dir")

        epic_count=$((epic_count + 1))

        log_yunxiao_info "处理Epic ($epic_count): $epic_name"

        if sync_single_epic_to_remote "$sync_mode" "$epic_name"; then
            success_count=$((success_count + 1))
            log_yunxiao_success "Epic同步成功: $epic_name"
        else
            log_yunxiao_error "Epic同步失败: $epic_name"
        fi
    done

    log_yunxiao_info "批量同步完成: 成功 $success_count/$epic_count"
    return 0
}

# =============================================================================
# Epic文件同步
# =============================================================================

# 同步Epic文件到远程
# Usage: sync_epic_file_to_remote "epic_file" "sync_mode"
sync_epic_file_to_remote() {
    local epic_file="$1"
    local sync_mode="$2"

    local epic_name
    epic_name=$(basename "$(dirname "$epic_file")")
    local local_id="epic:$epic_name"

    log_yunxiao_debug "同步Epic文件: $epic_file"

    # 检查是否需要同步
    if ! should_sync_file "$epic_file" "$sync_mode"; then
        log_yunxiao_debug "Epic无需同步: $epic_name"
        record_sync_result "$local_id" "$SYNC_STATUS_SKIPPED" "no changes"
        return 0
    fi

    # 提取Epic数据
    local epic_data
    epic_data=$(extract_epic_data "$epic_file") || return 1

    # 检查映射关系
    local yunxiao_id
    yunxiao_id=$(get_frontmatter_field "$epic_file" "yunxiao_id")

    if [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
        # 更新现有工作项
        update_remote_epic "$yunxiao_id" "$epic_data" "$epic_file" || return 1
        record_sync_result "$local_id" "$SYNC_STATUS_UPDATED" "updated workitem $yunxiao_id"
    else
        # 创建新工作项
        create_remote_epic "$epic_data" "$epic_file" || return 1
        record_sync_result "$local_id" "$SYNC_STATUS_CREATED" "created new workitem"
    fi

    # 更新映射信息
    update_epic_mapping "$local_id" "$epic_file"

    return 0
}

# 提取Epic数据
# Usage: extract_epic_data "epic_file"
# Returns: JSON string
extract_epic_data() {
    local epic_file="$1"

    if [ ! -f "$epic_file" ]; then
        log_yunxiao_error "Epic文件不存在: $epic_file"
        return 1
    fi

    # 提取frontmatter字段
    local name description status created updated
    name=$(get_frontmatter_field "$epic_file" "name")
    description=$(strip_frontmatter_content "$epic_file")
    status=$(get_frontmatter_field "$epic_file" "status" "open")
    created=$(get_frontmatter_field "$epic_file" "created")
    updated=$(get_frontmatter_field "$epic_file" "updated")

    # 转换状态
    local yunxiao_status="${STATUS_MAPPING[$status]:-新建}"

    # 构建工作项数据
    format_workitem_json \
        "" \
        "requirement" \
        "$name" \
        "$description" \
        "$yunxiao_status" \
        "" \
        "" \
        "" \
        "$created" \
        "$updated"
}

# 创建远程Epic
# Usage: create_remote_epic "epic_data" "epic_file"
create_remote_epic() {
    local epic_data="$1"
    local epic_file="$2"

    log_yunxiao_info "创建云效工作项: $(get_workitem_field "$epic_data" "title")"

    # 调用云效MCP服务创建工作项
    local create_result
    if create_result=$(yunxiao_create_workitem "$epic_data"); then
        # 提取新创建的工作项ID
        local new_yunxiao_id
        new_yunxiao_id=$(echo "$create_result" | jq -r '.workitem.id // empty')

        if [ -n "$new_yunxiao_id" ]; then
            # 更新Epic文件的yunxiao_id
            update_frontmatter_field "$epic_file" "yunxiao_id" "$new_yunxiao_id"
            update_frontmatter_field "$epic_file" "updated" "$(get_current_timestamp)"

            log_yunxiao_success "Epic创建成功，ID: $new_yunxiao_id"
            return 0
        else
            log_yunxiao_error "无法从创建结果中提取工作项ID"
            return 1
        fi
    else
        log_yunxiao_error "创建Epic工作项失败"
        return 1
    fi
}

# 更新远程Epic
# Usage: update_remote_epic "yunxiao_id" "epic_data" "epic_file"
update_remote_epic() {
    local yunxiao_id="$1"
    local epic_data="$2"
    local epic_file="$3"

    log_yunxiao_info "更新云效工作项: $yunxiao_id"

    # 构建更新数据（只包含变更的字段）
    local update_data
    update_data=$(build_epic_update_data "$epic_data") || return 1

    # 调用云效MCP服务更新工作项
    if yunxiao_update_workitem "$yunxiao_id" "$update_data"; then
        # 更新本地文件的更新时间
        update_frontmatter_field "$epic_file" "updated" "$(get_current_timestamp)"

        log_yunxiao_success "Epic更新成功: $yunxiao_id"
        return 0
    else
        log_yunxiao_error "更新Epic工作项失败: $yunxiao_id"
        return 1
    fi
}

# 构建Epic更新数据
# Usage: build_epic_update_data "epic_data"
# Returns: JSON string with update fields
build_epic_update_data() {
    local epic_data="$1"

    # 提取需要更新的字段
    local title description status
    title=$(get_workitem_field "$epic_data" "title")
    description=$(get_workitem_field "$epic_data" "description")
    status=$(get_workitem_field "$epic_data" "status")

    # 构建更新JSON
    jq -n \
        --arg title "$title" \
        --arg description "$description" \
        --arg status "$status" \
        --arg updated "$(get_current_timestamp)" \
        '{
            title: $title,
            description: $description,
            status: $status,
            updated_time: $updated
        }'
}

# =============================================================================
# Task文件同步
# =============================================================================

# 同步任务文件到远程
# Usage: sync_task_file_to_remote "task_file" "sync_mode" "epic_name"
sync_task_file_to_remote() {
    local task_file="$1"
    local sync_mode="$2"
    local epic_name="$3"

    local task_id
    task_id=$(basename "$task_file" .md)
    local local_id="task:$epic_name/$task_id"

    log_yunxiao_debug "同步任务文件: $task_file"

    # 检查是否需要同步
    if ! should_sync_file "$task_file" "$sync_mode"; then
        log_yunxiao_debug "任务无需同步: $task_id"
        record_sync_result "$local_id" "$SYNC_STATUS_SKIPPED" "no changes"
        return 0
    fi

    # 提取任务数据
    local task_data
    task_data=$(extract_task_data "$task_file") || return 1

    # 检查映射关系
    local yunxiao_id
    yunxiao_id=$(get_frontmatter_field "$task_file" "yunxiao_id")

    if [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
        # 更新现有工作项
        update_remote_task "$yunxiao_id" "$task_data" "$task_file" || return 1
        record_sync_result "$local_id" "$SYNC_STATUS_UPDATED" "updated workitem $yunxiao_id"
    else
        # 创建新工作项
        create_remote_task "$task_data" "$task_file" "$epic_name" || return 1
        record_sync_result "$local_id" "$SYNC_STATUS_CREATED" "created new workitem"
    fi

    # 更新映射信息
    update_task_mapping "$local_id" "$task_file"

    return 0
}

# 提取任务数据
# Usage: extract_task_data "task_file"
# Returns: JSON string
extract_task_data() {
    local task_file="$1"

    if [ ! -f "$task_file" ]; then
        log_yunxiao_error "任务文件不存在: $task_file"
        return 1
    fi

    # 提取frontmatter字段
    local name description status assignee created updated
    name=$(get_frontmatter_field "$task_file" "name")
    description=$(strip_frontmatter_content "$task_file")
    status=$(get_frontmatter_field "$task_file" "status" "open")
    assignee=$(get_frontmatter_field "$task_file" "assignee")
    created=$(get_frontmatter_field "$task_file" "created")
    updated=$(get_frontmatter_field "$task_file" "updated")

    # 转换状态
    local yunxiao_status="${STATUS_MAPPING[$status]:-新建}"

    # 构建工作项数据
    format_workitem_json \
        "" \
        "task" \
        "$name" \
        "$description" \
        "$yunxiao_status" \
        "" \
        "$assignee" \
        "" \
        "$created" \
        "$updated"
}

# 创建远程任务
# Usage: create_remote_task "task_data" "task_file" "epic_name"
create_remote_task() {
    local task_data="$1"
    local task_file="$2"
    local epic_name="$3"

    log_yunxiao_info "创建云效任务: $(get_workitem_field "$task_data" "title")"

    # 检查是否有父Epic的yunxiao_id
    local epic_file=".claude/epics/$epic_name/epic.md"
    local parent_yunxiao_id
    parent_yunxiao_id=$(get_frontmatter_field "$epic_file" "yunxiao_id")

    # 如果有父Epic ID，设置关联关系
    if [ -n "$parent_yunxiao_id" ] && [ "$parent_yunxiao_id" != "null" ]; then
        task_data=$(echo "$task_data" | jq --arg parent_id "$parent_yunxiao_id" '.workitem.parent_id = $parent_id')
    fi

    # 调用云效MCP服务创建工作项
    local create_result
    if create_result=$(yunxiao_create_workitem "$task_data"); then
        # 提取新创建的工作项ID
        local new_yunxiao_id
        new_yunxiao_id=$(echo "$create_result" | jq -r '.workitem.id // empty')

        if [ -n "$new_yunxiao_id" ]; then
            # 更新任务文件的yunxiao_id
            update_frontmatter_field "$task_file" "yunxiao_id" "$new_yunxiao_id"
            update_frontmatter_field "$task_file" "updated" "$(get_current_timestamp)"

            log_yunxiao_success "任务创建成功，ID: $new_yunxiao_id"
            return 0
        else
            log_yunxiao_error "无法从创建结果中提取工作项ID"
            return 1
        fi
    else
        log_yunxiao_error "创建任务工作项失败"
        return 1
    fi
}

# 更新远程任务
# Usage: update_remote_task "yunxiao_id" "task_data" "task_file"
update_remote_task() {
    local yunxiao_id="$1"
    local task_data="$2"
    local task_file="$3"

    log_yunxiao_info "更新云效任务: $yunxiao_id"

    # 构建更新数据
    local update_data
    update_data=$(build_task_update_data "$task_data") || return 1

    # 调用云效MCP服务更新工作项
    if yunxiao_update_workitem "$yunxiao_id" "$update_data"; then
        # 更新本地文件的更新时间
        update_frontmatter_field "$task_file" "updated" "$(get_current_timestamp)"

        log_yunxiao_success "任务更新成功: $yunxiao_id"
        return 0
    else
        log_yunxiao_error "更新任务工作项失败: $yunxiao_id"
        return 1
    fi
}

# 构建任务更新数据
# Usage: build_task_update_data "task_data"
# Returns: JSON string with update fields
build_task_update_data() {
    local task_data="$1"

    # 提取需要更新的字段
    local title description status assignee
    title=$(get_workitem_field "$task_data" "title")
    description=$(get_workitem_field "$task_data" "description")
    status=$(get_workitem_field "$task_data" "status")
    assignee=$(get_workitem_field "$task_data" "assignee")

    # 构建更新JSON
    jq -n \
        --arg title "$title" \
        --arg description "$description" \
        --arg status "$status" \
        --arg assignee "$assignee" \
        --arg updated "$(get_current_timestamp)" \
        '{
            title: $title,
            description: $description,
            status: $status,
            assignee: $assignee,
            updated_time: $updated
        }'
}

# =============================================================================
# 同步条件检查
# =============================================================================

# 检查文件是否需要同步
# Usage: should_sync_file "file_path" "sync_mode"
# Returns: 0 if should sync, 1 if not
should_sync_file() {
    local file_path="$1"
    local sync_mode="$2"

    case "$sync_mode" in
        "full")
            # 全量同步模式，所有文件都需要同步
            return 0
            ;;
        "incremental")
            # 增量同步模式，检查文件是否有变更
            return $(file_has_changes "$file_path")
            ;;
        "dry-run")
            # 干运行模式，不实际同步
            log_yunxiao_debug "[DRY-RUN] 将要同步文件: $file_path"
            return 1
            ;;
        *)
            log_yunxiao_error "不支持的同步模式: $sync_mode"
            return 1
            ;;
    esac
}

# 检查文件是否有变更
# Usage: file_has_changes "file_path"
# Returns: 0 if has changes, 1 if not
file_has_changes() {
    local file_path="$1"

    # 获取文件的最后修改时间
    local file_updated
    file_updated=$(get_frontmatter_field "$file_path" "updated")

    # 获取上次同步时间
    local last_sync
    last_sync=$(get_last_sync_time "$file_path")

    # 如果没有同步记录，认为需要同步
    if [ -z "$last_sync" ] || [ "$last_sync" = "null" ]; then
        log_yunxiao_debug "文件从未同步过: $file_path"
        return 0
    fi

    # 比较时间戳
    if [ -n "$file_updated" ] && [ "$file_updated" != "null" ]; then
        local file_timestamp
        file_timestamp=$(date -d "$file_updated" +%s 2>/dev/null || echo "0")
        local sync_timestamp
        sync_timestamp=$(date -d "$last_sync" +%s 2>/dev/null || echo "0")

        if [ $file_timestamp -gt $sync_timestamp ]; then
            log_yunxiao_debug "文件有更新，需要同步: $file_path"
            return 0
        else
            log_yunxiao_debug "文件无更新，跳过同步: $file_path"
            return 1
        fi
    else
        # 文件没有更新时间戳，检查文件系统修改时间
        local file_mtime
        file_mtime=$(stat -c %Y "$file_path" 2>/dev/null || echo "0")
        local sync_timestamp
        sync_timestamp=$(date -d "$last_sync" +%s 2>/dev/null || echo "0")

        if [ $file_mtime -gt $sync_timestamp ]; then
            log_yunxiao_debug "文件系统显示有更新，需要同步: $file_path"
            return 0
        else
            log_yunxiao_debug "文件系统显示无更新，跳过同步: $file_path"
            return 1
        fi
    fi
}

# =============================================================================
# 工具函数
# =============================================================================

# 初始化本地同步上下文
# Usage: init_local_sync_context
init_local_sync_context() {
    log_yunxiao_debug "初始化本地同步上下文"

    # 创建临时目录
    export LOCAL_SYNC_TEMP_DIR="/tmp/epic-sync-yunxiao-local-$$"
    mkdir -p "$LOCAL_SYNC_TEMP_DIR"

    # 初始化同步结果记录
    export LOCAL_SYNC_RESULTS="$LOCAL_SYNC_TEMP_DIR/sync-results.json"
    echo '{"results": []}' > "$LOCAL_SYNC_RESULTS"

    return 0
}

# 清理本地同步上下文
# Usage: cleanup_local_sync_context
cleanup_local_sync_context() {
    log_yunxiao_debug "清理本地同步上下文"

    # 清理临时文件
    if [ -n "$LOCAL_SYNC_TEMP_DIR" ] && [ -d "$LOCAL_SYNC_TEMP_DIR" ]; then
        rm -rf "$LOCAL_SYNC_TEMP_DIR"
    fi
}

# 记录同步结果
# Usage: record_sync_result "local_id" "status" "message"
record_sync_result() {
    local local_id="$1"
    local status="$2"
    local message="$3"

    if [ -f "$LOCAL_SYNC_RESULTS" ]; then
        local current_time
        current_time=$(get_current_timestamp)

        local result_entry
        result_entry=$(jq -n \
            --arg local_id "$local_id" \
            --arg status "$status" \
            --arg message "$message" \
            --arg timestamp "$current_time" \
            '{
                local_id: $local_id,
                status: $status,
                message: $message,
                timestamp: $timestamp
            }')

        # 添加到结果文件
        jq --argjson entry "$result_entry" '.results += [$entry]' "$LOCAL_SYNC_RESULTS" > "$LOCAL_SYNC_RESULTS.tmp"
        mv "$LOCAL_SYNC_RESULTS.tmp" "$LOCAL_SYNC_RESULTS"
    fi

    log_yunxiao_debug "记录同步结果: $local_id - $status"
}

# 获取当前时间戳
# Usage: get_current_timestamp
get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 去除frontmatter后获取内容
# Usage: strip_frontmatter_content "file_path"
strip_frontmatter_content() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        echo ""
        return 1
    fi

    # 去除frontmatter，返回内容部分
    sed '1,/^---$/d; 1,/^---$/d' "$file_path"
}

# 获取上次同步时间
# Usage: get_last_sync_time "file_path"
get_last_sync_time() {
    local file_path="$1"

    # 这里应该从映射管理器中获取，暂时简化处理
    echo ""
}

# 更新Epic映射信息
# Usage: update_epic_mapping "local_id" "epic_file"
update_epic_mapping() {
    local local_id="$1"
    local epic_file="$2"

    # 这里应该调用映射管理器更新映射
    log_yunxiao_debug "更新Epic映射: $local_id"
}

# 更新任务映射信息
# Usage: update_task_mapping "local_id" "task_file"
update_task_mapping() {
    local local_id="$1"
    local task_file="$2"

    # 这里应该调用映射管理器更新映射
    log_yunxiao_debug "更新任务映射: $local_id"
}

# =============================================================================
# 主程序入口（用于测试）
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # 如果脚本被直接执行，提供测试功能
    case "${1:-help}" in
        "sync")
            sync_local_to_remote "${2:-incremental}" "$3"
            ;;
        "epic")
            sync_single_epic_to_remote "${2:-incremental}" "$3"
            ;;
        "help"|*)
            cat << EOF
本地到云效同步工具

用法: $0 <命令> [参数...]

命令:
  sync [mode] [epic_name]    执行本地到云效同步
  epic [mode] <epic_name>    同步指定Epic到云效
  help                       显示此帮助信息

同步模式:
  incremental               增量同步（默认）
  full                      全量同步
  dry-run                   干运行模式

示例:
  $0 sync incremental        增量同步所有Epic
  $0 epic full my-feature    全量同步指定Epic
  $0 sync dry-run            干运行模式查看要同步的内容
EOF
            ;;
    esac
fi