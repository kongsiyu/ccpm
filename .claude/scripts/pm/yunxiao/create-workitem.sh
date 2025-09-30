#!/bin/bash

# 云效工作项创建脚本
# 创建不同类型的工作项（需求、任务、缺陷等）

# 获取脚本目录并引入通用函数
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/workitem-common.sh"

# =============================================================================
# 脚本帮助信息
# =============================================================================

show_help() {
    cat << EOF
云效工作项创建工具

用法:
    $0 [选项] <类型> <标题> [描述]

参数:
    类型     工作项类型 (requirement|task|bug|epic)
    标题     工作项标题 (5-100个字符)
    描述     工作项描述 (可选)

选项:
    -a, --assignee USER    指派给用户
    -p, --priority LEVEL   设置优先级 (高|中|低|紧急)
    -t, --template FILE    使用自定义模板文件
    -o, --output FORMAT    输出格式 (json|table|summary) [默认: summary]
    -n, --dry-run          仅验证参数，不实际创建
    --batch                批量创建模式（从标准输入读取）
    -v, --verbose          详细输出
    -h, --help             显示此帮助信息

示例:
    # 创建基本任务
    $0 task "实现用户登录功能" "添加用户名密码登录"

    # 创建高优先级需求并指派
    $0 -p 高 -a zhangsan requirement "用户管理系统" "完整的用户CRUD操作"

    # 使用自定义模板
    $0 -t custom.json bug "登录页面崩溃"

    # 批量创建（JSON格式输入）
    echo '{"type":"task","title":"任务1","description":"描述1"}' | $0 --batch

    # 仅验证参数
    $0 -n task "测试标题" "测试描述"

EOF
}

# =============================================================================
# 参数解析
# =============================================================================

parse_arguments() {
    local TEMP
    TEMP=$(getopt -o 'a:p:t:o:nvh' --long 'assignee:,priority:,template:,output:,dry-run,batch,verbose,help' -n "$0" -- "$@")

    if [ $? -ne 0 ]; then
        echo "参数解析失败，使用 --help 查看用法" >&2
        exit 1
    fi

    eval set -- "$TEMP"
    unset TEMP

    # 默认值
    ASSIGNEE=""
    PRIORITY=""
    TEMPLATE_FILE=""
    OUTPUT_FORMAT="summary"
    DRY_RUN=false
    BATCH_MODE=false
    VERBOSE=false

    while true; do
        case "$1" in
            '-a'|'--assignee')
                ASSIGNEE="$2"
                shift 2
                continue
                ;;
            '-p'|'--priority')
                PRIORITY="$2"
                shift 2
                continue
                ;;
            '-t'|'--template')
                TEMPLATE_FILE="$2"
                shift 2
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
            '--batch')
                BATCH_MODE=true
                shift
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

    # 非批量模式需要位置参数
    if [ "$BATCH_MODE" = false ]; then
        if [ $# -lt 2 ]; then
            echo "错误: 需要提供工作项类型和标题" >&2
            echo "使用 --help 查看用法" >&2
            exit 1
        fi

        WORKITEM_TYPE="$1"
        WORKITEM_TITLE="$2"
        WORKITEM_DESCRIPTION="$3"
    fi
}

# =============================================================================
# 工作项创建逻辑
# =============================================================================

# 创建单个工作项
# Usage: create_single_workitem "type" "title" "description" ["assignee"] ["priority"] ["template"]
create_single_workitem() {
    local type="$1"
    local title="$2"
    local description="$3"
    local assignee="$4"
    local priority="$5"
    local template="$6"

    # 参数验证
    validate_workitem_type "$type" || return 1
    validate_workitem_title "$title" || return 1
    [ -n "$priority" ] && validate_priority "$priority" || return 1

    if [ "$VERBOSE" = true ]; then
        log_yunxiao_info "创建工作项参数:"
        log_yunxiao_info "  类型: $type"
        log_yunxiao_info "  标题: $title"
        log_yunxiao_info "  描述: ${description:-无}"
        log_yunxiao_info "  指派人: ${assignee:-未指派}"
        log_yunxiao_info "  优先级: ${priority:-默认}"
        log_yunxiao_info "  模板: ${template:-默认}"
    fi

    # 构建工作项数据
    local workitem_json
    if [ -n "$template" ] && [ -f "$template" ]; then
        # 使用自定义模板
        log_yunxiao_info "使用自定义模板: $template"
        workitem_json=$(cat "$template")

        # 替换模板中的占位符
        workitem_json=$(echo "$workitem_json" | jq \
            --arg title "$title" \
            --arg description "$description" \
            --arg assignee "${assignee:-""}" \
            --arg priority "${priority:-""}" \
            '.workitem.title = $title |
             .workitem.description = $description |
             (.workitem.assignee = if $assignee == "" then null else $assignee end) |
             (.workitem.priority = if $priority == "" then null else $priority end)')
    else
        # 使用标准模板
        workitem_json=$(create_from_template "$type" "$title" "$description" "$assignee" "$priority")
    fi

    if [ $? -ne 0 ] || [ -z "$workitem_json" ]; then
        log_yunxiao_error "工作项数据构建失败"
        return 1
    fi

    # 验证JSON格式
    if ! validate_json "$workitem_json"; then
        log_yunxiao_error "工作项数据格式错误"
        return 1
    fi

    # 如果是干运行模式，仅显示数据
    if [ "$DRY_RUN" = true ]; then
        log_yunxiao_info "干运行模式 - 将要创建的工作项数据:"
        echo "$workitem_json" | jq .
        return 0
    fi

    # 调用MCP服务创建工作项
    log_yunxiao_info "正在创建工作项..."

    local result
    if result=$(yunxiao_retry_call yunxiao_create_workitem "$workitem_json"); then
        log_yunxiao_success "工作项创建成功"

        # 输出结果
        output_workitem_result "$result" "$workitem_json"
        return 0
    else
        log_yunxiao_error "工作项创建失败"
        return 1
    fi
}

# 批量创建工作项
# Usage: create_batch_workitems
create_batch_workitems() {
    log_yunxiao_info "进入批量创建模式，请输入JSON格式的工作项数据（每行一个）"
    log_yunxiao_info "输入格式: {\"type\":\"task\",\"title\":\"标题\",\"description\":\"描述\"}"
    log_yunxiao_info "按Ctrl+D结束输入"

    local line_number=0
    local success_count=0
    local fail_count=0

    while IFS= read -r line; do
        line_number=$((line_number + 1))

        # 跳过空行和注释
        if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        echo "[$line_number] 处理: $line"

        # 解析JSON数据
        local type title description assignee priority
        if ! validate_json "$line"; then
            log_yunxiao_error "第 $line_number 行: JSON格式错误"
            fail_count=$((fail_count + 1))
            continue
        fi

        type=$(echo "$line" | jq -r '.type // empty')
        title=$(echo "$line" | jq -r '.title // empty')
        description=$(echo "$line" | jq -r '.description // empty')
        assignee=$(echo "$line" | jq -r '.assignee // empty')
        priority=$(echo "$line" | jq -r '.priority // empty')

        if [ -z "$type" ] || [ -z "$title" ]; then
            log_yunxiao_error "第 $line_number 行: 缺少必需字段 type 或 title"
            fail_count=$((fail_count + 1))
            continue
        fi

        # 创建工作项
        if create_single_workitem "$type" "$title" "$description" "$assignee" "$priority"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi

        # 添加延迟避免API限流
        sleep 0.5
    done

    log_yunxiao_info "批量创建完成: 成功 $success_count，失败 $fail_count"

    if [ $fail_count -gt 0 ]; then
        return 1
    fi

    return 0
}

# =============================================================================
# 输出格式化
# =============================================================================

# 输出工作项创建结果
# Usage: output_workitem_result "result_json" "original_json"
output_workitem_result() {
    local result="$1"
    local original="$2"

    case "$OUTPUT_FORMAT" in
        json)
            echo "$result"
            ;;
        table)
            output_table_format "$result"
            ;;
        summary)
            output_summary_format "$result" "$original"
            ;;
    esac
}

# 表格格式输出
output_table_format() {
    local result="$1"

    echo "| 字段     | 值                |"
    echo "|----------|-------------------|"

    local id title type status
    id=$(get_workitem_field "$result" "id")
    title=$(get_workitem_field "$result" "title")
    type=$(get_workitem_field "$result" "type")
    status=$(get_workitem_field "$result" "status")

    echo "| ID       | ${id:-N/A}        |"
    echo "| 标题     | ${title:-N/A}     |"
    echo "| 类型     | ${type:-N/A}      |"
    echo "| 状态     | ${status:-N/A}    |"
}

# 摘要格式输出
output_summary_format() {
    local result="$1"
    local original="$2"

    local id title type
    id=$(get_workitem_field "$result" "id")
    title=$(get_workitem_field "$result" "title")
    type=$(get_workitem_field "$result" "type")

    echo "✅ 工作项创建成功"
    echo "   ID: ${id:-未返回}"
    echo "   标题: ${title}"
    echo "   类型: ${type}"

    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "完整数据:"
        echo "$result" | jq .
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

    # 验证模板文件（如果指定）
    if [ -n "$TEMPLATE_FILE" ] && [ ! -f "$TEMPLATE_FILE" ]; then
        error_exit "模板文件不存在: $TEMPLATE_FILE"
    fi

    # 根据模式执行
    if [ "$BATCH_MODE" = true ]; then
        create_batch_workitems
    else
        create_single_workitem "$WORKITEM_TYPE" "$WORKITEM_TITLE" "$WORKITEM_DESCRIPTION" "$ASSIGNEE" "$PRIORITY" "$TEMPLATE_FILE"
    fi
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi