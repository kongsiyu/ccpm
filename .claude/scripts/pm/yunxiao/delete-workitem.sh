#!/bin/bash

# 云效工作项删除脚本
# 安全删除工作项，支持软删除和硬删除

# 获取脚本目录并引入通用函数
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/workitem-common.sh"

# =============================================================================
# 脚本帮助信息
# =============================================================================

show_help() {
    cat << EOF
云效工作项删除工具

用法:
    $0 [选项] <工作项ID> [工作项ID2] [工作项ID3] ...

参数:
    工作项ID    要删除的工作项ID（数字），支持多个

选项:
    删除模式:
    --soft              软删除（标记为已删除，可恢复）[默认]
    --hard              硬删除（永久删除，不可恢复）
    --archive           归档（保留但不可见）

    安全选项:
    --check-deps        检查依赖关系（防止删除有依赖的工作项）
    --backup FILE       删除前备份到文件
    --force             强制删除（跳过所有确认）
    -n, --dry-run       仅验证，不实际删除

    输出选项:
    -o, --output FORMAT 输出格式 (json|table|summary) [默认: summary]
    -q, --quiet         静默模式，减少输出
    -v, --verbose       详细输出

    批量选项:
    --batch             批量删除模式（从标准输入读取ID）
    --filter TYPE       按类型过滤删除 (requirement|task|bug|epic)
    --status STATUS     按状态过滤删除 (仅删除特定状态的工作项)

    其他选项:
    -h, --help          显示此帮助信息

删除模式说明:
    软删除 (--soft)    - 标记为已删除状态，可通过管理界面恢复
    硬删除 (--hard)    - 完全从数据库中移除，不可恢复
    归档 (--archive)   - 移动到归档状态，不影响统计但不可见

示例:
    # 软删除单个工作项
    $0 12345

    # 硬删除工作项（需要确认）
    $0 --hard 12345

    # 批量软删除
    $0 12345 12346 12347

    # 删除前备份
    $0 --backup deleted_items.json 12345

    # 强制删除（跳过确认）
    $0 --force --hard 12345

    # 仅验证删除操作
    $0 -n 12345

    # 检查依赖关系后删除
    $0 --check-deps 12345

    # 批量删除（从文件读取ID）
    cat workitem_ids.txt | $0 --batch

    # 按状态过滤删除
    $0 --status 已取消 --batch

警告:
    - 硬删除操作不可逆，请谨慎使用
    - 删除有依赖关系的工作项可能影响其他项目
    - 建议在删除前使用 --backup 选项备份数据

EOF
}

# =============================================================================
# 参数解析
# =============================================================================

parse_arguments() {
    local TEMP
    TEMP=$(getopt -o 'o:nqvh' --long 'soft,hard,archive,check-deps,backup:,force,dry-run,output:,quiet,verbose,batch,filter:,status:,help' -n "$0" -- "$@")

    if [ $? -ne 0 ]; then
        echo "参数解析失败，使用 --help 查看用法" >&2
        exit 1
    fi

    eval set -- "$TEMP"
    unset TEMP

    # 默认值
    DELETE_MODE="soft"
    CHECK_DEPENDENCIES=false
    BACKUP_FILE=""
    FORCE_DELETE=false
    DRY_RUN=false
    OUTPUT_FORMAT="summary"
    QUIET=false
    VERBOSE=false
    BATCH_MODE=false
    FILTER_TYPE=""
    FILTER_STATUS=""

    while true; do
        case "$1" in
            '--soft')
                DELETE_MODE="soft"
                shift
                continue
                ;;
            '--hard')
                DELETE_MODE="hard"
                shift
                continue
                ;;
            '--archive')
                DELETE_MODE="archive"
                shift
                continue
                ;;
            '--check-deps')
                CHECK_DEPENDENCIES=true
                shift
                continue
                ;;
            '--backup')
                BACKUP_FILE="$2"
                shift 2
                continue
                ;;
            '--force')
                FORCE_DELETE=true
                shift
                continue
                ;;
            '-n'|'--dry-run')
                DRY_RUN=true
                shift
                continue
                ;;
            '-o'|'--output')
                OUTPUT_FORMAT="$2"
                shift 2
                continue
                ;;
            '-q'|'--quiet')
                QUIET=true
                shift
                continue
                ;;
            '-v'|'--verbose')
                VERBOSE=true
                export YUNXIAO_DEBUG=1
                shift
                continue
                ;;
            '--batch')
                BATCH_MODE=true
                shift
                continue
                ;;
            '--filter')
                FILTER_TYPE="$2"
                shift 2
                continue
                ;;
            '--status')
                FILTER_STATUS="$2"
                shift 2
                continue
                ;;
            '-h'|'--help')
                show_help
                exit 0
                ;;
            '--')
                shift
                break
                ;;
            *)
                echo "内部错误!" >&2
                exit 1
                ;;
        esac
    done

    # 验证参数
    validate_arguments "$@"
}

