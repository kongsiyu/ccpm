#!/bin/bash

# Conflict Resolver for Epic-Yunxiao Sync
# 冲突解决器，检测和解决本地Epic与云效工作项之间的同步冲突

# 获取脚本目录并引入依赖库
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")/lib"

# 引入必要的库
source "$LIB_DIR/error.sh"
source "$LIB_DIR/yunxiao.sh"
source "$LIB_DIR/frontmatter.sh"
source "$LIB_DIR/datetime.sh"

# =============================================================================
# 常量定义
# =============================================================================

# 冲突类型
readonly CONFLICT_TYPE_CONTENT="content"
readonly CONFLICT_TYPE_STATUS="status"
readonly CONFLICT_TYPE_METADATA="metadata"
readonly CONFLICT_TYPE_STRUCTURE="structure"

# 冲突解决策略
readonly RESOLUTION_LOCAL_WINS="local_wins"
readonly RESOLUTION_REMOTE_WINS="remote_wins"
readonly RESOLUTION_MANUAL="manual"
readonly RESOLUTION_MERGE="merge"
readonly RESOLUTION_TIMESTAMP="timestamp"

# 冲突状态
readonly CONFLICT_STATUS_DETECTED="detected"
readonly CONFLICT_STATUS_RESOLVED="resolved"
readonly CONFLICT_STATUS_PENDING="pending"

# 冲突记录文件
readonly CONFLICTS_DIR=".claude/sync-status/conflicts"
readonly CONFLICTS_INDEX="$CONFLICTS_DIR/index.json"
readonly CONFLICT_HISTORY="$CONFLICTS_DIR/history.json"

# =============================================================================
# 冲突检测主函数
# =============================================================================

# 检测所有冲突
# Usage: detect_conflicts
# Returns: 0 if no conflicts, 1 if conflicts found
detect_conflicts() {
    log_yunxiao_info "开始检测同步冲突"

    # 初始化冲突检测环境
    init_conflict_detection || return 1

    local conflicts_found=0

    # 检测映射冲突
    detect_mapping_conflicts || conflicts_found=1

    # 检测内容冲突
    detect_content_conflicts || conflicts_found=1

    # 检测状态冲突
    detect_status_conflicts || conflicts_found=1

    # 检测元数据冲突
    detect_metadata_conflicts || conflicts_found=1

    # 生成冲突报告
    generate_conflict_report

    if [ $conflicts_found -eq 0 ]; then
        log_yunxiao_success "未检测到同步冲突"
        return 0
    else
        log_yunxiao_warning "检测到同步冲突，需要解决"
        return 1
    fi
}

# 初始化冲突检测环境
# Usage: init_conflict_detection
init_conflict_detection() {
    log_yunxiao_debug "初始化冲突检测环境"

    # 创建冲突目录
    mkdir -p "$CONFLICTS_DIR"

    # 初始化冲突索引文件
    if [ ! -f "$CONFLICTS_INDEX" ]; then
        echo '{"conflicts": [], "last_check": null, "total_conflicts": 0}' > "$CONFLICTS_INDEX"
    fi

    # 初始化冲突历史文件
    if [ ! -f "$CONFLICT_HISTORY" ]; then
        echo '{"history": []}' > "$CONFLICT_HISTORY"
    fi

    return 0
}

# =============================================================================
# 具体冲突检测函数
# =============================================================================

# 检测映射冲突
# Usage: detect_mapping_conflicts
detect_mapping_conflicts() {
    log_yunxiao_debug "检测映射冲突"

    local conflicts_found=0

    # 检查是否有多个本地文件映射到同一个云效工作项
    check_duplicate_mappings || conflicts_found=1

    # 检查是否有映射指向不存在的文件或工作项
    check_orphaned_mappings || conflicts_found=1

    return $conflicts_found
}

