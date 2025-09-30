#!/bin/bash

# 云效工作项获取脚本
# 获取单个或多个工作项的详细信息

# 获取脚本目录并引入通用函数
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/workitem-common.sh"

# =============================================================================
# 脚本帮助信息
# =============================================================================

show_help() {
    cat << EOF
云效工作项查询工具

用法:
    $0 [选项] <工作项ID> [工作项ID2] [工作项ID3] ...

参数:
    工作项ID    要查询的工作项ID（数字），支持多个

选项:
    -o, --output FORMAT     输出格式 (json|table|summary|detail) [默认: detail]
    -f, --fields FIELDS     指定输出字段 (用逗号分隔)
    -c, --cache             使用缓存结果（如果可用）
    --no-format             原始输出，不进行格式化
    --batch                 批量模式（从标准输入读取ID）
    -v, --verbose           详细输出
    -h, --help              显示此帮助信息

输出格式:
    json     完整JSON格式
    table    表格格式
    summary  摘要格式
    detail   详细格式（默认）

字段选项（用于 --fields）:
    id, title, type, status, priority, assignee, creator,
    created_time, updated_time, description

示例:
    # 查询单个工作项
    $0 12345

    # 查询多个工作项
    $0 12345 12346 12347

    # 以JSON格式输出
    $0 -o json 12345

    # 只显示特定字段
    $0 -f "id,title,status" 12345

    # 批量查询（从文件读取ID）
    cat workitem_ids.txt | $0 --batch

    # 详细输出
    $0 -v 12345

EOF
}

# =============================================================================
# 参数解析
# =============================================================================

parse_arguments() {
    local TEMP
    TEMP=$(getopt -o 'o:f:cvh' --long 'output:,fields:,cache,no-format,batch,verbose,help' -n "$0" -- "$@")

    if [ $? -ne 0 ]; then
        echo "参数解析失败，使用 --help 查看用法" >&2
        exit 1
    fi

    eval set -- "$TEMP"
    unset TEMP

    # 默认值
    OUTPUT_FORMAT="detail"
    FIELDS=""
    USE_CACHE=false
    NO_FORMAT=false
    BATCH_MODE=false
    VERBOSE=false

    while true; do
        case "$1" in
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
            '-c'|'--cache')
                USE_CACHE=true
                shift
                continue
                ;;
            '--no-format')
                NO_FORMAT=true
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
        json|table|summary|detail)
            ;;
        *)
            error_exit "不支持的输出格式: $OUTPUT_FORMAT"
            ;;
    esac

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
}

# =============================================================================
# 缓存处理
# =============================================================================

# 获取缓存文件路径
# Usage: get_cache_file "workitem_id"
get_cache_file() {
    local workitem_id="$1"
    echo "/tmp/yunxiao_workitem_${workitem_id}.cache"
}

# 检查缓存是否有效
# Usage: is_cache_valid "cache_file"
is_cache_valid() {
    local cache_file="$1"
    local cache_ttl=300  # 5分钟

    if [ ! -f "$cache_file" ]; then
        return 1
    fi

    local cache_age
    cache_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null || echo 0) ))

    [ $cache_age -lt $cache_ttl ]
}

# 从缓存读取工作项
# Usage: read_from_cache "workitem_id"
read_from_cache() {
    local workitem_id="$1"
    local cache_file
    cache_file=$(get_cache_file "$workitem_id")

    if [ "$USE_CACHE" = true ] && is_cache_valid "$cache_file"; then
        log_yunxiao_debug "从缓存读取工作项 #$workitem_id"
        cat "$cache_file"
        return 0
    fi

    return 1
}

# 写入缓存
# Usage: write_to_cache "workitem_id" "data"
write_to_cache() {
    local workitem_id="$1"
    local data="$2"
    local cache_file
    cache_file=$(get_cache_file "$workitem_id")

    echo "$data" > "$cache_file" 2>/dev/null || true
}

# =============================================================================
# 工作项获取逻辑
# =============================================================================

# 获取单个工作项
# Usage: get_single_workitem "workitem_id"
get_single_workitem() {
    local workitem_id="$1"
    local result

    if [ "$VERBOSE" = true ]; then
        log_yunxiao_info "获取工作项 #$workitem_id"
    fi

    # 尝试从缓存读取
    if result=$(read_from_cache "$workitem_id"); then
        log_yunxiao_debug "缓存命中: 工作项 #$workitem_id"
    else
        # 从API获取
        log_yunxiao_debug "从API获取工作项 #$workitem_id"

        if result=$(yunxiao_retry_call yunxiao_get_workitem "$workitem_id"); then
            # 写入缓存
            write_to_cache "$workitem_id" "$result"
        else
            log_yunxiao_error "获取工作项 #$workitem_id 失败"
            return 1
        fi
    fi

    # 输出结果
    if [ "$NO_FORMAT" = true ]; then
        echo "$result"
    else
        output_workitem_result "$result"
    fi

    return 0
}

# 批量获取工作项
# Usage: get_multiple_workitems
get_multiple_workitems() {
    local -a workitem_ids

    if [ "$BATCH_MODE" = true ]; then
        # 从标准输入读取
        log_yunxiao_info "批量模式：请输入工作项ID（每行一个），按Ctrl+D结束"

        while IFS= read -r line; do
            # 跳过空行和注释
            if [ -z "$line" ] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi

            # 验证ID格式
            if validate_workitem_id "$line"; then
                workitem_ids+=("$line")
            else
                log_yunxiao_warning "忽略无效ID: $line"
            fi
        done
    else
        workitem_ids=("${WORKITEM_IDS[@]}")
    fi

    if [ ${#workitem_ids[@]} -eq 0 ]; then
        log_yunxiao_warning "没有有效的工作项ID"
        return 1
    fi

    local total=${#workitem_ids[@]}
    local success_count=0
    local fail_count=0

    log_yunxiao_info "开始获取 $total 个工作项"

    for i in "${!workitem_ids[@]}"; do
        local workitem_id="${workitem_ids[$i]}"
        local progress=$((i + 1))

        if [ $total -gt 1 ]; then
            echo "=== [$progress/$total] 工作项 #$workitem_id ==="
        fi

        if get_single_workitem "$workitem_id"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi

        # 多个工作项之间添加分隔
        if [ $total -gt 1 ] && [ $i -lt $((total - 1)) ]; then
            echo ""
        fi

        # 添加延迟避免API限流
        if [ $total -gt 1 ]; then
            sleep 0.1
        fi
    done

    if [ $total -gt 1 ]; then
        log_yunxiao_info "批量获取完成: 成功 $success_count，失败 $fail_count"
    fi

    [ $fail_count -eq 0 ]
}

# =============================================================================
# 输出格式化
# =============================================================================

# 输出工作项结果
# Usage: output_workitem_result "result_json"
output_workitem_result() {
    local result="$1"

    if [ -z "$result" ]; then
        log_yunxiao_error "无工作项数据"
        return 1
    fi

    # 如果指定了字段过滤
    if [ -n "$FIELDS" ]; then
        result=$(filter_fields "$result" "$FIELDS")
    fi

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
        detail)
            output_detail_format "$result"
            ;;
    esac
}

# 字段过滤
# Usage: filter_fields "json" "field1,field2,field3"
filter_fields() {
    local json="$1"
    local fields="$2"

    # 将逗号分隔的字段转换为jq查询
    local jq_query="{"
    local first=true

    IFS=',' read -ra FIELD_ARRAY <<< "$fields"
    for field in "${FIELD_ARRAY[@]}"; do
        field=$(echo "$field" | xargs)  # 去除空格

        if [ "$first" = true ]; then
            first=false
        else
            jq_query+=", "
        fi

        jq_query+="\"$field\": .workitem.$field"
    done

    jq_query+="}"

    echo "$json" | jq "$jq_query"
}

# 表格格式输出
output_table_format() {
    local result="$1"

    echo "| 字段         | 值                                  |"
    echo "|--------------|-------------------------------------|"

    local fields=("id" "title" "type" "status" "priority" "assignee" "creator" "created_time")

    for field in "${fields[@]}"; do
        local value
        value=$(get_workitem_field "$result" "$field")
        [ -z "$value" ] && value="N/A"

        # 截断长字段
        if [ ${#value} -gt 30 ]; then
            value="${value:0:27}..."
        fi

        printf "| %-12s | %-35s |\n" "$field" "$value"
    done
}

# 摘要格式输出
output_summary_format() {
    local result="$1"

    local id title type status
    id=$(get_workitem_field "$result" "id")
    title=$(get_workitem_field "$result" "title")
    type=$(get_workitem_field "$result" "type")
    status=$(get_workitem_field "$result" "status")

    echo "#$id - $title [$type] ($status)"
}

# 详细格式输出
output_detail_format() {
    local result="$1"

    format_workitem_display "$result"

    local description
    description=$(get_workitem_field "$result" "description")
    if [ -n "$description" ]; then
        echo "描述:"
        echo "$description" | fold -w 70 -s | sed 's/^/  /'
        echo ""
    fi

    if [ "$VERBOSE" = true ]; then
        echo "原始数据:"
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

    # 执行获取操作
    get_multiple_workitems
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi