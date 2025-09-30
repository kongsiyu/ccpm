#!/bin/bash

# 云效工作项列表脚本
# 列出工作项，支持过滤、分页和排序

# 获取脚本目录并引入通用函数
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/workitem-common.sh"

# =============================================================================
# 脚本帮助信息
# =============================================================================

show_help() {
    cat << EOF
云效工作项列表工具

用法:
    $0 [选项]

选项:
    过滤选项:
    -t, --type TYPE         按类型过滤 (requirement|task|bug|epic)
    -s, --status STATUS     按状态过滤 (新建|进行中|已完成|已关闭|暂停|已取消)
    -a, --assignee USER     按指派人过滤
    -c, --creator USER      按创建人过滤
    -p, --priority LEVEL    按优先级过滤 (高|中|低|紧急)
    --title-contains TEXT   标题包含指定文本
    --created-after DATE    创建时间晚于指定日期 (YYYY-MM-DD)
    --created-before DATE   创建时间早于指定日期 (YYYY-MM-DD)

    分页选项:
    --page NUM              页码 [默认: 1]
    --size NUM              每页数量 [默认: 20]
    --all                   获取所有结果（忽略分页）

    排序选项:
    --sort FIELD            排序字段 (id|title|status|created_time|updated_time)
    --order ORDER           排序顺序 (asc|desc) [默认: desc]

    输出选项:
    -o, --output FORMAT     输出格式 (json|table|summary|count) [默认: table]
    -f, --fields FIELDS     指定输出字段 (用逗号分隔)
    --no-header             不显示表头（仅table格式）
    --raw                   原始输出，不进行格式化

    其他选项:
    --save FILE             保存结果到文件
    -q, --quiet             静默模式，只输出结果
    -v, --verbose           详细输出
    -h, --help              显示此帮助信息

输出格式:
    json     完整JSON格式
    table    表格格式（默认）
    summary  摘要格式（一行一个工作项）
    count    仅显示数量

示例:
    # 列出所有工作项
    $0

    # 列出指定类型的工作项
    $0 -t task

    # 列出指派给特定用户的工作项
    $0 -a zhangsan

    # 列出高优先级的未完成工作项
    $0 -p 高 -s 进行中

    # 按创建时间排序
    $0 --sort created_time --order asc

    # 获取特定时间范围的工作项
    $0 --created-after 2024-01-01 --created-before 2024-12-31

    # 搜索标题包含特定文本的工作项
    $0 --title-contains "登录"

    # 导出到文件
    $0 -o json --save workitems.json

    # 只显示数量
    $0 -o count

EOF
}

# =============================================================================
# 参数解析
# =============================================================================

parse_arguments() {
    local TEMP
    TEMP=$(getopt -o 't:s:a:c:p:o:f:qvh' --long 'type:,status:,assignee:,creator:,priority:,title-contains:,created-after:,created-before:,page:,size:,all,sort:,order:,output:,fields:,no-header,raw,save:,quiet,verbose,help' -n "$0" -- "$@")

    if [ $? -ne 0 ]; then
        echo "参数解析失败，使用 --help 查看用法" >&2
        exit 1
    fi

    eval set -- "$TEMP"
    unset TEMP

    # 默认值
    FILTER_TYPE=""
    FILTER_STATUS=""
    FILTER_ASSIGNEE=""
    FILTER_CREATOR=""
    FILTER_PRIORITY=""
    FILTER_TITLE_CONTAINS=""
    FILTER_CREATED_AFTER=""
    FILTER_CREATED_BEFORE=""
    PAGE=1
    SIZE=20
    GET_ALL=false
    SORT_FIELD=""
    SORT_ORDER="desc"
    OUTPUT_FORMAT="table"
    FIELDS=""
    NO_HEADER=false
    RAW_OUTPUT=false
    SAVE_FILE=""
    QUIET=false
    VERBOSE=false

    while true; do
        case "$1" in
            '-t'|'--type')
                FILTER_TYPE="$2"
                shift 2
                continue
                ;;
            '-s'|'--status')
                FILTER_STATUS="$2"
                shift 2
                continue
                ;;
            '-a'|'--assignee')
                FILTER_ASSIGNEE="$2"
                shift 2
                continue
                ;;
            '-c'|'--creator')
                FILTER_CREATOR="$2"
                shift 2
                continue
                ;;
            '-p'|'--priority')
                FILTER_PRIORITY="$2"
                shift 2
                continue
                ;;
            '--title-contains')
                FILTER_TITLE_CONTAINS="$2"
                shift 2
                continue
                ;;
            '--created-after')
                FILTER_CREATED_AFTER="$2"
                shift 2
                continue
                ;;
            '--created-before')
                FILTER_CREATED_BEFORE="$2"
                shift 2
                continue
                ;;
            '--page')
                PAGE="$2"
                shift 2
                continue
                ;;
            '--size')
                SIZE="$2"
                shift 2
                continue
                ;;
            '--all')
                GET_ALL=true
                shift
                continue
                ;;
            '--sort')
                SORT_FIELD="$2"
                shift 2
                continue
                ;;
            '--order')
                SORT_ORDER="$2"
                shift 2
                continue
                ;;
            '-o'|'--output')
                OUTPUT_FORMAT="$2"
                shift 2
                continue
                ;;
            '-f'|'--fields')
                FIELDS="$2"
                shift 2
                continue
                ;;
            '--no-header')
                NO_HEADER=true
                shift
                continue
                ;;
            '--raw')
                RAW_OUTPUT=true
                shift
                continue
                ;;
            '--save')
                SAVE_FILE="$2"
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
    validate_arguments
}

# 验证参数
validate_arguments() {
    # 验证工作项类型
    if [ -n "$FILTER_TYPE" ]; then
        validate_workitem_type "$FILTER_TYPE" || exit 1
    fi

    # 验证优先级
    if [ -n "$FILTER_PRIORITY" ]; then
        validate_priority "$FILTER_PRIORITY" || exit 1
    fi

    # 验证输出格式
    case "$OUTPUT_FORMAT" in
        json|table|summary|count)
            ;;
        *)
            error_exit "不支持的输出格式: $OUTPUT_FORMAT"
            ;;
    esac

    # 验证排序字段
    if [ -n "$SORT_FIELD" ]; then
        case "$SORT_FIELD" in
            id|title|status|created_time|updated_time|priority)
                ;;
            *)
                error_exit "不支持的排序字段: $SORT_FIELD"
                ;;
        esac
    fi

    # 验证排序顺序
    case "$SORT_ORDER" in
        asc|desc)
            ;;
        *)
            error_exit "不支持的排序顺序: $SORT_ORDER"
            ;;
    esac

    # 验证分页参数
    if ! [[ "$PAGE" =~ ^[1-9][0-9]*$ ]]; then
        error_exit "页码必须为正整数: $PAGE"
    fi

    if ! [[ "$SIZE" =~ ^[1-9][0-9]*$ ]] || [ "$SIZE" -gt 100 ]; then
        error_exit "每页数量必须为1-100之间的整数: $SIZE"
    fi

    # 验证日期格式
    if [ -n "$FILTER_CREATED_AFTER" ]; then
        validate_date_format "$FILTER_CREATED_AFTER" || error_exit "创建后日期格式错误: $FILTER_CREATED_AFTER"
    fi

    if [ -n "$FILTER_CREATED_BEFORE" ]; then
        validate_date_format "$FILTER_CREATED_BEFORE" || error_exit "创建前日期格式错误: $FILTER_CREATED_BEFORE"
    fi
}

# 验证日期格式
validate_date_format() {
    local date="$1"
    if [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        return 0
    fi
    return 1
}

# =============================================================================
# 过滤器构建
# =============================================================================

# 构建查询过滤器
# Usage: build_filters
# Returns: JSON filter string
build_filters() {
    local filters="{}"

    # 类型过滤
    if [ -n "$FILTER_TYPE" ]; then
        filters=$(echo "$filters" | jq --arg type "$FILTER_TYPE" '.type = $type')
    fi

    # 状态过滤
    if [ -n "$FILTER_STATUS" ]; then
        filters=$(echo "$filters" | jq --arg status "$FILTER_STATUS" '.status = $status')
    fi

    # 指派人过滤
    if [ -n "$FILTER_ASSIGNEE" ]; then
        filters=$(echo "$filters" | jq --arg assignee "$FILTER_ASSIGNEE" '.assignee = $assignee')
    fi

    # 创建人过滤
    if [ -n "$FILTER_CREATOR" ]; then
        filters=$(echo "$filters" | jq --arg creator "$FILTER_CREATOR" '.creator = $creator')
    fi

    # 优先级过滤
    if [ -n "$FILTER_PRIORITY" ]; then
        filters=$(echo "$filters" | jq --arg priority "$FILTER_PRIORITY" '.priority = $priority')
    fi

    # 标题包含过滤
    if [ -n "$FILTER_TITLE_CONTAINS" ]; then
        filters=$(echo "$filters" | jq --arg text "$FILTER_TITLE_CONTAINS" '.title_contains = $text')
    fi

    # 创建时间过滤
    if [ -n "$FILTER_CREATED_AFTER" ]; then
        filters=$(echo "$filters" | jq --arg date "$FILTER_CREATED_AFTER" '.created_after = $date')
    fi

    if [ -n "$FILTER_CREATED_BEFORE" ]; then
        filters=$(echo "$filters" | jq --arg date "$FILTER_CREATED_BEFORE" '.created_before = $date')
    fi

    # 排序选项
    if [ -n "$SORT_FIELD" ]; then
        filters=$(echo "$filters" | jq --arg field "$SORT_FIELD" --arg order "$SORT_ORDER" '.sort_by = $field | .sort_order = $order')
    fi

    echo "$filters"
}

# =============================================================================
# 工作项列表获取
# =============================================================================

# 获取工作项列表
# Usage: get_workitems_list
get_workitems_list() {
    local filters
    filters=$(build_filters)

    if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
        log_yunxiao_info "查询参数:"
        echo "$filters" | jq . >&2
    fi

    local result
    if [ "$GET_ALL" = true ]; then
        result=$(get_all_workitems "$filters")
    else
        if [ "$QUIET" = false ]; then
            log_yunxiao_info "获取第 $PAGE 页，每页 $SIZE 个工作项"
        fi

        if result=$(yunxiao_retry_call yunxiao_list_workitems "$filters" "$PAGE" "$SIZE"); then
            if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
                log_yunxiao_success "工作项列表获取成功"
            fi
        else
            log_yunxiao_error "工作项列表获取失败"
            return 1
        fi
    fi

    # 处理结果
    process_results "$result"
}

# 获取所有工作项（分页迭代）
# Usage: get_all_workitems "filters"
get_all_workitems() {
    local filters="$1"
    local all_results="[]"
    local current_page=1
    local page_size=50  # 使用较大的页面大小提高效率

    if [ "$QUIET" = false ]; then
        log_yunxiao_info "获取所有工作项..."
    fi

    while true; do
        if [ "$VERBOSE" = true ] && [ "$QUIET" = false ]; then
            log_yunxiao_debug "获取第 $current_page 页"
        fi

        local page_result
        if ! page_result=$(yunxiao_retry_call yunxiao_list_workitems "$filters" "$current_page" "$page_size"); then
            log_yunxiao_error "获取第 $current_page 页失败"
            return 1
        fi

        # 解析结果
        local workitems total_count
        workitems=$(echo "$page_result" | jq '.workitems // .data // []')
        total_count=$(echo "$page_result" | jq '.total_count // .total // 0')

        # 合并结果
        all_results=$(echo "$all_results" | jq --argjson items "$workitems" '. + $items')

        # 检查是否还有更多数据
        local current_count
        current_count=$(echo "$all_results" | jq 'length')

        if [ "$current_count" -ge "$total_count" ] || [ "$(echo "$workitems" | jq 'length')" -eq 0 ]; then
            break
        fi

        current_page=$((current_page + 1))

        # 添加延迟避免API限流
        sleep 0.1
    done

    # 构建最终结果
    jq -n --argjson items "$all_results" --argjson total "$(echo "$all_results" | jq 'length')" '{
        workitems: $items,
        total_count: $total,
        page: 1,
        page_size: $total
    }'
}

# =============================================================================
# 结果处理和输出
# =============================================================================

# 处理和输出结果
# Usage: process_results "result_json"
process_results() {
    local result="$1"

    if [ -z "$result" ]; then
        log_yunxiao_error "无结果数据"
        return 1
    fi

    # 保存到文件（如果指定）
    if [ -n "$SAVE_FILE" ]; then
        echo "$result" > "$SAVE_FILE"
        if [ "$QUIET" = false ]; then
            log_yunxiao_success "结果已保存到: $SAVE_FILE"
        fi
    fi

    # 输出结果
    if [ "$RAW_OUTPUT" = true ]; then
        echo "$result"
    else
        output_formatted_results "$result"
    fi
}

# 格式化输出结果
# Usage: output_formatted_results "result_json"
output_formatted_results() {
    local result="$1"

    case "$OUTPUT_FORMAT" in
        json)
            echo "$result" | jq .
            ;;
        table)
            output_table_list "$result"
            ;;
        summary)
            output_summary_list "$result"
            ;;
        count)
            output_count_only "$result"
            ;;
    esac
}

# 表格格式输出
output_table_list() {
    local result="$1"
    local workitems
    workitems=$(echo "$result" | jq '.workitems // .data // []')

    if [ "$(echo "$workitems" | jq 'length')" -eq 0 ]; then
        if [ "$QUIET" = false ]; then
            echo "未找到符合条件的工作项"
        fi
        return
    fi

    # 确定要显示的字段
    local display_fields
    if [ -n "$FIELDS" ]; then
        IFS=',' read -ra display_fields <<< "$FIELDS"
    else
        display_fields=("id" "title" "type" "status" "assignee" "created_time")
    fi

    # 输出表头
    if [ "$NO_HEADER" = false ]; then
        printf "|"
        for field in "${display_fields[@]}"; do
            field=$(echo "$field" | xargs)  # 去除空格
            case "$field" in
                id) printf " %-8s |" "ID" ;;
                title) printf " %-30s |" "标题" ;;
                type) printf " %-10s |" "类型" ;;
                status) printf " %-8s |" "状态" ;;
                priority) printf " %-6s |" "优先级" ;;
                assignee) printf " %-10s |" "指派人" ;;
                creator) printf " %-10s |" "创建人" ;;
                created_time) printf " %-12s |" "创建时间" ;;
                updated_time) printf " %-12s |" "更新时间" ;;
                *) printf " %-12s |" "$field" ;;
            esac
        done
        echo ""

        # 分隔线
        printf "|"
        for field in "${display_fields[@]}"; do
            case "$field" in
                id) printf "----------|" ;;
                title) printf "--------------------------------|" ;;
                type) printf "-----------|" ;;
                status) printf "----------|" ;;
                priority) printf "--------|" ;;
                assignee) printf "-----------|" ;;
                creator) printf "-----------|" ;;
                created_time) printf "-------------|" ;;
                updated_time) printf "-------------|" ;;
                *) printf "-------------|" ;;
            esac
        done
        echo ""
    fi

    # 输出数据行
    echo "$workitems" | jq -c '.[]' | while IFS= read -r item; do
        printf "|"
        for field in "${display_fields[@]}"; do
            field=$(echo "$field" | xargs)  # 去除空格
            local value
            value=$(echo "$item" | jq -r ".$field // \"\"")

            case "$field" in
                id) printf " %-8s |" "$value" ;;
                title)
                    # 截断长标题
                    if [ ${#value} -gt 28 ]; then
                        value="${value:0:27}…"
                    fi
                    printf " %-30s |" "$value"
                    ;;
                type) printf " %-10s |" "$value" ;;
                status) printf " %-8s |" "$value" ;;
                priority) printf " %-6s |" "$value" ;;
                assignee) printf " %-10s |" "$value" ;;
                creator) printf " %-10s |" "$value" ;;
                created_time|updated_time)
                    # 格式化时间显示
                    if [ -n "$value" ] && [ "$value" != "null" ]; then
                        value=$(echo "$value" | cut -c1-10)  # 只显示日期部分
                    fi
                    printf " %-12s |" "$value"
                    ;;
                *) printf " %-12s |" "$value" ;;
            esac
        done
        echo ""
    done

    # 输出统计信息
    if [ "$QUIET" = false ]; then
        local total_count page_info
        total_count=$(echo "$result" | jq '.total_count // .total // 0')
        page_info=""

        if [ "$GET_ALL" = false ]; then
            local current_page page_size
            current_page=$(echo "$result" | jq '.page // 1')
            page_size=$(echo "$result" | jq '.page_size // 20')
            page_info=" (第 $current_page 页，每页 $page_size 个)"
        fi

        echo ""
        echo "总计: $total_count 个工作项$page_info"
    fi
}

# 摘要格式输出
output_summary_list() {
    local result="$1"
    local workitems
    workitems=$(echo "$result" | jq '.workitems // .data // []')

    echo "$workitems" | jq -c '.[]' | while IFS= read -r item; do
        local id title type status
        id=$(echo "$item" | jq -r '.id // ""')
        title=$(echo "$item" | jq -r '.title // ""')
        type=$(echo "$item" | jq -r '.type // ""')
        status=$(echo "$item" | jq -r '.status // ""')

        echo "#$id - $title [$type] ($status)"
    done
}

# 仅输出数量
output_count_only() {
    local result="$1"
    local total_count
    total_count=$(echo "$result" | jq '.total_count // .total // 0')
    echo "$total_count"
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    # 初始化环境
    init_workitem_environment

    # 解析参数
    parse_arguments "$@"

    # 获取工作项列表
    get_workitems_list
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi