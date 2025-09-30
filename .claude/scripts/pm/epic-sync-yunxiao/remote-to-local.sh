#!/bin/bash

# Remote to Local Sync
# 云效到本地同步模块，将云效工作项的变更拉取到本地Epic和任务文件

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

# 字段映射（云效字段 -> 本地字段）
declare -A REMOTE_FIELD_MAPPING=(
    ["title"]="name"
    ["description"]="description"
    ["status"]="status"
    ["assignee"]="assignee"
    ["creator"]="creator"
    ["created_time"]="created"
    ["updated_time"]="updated"
)

# 状态映射（云效状态 -> 本地状态）
declare -A REMOTE_STATUS_MAPPING=(
    ["新建"]="open"
    ["进行中"]="in_progress"
    ["已完成"]="completed"
    ["已关闭"]="closed"
    ["暂停"]="paused"
    ["已取消"]="cancelled"
)

# 工作项类型映射
declare -A WORKITEM_TYPE_MAPPING=(
    ["requirement"]="epic"
    ["task"]="task"
    ["bug"]="issue"
)

# =============================================================================
# 主要同步函数
# =============================================================================

# 云效到本地同步入口函数
# Usage: sync_remote_to_local "sync_mode" "epic_name"
# Returns: 0 on success, 1 on failure
sync_remote_to_local() {
    local sync_mode="$1"
    local epic_name="$2"

    log_yunxiao_info "开始云效到本地同步: mode=$sync_mode, epic=$epic_name"

    # 初始化同步上下文
    init_remote_sync_context || return 1

    local sync_result=0

    # 根据是否指定Epic名称决定同步范围
    if [ -n "$epic_name" ]; then
        # 同步指定Epic相关的工作项
        sync_epic_workitems_to_local "$sync_mode" "$epic_name" || sync_result=1
    else
        # 同步所有工作项
        sync_all_workitems_to_local "$sync_mode" || sync_result=1
    fi

    # 清理同步上下文
    cleanup_remote_sync_context

    if [ $sync_result -eq 0 ]; then
        log_yunxiao_success "云效到本地同步完成"
    else
        log_yunxiao_error "云效到本地同步失败"
    fi

    return $sync_result
}

# 同步指定Epic的工作项到本地
# Usage: sync_epic_workitems_to_local "sync_mode" "epic_name"
sync_epic_workitems_to_local() {
    local sync_mode="$1"
    local epic_name="$2"

    log_yunxiao_info "同步Epic工作项到本地: $epic_name"

    # 获取Epic的映射关系
    local epic_mappings
    epic_mappings=$(get_epic_mappings "$epic_name")

    if [ -z "$epic_mappings" ] || [ "$epic_mappings" = "[]" ]; then
        log_yunxiao_warning "未找到Epic的映射关系: $epic_name"
        return 1
    fi

    # 遍历映射关系，同步对应的云效工作项
    echo "$epic_mappings" | jq -r '.yunxiao_workitem_id' | while read -r yunxiao_id; do
        if [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
            sync_single_workitem_to_local "$yunxiao_id" "$sync_mode" || return 1
        fi
    done

    log_yunxiao_success "Epic工作项同步完成: $epic_name"
    return 0
}

# 同步所有工作项到本地
# Usage: sync_all_workitems_to_local "sync_mode"
sync_all_workitems_to_local() {
    local sync_mode="$1"

    log_yunxiao_info "同步所有云效工作项到本地"

    # 获取项目下的所有工作项
    local project_id
    project_id=$(get_project_id)

    if [ -z "$project_id" ]; then
        log_yunxiao_error "无法获取项目ID"
        return 1
    fi

    # 调用云效MCP服务获取工作项列表
    local workitems_result
    if workitems_result=$(yunxiao_list_workitems "{\"project_id\": \"$project_id\"}"); then
        # 解析工作项列表并同步每个工作项
        echo "$workitems_result" | jq -r '.workitems[].id' | while read -r yunxiao_id; do
            if [ -n "$yunxiao_id" ]; then
                sync_single_workitem_to_local "$yunxiao_id" "$sync_mode" || log_yunxiao_warning "同步工作项失败: $yunxiao_id"
            fi
        done
    else
        log_yunxiao_error "获取云效工作项列表失败"
        return 1
    fi

    log_yunxiao_success "所有工作项同步完成"
    return 0
}

# 同步单个工作项到本地
# Usage: sync_single_workitem_to_local "yunxiao_id" "sync_mode"
sync_single_workitem_to_local() {
    local yunxiao_id="$1"
    local sync_mode="$2"

    log_yunxiao_debug "同步工作项到本地: $yunxiao_id"

    # 获取云效工作项详情
    local workitem_data
    if ! workitem_data=$(yunxiao_get_workitem "$yunxiao_id"); then
        log_yunxiao_error "获取云效工作项失败: $yunxiao_id"
        record_remote_sync_result "$yunxiao_id" "$SYNC_STATUS_FAILED" "failed to fetch workitem"
        return 1
    fi

    # 检查是否需要同步
    if ! should_sync_workitem "$workitem_data" "$sync_mode"; then
        log_yunxiao_debug "工作项无需同步: $yunxiao_id"
        record_remote_sync_result "$yunxiao_id" "$SYNC_STATUS_SKIPPED" "no changes"
        return 0
    fi

    # 根据工作项类型决定处理方式
    local workitem_type
    workitem_type=$(get_workitem_field "$workitem_data" "type")

    case "$workitem_type" in
        "requirement")
            sync_requirement_to_epic "$workitem_data" "$sync_mode"
            ;;
        "task")
            sync_task_to_local "$workitem_data" "$sync_mode"
            ;;
        "bug")
            sync_bug_to_issue "$workitem_data" "$sync_mode"
            ;;
        *)
            log_yunxiao_warning "不支持的工作项类型: $workitem_type"
            record_remote_sync_result "$yunxiao_id" "$SYNC_STATUS_SKIPPED" "unsupported type: $workitem_type"
            return 1
            ;;
    esac
}

# =============================================================================
# 需求同步到Epic
# =============================================================================

# 同步云效需求到Epic
# Usage: sync_requirement_to_epic "workitem_data" "sync_mode"
sync_requirement_to_epic() {
    local workitem_data="$1"
    local sync_mode="$2"

    local yunxiao_id
    yunxiao_id=$(get_workitem_field "$workitem_data" "id")

    log_yunxiao_info "同步需求到Epic: $yunxiao_id"

    # 查找现有映射
    local local_id
    local_id=$(find_mapping_by_yunxiao_id "$yunxiao_id")

    if [ -n "$local_id" ]; then
        # 更新现有Epic
        update_existing_epic "$local_id" "$workitem_data" "$sync_mode"
        record_remote_sync_result "$yunxiao_id" "$SYNC_STATUS_UPDATED" "updated epic $local_id"
    else
        # 创建新Epic
        create_new_epic_from_requirement "$workitem_data" "$sync_mode"
        record_remote_sync_result "$yunxiao_id" "$SYNC_STATUS_CREATED" "created new epic"
    fi

    return 0
}

# 更新现有Epic
# Usage: update_existing_epic "local_id" "workitem_data" "sync_mode"
update_existing_epic() {
    local local_id="$1"
    local workitem_data="$2"
    local sync_mode="$3"

    # 解析local_id获取epic名称
    local epic_name
    epic_name=$(echo "$local_id" | sed 's/^epic://')

    local epic_file=".claude/epics/$epic_name/epic.md"

    if [ ! -f "$epic_file" ]; then
        log_yunxiao_warning "Epic文件不存在: $epic_file"
        return 1
    fi

    log_yunxiao_debug "更新Epic文件: $epic_file"

    # 提取工作项字段
    local title description status updated
    title=$(get_workitem_field "$workitem_data" "title")
    description=$(get_workitem_field "$workitem_data" "description")
    status=$(get_workitem_field "$workitem_data" "status")
    updated=$(get_workitem_field "$workitem_data" "updated_time")

    # 转换状态
    local local_status="${REMOTE_STATUS_MAPPING[$status]:-open}"

    # 更新frontmatter字段
    update_frontmatter_field "$epic_file" "name" "$title"
    update_frontmatter_field "$epic_file" "status" "$local_status"
    update_frontmatter_field "$epic_file" "updated" "$updated"

    # 更新描述内容（保留frontmatter，只更新内容部分）
    update_epic_content "$epic_file" "$description"

    log_yunxiao_success "Epic更新完成: $epic_name"
}

