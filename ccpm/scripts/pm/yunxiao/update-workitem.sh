#!/bin/bash

# 云效工作项更新脚本
# 更新工作项的各种属性

# 获取脚本目录并引入通用函数
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/workitem-common.sh"

# =============================================================================
# 脚本帮助信息
# =============================================================================

show_help() {
    cat << EOF
云效工作项更新工具

用法:
    $0 [选项] <工作项ID> [字段=值] [字段=值] ...

参数:
    工作项ID      要更新的工作项ID（数字）
    字段=值       要更新的字段和值（可指定多个）

支持的字段:
    title         标题
    description   描述
    status        状态 (新建|进行中|已完成|已关闭|暂停|已取消)
    priority      优先级 (高|中|低|紧急)
    assignee      指派人
    type          类型 (requirement|task|bug|epic)

选项:
    -f, --file FILE         从JSON文件读取更新数据
    -j, --json JSON         直接提供JSON格式的更新数据
    -i, --interactive       交互式更新模式
    -o, --output FORMAT     输出格式 (json|table|summary) [默认: summary]
    -n, --dry-run           仅验证更新，不实际执行
    --force                 强制更新（跳过确认）
    --comment TEXT          添加更新说明
    -v, --verbose           详细输出
    -h, --help              显示此帮助信息

示例:
    # 更新工作项标题
    $0 12345 title="新的标题"

    # 更新多个字段
    $0 12345 status=进行中 priority=高 assignee=zhangsan

    # 使用JSON文件更新
    $0 -f updates.json 12345

    # 使用JSON字符串更新
    $0 -j '{"status":"已完成","comment":"任务完成"}' 12345

    # 交互式更新
    $0 -i 12345

    # 批量更新（状态转换）
    $0 12345 12346 12347 status=已完成

    # 仅验证更新
    $0 -n 12345 title="测试标题"

JSON格式示例:
    {
        "title": "更新后的标题",
        "description": "更新后的描述",
        "status": "进行中",
        "priority": "高",
        "assignee": "zhangsan",
        "comment": "更新说明"
    }

EOF
}

# =============================================================================
# 参数解析
# =============================================================================

parse_arguments() {
    local TEMP
    TEMP=$(getopt -o 'f:j:io:nvh' --long 'file:,json:,interactive,output:,dry-run,force,comment:,verbose,help' -n "$0" -- "$@")

    if [ $? -ne 0 ]; then
        echo "参数解析失败，使用 --help 查看用法" >&2
        exit 1
    fi

    eval set -- "$TEMP"
    unset TEMP

    # 默认值
    UPDATE_FILE=""
    UPDATE_JSON=""
    INTERACTIVE_MODE=false
    OUTPUT_FORMAT="summary"
    DRY_RUN=false
    FORCE_UPDATE=false
    UPDATE_COMMENT=""
    VERBOSE=false

    while true; do
        case "$1" in
            '-f'|'--file')
                UPDATE_FILE="$2"
                shift 2
                continue
                ;;
            '-j'|'--json')
                UPDATE_JSON="$2"
                shift 2
                continue
                ;;
            '-i'|'--interactive')
                INTERACTIVE_MODE=true
                shift
                continue
                ;;
            '-o'|'--output')
                OUTPUT_FORMAT="$2"
                shift 2
                continue
                ;;
            '-n'|'--dry-run')
                DRY_RUN=true
                shift
                continue
                ;;
            '--force')
                FORCE_UPDATE=true
                shift
                continue
                ;;
            '--comment')
                UPDATE_COMMENT="$2"
                shift 2
                continue
                ;;
            '-v'|'--verbose')
                VERBOSE=true
                export YUNXIAO_DEBUG=1
                shift
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

    # 验证输出格式
    case "$OUTPUT_FORMAT" in
        json|table|summary)
            ;;
        *)
            error_exit "不支持的输出格式: $OUTPUT_FORMAT"
            ;;
    esac

    # 解析工作项ID和更新字段
    if [ $# -eq 0 ]; then
        echo "错误: 需要提供工作项ID" >&2
        echo "使用 --help 查看用法" >&2
        exit 1
    fi

    # 第一个参数是工作项ID
    WORKITEM_ID="$1"
    validate_workitem_id "$WORKITEM_ID" || exit 1
    shift

    # 剩余参数是字段更新（如果不是其他模式）
    if [ "$INTERACTIVE_MODE" = false ] && [ -z "$UPDATE_FILE" ] && [ -z "$UPDATE_JSON" ]; then
        FIELD_UPDATES=("$@")
    fi

    # 验证更新文件
    if [ -n "$UPDATE_FILE" ] && [ ! -f "$UPDATE_FILE" ]; then
        error_exit "更新文件不存在: $UPDATE_FILE"
    fi
}

# =============================================================================
# 更新数据构建
# =============================================================================

# 从字段参数构建更新数据
# Usage: build_updates_from_fields
build_updates_from_fields() {
    local updates="{}"

    for field_update in "${FIELD_UPDATES[@]}"; do
        if [[ "$field_update" == *"="* ]]; then
            local field="${field_update%%=*}"
            local value="${field_update#*=}"

            # 验证字段名
            case "$field" in
                title|description|status|priority|assignee|type)
                    ;;
                *)
                    log_yunxiao_warning "忽略不支持的字段: $field"
                    continue
                    ;;
            esac

            # 特殊验证
            case "$field" in
                title)
                    validate_workitem_title "$value" || return 1
                    ;;
                priority)
                    validate_priority "$value" || return 1
                    ;;
                type)
                    validate_workitem_type "$value" || return 1
                    ;;
            esac

            updates=$(echo "$updates" | jq --arg field "$field" --arg value "$value" '.[$field] = $value')
        else
            log_yunxiao_warning "忽略无效的字段更新格式: $field_update"
        fi
    done

    # 添加更新说明
    if [ -n "$UPDATE_COMMENT" ]; then
        updates=$(echo "$updates" | jq --arg comment "$UPDATE_COMMENT" '.comment = $comment')
    fi

    echo "$updates"
}

# 从文件读取更新数据
# Usage: build_updates_from_file
build_updates_from_file() {
    local updates
    updates=$(cat "$UPDATE_FILE")

    if ! validate_json "$updates"; then
        error_exit "更新文件JSON格式错误: $UPDATE_FILE"
    fi

    echo "$updates"
}

# 从JSON字符串构建更新数据
# Usage: build_updates_from_json
build_updates_from_json() {
    if ! validate_json "$UPDATE_JSON"; then
        error_exit "JSON格式错误: $UPDATE_JSON"
    fi

    echo "$UPDATE_JSON"
}

# 交互式构建更新数据
# Usage: build_updates_interactive
build_updates_interactive() {
    local updates="{}"

    echo "=== 交互式工作项更新 ==="
    echo "输入要更新的字段值，按回车跳过不更新的字段"
    echo ""

    # 获取当前工作项数据
    local current_data
    if current_data=$(yunxiao_retry_call yunxiao_get_workitem "$WORKITEM_ID"); then
        echo "当前工作项信息:"
        format_workitem_display "$current_data"
        echo ""
    else
        log_yunxiao_warning "无法获取当前工作项信息，继续更新..."
    fi

    # 逐个字段询问
    local fields=("title" "description" "status" "priority" "assignee")
    local field_names=("标题" "描述" "状态" "优先级" "指派人")

    for i in "${!fields[@]}"; do
        local field="${fields[$i]}"
        local field_name="${field_names[$i]}"
        local current_value=""

        if [ -n "$current_data" ]; then
            current_value=$(get_workitem_field "$current_data" "$field")
        fi

        echo -n "$field_name"
        [ -n "$current_value" ] && echo -n " [当前: $current_value]"
        echo -n ": "

        local new_value
        read -r new_value

        if [ -n "$new_value" ]; then
            # 验证输入
            case "$field" in
                title)
                    validate_workitem_title "$new_value" || continue
                    ;;
                priority)
                    validate_priority "$new_value" || continue
                    ;;
            esac

            updates=$(echo "$updates" | jq --arg field "$field" --arg value "$new_value" '.[$field] = $value')
        fi
    done

    # 询问更新说明
    echo -n "更新说明 (可选): "
    local comment
    read -r comment
    if [ -n "$comment" ]; then
        updates=$(echo "$updates" | jq --arg comment "$comment" '.comment = $comment')
    fi

    echo "$updates"
}

# =============================================================================
# 更新执行逻辑
# =============================================================================

# 执行工作项更新
# Usage: update_workitem
update_workitem() {
    local updates

    # 根据模式构建更新数据
    if [ "$INTERACTIVE_MODE" = true ]; then
        updates=$(build_updates_interactive)
    elif [ -n "$UPDATE_FILE" ]; then
        updates=$(build_updates_from_file)
    elif [ -n "$UPDATE_JSON" ]; then
        updates=$(build_updates_from_json)
    else
        if [ ${#FIELD_UPDATES[@]} -eq 0 ]; then
            error_exit "没有指定要更新的字段"
        fi
        updates=$(build_updates_from_fields)
    fi

    if [ $? -ne 0 ] || [ -z "$updates" ]; then
        error_exit "构建更新数据失败"
    fi

    # 检查是否有实际更新
    local update_count
    update_count=$(echo "$updates" | jq 'to_entries | length')
    if [ "$update_count" -eq 0 ]; then
        log_yunxiao_warning "没有指定任何更新字段"
        return 0
    fi

    if [ "$VERBOSE" = true ]; then
        log_yunxiao_info "更新数据:"
        echo "$updates" | jq . >&2
    fi

    # 如果是干运行模式
    if [ "$DRY_RUN" = true ]; then
        log_yunxiao_info "干运行模式 - 将要执行的更新:"
        echo "工作项ID: $WORKITEM_ID"
        echo "更新字段:"
        echo "$updates" | jq .
        return 0
    fi

    # 确认更新（除非强制模式）
    if [ "$FORCE_UPDATE" = false ] && [ "$INTERACTIVE_MODE" = false ]; then
        echo "即将更新工作项 #$WORKITEM_ID:"
        echo "$updates" | jq .
        echo ""

        if ! confirm "确认执行更新?" "n"; then
            log_yunxiao_info "更新已取消"
            return 0
        fi
    fi

    # 执行更新
    log_yunxiao_info "正在更新工作项 #$WORKITEM_ID..."

    local result
    if result=$(yunxiao_retry_call yunxiao_update_workitem "$WORKITEM_ID" "$updates"); then
        log_yunxiao_success "工作项更新成功"

        # 输出结果
        output_update_result "$result"
        return 0
    else
        log_yunxiao_error "工作项更新失败"
        return 1
    fi
}

# =============================================================================
# 输出格式化
# =============================================================================

# 输出更新结果
# Usage: output_update_result "result_json"
output_update_result() {
    local result="$1"

    case "$OUTPUT_FORMAT" in
        json)
            echo "$result" | jq .
            ;;
        table)
            output_table_format "$result"
            ;;
        summary)
            output_summary_format "$result"
            ;;
    esac
}

# 表格格式输出
output_table_format() {
    local result="$1"

    echo "| 字段     | 更新后的值          |"
    echo "|----------|---------------------|"

    local fields=("id" "title" "type" "status" "priority" "assignee" "updated_time")

    for field in "${fields[@]}"; do
        local value
        value=$(get_workitem_field "$result" "$field")
        [ -z "$value" ] && value="N/A"

        # 截断长字段
        if [ ${#value} -gt 18 ]; then
            value="${value:0:15}..."
        fi

        printf "| %-8s | %-19s |\n" "$field" "$value"
    done
}

# 摘要格式输出
output_summary_format() {
    local result="$1"

    local id title status updated_time
    id=$(get_workitem_field "$result" "id")
    title=$(get_workitem_field "$result" "title")
    status=$(get_workitem_field "$result" "status")
    updated_time=$(get_workitem_field "$result" "updated_time")

    echo "✅ 工作项 #$id 更新完成"
    echo "   标题: $title"
    echo "   状态: $status"
    [ -n "$updated_time" ] && echo "   更新时间: $updated_time"

    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "完整数据:"
        echo "$result" | jq .
    fi
}

# =============================================================================
# 批量更新支持
# =============================================================================

# 批量更新多个工作项
# Usage: batch_update_workitems
batch_update_workitems() {
    local workitem_ids=("$@")
    local total=${#workitem_ids[@]}

    if [ $total -le 1 ]; then
        return 0  # 单个工作项，使用普通流程
    fi

    log_yunxiao_info "批量更新 $total 个工作项"

    # 构建更新数据（使用第一个工作项的逻辑）
    local updates
    if [ -n "$UPDATE_FILE" ]; then
        updates=$(build_updates_from_file)
    elif [ -n "$UPDATE_JSON" ]; then
        updates=$(build_updates_from_json)
    else
        updates=$(build_updates_from_fields)
    fi

    if [ $? -ne 0 ] || [ -z "$updates" ]; then
        error_exit "构建更新数据失败"
    fi

    # 确认批量更新
    if [ "$FORCE_UPDATE" = false ]; then
        echo "即将批量更新 $total 个工作项:"
        printf "%s " "${workitem_ids[@]}"
        echo ""
        echo "更新内容:"
        echo "$updates" | jq .
        echo ""

        if ! confirm "确认执行批量更新?" "n"; then
            log_yunxiao_info "批量更新已取消"
            return 0
        fi
    fi

    # 执行批量更新
    local success_count=0
    local fail_count=0

    for i in "${!workitem_ids[@]}"; do
        local workitem_id="${workitem_ids[$i]}"
        local progress=$((i + 1))

        echo -n "[$progress/$total] 更新工作项 #$workitem_id... "

        if [ "$DRY_RUN" = true ]; then
            echo "✅ (干运行)"
            success_count=$((success_count + 1))
        else
            if yunxiao_retry_call yunxiao_update_workitem "$workitem_id" "$updates" >/dev/null; then
                echo "✅"
                success_count=$((success_count + 1))
            else
                echo "❌"
                fail_count=$((fail_count + 1))
            fi
        fi

        # 添加延迟避免API限流
        sleep 0.2
    done

    log_yunxiao_info "批量更新完成: 成功 $success_count，失败 $fail_count"

    [ $fail_count -eq 0 ]
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    # 初始化环境
    init_workitem_environment

    # 解析参数
    parse_arguments "$@"

    # 检查是否有多个工作项ID需要批量更新
    if [ $# -gt 0 ] && [ "$INTERACTIVE_MODE" = false ]; then
        # 额外的参数可能是更多的工作项ID
        local additional_ids=()
        for arg in "$@"; do
            if validate_workitem_id "$arg" 2>/dev/null; then
                additional_ids+=("$arg")
            else
                break  # 遇到非ID参数，停止收集
            fi
        done

        if [ ${#additional_ids[@]} -gt 0 ]; then
            # 批量更新模式
            batch_update_workitems "$WORKITEM_ID" "${additional_ids[@]}"
            return $?
        fi
    fi

    # 单个工作项更新
    update_workitem
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi