#!/bin/bash

# Sync Validator for Epic-Yunxiao Sync
# 同步验证器，验证Epic-云效同步的结果，确保数据一致性和完整性

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

# 验证类型
readonly VALIDATION_TYPE_CONTENT="content"
readonly VALIDATION_TYPE_MAPPING="mapping"
readonly VALIDATION_TYPE_INTEGRITY="integrity"
readonly VALIDATION_TYPE_CONSISTENCY="consistency"

# 验证状态
readonly VALIDATION_STATUS_PASSED="passed"
readonly VALIDATION_STATUS_FAILED="failed"
readonly VALIDATION_STATUS_WARNING="warning"
readonly VALIDATION_STATUS_SKIPPED="skipped"

# 验证级别
readonly VALIDATION_LEVEL_BASIC="basic"
readonly VALIDATION_LEVEL_DETAILED="detailed"
readonly VALIDATION_LEVEL_COMPREHENSIVE="comprehensive"

# 验证文件
readonly VALIDATION_DIR=".claude/sync-status/validation"
readonly VALIDATION_REPORT="$VALIDATION_DIR/validation-report.json"
readonly VALIDATION_LOG="$VALIDATION_DIR/validation.log"

# =============================================================================
# 验证器初始化
# =============================================================================

# 初始化验证器
# Usage: init_sync_validator
# Returns: 0 on success, 1 on failure
init_sync_validator() {
    log_yunxiao_debug "初始化同步验证器"

    # 创建验证目录
    mkdir -p "$VALIDATION_DIR"

    # 初始化验证报告
    create_validation_report_template

    # 清理旧的验证日志
    : > "$VALIDATION_LOG"

    log_yunxiao_debug "同步验证器初始化完成"
    return 0
}

# 创建验证报告模板
# Usage: create_validation_report_template
create_validation_report_template() {
    local current_time
    current_time=$(get_current_timestamp)

    cat > "$VALIDATION_REPORT" << EOF
{
  "validation_id": "validation-$(date +%Y%m%d-%H%M%S)-$$",
  "start_time": "$current_time",
  "end_time": null,
  "status": "running",
  "level": null,
  "summary": {
    "total_checks": 0,
    "passed": 0,
    "failed": 0,
    "warnings": 0,
    "skipped": 0
  },
  "validations": {
    "$VALIDATION_TYPE_CONTENT": [],
    "$VALIDATION_TYPE_MAPPING": [],
    "$VALIDATION_TYPE_INTEGRITY": [],
    "$VALIDATION_TYPE_CONSISTENCY": []
  },
  "errors": [],
  "recommendations": []
}
EOF

    log_yunxiao_debug "验证报告模板已创建"
}

# =============================================================================
# 主要验证函数
# =============================================================================

# 验证同步结果
# Usage: validate_sync_results "epic_name" ["validation_level"]
# Returns: 0 if validation passed, 1 if failed
validate_sync_results() {
    local epic_name="$1"
    local validation_level="${2:-$VALIDATION_LEVEL_BASIC}"

    log_yunxiao_info "开始验证同步结果: $epic_name (级别: $validation_level)"

    # 初始化验证器
    init_sync_validator || return 1

    # 设置验证级别
    update_validation_report ".level = \"$validation_level\""

    local validation_result=0

    # 根据验证级别执行不同的验证
    case "$validation_level" in
        "$VALIDATION_LEVEL_BASIC")
            validate_basic_sync "$epic_name" || validation_result=1
            ;;
        "$VALIDATION_LEVEL_DETAILED")
            validate_basic_sync "$epic_name" || validation_result=1
            validate_detailed_sync "$epic_name" || validation_result=1
            ;;
        "$VALIDATION_LEVEL_COMPREHENSIVE")
            validate_basic_sync "$epic_name" || validation_result=1
            validate_detailed_sync "$epic_name" || validation_result=1
            validate_comprehensive_sync "$epic_name" || validation_result=1
            ;;
        *)
            log_yunxiao_error "不支持的验证级别: $validation_level"
            validation_result=1
            ;;
    esac

    # 完成验证
    finalize_validation_report "$validation_result"

    # 生成验证摘要
    show_validation_summary

    if [ $validation_result -eq 0 ]; then
        log_yunxiao_success "同步验证通过"
    else
        log_yunxiao_error "同步验证失败"
    fi

    return $validation_result
}

# =============================================================================
# 基础验证
# =============================================================================

# 基础同步验证
# Usage: validate_basic_sync "epic_name"
validate_basic_sync() {
    local epic_name="$1"

    log_yunxiao_info "执行基础验证"

    local validation_failed=0

    # 验证映射完整性
    validate_mapping_integrity "$epic_name" || validation_failed=1

    # 验证文件存在性
    validate_file_existence "$epic_name" || validation_failed=1

    # 验证基本数据一致性
    validate_basic_consistency "$epic_name" || validation_failed=1

    log_yunxiao_info "基础验证完成"
    return $validation_failed
}

# 验证映射完整性
# Usage: validate_mapping_integrity "epic_name"
validate_mapping_integrity() {
    local epic_name="$1"

    log_validation "开始验证映射完整性: $epic_name"

    local validation_passed=0
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ ! -f "$mapping_file" ]; then
        record_validation_result \
            "$VALIDATION_TYPE_MAPPING" \
            "mapping_file_missing" \
            "$VALIDATION_STATUS_FAILED" \
            "映射文件不存在: $mapping_file"
        return 1
    fi

    # 检查映射文件格式
    if ! jq empty "$mapping_file" >/dev/null 2>&1; then
        record_validation_result \
            "$VALIDATION_TYPE_MAPPING" \
            "mapping_file_invalid" \
            "$VALIDATION_STATUS_FAILED" \
            "映射文件格式无效"
        return 1
    fi

    # 验证Epic映射
    local epic_mappings
    epic_mappings=$(get_epic_mappings "$epic_name")

    if [ -z "$epic_mappings" ] || [ "$epic_mappings" = "[]" ]; then
        record_validation_result \
            "$VALIDATION_TYPE_MAPPING" \
            "epic_mapping_missing" \
            "$VALIDATION_STATUS_WARNING" \
            "Epic没有映射关系: $epic_name"
        validation_passed=1
    else
        record_validation_result \
            "$VALIDATION_TYPE_MAPPING" \
            "epic_mapping_exists" \
            "$VALIDATION_STATUS_PASSED" \
            "Epic映射关系正常"
    fi

    # 验证映射的本地文件存在性
    jq -r ".mappings | to_entries[] | select(.value.local_path | startswith(\".claude/epics/$epic_name/\")) | .value.local_path" "$mapping_file" | \
    while read -r local_path; do
        if [ ! -f "$local_path" ]; then
            record_validation_result \
                "$VALIDATION_TYPE_MAPPING" \
                "mapped_file_missing" \
                "$VALIDATION_STATUS_FAILED" \
                "映射的本地文件不存在: $local_path"
            validation_passed=1
        fi
    done

    log_validation "映射完整性验证完成"
    return $validation_passed
}

# 验证文件存在性
# Usage: validate_file_existence "epic_name"
validate_file_existence() {
    local epic_name="$1"

    log_validation "开始验证文件存在性: $epic_name"

    local validation_passed=0
    local epic_dir=".claude/epics/$epic_name"
    local epic_file="$epic_dir/epic.md"

    # 检查Epic目录
    if [ ! -d "$epic_dir" ]; then
        record_validation_result \
            "$VALIDATION_TYPE_INTEGRITY" \
            "epic_directory_missing" \
            "$VALIDATION_STATUS_FAILED" \
            "Epic目录不存在: $epic_dir"
        return 1
    fi

    # 检查Epic文件
    if [ ! -f "$epic_file" ]; then
        record_validation_result \
            "$VALIDATION_TYPE_INTEGRITY" \
            "epic_file_missing" \
            "$VALIDATION_STATUS_FAILED" \
            "Epic文件不存在: $epic_file"
        validation_passed=1
    else
        # 验证Epic文件格式
        if validate_frontmatter "$epic_file" "name" "status"; then
            record_validation_result \
                "$VALIDATION_TYPE_INTEGRITY" \
                "epic_file_valid" \
                "$VALIDATION_STATUS_PASSED" \
                "Epic文件格式正确"
        else
            record_validation_result \
                "$VALIDATION_TYPE_INTEGRITY" \
                "epic_file_invalid" \
                "$VALIDATION_STATUS_FAILED" \
                "Epic文件格式无效"
            validation_passed=1
        fi
    fi

    # 检查任务文件
    find "$epic_dir" -name "*.md" -type f ! -name "epic.md" | while read -r task_file; do
        if validate_frontmatter "$task_file" "name" "status"; then
            record_validation_result \
                "$VALIDATION_TYPE_INTEGRITY" \
                "task_file_valid" \
                "$VALIDATION_STATUS_PASSED" \
                "任务文件格式正确: $(basename "$task_file")"
        else
            record_validation_result \
                "$VALIDATION_TYPE_INTEGRITY" \
                "task_file_invalid" \
                "$VALIDATION_STATUS_FAILED" \
                "任务文件格式无效: $(basename "$task_file")"
            validation_passed=1
        fi
    done

    log_validation "文件存在性验证完成"
    return $validation_passed
}

# 验证基本数据一致性
# Usage: validate_basic_consistency "epic_name"
validate_basic_consistency() {
    local epic_name="$1"

    log_validation "开始验证基本数据一致性: $epic_name"

    local validation_passed=0
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ ! -f "$mapping_file" ]; then
        return 0  # 已在映射验证中处理
    fi

    # 验证每个映射的数据一致性
    jq -r ".mappings | to_entries[] | select(.value.local_path | startswith(\".claude/epics/$epic_name/\")) | \"\(.key)|\(.value.local_path)|\(.value.yunxiao_workitem_id)\"" "$mapping_file" | \
    while IFS='|' read -r local_id local_path yunxiao_id; do
        if [ -f "$local_path" ] && [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
            validate_single_item_consistency "$local_id" "$local_path" "$yunxiao_id" || validation_passed=1
        fi
    done

    log_validation "基本数据一致性验证完成"
    return $validation_passed
}

# 验证单个项目的一致性
# Usage: validate_single_item_consistency "local_id" "local_path" "yunxiao_id"
validate_single_item_consistency() {
    local local_id="$1"
    local local_path="$2"
    local yunxiao_id="$3"

    log_validation "验证项目一致性: $local_id"

    # 检查本地文件中的yunxiao_id
    local file_yunxiao_id
    file_yunxiao_id=$(get_frontmatter_field "$local_path" "yunxiao_id")

    if [ -n "$file_yunxiao_id" ] && [ "$file_yunxiao_id" != "null" ] && [ "$file_yunxiao_id" != "$yunxiao_id" ]; then
        record_validation_result \
            "$VALIDATION_TYPE_CONSISTENCY" \
            "yunxiao_id_mismatch" \
            "$VALIDATION_STATUS_FAILED" \
            "本地文件中的yunxiao_id ($file_yunxiao_id) 与映射不符 ($yunxiao_id): $local_path"
        return 1
    fi

    # 尝试获取云效工作项验证存在性
    local remote_data
    if remote_data=$(yunxiao_get_workitem "$yunxiao_id" 2>/dev/null); then
        record_validation_result \
            "$VALIDATION_TYPE_CONSISTENCY" \
            "remote_workitem_exists" \
            "$VALIDATION_STATUS_PASSED" \
            "云效工作项存在: $yunxiao_id"
    else
        record_validation_result \
            "$VALIDATION_TYPE_CONSISTENCY" \
            "remote_workitem_missing" \
            "$VALIDATION_STATUS_WARNING" \
            "无法访问云效工作项或工作项不存在: $yunxiao_id"
        return 1
    fi

    return 0
}

# =============================================================================
# 详细验证
# =============================================================================

# 详细同步验证
# Usage: validate_detailed_sync "epic_name"
validate_detailed_sync() {
    local epic_name="$1"

    log_yunxiao_info "执行详细验证"

    local validation_failed=0

    # 验证内容一致性
    validate_content_consistency "$epic_name" || validation_failed=1

    # 验证状态一致性
    validate_status_consistency "$epic_name" || validation_failed=1

    # 验证时间戳一致性
    validate_timestamp_consistency "$epic_name" || validation_failed=1

    log_yunxiao_info "详细验证完成"
    return $validation_failed
}

# 验证内容一致性
# Usage: validate_content_consistency "epic_name"
validate_content_consistency() {
    local epic_name="$1"

    log_validation "开始验证内容一致性: $epic_name"

    local validation_passed=0
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ ! -f "$mapping_file" ]; then
        return 0
    fi

    # 验证每个映射项目的内容一致性
    jq -r ".mappings | to_entries[] | select(.value.local_path | startswith(\".claude/epics/$epic_name/\")) | \"\(.key)|\(.value.local_path)|\(.value.yunxiao_workitem_id)\"" "$mapping_file" | \
    while IFS='|' read -r local_id local_path yunxiao_id; do
        if [ -f "$local_path" ] && [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
            validate_item_content_consistency "$local_id" "$local_path" "$yunxiao_id" || validation_passed=1
        fi
    done

    log_validation "内容一致性验证完成"
    return $validation_passed
}

# 验证单个项目的内容一致性
# Usage: validate_item_content_consistency "local_id" "local_path" "yunxiao_id"
validate_item_content_consistency() {
    local local_id="$1"
    local local_path="$2"
    local yunxiao_id="$3"

    # 获取云效工作项数据
    local remote_data
    if ! remote_data=$(yunxiao_get_workitem "$yunxiao_id" 2>/dev/null); then
        record_validation_result \
            "$VALIDATION_TYPE_CONTENT" \
            "remote_data_unavailable" \
            "$VALIDATION_STATUS_SKIPPED" \
            "无法获取云效工作项数据: $yunxiao_id"
        return 1
    fi

    # 比较标题
    local local_title remote_title
    local_title=$(get_frontmatter_field "$local_path" "name")
    remote_title=$(get_workitem_field "$remote_data" "title")

    if [ "$local_title" != "$remote_title" ]; then
        record_validation_result \
            "$VALIDATION_TYPE_CONTENT" \
            "title_mismatch" \
            "$VALIDATION_STATUS_WARNING" \
            "标题不一致: 本地='$local_title', 远程='$remote_title'"
    else
        record_validation_result \
            "$VALIDATION_TYPE_CONTENT" \
            "title_consistent" \
            "$VALIDATION_STATUS_PASSED" \
            "标题一致"
    fi

    # 比较状态
    local local_status remote_status mapped_remote_status
    local_status=$(get_frontmatter_field "$local_path" "status")
    remote_status=$(get_workitem_field "$remote_data" "status")
    mapped_remote_status="${REMOTE_STATUS_MAPPING[$remote_status]:-$remote_status}"

    if [ "$local_status" != "$mapped_remote_status" ]; then
        record_validation_result \
            "$VALIDATION_TYPE_CONTENT" \
            "status_mismatch" \
            "$VALIDATION_STATUS_WARNING" \
            "状态不一致: 本地='$local_status', 远程='$mapped_remote_status'"
    else
        record_validation_result \
            "$VALIDATION_TYPE_CONTENT" \
            "status_consistent" \
            "$VALIDATION_STATUS_PASSED" \
            "状态一致"
    fi

    return 0
}