# 检查重复映射
# Usage: check_duplicate_mappings
check_duplicate_mappings() {
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ ! -f "$mapping_file" ]; then
        return 0
    fi

    log_yunxiao_debug "检查重复映射"

    # 获取所有yunxiao_workitem_id，检查是否有重复
    local duplicate_ids
    duplicate_ids=$(jq -r '.mappings | to_entries[] | .value.yunxiao_workitem_id' "$mapping_file" | sort | uniq -d)

    if [ -n "$duplicate_ids" ]; then
        echo "$duplicate_ids" | while read -r yunxiao_id; do
            if [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
                # 找到所有映射到这个ID的本地项目
                local local_ids
                local_ids=$(jq -r ".mappings | to_entries[] | select(.value.yunxiao_workitem_id == \"$yunxiao_id\") | .key" "$mapping_file")

                record_conflict \
                    "$CONFLICT_TYPE_STRUCTURE" \
                    "duplicate_mapping" \
                    "Multiple local items mapped to same Yunxiao workitem: $yunxiao_id" \
                    "$local_ids" \
                    "$yunxiao_id"
            fi
        done
        return 1
    fi

    return 0
}

# 检查孤立映射
# Usage: check_orphaned_mappings
check_orphaned_mappings() {
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ ! -f "$mapping_file" ]; then
        return 0
    fi

    log_yunxiao_debug "检查孤立映射"

    local conflicts_found=0

    # 检查映射的本地文件是否存在
    jq -r '.mappings | to_entries[] | "\(.key)|\(.value.local_path)"' "$mapping_file" | while IFS='|' read -r local_id local_path; do
        if [ ! -f "$local_path" ]; then
            record_conflict \
                "$CONFLICT_TYPE_STRUCTURE" \
                "orphaned_local_file" \
                "Mapped local file does not exist: $local_path" \
                "$local_id" \
                ""
            conflicts_found=1
        fi
    done

    return $conflicts_found
}

# 检测内容冲突
# Usage: detect_content_conflicts
detect_content_conflicts() {
    log_yunxiao_debug "检测内容冲突"

    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ ! -f "$mapping_file" ]; then
        return 0
    fi

    local conflicts_found=0

    # 遍历所有映射，比较本地和远程内容
    jq -r '.mappings | to_entries[] | "\(.key)|\(.value.local_path)|\(.value.yunxiao_workitem_id)"' "$mapping_file" | \
    while IFS='|' read -r local_id local_path yunxiao_id; do
        if [ -f "$local_path" ] && [ -n "$yunxiao_id" ] && [ "$yunxiao_id" != "null" ]; then
            check_content_conflict "$local_id" "$local_path" "$yunxiao_id" || conflicts_found=1
        fi
    done

    return $conflicts_found
}

# 检查单个文件的内容冲突
# Usage: check_content_conflict "local_id" "local_path" "yunxiao_id"
check_content_conflict() {
    local local_id="$1"
    local local_path="$2"
    local yunxiao_id="$3"

    log_yunxiao_debug "检查内容冲突: $local_id <-> $yunxiao_id"

    # 获取本地文件的更新时间
    local local_updated
    local_updated=$(get_frontmatter_field "$local_path" "updated")

    # 获取云效工作项的更新时间
    local remote_data
    if ! remote_data=$(yunxiao_get_workitem "$yunxiao_id"); then
        log_yunxiao_warning "无法获取云效工作项: $yunxiao_id"
        return 1
    fi

    local remote_updated
    remote_updated=$(get_workitem_field "$remote_data" "updated_time")

    # 比较时间戳
    if [ -n "$local_updated" ] && [ -n "$remote_updated" ] && [ "$local_updated" != "null" ] && [ "$remote_updated" != "null" ]; then
        local local_timestamp
        local_timestamp=$(date -d "$local_updated" +%s 2>/dev/null || echo "0")
        local remote_timestamp
        remote_timestamp=$(date -d "$remote_updated" +%s 2>/dev/null || echo "0")

        # 如果两者都在最近同步时间之后修改过，可能存在冲突
        local last_sync
        last_sync=$(get_last_sync_time "$local_id")

        if [ -n "$last_sync" ] && [ "$last_sync" != "null" ]; then
            local sync_timestamp
            sync_timestamp=$(date -d "$last_sync" +%s 2>/dev/null || echo "0")

            if [ $local_timestamp -gt $sync_timestamp ] && [ $remote_timestamp -gt $sync_timestamp ]; then
                # 检查具体内容是否有差异
                if check_detailed_content_diff "$local_path" "$remote_data"; then
                    record_conflict \
                        "$CONFLICT_TYPE_CONTENT" \
                        "concurrent_modification" \
                        "Both local and remote modified since last sync" \
                        "$local_id" \
                        "$yunxiao_id" \
                        "$local_updated" \
                        "$remote_updated"
                    return 1
                fi
            fi
        fi
    fi

    return 0
}

# 检查详细的内容差异
# Usage: check_detailed_content_diff "local_path" "remote_data"
# Returns: 0 if different, 1 if same
check_detailed_content_diff() {
    local local_path="$1"
    local remote_data="$2"

    # 比较标题
    local local_title remote_title
    local_title=$(get_frontmatter_field "$local_path" "name")
    remote_title=$(get_workitem_field "$remote_data" "title")

    if [ "$local_title" != "$remote_title" ]; then
        return 0
    fi

    # 比较描述内容
    local local_description remote_description
    local_description=$(strip_frontmatter_content "$local_path")
    remote_description=$(get_workitem_field "$remote_data" "description")

    # 简单的内容比较（可以进一步优化）
    if [ "$local_description" != "$remote_description" ]; then
        return 0
    fi

    # 比较状态
    local local_status remote_status
    local_status=$(get_frontmatter_field "$local_path" "status")
    remote_status=$(get_workitem_field "$remote_data" "status")

    # 进行状态映射比较
    local mapped_remote_status="${REMOTE_STATUS_MAPPING[$remote_status]:-$remote_status}"

    if [ "$local_status" != "$mapped_remote_status" ]; then
        return 0
    fi

    # 如果所有关键字段都相同，认为没有冲突
    return 1
}

# 检测状态冲突
# Usage: detect_status_conflicts
detect_status_conflicts() {
    log_yunxiao_debug "检测状态冲突"

    # 状态冲突通常在内容冲突检测中一起处理
    # 这里可以添加特定的状态冲突检测逻辑
    return 0
}

# 检测元数据冲突
# Usage: detect_metadata_conflicts
detect_metadata_conflicts() {
    log_yunxiao_debug "检测元数据冲突"

    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ ! -f "$mapping_file" ]; then
        return 0
    fi

    local conflicts_found=0

    # 检查映射配置的一致性
    jq -r '.mappings | to_entries[] | "\(.key)|\(.value.local_path)|\(.value.yunxiao_workitem_id)"' "$mapping_file" | \
    while IFS='|' read -r local_id local_path yunxiao_id; do
        check_metadata_consistency "$local_id" "$local_path" "$yunxiao_id" || conflicts_found=1
    done

    return $conflicts_found
}

# 检查元数据一致性
# Usage: check_metadata_consistency "local_id" "local_path" "yunxiao_id"
check_metadata_consistency() {
    local local_id="$1"
    local local_path="$2"
    local yunxiao_id="$3"

    # 检查本地文件中的yunxiao_id是否与映射一致
    local file_yunxiao_id
    file_yunxiao_id=$(get_frontmatter_field "$local_path" "yunxiao_id")

    if [ -n "$file_yunxiao_id" ] && [ "$file_yunxiao_id" != "null" ] && [ "$file_yunxiao_id" != "$yunxiao_id" ]; then
        record_conflict \
            "$CONFLICT_TYPE_METADATA" \
            "inconsistent_yunxiao_id" \
            "Yunxiao ID in file ($file_yunxiao_id) differs from mapping ($yunxiao_id)" \
            "$local_id" \
            "$yunxiao_id"
        return 1
    fi

    return 0
}

# =============================================================================
# 冲突解决函数
# =============================================================================

# 解决所有冲突
# Usage: resolve_all_conflicts
# Returns: 0 if all resolved, 1 if any unresolved
resolve_all_conflicts() {
    log_yunxiao_info "开始解决所有冲突"

    if [ ! -f "$CONFLICTS_INDEX" ]; then
        log_yunxiao_info "没有检测到冲突"
        return 0
    fi

    local total_conflicts
    total_conflicts=$(jq '.total_conflicts' "$CONFLICTS_INDEX")

    if [ "$total_conflicts" -eq 0 ]; then
        log_yunxiao_info "没有需要解决的冲突"
        return 0
    fi

    log_yunxiao_info "发现 $total_conflicts 个冲突，开始解决"

    local resolved_count=0
    local failed_count=0

    # 遍历所有冲突并尝试解决
    jq -r '.conflicts[] | @base64' "$CONFLICTS_INDEX" | while read -r conflict_data; do
        local conflict
        conflict=$(echo "$conflict_data" | base64 -d)

        local conflict_id
        conflict_id=$(echo "$conflict" | jq -r '.id')

        if resolve_single_conflict "$conflict"; then
            resolved_count=$((resolved_count + 1))
            mark_conflict_resolved "$conflict_id"
            log_yunxiao_success "冲突已解决: $conflict_id"
        else
            failed_count=$((failed_count + 1))
            log_yunxiao_error "冲突解决失败: $conflict_id"
        fi
    done

    log_yunxiao_info "冲突解决完成: 成功 $resolved_count, 失败 $failed_count"

    if [ $failed_count -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# 解决单个冲突
# Usage: resolve_single_conflict "conflict_json"
# Returns: 0 if resolved, 1 if not
resolve_single_conflict() {
    local conflict="$1"

    local conflict_type conflict_subtype local_id yunxiao_id
    conflict_type=$(echo "$conflict" | jq -r '.type')
    conflict_subtype=$(echo "$conflict" | jq -r '.subtype')
    local_id=$(echo "$conflict" | jq -r '.local_id')
    yunxiao_id=$(echo "$conflict" | jq -r '.yunxiao_id // empty')

    log_yunxiao_debug "解决冲突: $conflict_type/$conflict_subtype"

    # 根据冲突类型选择解决策略
    case "$conflict_type" in
        "$CONFLICT_TYPE_CONTENT")
            resolve_content_conflict "$conflict"
            ;;
        "$CONFLICT_TYPE_STATUS")
            resolve_status_conflict "$conflict"
            ;;
        "$CONFLICT_TYPE_METADATA")
            resolve_metadata_conflict "$conflict"
            ;;
        "$CONFLICT_TYPE_STRUCTURE")
            resolve_structure_conflict "$conflict"
            ;;
        *)
            log_yunxiao_error "不支持的冲突类型: $conflict_type"
            return 1
            ;;
    esac
}

# 解决内容冲突
# Usage: resolve_content_conflict "conflict_json"
resolve_content_conflict() {
    local conflict="$1"

    local local_id yunxiao_id resolution_strategy
    local_id=$(echo "$conflict" | jq -r '.local_id')
    yunxiao_id=$(echo "$conflict" | jq -r '.yunxiao_id')

    # 获取冲突解决策略
    resolution_strategy=$(get_resolution_strategy "$conflict")

    log_yunxiao_info "解决内容冲突: $local_id <-> $yunxiao_id (策略: $resolution_strategy)"

    case "$resolution_strategy" in
        "$RESOLUTION_LOCAL_WINS")
            resolve_with_local_wins "$local_id" "$yunxiao_id"
            ;;
        "$RESOLUTION_REMOTE_WINS")
            resolve_with_remote_wins "$local_id" "$yunxiao_id"
            ;;
        "$RESOLUTION_TIMESTAMP")
            resolve_with_timestamp_priority "$local_id" "$yunxiao_id"
            ;;
        "$RESOLUTION_MANUAL")
            resolve_with_manual_intervention "$conflict"
            ;;
        "$RESOLUTION_MERGE")
            resolve_with_merge "$local_id" "$yunxiao_id"
            ;;
        *)
            log_yunxiao_error "未知的解决策略: $resolution_strategy"
            return 1
            ;;
    esac
}

# 本地优先解决策略
# Usage: resolve_with_local_wins "local_id" "yunxiao_id"
resolve_with_local_wins() {
    local local_id="$1"
    local yunxiao_id="$2"

    log_yunxiao_info "使用本地优先策略解决冲突"

    # 获取本地文件路径
    local local_path
    local_path=$(get_mapping_local_path "$local_id")

    if [ ! -f "$local_path" ]; then
        log_yunxiao_error "本地文件不存在: $local_path"
        return 1
    fi

    # 将本地内容推送到云效
    sync_local_file_to_remote "$local_path" "$yunxiao_id"
}

# 远程优先解决策略
# Usage: resolve_with_remote_wins "local_id" "yunxiao_id"
resolve_with_remote_wins() {
    local local_id="$1"
    local yunxiao_id="$2"

    log_yunxiao_info "使用远程优先策略解决冲突"

    # 获取云效工作项数据
    local remote_data
    if ! remote_data=$(yunxiao_get_workitem "$yunxiao_id"); then
        log_yunxiao_error "无法获取云效工作项: $yunxiao_id"
        return 1
    fi

    # 将云效内容拉取到本地
    sync_remote_workitem_to_local "$remote_data" "$local_id"
}

# 时间戳优先解决策略
# Usage: resolve_with_timestamp_priority "local_id" "yunxiao_id"
resolve_with_timestamp_priority() {
    local local_id="$1"
    local yunxiao_id="$2"

    log_yunxiao_info "使用时间戳优先策略解决冲突"

    # 获取本地和远程的更新时间
    local local_path
    local_path=$(get_mapping_local_path "$local_id")

    local local_updated
    local_updated=$(get_frontmatter_field "$local_path" "updated")

    local remote_data
    if ! remote_data=$(yunxiao_get_workitem "$yunxiao_id"); then
        log_yunxiao_error "无法获取云效工作项: $yunxiao_id"
        return 1
    fi

    local remote_updated
    remote_updated=$(get_workitem_field "$remote_data" "updated_time")

    # 比较时间戳
    local local_timestamp
    local_timestamp=$(date -d "$local_updated" +%s 2>/dev/null || echo "0")
    local remote_timestamp
    remote_timestamp=$(date -d "$remote_updated" +%s 2>/dev/null || echo "0")

    if [ $local_timestamp -gt $remote_timestamp ]; then
        log_yunxiao_info "本地更新时间较新，使用本地版本"
        resolve_with_local_wins "$local_id" "$yunxiao_id"
    else
        log_yunxiao_info "远程更新时间较新，使用远程版本"
        resolve_with_remote_wins "$local_id" "$yunxiao_id"
    fi
}

# 手动干预解决策略
# Usage: resolve_with_manual_intervention "conflict_json"
resolve_with_manual_intervention() {
    local conflict="$1"

    log_yunxiao_info "需要手动解决冲突"

    # 显示冲突详情
    show_conflict_details "$conflict"

    # 提供交互式选择
    present_resolution_options "$conflict"
}

# 合并解决策略
# Usage: resolve_with_merge "local_id" "yunxiao_id"
resolve_with_merge() {
    local local_id="$1"
    local yunxiao_id="$2"

    log_yunxiao_info "使用合并策略解决冲突"

    # 简化的合并策略：使用本地的标题和状态，远程的描述
    # 实际应用中可以实现更复杂的合并逻辑

    local local_path
    local_path=$(get_mapping_local_path "$local_id")

    local remote_data
    if ! remote_data=$(yunxiao_get_workitem "$yunxiao_id"); then
        log_yunxiao_error "无法获取云效工作项: $yunxiao_id"
        return 1
    fi

    # 保留本地的标题和状态，使用远程的描述
    local local_title local_status remote_description
    local_title=$(get_frontmatter_field "$local_path" "name")
    local_status=$(get_frontmatter_field "$local_path" "status")
    remote_description=$(get_workitem_field "$remote_data" "description")

    # 更新本地文件
    update_frontmatter_field "$local_path" "updated" "$(get_current_timestamp)"

    # 更新描述内容
    update_file_content "$local_path" "$remote_description"

    # 同步到云效
    sync_local_file_to_remote "$local_path" "$yunxiao_id"

    log_yunxiao_success "冲突合并完成"
}

# 解决结构冲突
# Usage: resolve_structure_conflict "conflict_json"
resolve_structure_conflict() {
    local conflict="$1"

    local conflict_subtype
    conflict_subtype=$(echo "$conflict" | jq -r '.subtype')

    case "$conflict_subtype" in
        "duplicate_mapping")
            resolve_duplicate_mapping_conflict "$conflict"
            ;;
        "orphaned_local_file")
            resolve_orphaned_file_conflict "$conflict"
            ;;
        *)
            log_yunxiao_error "不支持的结构冲突子类型: $conflict_subtype"
            return 1
            ;;
    esac
}

# 解决重复映射冲突
# Usage: resolve_duplicate_mapping_conflict "conflict_json"
resolve_duplicate_mapping_conflict() {
    local conflict="$1"

    local yunxiao_id
    yunxiao_id=$(echo "$conflict" | jq -r '.yunxiao_id')

    log_yunxiao_info "解决重复映射冲突: $yunxiao_id"

    # 获取所有映射到这个yunxiao_id的本地项目
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"
    local local_ids
    local_ids=$(jq -r ".mappings | to_entries[] | select(.value.yunxiao_workitem_id == \"$yunxiao_id\") | .key" "$mapping_file")

    # 保留第一个映射，删除其他映射
    local first_id=""
    echo "$local_ids" | while read -r local_id; do
        if [ -z "$first_id" ]; then
            first_id="$local_id"
            log_yunxiao_info "保留映射: $local_id -> $yunxiao_id"
        else
            log_yunxiao_info "删除重复映射: $local_id -> $yunxiao_id"
            delete_mapping "$local_id"
        fi
    done
}

# 解决孤立文件冲突
# Usage: resolve_orphaned_file_conflict "conflict_json"
resolve_orphaned_file_conflict() {
    local conflict="$1"

    local local_id
    local_id=$(echo "$conflict" | jq -r '.local_id')

    log_yunxiao_info "解决孤立文件冲突: $local_id"

    # 删除指向不存在文件的映射
    delete_mapping "$local_id"
    log_yunxiao_info "已删除孤立映射: $local_id"
}

# 解决元数据冲突
# Usage: resolve_metadata_conflict "conflict_json"
resolve_metadata_conflict() {
    local conflict="$1"

    local conflict_subtype
    conflict_subtype=$(echo "$conflict" | jq -r '.subtype')

    case "$conflict_subtype" in
        "inconsistent_yunxiao_id")
            resolve_inconsistent_id_conflict "$conflict"
            ;;
        *)
            log_yunxiao_error "不支持的元数据冲突子类型: $conflict_subtype"
            return 1
            ;;
    esac
}

# 解决不一致ID冲突
# Usage: resolve_inconsistent_id_conflict "conflict_json"
resolve_inconsistent_id_conflict() {
    local conflict="$1"

    local local_id yunxiao_id
    local_id=$(echo "$conflict" | jq -r '.local_id')
    yunxiao_id=$(echo "$conflict" | jq -r '.yunxiao_id')

    log_yunxiao_info "解决ID不一致冲突: $local_id"

    # 更新本地文件中的yunxiao_id以匹配映射
    local local_path
    local_path=$(get_mapping_local_path "$local_id")

    if [ -f "$local_path" ]; then
        update_frontmatter_field "$local_path" "yunxiao_id" "$yunxiao_id"
        log_yunxiao_success "已更新本地文件的yunxiao_id: $local_path"
    fi
}

# =============================================================================
# 冲突记录和管理
# =============================================================================

# 记录冲突
# Usage: record_conflict "type" "subtype" "description" "local_id" "yunxiao_id" ["local_timestamp"] ["remote_timestamp"]
record_conflict() {
    local type="$1"
    local subtype="$2"
    local description="$3"
    local local_id="$4"
    local yunxiao_id="$5"
    local local_timestamp="${6:-}"
    local remote_timestamp="${7:-}"

    local conflict_id
    conflict_id="conflict-$(date +%s)-$$"

    local current_time
    current_time=$(get_current_timestamp)

    # 构建冲突记录
    local conflict_data
    conflict_data=$(jq -n \
        --arg id "$conflict_id" \
        --arg type "$type" \
        --arg subtype "$subtype" \
        --arg description "$description" \
        --arg local_id "$local_id" \
        --arg yunxiao_id "$yunxiao_id" \
        --arg local_timestamp "$local_timestamp" \
        --arg remote_timestamp "$remote_timestamp" \
        --arg detected_time "$current_time" \
        --arg status "$CONFLICT_STATUS_DETECTED" \
        '{
            id: $id,
            type: $type,
            subtype: $subtype,
            description: $description,
            local_id: $local_id,
            yunxiao_id: $yunxiao_id,
            local_timestamp: $local_timestamp,
            remote_timestamp: $remote_timestamp,
            detected_time: $detected_time,
            status: $status,
            resolution: null,
            resolved_time: null
        }')

    # 添加到冲突索引
    local temp_file
    temp_file=$(mktemp)

    jq \
        --argjson conflict "$conflict_data" \
        --arg current_time "$current_time" \
        '.conflicts += [$conflict] |
         .last_check = $current_time |
         .total_conflicts = (.conflicts | length)' \
        "$CONFLICTS_INDEX" > "$temp_file"

    mv "$temp_file" "$CONFLICTS_INDEX"

    log_yunxiao_warning "记录冲突: $conflict_id - $description"
}

# 标记冲突已解决
# Usage: mark_conflict_resolved "conflict_id" ["resolution_method"]
mark_conflict_resolved() {
    local conflict_id="$1"
    local resolution_method="${2:-auto}"

    local current_time
    current_time=$(get_current_timestamp)

    # 更新冲突状态
    local temp_file
    temp_file=$(mktemp)

    jq \
        --arg conflict_id "$conflict_id" \
        --arg resolution "$resolution_method" \
        --arg resolved_time "$current_time" \
        --arg status "$CONFLICT_STATUS_RESOLVED" \
        '(.conflicts[] | select(.id == $conflict_id)) |=
         (.status = $status | .resolution = $resolution | .resolved_time = $resolved_time)' \
        "$CONFLICTS_INDEX" > "$temp_file"

    mv "$temp_file" "$CONFLICTS_INDEX"

    # 添加到历史记录
    add_to_conflict_history "$conflict_id" "$resolution_method"

    log_yunxiao_debug "冲突已标记为已解决: $conflict_id"
}

# 添加到冲突历史
# Usage: add_to_conflict_history "conflict_id" "resolution_method"
add_to_conflict_history() {
    local conflict_id="$1"
    local resolution_method="$2"

    local current_time
    current_time=$(get_current_timestamp)

    # 获取冲突详情
    local conflict_details
    conflict_details=$(jq ".conflicts[] | select(.id == \"$conflict_id\")" "$CONFLICTS_INDEX")

    # 添加解决方法和时间
    local history_entry
    history_entry=$(echo "$conflict_details" | jq \
        --arg resolution "$resolution_method" \
        --arg resolved_time "$current_time" \
        '. + {resolution: $resolution, resolved_time: $resolved_time}')

    # 更新历史文件
    local temp_file
    temp_file=$(mktemp)

    jq \
        --argjson entry "$history_entry" \
        '.history += [$entry]' \
        "$CONFLICT_HISTORY" > "$temp_file"

    mv "$temp_file" "$CONFLICT_HISTORY"
}

# =============================================================================
# 冲突查询和报告
# =============================================================================

# 检查是否有未解决的冲突
# Usage: has_unresolved_conflicts
# Returns: 0 if has conflicts, 1 if no conflicts
has_unresolved_conflicts() {
    if [ ! -f "$CONFLICTS_INDEX" ]; then
        return 1
    fi

    local unresolved_count
    unresolved_count=$(jq '[.conflicts[] | select(.status != "resolved")] | length' "$CONFLICTS_INDEX")

    [ "$unresolved_count" -gt 0 ]
}

# 生成冲突报告
# Usage: generate_conflict_report
generate_conflict_report() {
    if [ ! -f "$CONFLICTS_INDEX" ]; then
        log_yunxiao_info "没有冲突记录"
        return 0
    fi

    local total_conflicts unresolved_conflicts
    total_conflicts=$(jq '.total_conflicts' "$CONFLICTS_INDEX")
    unresolved_conflicts=$(jq '[.conflicts[] | select(.status != "resolved")] | length' "$CONFLICTS_INDEX")

    log_yunxiao_info "=== 冲突报告 ==="
    log_yunxiao_info "总冲突数: $total_conflicts"
    log_yunxiao_info "未解决冲突: $unresolved_conflicts"
    log_yunxiao_info "已解决冲突: $((total_conflicts - unresolved_conflicts))"

    if [ "$unresolved_conflicts" -gt 0 ]; then
        log_yunxiao_info ""
        log_yunxiao_info "未解决的冲突:"
        jq -r '.conflicts[] | select(.status != "resolved") | "- \(.id): \(.description)"' "$CONFLICTS_INDEX"
    fi

    log_yunxiao_info "=================="
}

# 显示冲突详情
# Usage: show_conflict_details "conflict_json"
show_conflict_details() {
    local conflict="$1"

    echo "=== 冲突详情 ==="
    echo "$conflict" | jq -r '
        "ID: \(.id)",
        "类型: \(.type)/\(.subtype)",
        "描述: \(.description)",
        "本地ID: \(.local_id)",
        "云效ID: \(.yunxiao_id // "N/A")",
        "检测时间: \(.detected_time)"
    '
    echo "================"
}

# 提供解决选项
# Usage: present_resolution_options "conflict_json"
present_resolution_options() {
    local conflict="$1"

    echo "请选择解决策略:"
    echo "1) 本地优先 (local_wins)"
    echo "2) 远程优先 (remote_wins)"
    echo "3) 时间戳优先 (timestamp)"
    echo "4) 合并 (merge)"
    echo "5) 跳过 (skip)"

    read -p "请输入选择 (1-5): " choice

    case "$choice" in
        1) echo "$RESOLUTION_LOCAL_WINS" ;;
        2) echo "$RESOLUTION_REMOTE_WINS" ;;
        3) echo "$RESOLUTION_TIMESTAMP" ;;
        4) echo "$RESOLUTION_MERGE" ;;
        5) echo "skip" ;;
        *) echo "$RESOLUTION_MANUAL" ;;
    esac
}

# =============================================================================
# 工具函数
# =============================================================================

# 获取解决策略
# Usage: get_resolution_strategy "conflict_json"
get_resolution_strategy() {
    local conflict="$1"

    # 从配置文件中获取默认策略
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"
    local default_strategy

    if [ -f "$mapping_file" ]; then
        default_strategy=$(jq -r '.config.conflict_resolution // "manual"' "$mapping_file")
    else
        default_strategy="manual"
    fi

    echo "$default_strategy"
}

# 获取映射的本地文件路径
# Usage: get_mapping_local_path "local_id"
get_mapping_local_path() {
    local local_id="$1"
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ -f "$mapping_file" ]; then
        jq -r ".mappings[\"$local_id\"].local_path // empty" "$mapping_file"
    fi
}

# 获取当前时间戳
# Usage: get_current_timestamp
get_current_timestamp() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# 去除frontmatter后获取内容
# Usage: strip_frontmatter_content "file_path"
strip_frontmatter_content() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        echo ""
        return 1
    fi

    sed '1,/^---$/d; 1,/^---$/d' "$file_path"
}

# 更新文件内容（保留frontmatter）
# Usage: update_file_content "file_path" "new_content"
update_file_content() {
    local file_path="$1"
    local new_content="$2"

    if [ ! -f "$file_path" ]; then
        return 1
    fi

    # 提取frontmatter
    local frontmatter
    frontmatter=$(awk '/^---$/,/^---$/ {print}' "$file_path")

    # 创建新文件内容
    {
        echo "$frontmatter"
        echo ""
        echo "$new_content"
    } > "$file_path.tmp"

    mv "$file_path.tmp" "$file_path"
}

# 获取最后同步时间
# Usage: get_last_sync_time "local_id"
get_last_sync_time() {
    local local_id="$1"
    local mapping_file=".claude/sync-status/yunxiao-mappings.json"

    if [ -f "$mapping_file" ]; then
        jq -r ".mappings[\"$local_id\"].last_sync // empty" "$mapping_file"
    fi
}

# 同步本地文件到远程（简化版本）
# Usage: sync_local_file_to_remote "local_path" "yunxiao_id"
sync_local_file_to_remote() {
    local local_path="$1"
    local yunxiao_id="$2"

    log_yunxiao_debug "同步本地文件到云效: $local_path -> $yunxiao_id"
    # 这里应该调用local-to-remote.sh的相关函数
    # 简化处理
    return 0
}

# 同步远程工作项到本地（简化版本）
# Usage: sync_remote_workitem_to_local "remote_data" "local_id"
sync_remote_workitem_to_local() {
    local remote_data="$1"
    local local_id="$2"

    log_yunxiao_debug "同步云效工作项到本地: $local_id"
    # 这里应该调用remote-to-local.sh的相关函数
    # 简化处理
    return 0
}

# =============================================================================
# 主程序入口（用于测试）
# =============================================================================

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    # 如果脚本被直接执行，提供测试功能
    case "${1:-help}" in
        "detect")
            detect_conflicts
            ;;
        "resolve")
            resolve_all_conflicts
            ;;
        "status")
            generate_conflict_report
            ;;
        "show")
            if [ -f "$CONFLICTS_INDEX" ]; then
                jq '.conflicts[]' "$CONFLICTS_INDEX"
            else
                echo "没有冲突记录"
            fi
            ;;
        "help"|*)
            cat << EOF
冲突解决器工具

用法: $0 <命令> [参数...]

命令:
  detect          检测所有冲突
  resolve         解决所有冲突
  status          显示冲突状态报告
  show            显示所有冲突详情
  help            显示此帮助信息

示例:
  $0 detect       检测同步冲突
  $0 resolve      自动解决冲突
  $0 status       查看冲突状态
EOF
            ;;
    esac
fi