#!/bin/bash

# 云效功能完整性测试套件
# 验证云效平台所有功能正常工作

# =============================================================================
# 测试配置和初始化
# =============================================================================

set -u

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
CLAUDE_DIR="$PROJECT_ROOT/.claude"

# 加载测试工具
source "$CLAUDE_DIR/tests/utils/test-framework.sh"

# 加载平台检测库
source "$CLAUDE_DIR/lib/platform-detection.sh"

# 测试环境配置
TEST_NAME="云效功能完整性测试"
TEMP_DIR="/tmp/yunxiao_complete_test_$$"
YUNXIAO_TEST_CONFIG="$TEMP_DIR/test-yunxiao-config.yaml"

# 测试用例配置
TEST_PROJECT_ID="12345"
TEST_WORKITEM_PREFIX="test_$(date +%s)"

# =============================================================================
# 测试工具函数
# =============================================================================

# 初始化云效测试环境
setup_yunxiao_test_environment() {
    echo "=== 云效功能完整性测试 ==="
    echo "测试时间: $(date)"
    echo "项目根目录: $PROJECT_ROOT"
    echo ""

    # 创建临时目录
    mkdir -p "$TEMP_DIR"

    # 保存当前配置
    if [ -f "$PROJECT_ROOT/.ccpm-config.yaml" ]; then
        cp "$PROJECT_ROOT/.ccpm-config.yaml" "$TEMP_DIR/original-config.yaml"
        echo "✅ 已备份原始配置"
    fi

    echo "✅ 云效测试环境初始化完成"
    echo ""
}

# 清理云效测试环境
cleanup_yunxiao_test_environment() {
    echo ""
    echo "=== 清理云效测试环境 ==="

    # 恢复原始配置
    if [ -f "$TEMP_DIR/original-config.yaml" ]; then
        cp "$TEMP_DIR/original-config.yaml" "$PROJECT_ROOT/.ccpm-config.yaml"
        echo "✅ 已恢复原始配置"
    else
        rm -f "$PROJECT_ROOT/.ccpm-config.yaml"
    fi

    # 删除临时文件
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        echo "✅ 已清理临时文件"
    fi

    echo "✅ 云效测试环境清理完成"
}

# 创建云效测试配置
create_yunxiao_test_config() {
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: yunxiao
project_id: $TEST_PROJECT_ID
EOF

    if [ -f "$PROJECT_ROOT/.ccpm-config.yaml" ]; then
        record_test_result "创建云效配置" "PASS" "配置文件已创建"
        return 0
    else
        record_test_result "创建云效配置" "FAIL" "配置文件创建失败"
        return 1
    fi
}

# =============================================================================
# 平台检测测试
# =============================================================================

test_platform_detection() {
    echo "=== 平台检测功能测试 ==="

    # 测试1: 无配置文件时默认GitHub
    echo "测试1: 无配置时默认GitHub"
    rm -f "$PROJECT_ROOT/.ccpm-config.yaml"

    local platform
    platform=$(cd "$PROJECT_ROOT" && source "$CLAUDE_DIR/lib/platform-detection.sh" && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "平台检测 - 默认GitHub" "PASS" "无配置时正确返回github"
    else
        record_test_result "平台检测 - 默认GitHub" "FAIL" "期望github，实际: $platform"
    fi

    # 测试2: 云效配置时检测到yunxiao
    echo "测试2: 云效配置检测"
    create_yunxiao_test_config

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "yunxiao" ]; then
        record_test_result "平台检测 - 云效平台" "PASS" "正确检测到yunxiao平台"
    else
        record_test_result "平台检测 - 云效平台" "FAIL" "期望yunxiao，实际: $platform"
    fi

    # 测试3: GitHub配置时检测到github
    echo "测试3: GitHub配置检测"
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: github
EOF

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "平台检测 - GitHub配置" "PASS" "正确检测到github平台"
    else
        record_test_result "平台检测 - GitHub配置" "FAIL" "期望github，实际: $platform"
    fi

    # 测试4: 无效配置时回退到GitHub
    echo "测试4: 无效配置回退"
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: invalid_platform
EOF

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "平台检测 - 无效平台回退" "PASS" "无效配置正确回退到github"
    else
        record_test_result "平台检测 - 无效平台回退" "FAIL" "期望github，实际: $platform"
    fi

    echo ""
}

# =============================================================================
# 配置验证测试
# =============================================================================

test_config_validation() {
    echo "=== 配置验证功能测试 ==="

    # 测试1: 云效配置缺少project_id
    echo "测试1: 云效配置缺少project_id"
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: yunxiao
EOF

    if ! (cd "$PROJECT_ROOT" && source "$CLAUDE_DIR/lib/platform-detection.sh" && validate_yunxiao_platform_config 2>/dev/null); then
        record_test_result "配置验证 - 缺少project_id" "PASS" "正确检测到缺少project_id"
    else
        record_test_result "配置验证 - 缺少project_id" "FAIL" "应该验证失败但通过了"
    fi

    # 测试2: 云效配置project_id格式错误
    echo "测试2: project_id格式错误"
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: yunxiao
project_id: invalid_id
EOF

    if ! (cd "$PROJECT_ROOT" && source "$CLAUDE_DIR/lib/platform-detection.sh" && validate_yunxiao_platform_config 2>/dev/null); then
        record_test_result "配置验证 - project_id格式错误" "PASS" "正确检测到格式错误"
    else
        record_test_result "配置验证 - project_id格式错误" "FAIL" "应该验证失败但通过了"
    fi

    # 测试3: 有效的云效配置（跳过MCP连接测试）
    echo "测试3: 有效配置格式"
    create_yunxiao_test_config

    # 只测试配置格式，不测试MCP连接
    local project_id
    project_id=$(cd "$PROJECT_ROOT" && source "$CLAUDE_DIR/lib/platform-detection.sh" && get_project_id)

    if [ "$project_id" = "$TEST_PROJECT_ID" ]; then
        record_test_result "配置验证 - 有效配置" "PASS" "配置格式验证通过"
    else
        record_test_result "配置验证 - 有效配置" "FAIL" "project_id读取错误: $project_id"
    fi

    echo ""
}

# =============================================================================
# 命令路由测试
# =============================================================================

test_command_routing() {
    echo "=== 命令路由功能测试 ==="

    # 测试1: GitHub配置时路由到GitHub脚本
    echo "测试1: GitHub命令路由"
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: github
EOF

    # 检查路由逻辑（不实际执行命令）
    local platform
    platform=$(cd "$PROJECT_ROOT" && source "$CLAUDE_DIR/lib/platform-detection.sh" && get_platform_type)

    if [ "$platform" = "github" ]; then
        # 验证GitHub脚本存在
        if [ -f "$CLAUDE_DIR/scripts/pm/status.sh" ]; then
            record_test_result "命令路由 - GitHub脚本" "PASS" "GitHub脚本路径正确"
        else
            record_test_result "命令路由 - GitHub脚本" "FAIL" "GitHub脚本不存在"
        fi
    else
        record_test_result "命令路由 - GitHub路由" "FAIL" "平台检测错误"
    fi

    # 测试2: 云效配置时路由到云效脚本
    echo "测试2: 云效命令路由"
    create_yunxiao_test_config

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "yunxiao" ]; then
        # 验证云效脚本存在
        if [ -f "$CLAUDE_DIR/scripts/pm/init-yunxiao.sh" ]; then
            record_test_result "命令路由 - 云效脚本" "PASS" "云效脚本路径正确"
        else
            record_test_result "命令路由 - 云效脚本" "FAIL" "云效脚本不存在"
        fi
    else
        record_test_result "命令路由 - 云效路由" "FAIL" "平台检测错误"
    fi

    # 测试3: 平台切换后路由更新
    echo "测试3: 平台切换路由更新"
    local prev_platform="yunxiao"
    local next_platform

    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: github
EOF

    next_platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$next_platform" = "github" ] && [ "$prev_platform" = "yunxiao" ]; then
        record_test_result "命令路由 - 平台切换" "PASS" "平台切换后路由正确更新"
    else
        record_test_result "命令路由 - 平台切换" "FAIL" "平台切换后路由未更新"
    fi

    echo ""
}

# =============================================================================
# 云效工作项CRUD测试（模拟）
# =============================================================================

test_yunxiao_workitem_crud() {
    echo "=== 云效工作项CRUD测试 ==="

    # 注意：这些测试需要实际的MCP连接，在无连接环境下跳过
    echo "注意: 云效工作项CRUD测试需要MCP连接"

    create_yunxiao_test_config

    # 测试1: 检查工作项脚本存在性
    echo "测试1: 工作项脚本存在性"
    local crud_scripts=(
        "yunxiao/create-workitem.sh"
        "yunxiao/get-workitem.sh"
        "yunxiao/update-workitem.sh"
        "yunxiao/delete-workitem.sh"
        "yunxiao/list-workitems.sh"
    )

    local all_scripts_exist=true
    for script in "${crud_scripts[@]}"; do
        if [ ! -f "$CLAUDE_DIR/scripts/pm/$script" ]; then
            all_scripts_exist=false
            echo "  ❌ 缺少脚本: $script"
        fi
    done

    if [ "$all_scripts_exist" = true ]; then
        record_test_result "工作项CRUD - 脚本存在" "PASS" "所有CRUD脚本都存在"
    else
        record_test_result "工作项CRUD - 脚本存在" "FAIL" "部分CRUD脚本缺失"
    fi

    # 测试2: 工作项公共库存在性
    echo "测试2: 工作项公共库"
    if [ -f "$CLAUDE_DIR/scripts/pm/yunxiao/workitem-common.sh" ]; then
        record_test_result "工作项CRUD - 公共库" "PASS" "公共库文件存在"
    else
        record_test_result "工作项CRUD - 公共库" "FAIL" "公共库文件不存在"
    fi

    echo ""
    echo "💡 完整的工作项CRUD测试需要在有MCP连接的环境中运行"
    echo ""
}

# =============================================================================
# Epic同步功能测试（模拟）
# =============================================================================

test_epic_sync_functionality() {
    echo "=== Epic同步功能测试 ==="

    create_yunxiao_test_config

    # 测试1: Epic同步脚本目录结构
    echo "测试1: Epic同步脚本结构"
    local epic_sync_scripts=(
        "epic-sync-yunxiao/sync-main.sh"
        "epic-sync-yunxiao/mapping-manager.sh"
        "epic-sync-yunxiao/local-to-remote.sh"
        "epic-sync-yunxiao/remote-to-local.sh"
        "epic-sync-yunxiao/conflict-resolver.sh"
        "epic-sync-yunxiao/progress-tracker.sh"
        "epic-sync-yunxiao/sync-validator.sh"
    )

    local all_scripts_exist=true
    for script in "${epic_sync_scripts[@]}"; do
        if [ ! -f "$CLAUDE_DIR/scripts/pm/$script" ]; then
            all_scripts_exist=false
            echo "  ❌ 缺少脚本: $script"
        fi
    done

    if [ "$all_scripts_exist" = true ]; then
        record_test_result "Epic同步 - 脚本结构" "PASS" "Epic同步脚本结构完整"
    else
        record_test_result "Epic同步 - 脚本结构" "FAIL" "Epic同步脚本结构不完整"
    fi

    # 测试2: Issue同步脚本存在性
    echo "测试2: Issue同步脚本"
    local issue_sync_scripts=(
        "issue-sync-yunxiao/preflight-validation-yunxiao.sh"
        "issue-sync-yunxiao/update-frontmatter-yunxiao.sh"
        "issue-sync-yunxiao/post-comment-yunxiao.sh"
        "issue-sync-yunxiao/check-sync-timing-yunxiao.sh"
        "issue-sync-yunxiao/calculate-epic-progress-yunxiao.sh"
    )

    all_scripts_exist=true
    for script in "${issue_sync_scripts[@]}"; do
        if [ ! -f "$CLAUDE_DIR/scripts/pm/$script" ]; then
            all_scripts_exist=false
            echo "  ❌ 缺少脚本: $script"
        fi
    done

    if [ "$all_scripts_exist" = true ]; then
        record_test_result "Issue同步 - 脚本存在" "PASS" "Issue同步脚本完整"
    else
        record_test_result "Issue同步 - 脚本存在" "FAIL" "Issue同步脚本不完整"
    fi

    echo ""
}

# =============================================================================
# 错误处理测试
# =============================================================================

test_error_handling() {
    echo "=== 错误处理测试 ==="

    # 测试1: 缺少配置文件时的错误处理
    echo "测试1: 缺少配置时默认行为"
    rm -f "$PROJECT_ROOT/.ccpm-config.yaml"

    local platform
    platform=$(cd "$PROJECT_ROOT" && source "$CLAUDE_DIR/lib/platform-detection.sh" && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "错误处理 - 缺少配置" "PASS" "正确回退到GitHub默认"
    else
        record_test_result "错误处理 - 缺少配置" "FAIL" "错误处理不正确"
    fi

    # 测试2: 配置文件格式错误
    echo "测试2: 配置格式错误处理"
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
invalid yaml content
  wrong: indentation
EOF

    # 尝试读取配置（应该回退到默认）
    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type 2>/dev/null)

    if [ "$platform" = "github" ]; then
        record_test_result "错误处理 - 格式错误" "PASS" "格式错误时正确回退"
    else
        record_test_result "错误处理 - 格式错误" "FAIL" "格式错误处理不当"
    fi

    # 测试3: 空配置文件
    echo "测试3: 空配置文件处理"
    echo "" > "$PROJECT_ROOT/.ccpm-config.yaml"

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "错误处理 - 空配置" "PASS" "空配置时正确回退"
    else
        record_test_result "错误处理 - 空配置" "FAIL" "空配置处理不当"
    fi

    echo ""
}

# =============================================================================
# 主测试函数
# =============================================================================

run_yunxiao_complete_tests() {
    setup_yunxiao_test_environment

    # 允许单个测试失败但继续执行
    set +e

    # 执行所有测试
    test_platform_detection
    test_config_validation
    test_command_routing
    test_yunxiao_workitem_crud
    test_epic_sync_functionality
    test_error_handling

    # 生成测试报告
    show_test_summary

    cleanup_yunxiao_test_environment

    # 返回测试结果
    if [ $FAILED_TESTS -gt 0 ]; then
        echo "❌ 云效功能测试失败: $FAILED_TESTS 个测试失败"
        return 1
    else
        echo "✅ 云效功能测试通过: 所有 $PASSED_TESTS 个测试成功"
        return 0
    fi
}

# 显示帮助信息
show_help() {
    cat << EOF
云效功能完整性测试工具

用法:
    $0 [选项]

选项:
    --platform      仅测试平台检测功能
    --config        仅测试配置验证功能
    --routing       仅测试命令路由功能
    --workitem      仅测试工作项CRUD功能
    --epic          仅测试Epic同步功能
    --error         仅测试错误处理功能
    -v, --verbose   详细输出模式
    -h, --help      显示此帮助信息

示例:
    $0                    # 运行所有云效功能测试
    $0 --platform         # 仅测试平台检测
    $0 --verbose          # 详细输出模式

EOF
}

# =============================================================================
# 主程序
# =============================================================================

main() {
    local test_mode="all"

    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --platform)
                test_mode="platform"
                shift
                ;;
            --config)
                test_mode="config"
                shift
                ;;
            --routing)
                test_mode="routing"
                shift
                ;;
            --workitem)
                test_mode="workitem"
                shift
                ;;
            --epic)
                test_mode="epic"
                shift
                ;;
            --error)
                test_mode="error"
                shift
                ;;
            -v|--verbose)
                export DEBUG_MODE=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo "无效选项: $1" >&2
                show_help
                exit 1
                ;;
        esac
    done

    # 根据模式运行测试
    case "$test_mode" in
        all)
            run_yunxiao_complete_tests
            ;;
        platform)
            setup_yunxiao_test_environment
            test_platform_detection
            show_test_summary
            cleanup_yunxiao_test_environment
            ;;
        config)
            setup_yunxiao_test_environment
            test_config_validation
            show_test_summary
            cleanup_yunxiao_test_environment
            ;;
        routing)
            setup_yunxiao_test_environment
            test_command_routing
            show_test_summary
            cleanup_yunxiao_test_environment
            ;;
        workitem)
            setup_yunxiao_test_environment
            test_yunxiao_workitem_crud
            show_test_summary
            cleanup_yunxiao_test_environment
            ;;
        epic)
            setup_yunxiao_test_environment
            test_epic_sync_functionality
            show_test_summary
            cleanup_yunxiao_test_environment
            ;;
        error)
            setup_yunxiao_test_environment
            test_error_handling
            show_test_summary
            cleanup_yunxiao_test_environment
            ;;
    esac
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi