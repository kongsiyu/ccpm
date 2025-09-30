#!/bin/bash

# Progress Tracker for Epic-Yunxiao Sync
# 进度跟踪器，监控和报告Epic-云效同步的进度和状态

# 获取脚本目录并引入依赖库
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$LIB_DIR/datetime.sh"

# =============================================================================
# 常量定义
# =============================================================================

# 进度状态
readonly PROGRESS_STATUS_INITIALIZING="initializing"
readonly PROGRESS_STATUS_COLLECTING="collecting"
readonly PROGRESS_STATUS_SYNCING="syncing"
readonly PROGRESS_STATUS_VALIDATING="validating"
readonly PROGRESS_STATUS_COMPLETED="completed"
readonly PROGRESS_STATUS_FAILED="failed"

# 进度阶段
readonly PHASE_INIT="initialization"
readonly PHASE_LOCAL_COLLECTION="local_collection"
readonly PHASE_REMOTE_COLLECTION="remote_collection"
readonly PHASE_CONFLICT_DETECTION="conflict_detection"
readonly PHASE_LOCAL_TO_REMOTE="local_to_remote"
readonly PHASE_REMOTE_TO_LOCAL="remote_to_local"
readonly PHASE_VALIDATION="validation"
readonly PHASE_CLEANUP="cleanup"

# 进度文件
readonly PROGRESS_DIR=".claude/sync-status/progress"
readonly PROGRESS_FILE="$PROGRESS_DIR/current.json"
readonly PROGRESS_HISTORY="$PROGRESS_DIR/history.json"
readonly PROGRESS_LOG="$PROGRESS_DIR/progress.log"

# =============================================================================
# 进度跟踪初始化
# =============================================================================

# 初始化进度跟踪器
# Usage: init_progress_tracker
# Returns: 0 on success, 1 on failure
init_progress_tracker() {
    log_yunxiao_debug "初始化进度跟踪器"

    # 创建进度目录
    mkdir -p "$PROGRESS_DIR"

    # 初始化进度文件
    if [ ! -f "$PROGRESS_FILE" ]; then
        create_initial_progress_file
    fi

    # 初始化历史文件
    if [ ! -f "$PROGRESS_HISTORY" ]; then
        echo '{"sessions": []}' > "$PROGRESS_HISTORY"
    fi

    # 清理旧的进度日志
    : > "$PROGRESS_LOG"

    log_yunxiao_debug "进度跟踪器初始化完成"
    return 0
}

# 创建初始进度文件
# Usage: create_initial_progress_file
create_initial_progress_file() {
    local current_time
    current_time=$(get_current_timestamp)

    local session_id
    session_id="sync-$(date +%Y%m%d-%H%M%S)-$$"

    cat > "$PROGRESS_FILE" << EOF
{
  "session_id": "$session_id",
  "status": "$PROGRESS_STATUS_INITIALIZING",
  "start_time": "$current_time",
  "end_time": null,
  "current_phase": "$PHASE_INIT",
  "phases": {
    "$PHASE_INIT": {"status": "pending", "start_time": null, "end_time": null, "progress": 0},
    "$PHASE_LOCAL_COLLECTION": {"status": "pending", "start_time": null, "end_time": null, "progress": 0},
    "$PHASE_REMOTE_COLLECTION": {"status": "pending", "start_time": null, "end_time": null, "progress": 0},
    "$PHASE_CONFLICT_DETECTION": {"status": "pending", "start_time": null, "end_time": null, "progress": 0},
    "$PHASE_LOCAL_TO_REMOTE": {"status": "pending", "start_time": null, "end_time": null, "progress": 0},
    "$PHASE_REMOTE_TO_LOCAL": {"status": "pending", "start_time": null, "end_time": null, "progress": 0},
    "$PHASE_VALIDATION": {"status": "pending", "start_time": null, "end_time": null, "progress": 0},
    "$PHASE_CLEANUP": {"status": "pending", "start_time": null, "end_time": null, "progress": 0}
  },
  "statistics": {
    "total_epics": 0,
    "processed_epics": 0,
    "total_tasks": 0,
    "processed_tasks": 0,
    "created_items": 0,
    "updated_items": 0,
    "skipped_items": 0,
    "failed_items": 0,
    "conflicts_detected": 0,
    "conflicts_resolved": 0
  },
  "errors": [],
  "warnings": []
}
EOF

    log_yunxiao_debug "初始进度文件已创建"
}

# =============================================================================
# 进度状态管理
# =============================================================================

# 开始新阶段
# Usage: start_phase "phase_name" ["description"]
# Returns: 0 on success, 1 on failure
start_phase() {
    local phase="$1"
    local description="${2:-}"

    log_yunxiao_info "开始阶段: $phase"

    if [ -n "$description" ]; then
        log_progress "开始阶段: $phase - $description"
    else
        log_progress "开始阶段: $phase"
    fi

    local current_time
    current_time=$(get_current_timestamp)

    # 更新进度文件
    update_progress_file \
        ".current_phase = \"$phase\"" \
        ".phases[\"$phase\"].status = \"running\"" \
        ".phases[\"$phase\"].start_time = \"$current_time\"" \
        ".phases[\"$phase\"].progress = 0"

    return 0
}

# 完成阶段
# Usage: complete_phase "phase_name" ["success"]
# Returns: 0 on success, 1 on failure
complete_phase() {
    local phase="$1"
    local success="${2:-true}"

    local status
    if [ "$success" = "true" ]; then
        status="completed"
        log_yunxiao_success "阶段完成: $phase"
    else
        status="failed"
        log_yunxiao_error "阶段失败: $phase"
    fi

    log_progress "阶段$status: $phase"

    local current_time
    current_time=$(get_current_timestamp)

    # 更新进度文件
    update_progress_file \
        ".phases[\"$phase\"].status = \"$status\"" \
        ".phases[\"$phase\"].end_time = \"$current_time\"" \
        ".phases[\"$phase\"].progress = 100"

    return 0
}

# 更新阶段进度
# Usage: update_phase_progress "phase_name" "progress_percentage" ["message"]
update_phase_progress() {
    local phase="$1"
    local progress="$2"
    local message="${3:-}"

    # 验证进度百分比
    if ! [[ "$progress" =~ ^[0-9]+$ ]] || [ "$progress" -lt 0 ] || [ "$progress" -gt 100 ]; then
        log_yunxiao_error "无效的进度百分比: $progress"
        return 1
    fi

    if [ -n "$message" ]; then
        log_yunxiao_debug "$phase: $progress% - $message"
        log_progress "$phase: $progress% - $message"
    else
        log_yunxiao_debug "$phase: $progress%"
    fi

    # 更新进度文件
    update_progress_file ".phases[\"$phase\"].progress = $progress"

    return 0
}

# 设置总体同步状态
# Usage: set_sync_status "status" ["message"]
set_sync_status() {
    local status="$1"
    local message="${2:-}"

    log_yunxiao_info "同步状态: $status"

    if [ -n "$message" ]; then
        log_progress "状态变更: $status - $message"
    else
        log_progress "状态变更: $status"
    fi

    local updates=(".status = \"$status\"")

    # 如果是完成或失败状态，设置结束时间
    if [ "$status" = "$PROGRESS_STATUS_COMPLETED" ] || [ "$status" = "$PROGRESS_STATUS_FAILED" ]; then
        local current_time
        current_time=$(get_current_timestamp)
        updates+=(".end_time = \"$current_time\"")
    fi

    # 更新进度文件
    update_progress_file "${updates[@]}"

    return 0
}

# =============================================================================
# 统计数据管理
# =============================================================================

# 设置总项目数
# Usage: set_total_items "epics_count" "tasks_count"
set_total_items() {
    local epics_count="$1"
    local tasks_count="$2"

    log_yunxiao_info "设置总项目数: Epic $epics_count, 任务 $tasks_count"

    update_progress_file \
        ".statistics.total_epics = $epics_count" \
        ".statistics.total_tasks = $tasks_count"
}

# 增加处理计数
# Usage: increment_processed "type" ["count"]
increment_processed() {
    local type="$1"
    local count="${2:-1}"

    case "$type" in
        "epic"|"epics")
            update_progress_file ".statistics.processed_epics += $count"
            ;;
        "task"|"tasks")
            update_progress_file ".statistics.processed_tasks += $count"
            ;;
        *)
            log_yunxiao_error "未知的项目类型: $type"
            return 1
            ;;
    esac

    log_yunxiao_debug "增加处理计数: $type +$count"
}