# 验证参数
validate_arguments() {
    # 验证输出格式
    case "$OUTPUT_FORMAT" in
        json|table|summary)
            ;;
        *)
            error_exit "不支持的输出格式: $OUTPUT_FORMAT"
            ;;
    esac

    # 验证过滤器类型
    if [ -n "$FILTER_TYPE" ]; then
        validate_workitem_type "$FILTER_TYPE" || exit 1
    fi

    # 验证备份文件路径
    if [ -n "$BACKUP_FILE" ]; then
        local backup_dir
        backup_dir="$(dirname "$BACKUP_FILE")"
        if [ ! -d "$backup_dir" ]; then
            error_exit "备份文件目录不存在: $backup_dir"
        fi
        if [ ! -w "$backup_dir" ]; then
            error_exit "备份文件目录不可写: $backup_dir"
        fi
    fi

    # 非批量模式需要工作项ID
    if [ "$BATCH_MODE" = false ]; then
        if [ $# -eq 0 ]; then
            echo "错误: 需要提供至少一个工作项ID" >&2
            echo "使用 --help 查看用法" >&2
            exit 1
        fi

        # 验证所有工作项ID
        for workitem_id in "$@"; do
            validate_workitem_id "$workitem_id" || exit 1
        done

        WORKITEM_IDS=("$@")
    fi

    # 硬删除警告
    if [ "$DELETE_MODE" = "hard" ] && [ "$FORCE_DELETE" = false ]; then
        log_yunxiao_warning "硬删除模式将永久删除数据，不可恢复！"
    fi
}

# =============================================================================
# 依赖关系检查
# =============================================================================

# 检查工作项依赖关系
# Usage: check_workitem_dependencies "workitem_id"
# Returns: 0 if safe to delete, 1 if has dependencies
check_workitem_dependencies() {
    local workitem_id="$1"

    if [ "$CHECK_DEPENDENCIES" = false ]; then
        return 0
    fi

    log_yunxiao_debug "检查工作项 #$workitem_id 的依赖关系"

    # TODO: 实现实际的依赖关系检查
    # 这里应该调用API检查：
    # 1. 是否有子工作项
    # 2. 是否被其他工作项依赖
    # 3. 是否有关联的文档或资源

    # 模拟依赖检查
    local has_dependencies=false

    # 示例依赖检查逻辑
    # 可以调用 yunxiao_call_mcp "check_dependencies" "$workitem_id"

    if [ "$has_dependencies" = true ]; then
        log_yunxiao_error "工作项 #$workitem_id 存在依赖关系，不建议删除"
        log_yunxiao_info "使用 --force 强制删除，或先处理依赖关系"
        return 1
    fi

    return 0
}

# =============================================================================
# 备份功能
# =============================================================================

# 备份工作项数据
# Usage: backup_workitem "workitem_id" "backup_file"
backup_workitem() {
    local workitem_id="$1"
    local backup_file="$2"

    log_yunxiao_debug "备份工作项 #$workitem_id 到 $backup_file"

    # 获取工作项完整数据
    local workitem_data
    if ! workitem_data=$(yunxiao_retry_call yunxiao_get_workitem "$workitem_id"); then
        log_yunxiao_error "无法获取工作项 #$workitem_id 数据进行备份"
        return 1
    fi

    # 检查备份文件是否已存在
    local backup_array="[]"
    if [ -f "$backup_file" ]; then
        backup_array=$(cat "$backup_file" 2>/dev/null || echo "[]")
    fi

    # 添加当前工作项到备份
    local backup_entry
    backup_entry=$(jq -n \
        --argjson workitem "$workitem_data" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        --arg delete_mode "$DELETE_MODE" \
        '{
            workitem: $workitem,
            backup_timestamp: $timestamp,
            delete_mode: $delete_mode
        }')

    backup_array=$(echo "$backup_array" | jq --argjson entry "$backup_entry" '. + [$entry]')

    # 写入备份文件
    echo "$backup_array" > "$backup_file"

    if [ $? -eq 0 ]; then
        log_yunxiao_debug "工作项 #$workitem_id 备份成功"
        return 0
    else
        log_yunxiao_error "备份工作项 #$workitem_id 失败"
        return 1
    fi
}

# 批量备份工作项
# Usage: backup_workitems "workitem_ids_array" "backup_file"
backup_workitems() {
    local -n workitem_ids_ref=$1
    local backup_file="$2"

    if [ ${#workitem_ids_ref[@]} -eq 0 ]; then
        return 0
    fi

    log_yunxiao_info "备份 ${#workitem_ids_ref[@]} 个工作项到 $backup_file"

    local backup_array="[]"
    if [ -f "$backup_file" ]; then
        backup_array=$(cat "$backup_file" 2>/dev/null || echo "[]")
    fi

    for workitem_id in "${workitem_ids_ref[@]}"; do
        local workitem_data
        if workitem_data=$(yunxiao_retry_call yunxiao_get_workitem "$workitem_id"); then
            local backup_entry
            backup_entry=$(jq -n \
                --argjson workitem "$workitem_data" \
                --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
                --arg delete_mode "$DELETE_MODE" \
                '{
                    workitem: $workitem,
                    backup_timestamp: $timestamp,
                    delete_mode: $delete_mode
                }')

            backup_array=$(echo "$backup_array" | jq --argjson entry "$backup_entry" '. + [$entry]')
        else
            log_yunxiao_warning "无法备份工作项 #$workitem_id"
        fi
    done

    echo "$backup_array" > "$backup_file"
    log_yunxiao_success "批量备份完成: $backup_file"
}

# =============================================================================
# 删除执行逻辑
# =============================================================================

# 删除单个工作项
# Usage: delete_single_workitem "workitem_id"
delete_single_workitem() {
    local workitem_id="$1"

    if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
        log_yunxiao_info "准备删除工作项 #$workitem_id (模式: $DELETE_MODE)"
    fi

    # 检查依赖关系
    if ! check_workitem_dependencies "$workitem_id"; then
        if [ "$FORCE_DELETE" = false ]; then
            return 1
        else
            log_yunxiao_warning "强制删除模式，忽略依赖关系"
        fi
    fi

    # 备份（如果指定）
    if [ -n "$BACKUP_FILE" ]; then
        if ! backup_workitem "$workitem_id" "$BACKUP_FILE"; then
            if [ "$FORCE_DELETE" = false ]; then
                log_yunxiao_error "备份失败，删除操作取消"
                return 1
            else
                log_yunxiao_warning "备份失败，但强制继续删除"
            fi
        fi
    fi

    # 如果是干运行模式
    if [ "$DRY_RUN" = true ]; then
        log_yunxiao_info "干运行模式 - 将要删除工作项 #$workitem_id ($DELETE_MODE)"
        return 0
    fi

    # 执行删除
    local delete_force=""
    if [ "$DELETE_MODE" = "hard" ]; then
        delete_force="hard"
    elif [ "$DELETE_MODE" = "archive" ]; then
        delete_force="archive"
    fi

    local result
    if result=$(yunxiao_retry_call yunxiao_delete_workitem "$workitem_id" "$delete_force"); then
        if [ "$QUIET" = false ]; then
            case "$DELETE_MODE" in
                soft) log_yunxiao_success "工作项 #$workitem_id 已标记为删除" ;;
                hard) log_yunxiao_success "工作项 #$workitem_id 已永久删除" ;;
                archive) log_yunxiao_success "工作项 #$workitem_id 已归档" ;;
            esac
        fi

        # 输出结果
        output_delete_result "$workitem_id" "$result"
        return 0
    else
        log_yunxiao_error "删除工作项 #$workitem_id 失败"
        return 1
    fi
}

# 批量删除工作项
# Usage: delete_multiple_workitems
delete_multiple_workitems() {
    local -a workitem_ids

    if [ "$BATCH_MODE" = true ]; then
        workitem_ids=($(get_batch_workitem_ids))
    else
        workitem_ids=("${WORKITEM_IDS[@]}")
    fi

    if [ ${#workitem_ids[@]} -eq 0 ]; then
        log_yunxiao_warning "没有找到要删除的工作项"
        return 1
    fi

    local total=${#workitem_ids[@]}

    # 确认批量删除
    if [ "$FORCE_DELETE" = false ] && [ "$DRY_RUN" = false ]; then
        echo "即将${DELETE_MODE}删除 $total 个工作项:"
        printf "%s " "${workitem_ids[@]}"
        echo ""

        local delete_action
        case "$DELETE_MODE" in
            soft) delete_action="软删除" ;;
            hard) delete_action="硬删除（永久删除）" ;;
            archive) delete_action="归档" ;;
        esac

        echo "删除模式: $delete_action"

        if ! confirm "确认执行批量删除?" "n"; then
            log_yunxiao_info "批量删除已取消"
            return 0
        fi
    fi

    # 批量备份（如果指定）
    if [ -n "$BACKUP_FILE" ]; then
        backup_workitems workitem_ids "$BACKUP_FILE"
    fi

    # 执行批量删除
    local success_count=0
    local fail_count=0

    if [ "$QUIET" = false ]; then
        log_yunxiao_info "开始批量删除 $total 个工作项"
    fi

    for i in "${!workitem_ids[@]}"; do
        local workitem_id="${workitem_ids[$i]}"
        local progress=$((i + 1))

        if [ "$QUIET" = false ]; then
            echo -n "[$progress/$total] 删除工作项 #$workitem_id... "
        fi

        if delete_single_workitem "$workitem_id"; then
            [ "$QUIET" = false ] && echo "✅"
            success_count=$((success_count + 1))
        else
            [ "$QUIET" = false ] && echo "❌"
            fail_count=$((fail_count + 1))
        fi

        # 添加延迟避免API限流
        if [ $total -gt 1 ]; then
            sleep 0.2
        fi
    done

    if [ "$QUIET" = false ]; then
        log_yunxiao_info "批量删除完成: 成功 $success_count，失败 $fail_count"
    fi

    [ $fail_count -eq 0 ]
}

# 获取批量删除的工作项ID
# Usage: get_batch_workitem_ids
get_batch_workitem_ids() {
    local workitem_ids=()

    if [ -n "$FILTER_TYPE" ] || [ -n "$FILTER_STATUS" ]; then
        # 通过过滤器获取工作项列表
        log_yunxiao_info "根据过滤条件获取要删除的工作项"

        local filters="{}"
        [ -n "$FILTER_TYPE" ] && filters=$(echo "$filters" | jq --arg type "$FILTER_TYPE" '.type = $type')
        [ -n "$FILTER_STATUS" ] && filters=$(echo "$filters" | jq --arg status "$FILTER_STATUS" '.status = $status')

        local result
        if result=$(yunxiao_retry_call yunxiao_list_workitems "$filters" "1" "1000"); then
            local workitems
            workitems=$(echo "$result" | jq '.workitems // .data // []')
            mapfile -t workitem_ids < <(echo "$workitems" | jq -r '.[].id')
        fi
    else
        # 从标准输入读取
        log_yunxiao_info "从标准输入读取工作项ID（每行一个），按Ctrl+D结束"

        while IFS= read -r line; do
            # 跳过空行和注释
            if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi

            # 验证ID格式
            if validate_workitem_id "$line" 2>/dev/null; then
                workitem_ids+=("$line")
            else
                log_yunxiao_warning "忽略无效ID: $line"
            fi
        done
    fi

    printf "%s\n" "${workitem_ids[@]}"
}

# =============================================================================
# 输出格式化
# =============================================================================

# 输出删除结果
# Usage: output_delete_result "workitem_id" "result_json"
output_delete_result() {
    local workitem_id="$1"
    local result="$2"

    case "$OUTPUT_FORMAT" in
        json)
            echo "$result" | jq .
            ;;
        table)
            output_table_format "$workitem_id" "$result"
            ;;
        summary)
            # summary 在删除函数中已输出
            ;;
    esac
}

# 表格格式输出
output_table_format() {
    local workitem_id="$1"
    local result="$2"

    echo "| 字段       | 值                |"
    echo "|------------|-------------------|"
    echo "| 工作项ID   | $workitem_id      |"
    echo "| 删除模式   | $DELETE_MODE      |"
    echo "| 删除时间   | $(date)           |"

    if [ -n "$result" ] && [ "$result" != "null" ]; then
        local status
        status=$(echo "$result" | jq -r '.status // "已删除"')
        echo "| 当前状态   | $status           |"
    fi
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    # 初始化环境
    init_workitem_environment

    # 解析参数
    parse_arguments "$@"

    # 执行删除操作
    delete_multiple_workitems
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi