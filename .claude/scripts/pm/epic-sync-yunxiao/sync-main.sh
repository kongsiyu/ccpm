#!/bin/bash

# Epic-Yunxiao Sync Main Controller
# 主同步控制器，实现ccpm本地Epic与阿里云云效工作项之间的双向同步

# 获取脚本目录并引入依赖库
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$LIB_DIR/frontmatter.sh"
source "$LIB_DIR/datetime.sh"

# 引入同步相关的脚本
source "$SCRIPT_DIR/mapping-manager.sh"
source "$SCRIPT_DIR/conflict-resolver.sh"
source "$SCRIPT_DIR/local-to-remote.sh"
source "$SCRIPT_DIR/remote-to-local.sh"
source "$SCRIPT_DIR/progress-tracker.sh"
source "$SCRIPT_DIR/sync-validator.sh"

# =============================================================================
# 常量定义
# =============================================================================

# 同步模式
readonly SYNC_MODE_INCREMENTAL="incremental"
readonly SYNC_MODE_FULL="full"
readonly SYNC_MODE_DRY_RUN="dry-run"

# 同步方向
readonly SYNC_DIRECTION_PUSH="push"
readonly SYNC_DIRECTION_PULL="pull"
readonly SYNC_DIRECTION_BIDIRECTIONAL="bidirectional"

# 同步状态文件
readonly SYNC_STATUS_DIR=".claude/sync-status"
readonly SYNC_LOCK_FILE="$SYNC_STATUS_DIR/yunxiao-sync.lock"
readonly SYNC_LOG_FILE="$SYNC_STATUS_DIR/yunxiao-sync.log"

# =============================================================================
# 核心同步函数
# =============================================================================

# 主同步函数
# Usage: epic_sync_yunxiao [sync_mode] [direction] [epic_name]
# Returns: 0 on success, 1 on failure
epic_sync_yunxiao() {
    local sync_mode="${1:-$SYNC_MODE_INCREMENTAL}"
    local direction="${2:-$SYNC_DIRECTION_BIDIRECTIONAL}"
    local epic_name="$3"

    log_yunxiao_info "开始Epic-云效同步: 模式=$sync_mode, 方向=$direction, Epic=$epic_name"

    # 初始化同步环境
    init_sync_environment || return 1

    # 获取同步锁
    acquire_sync_lock || return 1

    # 设置清理陷阱
    trap cleanup_sync_environment EXIT

    local sync_result=0

    # 执行同步流程
    {
        # 1. 预检查和验证
        validate_sync_prerequisites "$epic_name" || { sync_result=1; return 1; }

        # 2. 加载映射配置
        load_mapping_configuration || { sync_result=1; return 1; }

        # 3. 数据收集
        collect_local_changes "$epic_name" || { sync_result=1; return 1; }
        collect_remote_changes "$epic_name" || { sync_result=1; return 1; }

        # 4. 冲突检测
        detect_conflicts || { sync_result=1; return 1; }

        # 5. 同步执行
        case "$direction" in
            "$SYNC_DIRECTION_PUSH")
                sync_local_to_remote "$sync_mode" "$epic_name" || sync_result=1
                ;;
            "$SYNC_DIRECTION_PULL")
                sync_remote_to_local "$sync_mode" "$epic_name" || sync_result=1
                ;;
            "$SYNC_DIRECTION_BIDIRECTIONAL")
                sync_bidirectional "$sync_mode" "$epic_name" || sync_result=1
                ;;
            *)
                log_yunxiao_error "不支持的同步方向: $direction"
                sync_result=1
                ;;
        esac

        # 6. 验证和报告
        if [ $sync_result -eq 0 ]; then
            validate_sync_results "$epic_name" || sync_result=1
            generate_sync_report "$sync_mode" "$direction" "$epic_name"
        fi

    } | tee -a "$SYNC_LOG_FILE"

    # 释放锁并清理
    release_sync_lock

    if [ $sync_result -eq 0 ]; then
        log_yunxiao_success "Epic-云效同步完成"
    else
        log_yunxiao_error "Epic-云效同步失败"
    fi

    return $sync_result
}

# 双向同步实现
# Usage: sync_bidirectional "sync_mode" "epic_name"
sync_bidirectional() {
    local sync_mode="$1"
    local epic_name="$2"

    log_yunxiao_info "执行双向同步"

    # 首先解决冲突
    if has_unresolved_conflicts; then
        log_yunxiao_warning "检测到未解决的冲突，需要先解决冲突"
        resolve_all_conflicts || return 1
    fi

    # 推送本地变更到远程
    log_yunxiao_info "第一阶段：推送本地变更到云效"
    sync_local_to_remote "$sync_mode" "$epic_name" || return 1

    # 拉取远程变更到本地
    log_yunxiao_info "第二阶段：拉取云效变更到本地"
    sync_remote_to_local "$sync_mode" "$epic_name" || return 1

    # 更新映射关系
    update_mapping_after_sync "$epic_name" || return 1

    log_yunxiao_success "双向同步完成"
    return 0
}

# =============================================================================
# 环境初始化和清理函数
# =============================================================================

# 初始化同步环境
# Usage: init_sync_environment
init_sync_environment() {
    log_yunxiao_debug "初始化同步环境"

    # 创建必要的目录
    mkdir -p "$SYNC_STATUS_DIR"

    # 检查依赖
    require_commands "jq" "date"

    # 验证云效配置
    validate_yunxiao_config || return 1

    # 验证MCP服务
    validate_yunxiao_mcp_service || return 1

    # 初始化进度跟踪
    init_progress_tracker || return 1

    # 初始化映射管理器
    init_mapping_manager || return 1

    log_yunxiao_debug "同步环境初始化完成"
    return 0
}

# 清理同步环境
# Usage: cleanup_sync_environment
cleanup_sync_environment() {
    log_yunxiao_debug "清理同步环境"

    # 清理临时文件
    cleanup_temp_files

    # 释放锁（如果还持有）
    release_sync_lock 2>/dev/null || true

    # 关闭进度跟踪
    cleanup_progress_tracker 2>/dev/null || true

    log_yunxiao_debug "同步环境清理完成"
}

# =============================================================================
# 同步锁管理
# =============================================================================

# 获取同步锁
# Usage: acquire_sync_lock
acquire_sync_lock() {
    local max_wait=300  # 最大等待5分钟
    local wait_time=0

    while [ $wait_time -lt $max_wait ]; do
        if [ ! -f "$SYNC_LOCK_FILE" ]; then
            # 创建锁文件
            echo "$$:$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$SYNC_LOCK_FILE"
            log_yunxiao_debug "获取同步锁成功"
            return 0
        fi

        # 检查锁文件是否过期（超过1小时）
        if [ -f "$SYNC_LOCK_FILE" ]; then
            local lock_time
            lock_time=$(cut -d: -f2- "$SYNC_LOCK_FILE" 2>/dev/null || echo "")

            if [ -n "$lock_time" ]; then
                local lock_timestamp
                lock_timestamp=$(date -d "$lock_time" +%s 2>/dev/null || echo "0")
                local current_timestamp
                current_timestamp=$(date +%s)
                local age=$((current_timestamp - lock_timestamp))

                # 如果锁文件超过1小时，认为是失效锁
                if [ $age -gt 3600 ]; then
                    log_yunxiao_warning "检测到失效的同步锁，将清除"
                    rm -f "$SYNC_LOCK_FILE"
                    continue
                fi
            fi
        fi

        log_yunxiao_info "等待同步锁释放... ($wait_time/$max_wait 秒)"
        sleep 5
        wait_time=$((wait_time + 5))
    done

    log_yunxiao_error "无法获取同步锁，请检查是否有其他同步进程在运行"
    return 1
}

# 释放同步锁
# Usage: release_sync_lock
release_sync_lock() {
    if [ -f "$SYNC_LOCK_FILE" ]; then
        rm -f "$SYNC_LOCK_FILE"
        log_yunxiao_debug "释放同步锁"
    fi
}

# =============================================================================
# 数据收集函数
# =============================================================================

# 收集本地变更
# Usage: collect_local_changes "epic_name"
collect_local_changes() {
    local epic_name="$1"

    log_yunxiao_info "收集本地Epic变更"

    # 如果指定了epic名称，只收集该epic的变更
    if [ -n "$epic_name" ]; then
        collect_epic_changes "$epic_name"
    else
        # 收集所有epic的变更
        find .claude/epics -name "*.md" -type f | while read -r epic_file; do
            local dir_name
            dir_name=$(basename "$(dirname "$epic_file")")
            if [ "$(basename "$epic_file")" = "epic.md" ]; then
                collect_epic_changes "$dir_name"
            fi
        done
    fi

    return 0
}

# 收集远程变更
# Usage: collect_remote_changes "epic_name"
collect_remote_changes() {
    local epic_name="$1"

    log_yunxiao_info "收集云效工作项变更"

    # 获取项目下的所有工作项
    if [ -n "$epic_name" ]; then
        # 只获取与指定epic关联的工作项
        collect_epic_workitems "$epic_name"
    else
        # 获取所有工作项
        yunxiao_call_mcp "list_work_items" "{\"project_id\": \"$(get_project_id)\"}"
    fi

    return 0
}

# 收集单个Epic的变更
# Usage: collect_epic_changes "epic_name"
collect_epic_changes() {
    local epic_name="$1"
    local epic_dir=".claude/epics/$epic_name"
    local epic_file="$epic_dir/epic.md"

    if [ ! -f "$epic_file" ]; then
        log_yunxiao_warning "Epic文件不存在: $epic_file"
        return 1
    fi

    log_yunxiao_debug "收集Epic变更: $epic_name"

    # 获取Epic的基本信息
    local epic_status epic_updated epic_yunxiao_id
    epic_status=$(get_frontmatter_field "$epic_file" "status" "open")
    epic_updated=$(get_frontmatter_field "$epic_file" "updated")
    epic_yunxiao_id=$(get_frontmatter_field "$epic_file" "yunxiao_id")

    # 记录变更信息
    record_local_change "epic" "$epic_name" "$epic_status" "$epic_updated" "$epic_yunxiao_id"

    # 收集Epic下的任务变更
    find "$epic_dir" -name "*.md" -type f ! -name "epic.md" | while read -r task_file; do
        collect_task_changes "$epic_name" "$task_file"
    done

    return 0
}

# 收集任务变更
# Usage: collect_task_changes "epic_name" "task_file"
collect_task_changes() {
    local epic_name="$1"
    local task_file="$2"
    local task_id
    task_id=$(basename "$task_file" .md)

    log_yunxiao_debug "收集任务变更: $epic_name/$task_id"

    # 获取任务的基本信息
    local task_status task_updated task_yunxiao_id
    task_status=$(get_frontmatter_field "$task_file" "status" "open")
    task_updated=$(get_frontmatter_field "$task_file" "updated")
    task_yunxiao_id=$(get_frontmatter_field "$task_file" "yunxiao_id")

    # 记录变更信息
    record_local_change "task" "$epic_name/$task_id" "$task_status" "$task_updated" "$task_yunxiao_id"

    return 0
}

# =============================================================================
# 验证函数
# =============================================================================

# 验证同步前置条件
# Usage: validate_sync_prerequisites ["epic_name"]
validate_sync_prerequisites() {
    local epic_name="$1"

    log_yunxiao_info "验证同步前置条件"

    # 检查是否在有效的项目目录
    if [ ! -f ".ccpm-config.yaml" ]; then
        log_yunxiao_error "当前目录不是有效的ccpm项目"
        return 1
    fi

    # 验证云效配置
    validate_yunxiao_config || return 1

    # 如果指定了epic名称，验证epic是否存在
    if [ -n "$epic_name" ]; then
        if [ ! -d ".claude/epics/$epic_name" ]; then
            log_yunxiao_error "Epic不存在: $epic_name"
            return 1
        fi

        if [ ! -f ".claude/epics/$epic_name/epic.md" ]; then
            log_yunxiao_error "Epic文件不存在: .claude/epics/$epic_name/epic.md"
            return 1
        fi
    fi

    # 检查同步权限
    check_sync_permissions || return 1

    log_yunxiao_success "前置条件验证通过"
    return 0
}

# 检查同步权限
# Usage: check_sync_permissions
check_sync_permissions() {
    # 检查是否有读写权限
    if [ ! -w ".claude/epics" ]; then
        log_yunxiao_error "没有Epic目录的写权限"
        return 1
    fi

    # 检查是否能创建状态目录
    if ! mkdir -p "$SYNC_STATUS_DIR" 2>/dev/null; then
        log_yunxiao_error "无法创建同步状态目录"
        return 1
    fi

    return 0
}

# =============================================================================
# 工具函数
# =============================================================================

# 清理临时文件
# Usage: cleanup_temp_files
cleanup_temp_files() {
    local temp_pattern="/tmp/epic-sync-yunxiao-$$*"
    rm -f $temp_pattern 2>/dev/null || true
}

# 记录本地变更
# Usage: record_local_change "type" "name" "status" "updated" "yunxiao_id"
record_local_change() {
    local type="$1"
    local name="$2"
    local status="$3"
    local updated="$4"
    local yunxiao_id="$5"

    # 这里应该记录到某个变更跟踪文件
    # 为了简化，目前只记录到调试日志
    log_yunxiao_debug "记录变更: $type $name status=$status updated=$updated yunxiao_id=$yunxiao_id"
}

# 收集与Epic关联的云效工作项
# Usage: collect_epic_workitems "epic_name"
collect_epic_workitems() {
    local epic_name="$1"

    # 查找映射关系，获取与该epic相关的工作项
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ -f "$mapping_file" ]; then
        # 从映射文件中查找相关工作项
        jq -r ".mappings | to_entries[] | select(.value.epic_name == \"$epic_name\") | .value.yunxiao_workitem_id" "$mapping_file" 2>/dev/null | while read -r workitem_id; do
            if [ -n "$workitem_id" ] && [ "$workitem_id" != "null" ]; then
                yunxiao_call_mcp "get_work_item" "$workitem_id"
            fi
        done
    fi
}

# =============================================================================
# 主程序入口
# =============================================================================

# 如果脚本被直接执行，运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # 解析命令行参数
    SYNC_MODE="${1:-$SYNC_MODE_INCREMENTAL}"
    SYNC_DIRECTION="${2:-$SYNC_DIRECTION_BIDIRECTIONAL}"
    EPIC_NAME="$3"

    # 显示使用说明
    if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        cat << EOF
用法: $0 [同步模式] [同步方向] [Epic名称]

同步模式:
  incremental  增量同步（默认）
  full         全量同步
  dry-run      干运行模式

同步方向:
  push            推送本地到云效
  pull            拉取云效到本地
  bidirectional   双向同步（默认）

示例:
  $0                                    # 双向增量同步所有Epic
  $0 full bidirectional                # 双向全量同步所有Epic
  $0 incremental push my-epic           # 增量推送指定Epic到云效
  $0 dry-run pull                       # 干运行模式拉取云效数据
EOF
        exit 0
    fi

    # 执行同步
    epic_sync_yunxiao "$SYNC_MODE" "$SYNC_DIRECTION" "$EPIC_NAME"
fi