# 从云效需求创建新Epic
# Usage: create_new_epic_from_requirement "workitem_data" "sync_mode"
create_new_epic_from_requirement() {
    local workitem_data="$1"
    local sync_mode="$2"

    local yunxiao_id title description status created updated
    yunxiao_id=$(get_workitem_field "$workitem_data" "id")
    title=$(get_workitem_field "$workitem_data" "title")
    description=$(get_workitem_field "$workitem_data" "description")
    status=$(get_workitem_field "$workitem_data" "status")
    created=$(get_workitem_field "$workitem_data" "created_time")
    updated=$(get_workitem_field "$workitem_data" "updated_time")

    # 生成Epic名称（从title生成安全的目录名）
    local epic_name
    epic_name=$(generate_epic_name "$title")

    log_yunxiao_info "创建新Epic: $epic_name (云效ID: $yunxiao_id)"

    # 创建Epic目录和文件
    local epic_dir=".claude/epics/$epic_name"
    local epic_file="$epic_dir/epic.md"

    mkdir -p "$epic_dir"

    # 转换状态
    local local_status="${REMOTE_STATUS_MAPPING[$status]:-open}"

    # 创建Epic文件内容
    create_epic_file_content "$epic_file" "$title" "$description" "$local_status" "$yunxiao_id" "$created" "$updated"

    # 创建映射关系
    create_mapping "epic:$epic_name" "$epic_file" "$yunxiao_id" "epic_to_requirement"

    log_yunxiao_success "新Epic创建完成: $epic_name"
}

# 生成Epic名称
# Usage: generate_epic_name "title"
# Returns: safe directory name
generate_epic_name() {
    local title="$1"

    # 转换为安全的目录名
    echo "$title" | \
        tr '[:upper:]' '[:lower:]' | \
        sed 's/[^a-z0-9\-]/-/g' | \
        sed 's/--*/-/g' | \
        sed 's/^-\|-$//g' | \
        cut -c 1-50
}

# 创建Epic文件内容
# Usage: create_epic_file_content "epic_file" "title" "description" "status" "yunxiao_id" "created" "updated"
create_epic_file_content() {
    local epic_file="$1"
    local title="$2"
    local description="$3"
    local status="$4"
    local yunxiao_id="$5"
    local created="$6"
    local updated="$7"

    cat > "$epic_file" << EOF
---
name: $title
status: $status
created: $created
updated: $updated
yunxiao_id: $yunxiao_id
---

$description
EOF

    log_yunxiao_debug "Epic文件已创建: $epic_file"
}

# 更新Epic内容
# Usage: update_epic_content "epic_file" "new_description"
update_epic_content() {
    local epic_file="$1"
    local new_description="$2"

    if [ ! -f "$epic_file" ]; then
        return 1
    fi

    # 提取frontmatter
    local frontmatter
    frontmatter=$(awk '/^---$/,/^---$/ {print}' "$epic_file")

    # 创建新文件内容
    {
        echo "$frontmatter"
        echo ""
        echo "$new_description"
    } > "$epic_file.tmp"

    mv "$epic_file.tmp" "$epic_file"
    log_yunxiao_debug "Epic内容已更新: $epic_file"
}

# =============================================================================
# 任务同步到本地
# =============================================================================

# 同步云效任务到本地
# Usage: sync_task_to_local "workitem_data" "sync_mode"
sync_task_to_local() {
    local workitem_data="$1"
    local sync_mode="$2"

    local yunxiao_id
    yunxiao_id=$(get_workitem_field "$workitem_data" "id")

    log_yunxiao_info "同步任务到本地: $yunxiao_id"

    # 查找现有映射
    local local_id
    local_id=$(find_mapping_by_yunxiao_id "$yunxiao_id")

    if [ -n "$local_id" ]; then
        # 更新现有任务
        update_existing_task "$local_id" "$workitem_data" "$sync_mode"
        record_remote_sync_result "$yunxiao_id" "$SYNC_STATUS_UPDATED" "updated task $local_id"
    else
        # 创建新任务
        create_new_task_from_workitem "$workitem_data" "$sync_mode"
        record_remote_sync_result "$yunxiao_id" "$SYNC_STATUS_CREATED" "created new task"
    fi

    return 0
}

# 更新现有任务
# Usage: update_existing_task "local_id" "workitem_data" "sync_mode"
update_existing_task() {
    local local_id="$1"
    local workitem_data="$2"
    local sync_mode="$3"

    # 解析local_id获取任务路径
    local task_path
    task_path=$(echo "$local_id" | sed 's/^task://')
    local task_file=".claude/epics/$task_path.md"

    if [ ! -f "$task_file" ]; then
        log_yunxiao_warning "任务文件不存在: $task_file"
        return 1
    fi

    log_yunxiao_debug "更新任务文件: $task_file"

    # 提取工作项字段
    local title description status assignee updated
    title=$(get_workitem_field "$workitem_data" "title")
    description=$(get_workitem_field "$workitem_data" "description")
    status=$(get_workitem_field "$workitem_data" "status")
    assignee=$(get_workitem_field "$workitem_data" "assignee")
    updated=$(get_workitem_field "$workitem_data" "updated_time")

    # 转换状态
    local local_status="${REMOTE_STATUS_MAPPING[$status]:-open}"

    # 更新frontmatter字段
    update_frontmatter_field "$task_file" "name" "$title"
    update_frontmatter_field "$task_file" "status" "$local_status"
    update_frontmatter_field "$task_file" "updated" "$updated"
    [ -n "$assignee" ] && update_frontmatter_field "$task_file" "assignee" "$assignee"

    # 更新任务内容
    update_task_content "$task_file" "$description"

    log_yunxiao_success "任务更新完成: $task_path"
}

# 从云效工作项创建新任务
# Usage: create_new_task_from_workitem "workitem_data" "sync_mode"
create_new_task_from_workitem() {
    local workitem_data="$1"
    local sync_mode="$2"

    local yunxiao_id title description status assignee created updated
    yunxiao_id=$(get_workitem_field "$workitem_data" "id")
    title=$(get_workitem_field "$workitem_data" "title")
    description=$(get_workitem_field "$workitem_data" "description")
    status=$(get_workitem_field "$workitem_data" "status")
    assignee=$(get_workitem_field "$workitem_data" "assignee")
    created=$(get_workitem_field "$workitem_data" "created_time")
    updated=$(get_workitem_field "$workitem_data" "updated_time")

    # 确定任务应该放在哪个Epic下
    local epic_name
    epic_name=$(determine_task_epic "$workitem_data")

    if [ -z "$epic_name" ]; then
        log_yunxiao_warning "无法确定任务所属Epic，使用默认: $yunxiao_id"
        epic_name="imported-tasks"
    fi

    # 生成任务ID
    local task_id="$yunxiao_id"

    log_yunxiao_info "创建新任务: $epic_name/$task_id (云效ID: $yunxiao_id)"

    # 创建任务文件
    local epic_dir=".claude/epics/$epic_name"
    local task_file="$epic_dir/$task_id.md"

    mkdir -p "$epic_dir"

    # 转换状态
    local local_status="${REMOTE_STATUS_MAPPING[$status]:-open}"

    # 创建任务文件内容
    create_task_file_content "$task_file" "$title" "$description" "$local_status" "$assignee" "$yunxiao_id" "$created" "$updated"

    # 创建映射关系
    create_mapping "task:$epic_name/$task_id" "$task_file" "$yunxiao_id" "task_to_task"

    log_yunxiao_success "新任务创建完成: $epic_name/$task_id"
}

# 确定任务所属Epic
# Usage: determine_task_epic "workitem_data"
# Returns: epic name or empty
determine_task_epic() {
    local workitem_data="$1"

    # 检查是否有父工作项ID
    local parent_id
    parent_id=$(get_workitem_field "$workitem_data" "parent_id")

    if [ -n "$parent_id" ] && [ "$parent_id" != "null" ]; then
        # 根据父工作项ID查找对应的Epic
        local parent_local_id
        parent_local_id=$(find_mapping_by_yunxiao_id "$parent_id")

        if [ -n "$parent_local_id" ]; then
            # 提取Epic名称
            echo "$parent_local_id" | sed 's/^epic://'
            return 0
        fi
    fi

    # 如果没有父工作项或找不到映射，返回空
    echo ""
}

# 创建任务文件内容
# Usage: create_task_file_content "task_file" "title" "description" "status" "assignee" "yunxiao_id" "created" "updated"
create_task_file_content() {
    local task_file="$1"
    local title="$2"
    local description="$3"
    local status="$4"
    local assignee="$5"
    local yunxiao_id="$6"
    local created="$7"
    local updated="$8"

    cat > "$task_file" << EOF
---
name: $title
status: $status
created: $created
updated: $updated
yunxiao_id: $yunxiao_id
EOF

    [ -n "$assignee" ] && echo "assignee: $assignee" >> "$task_file"

    cat >> "$task_file" << EOF
---

$description
EOF

    log_yunxiao_debug "任务文件已创建: $task_file"
}

# 更新任务内容
# Usage: update_task_content "task_file" "new_description"
update_task_content() {
    local task_file="$1"
    local new_description="$2"

    if [ ! -f "$task_file" ]; then
        return 1
    fi

    # 提取frontmatter
    local frontmatter
    frontmatter=$(awk '/^---$/,/^---$/ {print}' "$task_file")

    # 创建新文件内容
    {
        echo "$frontmatter"
        echo ""
        echo "$new_description"
    } > "$task_file.tmp"

    mv "$task_file.tmp" "$task_file"
    log_yunxiao_debug "任务内容已更新: $task_file"
}

# =============================================================================
# Bug同步到Issue
# =============================================================================

# 同步云效Bug到Issue
# Usage: sync_bug_to_issue "workitem_data" "sync_mode"
sync_bug_to_issue() {
    local workitem_data="$1"
    local sync_mode="$2"

    local yunxiao_id
    yunxiao_id=$(get_workitem_field "$workitem_data" "id")

    log_yunxiao_info "同步Bug到Issue: $yunxiao_id"

    # Bug同步逻辑与任务类似，但文件结构可能不同
    # 这里简化处理，将Bug作为任务处理
    sync_task_to_local "$workitem_data" "$sync_mode"

    record_remote_sync_result "$yunxiao_id" "$SYNC_STATUS_UPDATED" "synced as task"
    return 0
}

# =============================================================================
# 同步条件检查
# =============================================================================

# 检查工作项是否需要同步
# Usage: should_sync_workitem "workitem_data" "sync_mode"
# Returns: 0 if should sync, 1 if not
should_sync_workitem() {
    local workitem_data="$1"
    local sync_mode="$2"

    case "$sync_mode" in
        "full")
            # 全量同步模式，所有工作项都需要同步
            return 0
            ;;
        "incremental")
            # 增量同步模式，检查工作项是否有变更
            return $(workitem_has_changes "$workitem_data")
            ;;
        "dry-run")
            # 干运行模式，不实际同步
            local yunxiao_id
            yunxiao_id=$(get_workitem_field "$workitem_data" "id")
            log_yunxiao_debug "[DRY-RUN] 将要同步工作项: $yunxiao_id"
            return 1
            ;;
        *)
            log_yunxiao_error "不支持的同步模式: $sync_mode"
            return 1
            ;;
    esac
}

# 检查工作项是否有变更
# Usage: workitem_has_changes "workitem_data"
# Returns: 0 if has changes, 1 if not
workitem_has_changes() {
    local workitem_data="$1"

    local yunxiao_id updated_time
    yunxiao_id=$(get_workitem_field "$workitem_data" "id")
    updated_time=$(get_workitem_field "$workitem_data" "updated_time")

    # 查找本地映射
    local local_id
    local_id=$(find_mapping_by_yunxiao_id "$yunxiao_id")

    if [ -z "$local_id" ]; then
        # 没有本地映射，需要同步
        log_yunxiao_debug "工作项无本地映射，需要同步: $yunxiao_id"
        return 0
    fi

    # 获取上次同步时间
    local last_sync
    last_sync=$(get_mapping_last_sync "$local_id")

    if [ -z "$last_sync" ] || [ "$last_sync" = "null" ]; then
        log_yunxiao_debug "工作项从未同步过: $yunxiao_id"
        return 0
    fi

    # 比较时间戳
    if [ -n "$updated_time" ] && [ "$updated_time" != "null" ]; then
        local workitem_timestamp
        workitem_timestamp=$(date -d "$updated_time" +%s 2>/dev/null || echo "0")
        local sync_timestamp
        sync_timestamp=$(date -d "$last_sync" +%s 2>/dev/null || echo "0")

        if [ $workitem_timestamp -gt $sync_timestamp ]; then
            log_yunxiao_debug "工作项有更新，需要同步: $yunxiao_id"
            return 0
        else
            log_yunxiao_debug "工作项无更新，跳过同步: $yunxiao_id"
            return 1
        fi
    else
        # 没有更新时间，假设需要同步
        log_yunxiao_debug "工作项无更新时间，需要同步: $yunxiao_id"
        return 0
    fi
}

# =============================================================================
# 工具函数
# =============================================================================

# 初始化远程同步上下文
# Usage: init_remote_sync_context
init_remote_sync_context() {
    log_yunxiao_debug "初始化远程同步上下文"

    # 创建临时目录
    export REMOTE_SYNC_TEMP_DIR="/tmp/epic-sync-yunxiao-remote-$$"
    mkdir -p "$REMOTE_SYNC_TEMP_DIR"

    # 初始化同步结果记录
    export REMOTE_SYNC_RESULTS="$REMOTE_SYNC_TEMP_DIR/sync-results.json"
    echo '{"results": []}' > "$REMOTE_SYNC_RESULTS"

    return 0
}

# 清理远程同步上下文
# Usage: cleanup_remote_sync_context
cleanup_remote_sync_context() {
    log_yunxiao_debug "清理远程同步上下文"

    # 清理临时文件
    if [ -n "$REMOTE_SYNC_TEMP_DIR" ] && [ -d "$REMOTE_SYNC_TEMP_DIR" ]; then
        rm -rf "$REMOTE_SYNC_TEMP_DIR"
    fi
}

# 记录远程同步结果
# Usage: record_remote_sync_result "yunxiao_id" "status" "message"
record_remote_sync_result() {
    local yunxiao_id="$1"
    local status="$2"
    local message="$3"

    if [ -f "$REMOTE_SYNC_RESULTS" ]; then
        local current_time
        current_time=$(get_current_timestamp)

        local result_entry
        result_entry=$(jq -n \
            --arg yunxiao_id "$yunxiao_id" \
            --arg status "$status" \
            --arg message "$message" \
            --arg timestamp "$current_time" \
            '{
                yunxiao_id: $yunxiao_id,
                status: $status,
                message: $message,
                timestamp: $timestamp
            }')

        # 添加到结果文件
        jq --argjson entry "$result_entry" '.results += [$entry]' "$REMOTE_SYNC_RESULTS" > "$REMOTE_SYNC_RESULTS.tmp"
        mv "$REMOTE_SYNC_RESULTS.tmp" "$REMOTE_SYNC_RESULTS"
    fi

    log_yunxiao_debug "记录远程同步结果: $yunxiao_id - $status"
}

# 获取当前时间戳
# Usage: get_current_timestamp
get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 获取映射的最后同步时间
# Usage: get_mapping_last_sync "local_id"
get_mapping_last_sync() {
    local local_id="$1"

    # 这里应该从映射管理器中获取，暂时简化处理
    echo ""
}

# =============================================================================
# 主程序入口（用于测试）
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # 如果脚本被直接执行，提供测试功能
    case "${1:-help}" in
        "sync")
            sync_remote_to_local "${2:-incremental}" "$3"
            ;;
        "epic")
            sync_epic_workitems_to_local "${2:-incremental}" "$3"
            ;;
        "workitem")
            sync_single_workitem_to_local "$2" "${3:-incremental}"
            ;;
        "help"|*)
            cat << EOF
云效到本地同步工具

用法: $0 <命令> [参数...]

命令:
  sync [mode] [epic_name]     执行云效到本地同步
  epic [mode] <epic_name>     同步指定Epic的工作项到本地
  workitem <yunxiao_id> [mode] 同步指定工作项到本地
  help                        显示此帮助信息

同步模式:
  incremental                 增量同步（默认）
  full                        全量同步
  dry-run                     干运行模式

示例:
  $0 sync incremental         增量同步所有工作项
  $0 epic full my-feature     全量同步指定Epic的工作项
  $0 workitem 12345           同步指定工作项
  $0 sync dry-run             干运行模式查看要同步的内容
EOF
            ;;
    esac
fi