# 验证状态一致性
# Usage: validate_status_consistency "epic_name"
validate_status_consistency() {
    local epic_name="$1"

    log_validation "开始验证状态一致性: $epic_name"

    # 状态一致性在内容验证中已经处理
    record_validation_result \
        "$VALIDATION_TYPE_CONSISTENCY" \
        "status_validation_completed" \
        "$VALIDATION_STATUS_PASSED" \
        "状态一致性验证已在内容验证中完成"

    return 0
}

# 验证时间戳一致性
# Usage: validate_timestamp_consistency "epic_name"
validate_timestamp_consistency() {
    local epic_name="$1"

    log_validation "开始验证时间戳一致性: $epic_name"

    local validation_passed=0
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ ! -f "$mapping_file" ]; then
        return 0
    fi

    # 验证时间戳的合理性
    jq -r ".mappings | to_entries[] | select(.value.local_path | startswith(\".claude/epics/$epic_name/\")) | \"\(.key)|\(.value.local_path)|\(.value.last_sync)\"" "$mapping_file" | \
    while IFS='|' read -r local_id local_path last_sync; do
        if [ -f "$local_path" ]; then
            validate_item_timestamps "$local_id" "$local_path" "$last_sync" || validation_passed=1
        fi
    done

    log_validation "时间戳一致性验证完成"
    return $validation_passed
}

# 验证单个项目的时间戳
# Usage: validate_item_timestamps "local_id" "local_path" "last_sync"
validate_item_timestamps() {
    local local_id="$1"
    local local_path="$2"
    local last_sync="$3"

    # 获取文件的更新时间
    local file_updated
    file_updated=$(get_frontmatter_field "$local_path" "updated")

    # 检查时间戳格式
    if [ -n "$file_updated" ] && [ "$file_updated" != "null" ]; then
        if date -d "$file_updated" >/dev/null 2>&1; then
            record_validation_result \
                "$VALIDATION_TYPE_CONSISTENCY" \
                "timestamp_format_valid" \
                "$VALIDATION_STATUS_PASSED" \
                "时间戳格式正确: $local_id"
        else
            record_validation_result \
                "$VALIDATION_TYPE_CONSISTENCY" \
                "timestamp_format_invalid" \
                "$VALIDATION_STATUS_FAILED" \
                "时间戳格式无效: $local_id ($file_updated)"
            return 1
        fi
    fi

    # 检查同步时间戳
    if [ -n "$last_sync" ] && [ "$last_sync" != "null" ]; then
        if date -d "$last_sync" >/dev/null 2>&1; then
            record_validation_result \
                "$VALIDATION_TYPE_CONSISTENCY" \
                "sync_timestamp_valid" \
                "$VALIDATION_STATUS_PASSED" \
                "同步时间戳正确: $local_id"
        else
            record_validation_result \
                "$VALIDATION_TYPE_CONSISTENCY" \
                "sync_timestamp_invalid" \
                "$VALIDATION_STATUS_WARNING" \
                "同步时间戳无效: $local_id ($last_sync)"
            return 1
        fi
    fi

    return 0
}

# =============================================================================
# 综合验证
# =============================================================================

# 综合同步验证
# Usage: validate_comprehensive_sync "epic_name"
validate_comprehensive_sync() {
    local epic_name="$1"

    log_yunxiao_info "执行综合验证"

    local validation_failed=0

    # 验证关联关系
    validate_relationship_integrity "$epic_name" || validation_failed=1

    # 验证业务逻辑
    validate_business_logic "$epic_name" || validation_failed=1

    # 验证性能指标
    validate_performance_metrics "$epic_name" || validation_failed=1

    log_yunxiao_info "综合验证完成"
    return $validation_failed
}

# 验证关联关系完整性
# Usage: validate_relationship_integrity "epic_name"
validate_relationship_integrity() {
    local epic_name="$1"

    log_validation "开始验证关联关系完整性: $epic_name"

    local validation_passed=0
    local epic_dir=".claude/epics/$epic_name"

    # 检查Epic与任务的关联关系
    find "$epic_dir" -name "*.md" -type f ! -name "epic.md" | while read -r task_file; do
        # 检查任务是否有正确的Epic关联
        local task_epic_reference
        task_epic_reference=$(dirname "$task_file")

        if [ "$(basename "$task_epic_reference")" = "$epic_name" ]; then
            record_validation_result \
                "$VALIDATION_TYPE_INTEGRITY" \
                "task_epic_relationship_valid" \
                "$VALIDATION_STATUS_PASSED" \
                "任务与Epic关联关系正确: $(basename "$task_file")"
        else
            record_validation_result \
                "$VALIDATION_TYPE_INTEGRITY" \
                "task_epic_relationship_invalid" \
                "$VALIDATION_STATUS_FAILED" \
                "任务与Epic关联关系错误: $(basename "$task_file")"
            validation_passed=1
        fi
    done

    log_validation "关联关系完整性验证完成"
    return $validation_passed
}

# 验证业务逻辑
# Usage: validate_business_logic "epic_name"
validate_business_logic() {
    local epic_name="$1"

    log_validation "开始验证业务逻辑: $epic_name"

    local validation_passed=0
    local epic_file=".claude/epics/$epic_name/epic.md"

    if [ -f "$epic_file" ]; then
        # 验证Epic状态逻辑
        local epic_status
        epic_status=$(get_frontmatter_field "$epic_file" "status")

        case "$epic_status" in
            "completed"|"closed")
                # 检查是否有未完成的任务
                local incomplete_tasks
                incomplete_tasks=$(find ".claude/epics/$epic_name" -name "*.md" -type f ! -name "epic.md" -exec grep -l "status: open\|status: in_progress" {} \; 2>/dev/null | wc -l)

                if [ "$incomplete_tasks" -gt 0 ]; then
                    record_validation_result \
                        "$VALIDATION_TYPE_CONSISTENCY" \
                        "epic_status_logic_invalid" \
                        "$VALIDATION_STATUS_WARNING" \
                        "Epic已完成但仍有未完成的任务: $incomplete_tasks 个"
                    validation_passed=1
                else
                    record_validation_result \
                        "$VALIDATION_TYPE_CONSISTENCY" \
                        "epic_status_logic_valid" \
                        "$VALIDATION_STATUS_PASSED" \
                        "Epic状态逻辑正确"
                fi
                ;;
            *)
                record_validation_result \
                    "$VALIDATION_TYPE_CONSISTENCY" \
                    "epic_status_normal" \
                    "$VALIDATION_STATUS_PASSED" \
                    "Epic状态正常"
                ;;
        esac
    fi

    log_validation "业务逻辑验证完成"
    return $validation_passed
}

# 验证性能指标
# Usage: validate_performance_metrics "epic_name"
validate_performance_metrics() {
    local epic_name="$1"

    log_validation "开始验证性能指标: $epic_name"

    # 计算同步相关的性能指标
    local epic_dir=".claude/epics/$epic_name"
    local total_files
    total_files=$(find "$epic_dir" -name "*.md" -type f | wc -l)

    local mapping_file=".claude/sync-status/yunxiao-mappings.json"
    local mapped_files
    mapped_files=$(jq "[.mappings | to_entries[] | select(.value.local_path | startswith(\"$epic_dir/\"))] | length" "$mapping_file" 2>/dev/null || echo "0")

    # 检查映射覆盖率
    local coverage_percentage
    if [ "$total_files" -gt 0 ]; then
        coverage_percentage=$((mapped_files * 100 / total_files))
    else
        coverage_percentage=100
    fi

    if [ "$coverage_percentage" -ge 80 ]; then
        record_validation_result \
            "$VALIDATION_TYPE_INTEGRITY" \
            "mapping_coverage_good" \
            "$VALIDATION_STATUS_PASSED" \
            "映射覆盖率良好: $coverage_percentage% ($mapped_files/$total_files)"
    elif [ "$coverage_percentage" -ge 50 ]; then
        record_validation_result \
            "$VALIDATION_TYPE_INTEGRITY" \
            "mapping_coverage_moderate" \
            "$VALIDATION_STATUS_WARNING" \
            "映射覆盖率中等: $coverage_percentage% ($mapped_files/$total_files)"
    else
        record_validation_result \
            "$VALIDATION_TYPE_INTEGRITY" \
            "mapping_coverage_low" \
            "$VALIDATION_STATUS_FAILED" \
            "映射覆盖率过低: $coverage_percentage% ($mapped_files/$total_files)"
    fi

    log_validation "性能指标验证完成"
    return 0
}

# =============================================================================
# 验证结果管理
# =============================================================================

# 记录验证结果
# Usage: record_validation_result "type" "check_id" "status" "message" ["details"]
record_validation_result() {
    local type="$1"
    local check_id="$2"
    local status="$3"
    local message="$4"
    local details="${5:-}"

    local current_time
    current_time=$(get_current_timestamp)

    # 构建验证结果条目
    local result_entry
    result_entry=$(jq -n \
        --arg check_id "$check_id" \
        --arg status "$status" \
        --arg message "$message" \
        --arg details "$details" \
        --arg timestamp "$current_time" \
        '{
            check_id: $check_id,
            status: $status,
            message: $message,
            details: $details,
            timestamp: $timestamp
        }')

    # 添加到验证报告
    local temp_file
    temp_file=$(mktemp)

    jq \
        --arg type "$type" \
        --argjson result "$result_entry" \
        '.validations[$type] += [$result] |
         .summary.total_checks += 1 |
         if $result.status == "passed" then .summary.passed += 1
         elif $result.status == "failed" then .summary.failed += 1
         elif $result.status == "warning" then .summary.warnings += 1
         else .summary.skipped += 1 end' \
        "$VALIDATION_REPORT" > "$temp_file"

    mv "$temp_file" "$VALIDATION_REPORT"

    # 记录到日志
    log_validation "[$status] $check_id: $message"

    # 根据状态输出到控制台
    case "$status" in
        "$VALIDATION_STATUS_PASSED")
            log_yunxiao_debug "验证通过: $message"
            ;;
        "$VALIDATION_STATUS_WARNING")
            log_yunxiao_warning "验证警告: $message"
            ;;
        "$VALIDATION_STATUS_FAILED")
            log_yunxiao_error "验证失败: $message"
            ;;
        "$VALIDATION_STATUS_SKIPPED")
            log_yunxiao_debug "验证跳过: $message"
            ;;
    esac
}

# 完成验证报告
# Usage: finalize_validation_report "overall_result"
finalize_validation_report() {
    local overall_result="$1"

    local current_time
    current_time=$(get_current_timestamp)

    local overall_status
    if [ "$overall_result" -eq 0 ]; then
        overall_status="passed"
    else
        overall_status="failed"
    fi

    update_validation_report \
        ".end_time = \"$current_time\"" \
        ".status = \"$overall_status\""

    log_validation "验证报告已完成，总体状态: $overall_status"
}

# 更新验证报告
# Usage: update_validation_report "jq_expression1" ["jq_expression2" ...]
update_validation_report() {
    local expressions=("$@")

    if [ ! -f "$VALIDATION_REPORT" ]; then
        log_yunxiao_error "验证报告文件不存在"
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
    jq "$jq_expression" "$VALIDATION_REPORT" > "$temp_file"

    if [ $? -eq 0 ]; then
        mv "$temp_file" "$VALIDATION_REPORT"
    else
        rm -f "$temp_file"
        log_yunxiao_error "更新验证报告失败"
        return 1
    fi
}

# =============================================================================
# 验证报告和显示
# =============================================================================

# 显示验证摘要
# Usage: show_validation_summary
show_validation_summary() {
    if [ ! -f "$VALIDATION_REPORT" ]; then
        log_yunxiao_info "没有验证报告"
        return 1
    fi

    local report_data
    report_data=$(cat "$VALIDATION_REPORT")

    local validation_id status level
    validation_id=$(echo "$report_data" | jq -r '.validation_id')
    status=$(echo "$report_data" | jq -r '.status')
    level=$(echo "$report_data" | jq -r '.level')

    echo "=== 验证摘要 ==="
    echo "验证ID: $validation_id"
    echo "状态: $status"
    echo "级别: $level"

    # 显示统计信息
    echo ""
    echo "=== 验证统计 ==="
    echo "$report_data" | jq -r '
        .summary |
        "总检查项: \(.total_checks)",
        "通过: \(.passed)",
        "失败: \(.failed)",
        "警告: \(.warnings)",
        "跳过: \(.skipped)"
    '

    # 显示时间信息
    local start_time end_time
    start_time=$(echo "$report_data" | jq -r '.start_time')
    end_time=$(echo "$report_data" | jq -r '.end_time // "进行中"')

    echo ""
    echo "=== 时间信息 ==="
    echo "开始时间: $start_time"
    echo "结束时间: $end_time"

    echo "=================="
}

# 显示详细验证报告
# Usage: show_detailed_validation_report
show_detailed_validation_report() {
    if [ ! -f "$VALIDATION_REPORT" ]; then
        log_yunxiao_info "没有验证报告"
        return 1
    fi

    local report_data
    report_data=$(cat "$VALIDATION_REPORT")

    # 显示摘要
    show_validation_summary

    # 显示各类型的验证结果
    for validation_type in "$VALIDATION_TYPE_CONTENT" "$VALIDATION_TYPE_MAPPING" "$VALIDATION_TYPE_INTEGRITY" "$VALIDATION_TYPE_CONSISTENCY"; do
        local type_results
        type_results=$(echo "$report_data" | jq ".validations[\"$validation_type\"]")

        local result_count
        result_count=$(echo "$type_results" | jq 'length')

        if [ "$result_count" -gt 0 ]; then
            echo ""
            echo "=== $validation_type 验证结果 ==="
            echo "$type_results" | jq -r '.[] | "[\(.status)] \(.check_id): \(.message)"'
        fi
    done

    # 显示错误和建议
    local error_count
    error_count=$(echo "$report_data" | jq '.errors | length')

    if [ "$error_count" -gt 0 ]; then
        echo ""
        echo "=== 错误详情 ==="
        echo "$report_data" | jq -r '.errors[] | "- \(.)"'
    fi

    local recommendation_count
    recommendation_count=$(echo "$report_data" | jq '.recommendations | length')

    if [ "$recommendation_count" -gt 0 ]; then
        echo ""
        echo "=== 建议 ==="
        echo "$report_data" | jq -r '.recommendations[] | "- \(.)"'
    fi
}

# =============================================================================
# 工具函数
# =============================================================================

# 记录验证日志
# Usage: log_validation "message"
log_validation() {
    local message="$1"
    local timestamp
    timestamp=$(get_current_timestamp)

    echo "[$timestamp] $message" >> "$VALIDATION_LOG"
}

# 获取当前时间戳
# Usage: get_current_timestamp
get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# =============================================================================
# 主程序入口（用于测试）
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # 如果脚本被直接执行，提供测试功能
    case "${1:-help}" in
        "validate")
            validate_sync_results "$2" "${3:-basic}"
            ;;
        "summary")
            show_validation_summary
            ;;
        "detail"|"detailed")
            show_detailed_validation_report
            ;;
        "init")
            init_sync_validator
            ;;
        "help"|*)
            cat << EOF
同步验证器工具

用法: $0 <命令> [参数...]

命令:
  validate <epic_name> [level]  执行同步验证
  summary                       显示验证摘要
  detail                        显示详细验证报告
  init                         初始化验证器
  help                         显示此帮助信息

验证级别:
  basic                        基础验证（默认）
  detailed                     详细验证
  comprehensive                综合验证

示例:
  $0 validate my-epic basic     基础验证指定Epic
  $0 validate my-epic detailed  详细验证指定Epic
  $0 summary                    查看验证摘要
  $0 detail                     查看详细报告
EOF
            ;;
    esac
fi