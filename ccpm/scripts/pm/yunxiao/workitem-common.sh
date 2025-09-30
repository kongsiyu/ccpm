#!/bin/bash

# Yunxiao 工作项通用功能库
# 提供工作项操作的通用函数，数据格式标准化，以及错误处理机制

# 获取脚本目录
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"

# =============================================================================
# 工作项类型和状态定义
# =============================================================================

# 支持的工作项类型
WORKITEM_TYPES=("requirement" "task" "bug" "epic")

# 工作项状态映射
declare -A WORKITEM_STATUS_MAP=(
    ["新建"]="new"
    ["进行中"]="in_progress"
    ["已完成"]="completed"
    ["已关闭"]="closed"
    ["暂停"]="paused"
    ["已取消"]="cancelled"
)

# 优先级映射
declare -A PRIORITY_MAP=(
    ["高"]="high"
    ["中"]="medium"
    ["低"]="low"
    ["紧急"]="urgent"
)

# =============================================================================
# 工作项数据验证函数
# =============================================================================

# 验证工作项类型
# Usage: validate_workitem_type "type"
# Returns: 0 if valid, 1 if invalid
validate_workitem_type() {
    local type="$1"

    if [ -z "$type" ]; then
        log_yunxiao_error "工作项类型不能为空"
        return 1
    fi

    for valid_type in "${WORKITEM_TYPES[@]}"; do
        if [ "$type" = "$valid_type" ]; then
            return 0
        fi
    done

    log_yunxiao_error "不支持的工作项类型: $type"
    log_yunxiao_info "支持的类型: ${WORKITEM_TYPES[*]}"
    return 1
}

# 验证工作项标题
# Usage: validate_workitem_title "title"
# Returns: 0 if valid, 1 if invalid
validate_workitem_title() {
    local title="$1"

    if [ -z "$title" ]; then
        log_yunxiao_error "工作项标题不能为空"
        return 1
    fi

    if [ ${#title} -lt 5 ]; then
        log_yunxiao_error "工作项标题过短，至少需要5个字符"
        return 1
    fi

    if [ ${#title} -gt 100 ]; then
        log_yunxiao_error "工作项标题过长，最多100个字符"
        return 1
    fi

    return 0
}

# 验证工作项ID格式
# Usage: validate_workitem_id "workitem_id"
# Returns: 0 if valid, 1 if invalid
validate_workitem_id() {
    local workitem_id="$1"

    if [ -z "$workitem_id" ]; then
        log_yunxiao_error "工作项ID不能为空"
        return 1
    fi

    # 验证是否为数字
    if ! [[ "$workitem_id" =~ ^[0-9]+$ ]]; then
        log_yunxiao_error "工作项ID必须为数字: $workitem_id"
        return 1
    fi

    return 0
}

# 验证优先级
# Usage: validate_priority "priority"
# Returns: 0 if valid, 1 if invalid
validate_priority() {
    local priority="$1"

    if [ -z "$priority" ]; then
        return 0  # 优先级可选
    fi

    for valid_priority in "${!PRIORITY_MAP[@]}"; do
        if [ "$priority" = "$valid_priority" ] || [ "$priority" = "${PRIORITY_MAP[$valid_priority]}" ]; then
            return 0
        fi
    done

    log_yunxiao_error "不支持的优先级: $priority"
    log_yunxiao_info "支持的优先级: ${!PRIORITY_MAP[*]}"
    return 1
}

# =============================================================================
# 工作项数据格式化函数
# =============================================================================

# 标准化工作项数据为JSON格式
# Usage: format_workitem_json "id" "type" "title" "description" "status" "priority" "assignee" "creator"
# Returns: JSON string
format_workitem_json() {
    local id="$1"
    local type="$2"
    local title="$3"
    local description="$4"
    local status="$5"
    local priority="$6"
    local assignee="$7"
    local creator="$8"
    local created_time="$9"
    local updated_time="${10}"

    # 使用jq构建JSON，避免转义问题
    jq -n \
        --arg id "${id:-""}" \
        --arg type "${type:-""}" \
        --arg title "${title:-""}" \
        --arg description "${description:-""}" \
        --arg status "${status:-""}" \
        --arg priority "${priority:-""}" \
        --arg assignee "${assignee:-""}" \
        --arg creator "${creator:-""}" \
        --arg created_time "${created_time:-""}" \
        --arg updated_time "${updated_time:-""}" \
        '{
            workitem: {
                id: $id,
                type: $type,
                title: $title,
                description: $description,
                status: $status,
                priority: $priority,
                assignee: $assignee,
                creator: $creator,
                created_time: $created_time,
                updated_time: $updated_time
            }
        }'
}

# 从JSON解析工作项字段
# Usage: get_workitem_field "json_string" "field_name"
# Returns: Field value
get_workitem_field() {
    local json="$1"
    local field="$2"

    if [ -z "$json" ] || [ -z "$field" ]; then
        return 1
    fi

    echo "$json" | jq -r ".workitem.${field} // empty"
}

# 格式化工作项显示输出
# Usage: format_workitem_display "json_string"
format_workitem_display() {
    local json="$1"

    if [ -z "$json" ]; then
        log_yunxiao_error "无工作项数据"
        return 1
    fi

    local id title type status priority assignee created_time
    id=$(get_workitem_field "$json" "id")
    title=$(get_workitem_field "$json" "title")
    type=$(get_workitem_field "$json" "type")
    status=$(get_workitem_field "$json" "status")
    priority=$(get_workitem_field "$json" "priority")
    assignee=$(get_workitem_field "$json" "assignee")
    created_time=$(get_workitem_field "$json" "created_time")

    echo "=== 工作项 #${id} ==="
    echo "标题: $title"
    echo "类型: $type"
    echo "状态: $status"
    [ -n "$priority" ] && echo "优先级: $priority"
    [ -n "$assignee" ] && echo "指派人: $assignee"
    [ -n "$created_time" ] && echo "创建时间: $created_time"
    echo ""
}

# =============================================================================
# 工作项模板处理函数
# =============================================================================

# 获取工作项模板路径
# Usage: get_workitem_template_path "type"
# Returns: Template file path
get_workitem_template_path() {
    local type="$1"

    if [ -z "$type" ]; then
        log_yunxiao_error "工作项类型不能为空"
        return 1
    fi

    local template_file="$SCRIPT_DIR/workitem-templates/${type}.json"

    if [ ! -f "$template_file" ]; then
        log_yunxiao_warning "模板文件不存在: $template_file"
        return 1
    fi

    echo "$template_file"
    return 0
}

# 从模板创建工作项数据
# Usage: create_from_template "type" "title" "description" ["assignee"] ["priority"]
# Returns: JSON string
create_from_template() {
    local type="$1"
    local title="$2"
    local description="$3"
    local assignee="$4"
    local priority="$5"

    validate_workitem_type "$type" || return 1
    validate_workitem_title "$title" || return 1

    local template_path
    template_path=$(get_workitem_template_path "$type")

    if [ $? -eq 0 ] && [ -f "$template_path" ]; then
        # 使用模板文件
        local template_json
        template_json=$(cat "$template_path")

        # 替换模板中的占位符
        echo "$template_json" | jq \
            --arg title "$title" \
            --arg description "$description" \
            --arg assignee "${assignee:-""}" \
            --arg priority "${priority:-""}" \
            '.workitem.title = $title |
             .workitem.description = $description |
             (.workitem.assignee = $assignee | if $assignee == "" then .workitem.assignee = null else . end) |
             (.workitem.priority = $priority | if $priority == "" then .workitem.priority = null else . end)'
    else
        # 使用默认格式
        local current_time
        current_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

        format_workitem_json \
            "" \
            "$type" \
            "$title" \
            "$description" \
            "新建" \
            "$priority" \
            "$assignee" \
            "" \
            "$current_time" \
            "$current_time"
    fi
}

# =============================================================================
# MCP调用封装函数
# =============================================================================

# 调用云效MCP服务创建工作项
# Usage: yunxiao_create_workitem "workitem_json"
# Returns: 0 on success, 1 on failure
yunxiao_create_workitem() {
    local workitem_json="$1"

    if [ -z "$workitem_json" ]; then
        log_yunxiao_error "工作项数据不能为空"
        return 1
    fi

    # 验证JSON格式
    if ! validate_json "$workitem_json"; then
        log_yunxiao_error "工作项数据格式错误"
        return 1
    fi

    # TODO: 实现实际的MCP调用
    log_yunxiao_debug "创建工作项 MCP调用: $workitem_json"

    # 调用yunxiao库的MCP函数
    yunxiao_call_mcp "create_work_item" "$workitem_json"
}

# 调用云效MCP服务获取工作项
# Usage: yunxiao_get_workitem "workitem_id"
# Returns: 0 on success, 1 on failure
yunxiao_get_workitem() {
    local workitem_id="$1"

    validate_workitem_id "$workitem_id" || return 1

    log_yunxiao_debug "获取工作项 MCP调用: ID=$workitem_id"

    yunxiao_call_mcp "get_work_item" "$workitem_id"
}

# 调用云效MCP服务列出工作项
# Usage: yunxiao_list_workitems ["filters"] ["page"] ["size"]
# Returns: 0 on success, 1 on failure
yunxiao_list_workitems() {
    local filters="$1"
    local page="${2:-1}"
    local size="${3:-20}"

    log_yunxiao_debug "列出工作项 MCP调用: filters=$filters, page=$page, size=$size"

    yunxiao_call_mcp "list_work_items" "$filters" "$page" "$size"
}

# 调用云效MCP服务更新工作项
# Usage: yunxiao_update_workitem "workitem_id" "updates_json"
# Returns: 0 on success, 1 on failure
yunxiao_update_workitem() {
    local workitem_id="$1"
    local updates_json="$2"

    validate_workitem_id "$workitem_id" || return 1

    if [ -z "$updates_json" ]; then
        log_yunxiao_error "更新数据不能为空"
        return 1
    fi

    # 验证JSON格式
    if ! validate_json "$updates_json"; then
        log_yunxiao_error "更新数据格式错误"
        return 1
    fi

    log_yunxiao_debug "更新工作项 MCP调用: ID=$workitem_id, updates=$updates_json"

    yunxiao_call_mcp "update_work_item" "$workitem_id" "$updates_json"
}

# 调用云效MCP服务删除工作项
# Usage: yunxiao_delete_workitem "workitem_id" ["force"]
# Returns: 0 on success, 1 on failure
yunxiao_delete_workitem() {
    local workitem_id="$1"
    local force="$2"

    validate_workitem_id "$workitem_id" || return 1

    log_yunxiao_debug "删除工作项 MCP调用: ID=$workitem_id, force=$force"

    yunxiao_call_mcp "delete_work_item" "$workitem_id" "$force"
}

# =============================================================================
# 错误重试机制
# =============================================================================

# 带重试的MCP调用
# Usage: yunxiao_retry_call "function_name" [args...]
# Returns: 0 on success, 1 on failure
yunxiao_retry_call() {
    local func_name="$1"
    shift
    local max_retries=3
    local retry_delay=2
    local attempt=1

    while [ $attempt -le $max_retries ]; do
        log_yunxiao_debug "尝试 $attempt/$max_retries: $func_name"

        if "$func_name" "$@"; then
            return 0
        fi

        if [ $attempt -lt $max_retries ]; then
            log_yunxiao_warning "调用失败，${retry_delay}秒后重试..."
            sleep $retry_delay
            retry_delay=$((retry_delay * 2))  # 指数退避
        fi

        attempt=$((attempt + 1))
    done

    log_yunxiao_error "MCP调用失败，已达到最大重试次数"
    return 1
}

# =============================================================================
# 批量操作支持
# =============================================================================

# 批量处理工作项
# Usage: batch_process_workitems "operation" "workitem_ids_array" ["additional_args"]
batch_process_workitems() {
    local operation="$1"
    local -n workitem_ids_ref=$2
    shift 2
    local additional_args=("$@")

    local total=${#workitem_ids_ref[@]}
    local success_count=0
    local fail_count=0

    log_yunxiao_info "开始批量$operation，共 $total 个工作项"

    for i in "${!workitem_ids_ref[@]}"; do
        local workitem_id="${workitem_ids_ref[$i]}"
        local progress=$((i + 1))

        echo -n "[$progress/$total] 处理工作项 #$workitem_id... "

        case "$operation" in
            "get")
                if yunxiao_retry_call yunxiao_get_workitem "$workitem_id"; then
                    echo "✅"
                    success_count=$((success_count + 1))
                else
                    echo "❌"
                    fail_count=$((fail_count + 1))
                fi
                ;;
            "delete")
                if yunxiao_retry_call yunxiao_delete_workitem "$workitem_id" "${additional_args[@]}"; then
                    echo "✅"
                    success_count=$((success_count + 1))
                else
                    echo "❌"
                    fail_count=$((fail_count + 1))
                fi
                ;;
            *)
                log_yunxiao_error "不支持的批量操作: $operation"
                return 1
                ;;
        esac

        # 添加短暂延迟，避免API限流
        sleep 0.1
    done

    log_yunxiao_info "批量操作完成: 成功 $success_count，失败 $fail_count"

    if [ $fail_count -gt 0 ]; then
        return 1
    fi

    return 0
}

# =============================================================================
# 初始化和依赖检查
# =============================================================================

# 检查依赖和环境
# Usage: check_workitem_dependencies
# Returns: 0 if all dependencies available, 1 if not
check_workitem_dependencies() {
    # 检查必要的命令
    require_commands "jq"

    # 检查yunxiao配置
    if ! validate_yunxiao_config; then
        log_yunxiao_error "云效配置验证失败"
        return 1
    fi

    # 检查MCP服务
    if ! check_yunxiao_mcp_service; then
        log_yunxiao_error "云效MCP服务不可用"
        return 1
    fi

    return 0
}

# 初始化工作项脚本环境
# Usage: init_workitem_environment
init_workitem_environment() {
    # 启用严格模式
    set_strict_mode

    # 检查依赖
    check_workitem_dependencies || error_exit "依赖检查失败"

    # 设置调试模式（如果启用）
    if [ "${YUNXIAO_DEBUG:-}" = "1" ]; then
        export YUNXIAO_DEBUG=1
        log_yunxiao_debug "调试模式已启用"
    fi

    log_yunxiao_debug "工作项脚本环境初始化完成"
}