# 增加操作计数
# Usage: increment_operation "operation" ["count"]
increment_operation() {
    local operation="$1"
    local count="${2:-1}"

    case "$operation" in
        "created")
            update_progress_file ".statistics.created_items += $count"
            ;;
        "updated")
            update_progress_file ".statistics.updated_items += $count"
            ;;
        "skipped")
            update_progress_file ".statistics.skipped_items += $count"
            ;;
        "failed")
            update_progress_file ".statistics.failed_items += $count"
            ;;
        "conflicts_detected")
            update_progress_file ".statistics.conflicts_detected += $count"
            ;;
        "conflicts_resolved")
            update_progress_file ".statistics.conflicts_resolved += $count"
            ;;
        *)
            log_yunxiao_error "未知的操作类型: $operation"
            return 1
            ;;
    esac

    log_yunxiao_debug "增加操作计数: $operation +$count"
}

# =============================================================================
# 错误和警告管理
# =============================================================================

# 添加错误
# Usage: add_error "error_message" ["context"]
add_error() {
    local error_message="$1"
    local context="${2:-}"

    local current_time
    current_time=$(get_current_timestamp)

    local error_entry
    error_entry=$(jq -n \
        --arg message "$error_message" \
        --arg context "$context" \
        --arg timestamp "$current_time" \
        '{
            message: $message,
            context: $context,
            timestamp: $timestamp
        }')

    # 添加到进度文件
    local temp_file
    temp_file=$(mktemp)

    jq --argjson error "$error_entry" '.errors += [$error]' "$PROGRESS_FILE" > "$temp_file"
    mv "$temp_file" "$PROGRESS_FILE"

    log_yunxiao_error "$error_message"
    log_progress "错误: $error_message"
}

# 添加警告
# Usage: add_warning "warning_message" ["context"]
add_warning() {
    local warning_message="$1"
    local context="${2:-}"

    local current_time
    current_time=$(get_current_timestamp)

    local warning_entry
    warning_entry=$(jq -n \
        --arg message "$warning_message" \
        --arg context "$context" \
        --arg timestamp "$current_time" \
        '{
            message: $message,
            context: $context,
            timestamp: $timestamp
        }')

    # 添加到进度文件
    local temp_file
    temp_file=$(mktemp)

    jq --argjson warning "$warning_entry" '.warnings += [$warning]' "$PROGRESS_FILE" > "$temp_file"
    mv "$temp_file" "$PROGRESS_FILE"

    log_yunxiao_warning "$warning_message"
    log_progress "警告: $warning_message"
}

# =============================================================================
# 进度查询和显示
# =============================================================================

# 获取当前进度
# Usage: get_current_progress
# Returns: JSON string with current progress
get_current_progress() {
    if [ -f "$PROGRESS_FILE" ]; then
        cat "$PROGRESS_FILE"
    else
        echo "{}"
    fi
}

# 显示进度摘要
# Usage: show_progress_summary
show_progress_summary() {
    if [ ! -f "$PROGRESS_FILE" ]; then
        log_yunxiao_info "没有进度信息"
        return 1
    fi

    local progress_data
    progress_data=$(cat "$PROGRESS_FILE")

    local session_id status current_phase
    session_id=$(echo "$progress_data" | jq -r '.session_id')
    status=$(echo "$progress_data" | jq -r '.status')
    current_phase=$(echo "$progress_data" | jq -r '.current_phase')

    echo "=== 同步进度摘要 ==="
    echo "会话ID: $session_id"
    echo "状态: $status"
    echo "当前阶段: $current_phase"

    # 显示统计信息
    echo ""
    echo "=== 统计信息 ==="
    echo "$progress_data" | jq -r '
        .statistics |
        "Epic: \(.processed_epics)/\(.total_epics)",
        "任务: \(.processed_tasks)/\(.total_tasks)",
        "创建: \(.created_items)",
        "更新: \(.updated_items)",
        "跳过: \(.skipped_items)",
        "失败: \(.failed_items)",
        "冲突检测: \(.conflicts_detected)",
        "冲突解决: \(.conflicts_resolved)"
    '

    # 显示阶段进度
    echo ""
    echo "=== 阶段进度 ==="
    echo "$progress_data" | jq -r '
        .phases | to_entries[] |
        "\(.key): \(.value.status) (\(.value.progress)%)"
    '

    # 显示错误和警告数量
    local error_count warning_count
    error_count=$(echo "$progress_data" | jq '.errors | length')
    warning_count=$(echo "$progress_data" | jq '.warnings | length')

    if [ "$error_count" -gt 0 ] || [ "$warning_count" -gt 0 ]; then
        echo ""
        echo "=== 问题报告 ==="
        echo "错误: $error_count"
        echo "警告: $warning_count"
    fi

    echo "=================="
}

# 显示详细进度
# Usage: show_detailed_progress
show_detailed_progress() {
    if [ ! -f "$PROGRESS_FILE" ]; then
        log_yunxiao_info "没有进度信息"
        return 1
    fi

    local progress_data
    progress_data=$(cat "$PROGRESS_FILE")

    # 显示基本信息
    show_progress_summary

    # 显示错误详情
    local error_count
    error_count=$(echo "$progress_data" | jq '.errors | length')

    if [ "$error_count" -gt 0 ]; then
        echo ""
        echo "=== 错误详情 ==="
        echo "$progress_data" | jq -r '.errors[] | "[\(.timestamp)] \(.message)"'
    fi

    # 显示警告详情
    local warning_count
    warning_count=$(echo "$progress_data" | jq '.warnings | length')

    if [ "$warning_count" -gt 0 ]; then
        echo ""
        echo "=== 警告详情 ==="
        echo "$progress_data" | jq -r '.warnings[] | "[\(.timestamp)] \(.message)"'
    fi

    # 显示阶段时间信息
    echo ""
    echo "=== 阶段时间 ==="
    echo "$progress_data" | jq -r '
        .phases | to_entries[] |
        select(.value.start_time != null) |
        "\(.key): \(.value.start_time) - \(.value.end_time // "进行中")"
    '
}

# 实时显示进度
# Usage: watch_progress ["interval_seconds"]
watch_progress() {
    local interval="${1:-5}"

    log_yunxiao_info "开始实时监控进度 (每${interval}秒更新)"

    while true; do
        clear
        show_progress_summary

        # 检查是否完成
        if [ -f "$PROGRESS_FILE" ]; then
            local status
            status=$(jq -r '.status' "$PROGRESS_FILE")

            if [ "$status" = "$PROGRESS_STATUS_COMPLETED" ] || [ "$status" = "$PROGRESS_STATUS_FAILED" ]; then
                echo ""
                log_yunxiao_info "同步已完成，状态: $status"
                break
            fi
        fi

        sleep "$interval"
    done
}

# =============================================================================
# 进度历史管理
# =============================================================================

# 保存当前会话到历史
# Usage: save_session_to_history
save_session_to_history() {
    if [ ! -f "$PROGRESS_FILE" ]; then
        log_yunxiao_warning "没有当前进度信息可保存"
        return 1
    fi

    local progress_data
    progress_data=$(cat "$PROGRESS_FILE")

    # 添加到历史文件
    local temp_file
    temp_file=$(mktemp)

    jq --argjson session "$progress_data" '.sessions += [$session]' "$PROGRESS_HISTORY" > "$temp_file"
    mv "$temp_file" "$PROGRESS_HISTORY"

    local session_id
    session_id=$(echo "$progress_data" | jq -r '.session_id')

    log_yunxiao_debug "会话已保存到历史: $session_id"
}

# 清理进度跟踪器
# Usage: cleanup_progress_tracker
cleanup_progress_tracker() {
    log_yunxiao_debug "清理进度跟踪器"

    # 保存当前会话到历史
    save_session_to_history

    # 清理当前进度文件
    if [ -f "$PROGRESS_FILE" ]; then
        rm -f "$PROGRESS_FILE"
    fi

    # 清理临时文件
    find "$PROGRESS_DIR" -name "*.tmp" -type f -delete 2>/dev/null || true

    log_yunxiao_debug "进度跟踪器清理完成"
}

# 显示历史会话
# Usage: show_session_history ["limit"]
show_session_history() {
    local limit="${1:-10}"

    if [ ! -f "$PROGRESS_HISTORY" ]; then
        log_yunxiao_info "没有历史记录"
        return 1
    fi

    echo "=== 同步历史 (最近 $limit 次) ==="

    jq -r --arg limit "$limit" '
        .sessions |
        sort_by(.start_time) |
        reverse |
        .[:($limit | tonumber)] |
        .[] |
        "[\(.start_time)] \(.session_id): \(.status) (\(.statistics.processed_epics) epics, \(.statistics.processed_tasks) tasks)"
    ' "$PROGRESS_HISTORY"

    echo "========================="
}

# =============================================================================
# 工具函数
# =============================================================================

# 更新进度文件
# Usage: update_progress_file "jq_expression1" ["jq_expression2" ...]
update_progress_file() {
    local expressions=("$@")

    if [ ! -f "$PROGRESS_FILE" ]; then
        log_yunxiao_error "进度文件不存在"
        return 1
    fi

    local temp_file
    temp_file=$(mktemp)

    # 构建jq表达式
    local jq_expression=""
    for expr in "${expressions[@]}"; do
        if [ -n "$jq_expression" ]; then
            jq_expression="$jq_expression | $expr"
        else
            jq_expression="$expr"
        fi
    done

    # 应用更新
    jq "$jq_expression" "$PROGRESS_FILE" > "$temp_file"

    if [ $? -eq 0 ]; then
        mv "$temp_file" "$PROGRESS_FILE"
    else
        rm -f "$temp_file"
        log_yunxiao_error "更新进度文件失败"
        return 1
    fi
}

# 记录进度日志
# Usage: log_progress "message"
log_progress() {
    local message="$1"
    local timestamp
    timestamp=$(get_current_timestamp)

    echo "[$timestamp] $message" >> "$PROGRESS_LOG"
}

# 获取当前时间戳
# Usage: get_current_timestamp
get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 计算完成百分比
# Usage: calculate_completion_percentage "completed" "total"
calculate_completion_percentage() {
    local completed="$1"
    local total="$2"

    if [ "$total" -eq 0 ]; then
        echo "0"
        return 0
    fi

    local percentage=$((completed * 100 / total))
    echo "$percentage"
}

# 估算剩余时间
# Usage: estimate_remaining_time "completed" "total" "elapsed_seconds"
estimate_remaining_time() {
    local completed="$1"
    local total="$2"
    local elapsed="$3"

    if [ "$completed" -eq 0 ] || [ "$total" -eq 0 ]; then
        echo "未知"
        return 0
    fi

    local remaining=$((total - completed))
    local avg_time_per_item=$((elapsed / completed))
    local estimated_remaining=$((remaining * avg_time_per_item))

    # 转换为人类可读的时间格式
    if [ $estimated_remaining -lt 60 ]; then
        echo "${estimated_remaining}秒"
    elif [ $estimated_remaining -lt 3600 ]; then
        local minutes=$((estimated_remaining / 60))
        echo "${minutes}分钟"
    else
        local hours=$((estimated_remaining / 3600))
        local minutes=$(((estimated_remaining % 3600) / 60))
        echo "${hours}小时${minutes}分钟"
    fi
}

# =============================================================================
# 主程序入口（用于测试）
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # 如果脚本被直接执行，提供测试功能
    case "${1:-help}" in
        "init")
            init_progress_tracker
            ;;
        "status"|"summary")
            show_progress_summary
            ;;
        "detail"|"detailed")
            show_detailed_progress
            ;;
        "watch")
            watch_progress "${2:-5}"
            ;;
        "history")
            show_session_history "${2:-10}"
            ;;
        "start")
            start_phase "$2" "$3"
            ;;
        "complete")
            complete_phase "$2" "${3:-true}"
            ;;
        "progress")
            update_phase_progress "$2" "$3" "$4"
            ;;
        "set-status")
            set_sync_status "$2" "$3"
            ;;
        "cleanup")
            cleanup_progress_tracker
            ;;
        "help"|*)
            cat << EOF
进度跟踪器工具

用法: $0 <命令> [参数...]

命令:
  init                     初始化进度跟踪器
  status                   显示进度摘要
  detail                   显示详细进度
  watch [interval]         实时监控进度
  history [limit]          显示历史记录
  start <phase> [desc]     开始新阶段
  complete <phase> [success] 完成阶段
  progress <phase> <pct> [msg] 更新阶段进度
  set-status <status> [msg] 设置同步状态
  cleanup                  清理进度跟踪器
  help                     显示此帮助信息

示例:
  $0 init                  初始化跟踪器
  $0 status                查看当前进度
  $0 watch 3               每3秒更新进度
  $0 start local_collection "收集本地文件"
  $0 progress local_collection 50 "已完成一半"
  $0 complete local_collection true
EOF
            ;;
    esac
fi