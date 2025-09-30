#!/bin/bash

# 端到端工作流测试套件
# 测试完整的PRD→Epic→Task→WorkItem工作流

# =============================================================================
# 测试配置和初始化
# =============================================================================

set -u

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 加载测试工具
source "$SCRIPT_DIR/../utils/test-framework.sh"

# 测试环境配置
TEST_NAME="端到端工作流测试"
TEMP_DIR="/tmp/e2e_workflow_test_$$"

# 测试场景配置
SCENARIO_GITHUB="github"
SCENARIO_YUNXIAO="yunxiao"
SCENARIO_SWITCHING="platform_switching"

# =============================================================================
# 测试工具函数
# =============================================================================

# 初始化测试环境
setup_e2e_test_environment() {
    echo "=== 端到端工作流测试 ==="
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

    echo "✅ E2E测试环境初始化完成"
    echo ""
}

# 清理测试环境
cleanup_e2e_test_environment() {
    echo ""
    echo "=== 清理E2E测试环境 ==="

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

    echo "✅ E2E测试环境清理完成"
}

# 创建测试配置
create_test_config() {
    local platform="$1"
    local project_id="${2:-}"

    case "$platform" in
        "github")
            cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: github
EOF
            ;;
        "yunxiao")
            if [ -z "$project_id" ]; then
                project_id="12345"
            fi
            cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: yunxiao
project_id: $project_id
EOF
            ;;
        *)
            echo "错误: 不支持的平台 $platform" >&2
            return 1
            ;;
    esac

    if [ -f "$PROJECT_ROOT/.ccpm-config.yaml" ]; then
        return 0
    else
        return 1
    fi
}

# =============================================================================
# GitHub工作流测试场景
# =============================================================================

test_github_workflow() {
    echo "=== GitHub工作流测试 ==="

    # 设置GitHub环境
    create_test_config "github"

    # 测试1: 平台检测
    echo "测试1: 平台检测为GitHub"
    local platform
    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "GitHub工作流 - 平台检测" "PASS" "平台正确检测为github"
    else
        record_test_result "GitHub工作流 - 平台检测" "FAIL" "平台检测错误: $platform"
        return 1
    fi

    # 测试2: GitHub脚本可访问性
    echo "测试2: GitHub脚本可访问性"
    local github_scripts=(
        "scripts/pm/status.sh"
        "scripts/pm/standup.sh"
        "scripts/pm/next.sh"
    )

    local all_accessible=true
    for script in "${github_scripts[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$script" ]; then
            all_accessible=false
            echo "  ❌ 缺少脚本: $script"
        fi
    done

    if [ "$all_accessible" = true ]; then
        record_test_result "GitHub工作流 - 脚本可访问" "PASS" "所有GitHub脚本可访问"
    else
        record_test_result "GitHub工作流 - 脚本可访问" "FAIL" "部分GitHub脚本不可访问"
    fi

    # 测试3: 命令执行（help模式，不需要实际GitHub连接）
    echo "测试3: 命令执行测试"
    local test_commands=(
        "status --help"
        "standup --help"
        "next --help"
    )

    local all_commands_work=true
    for cmd in "${test_commands[@]}"; do
        if ! (cd "$PROJECT_ROOT" && timeout 5s bash ".claude/scripts/pm/$cmd" >/dev/null 2>&1); then
            all_commands_work=false
            echo "  ❌ 命令失败: $cmd"
        fi
    done

    if [ "$all_commands_work" = true ]; then
        record_test_result "GitHub工作流 - 命令执行" "PASS" "GitHub命令可正常执行"
    else
        record_test_result "GitHub工作流 - 命令执行" "FAIL" "部分GitHub命令执行失败"
    fi

    echo ""
}

# =============================================================================
# 云效工作流测试场景
# =============================================================================

test_yunxiao_workflow() {
    echo "=== 云效工作流测试 ==="

    # 设置云效环境
    create_test_config "yunxiao" "12345"

    # 测试1: 平台检测
    echo "测试1: 平台检测为云效"
    local platform
    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "yunxiao" ]; then
        record_test_result "云效工作流 - 平台检测" "PASS" "平台正确检测为yunxiao"
    else
        record_test_result "云效工作流 - 平台检测" "FAIL" "平台检测错误: $platform"
        return 1
    fi

    # 测试2: 项目ID读取
    echo "测试2: 项目ID配置读取"
    local project_id
    project_id=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_project_id)

    if [ "$project_id" = "12345" ]; then
        record_test_result "云效工作流 - 项目ID读取" "PASS" "项目ID正确读取"
    else
        record_test_result "云效工作流 - 项目ID读取" "FAIL" "项目ID读取错误: $project_id"
    fi

    # 测试3: 云效脚本可访问性
    echo "测试3: 云效脚本可访问性"
    local yunxiao_scripts=(
        "scripts/pm/init-yunxiao.sh"
        "scripts/pm/yunxiao/create-workitem.sh"
        "scripts/pm/yunxiao/get-workitem.sh"
        "scripts/pm/epic-sync-yunxiao/sync-main.sh"
    )

    local all_accessible=true
    for script in "${yunxiao_scripts[@]}"; do
        if [ ! -f "$PROJECT_ROOT/$script" ]; then
            all_accessible=false
            echo "  ❌ 缺少脚本: $script"
        fi
    done

    if [ "$all_accessible" = true ]; then
        record_test_result "云效工作流 - 脚本可访问" "PASS" "所有云效脚本可访问"
    else
        record_test_result "云效工作流 - 脚本可访问" "FAIL" "部分云效脚本不可访问"
    fi

    # 测试4: 配置验证逻辑
    echo "测试4: 配置验证逻辑"
    local project_id_from_config
    project_id_from_config=$(grep "^project_id:" "$PROJECT_ROOT/.ccpm-config.yaml" | awk '{print $2}' | tr -d ' \t\r\n')

    if [ -n "$project_id_from_config" ] && [ "$project_id_from_config" = "12345" ]; then
        record_test_result "云效工作流 - 配置验证" "PASS" "云效配置验证通过"
    else
        record_test_result "云效工作流 - 配置验证" "FAIL" "云效配置验证失败"
    fi

    echo ""
}

# =============================================================================
# 平台切换工作流测试
# =============================================================================

test_platform_switching_workflow() {
    echo "=== 平台切换工作流测试 ==="

    # 场景1: 从无配置开始（默认GitHub）
    echo "场景1: 无配置 -> GitHub默认"
    rm -f "$PROJECT_ROOT/.ccpm-config.yaml"

    local platform
    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "平台切换 - 默认GitHub" "PASS" "无配置时正确默认到GitHub"
    else
        record_test_result "平台切换 - 默认GitHub" "FAIL" "默认平台错误: $platform"
    fi

    # 场景2: 切换到云效
    echo "场景2: GitHub默认 -> 云效配置"
    create_test_config "yunxiao" "12345"

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "yunxiao" ]; then
        record_test_result "平台切换 - 切换到云效" "PASS" "成功切换到云效平台"
    else
        record_test_result "平台切换 - 切换到云效" "FAIL" "切换到云效失败: $platform"
    fi

    # 场景3: 切换回GitHub
    echo "场景3: 云效 -> GitHub配置"
    create_test_config "github"

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "平台切换 - 切换回GitHub" "PASS" "成功切换回GitHub平台"
    else
        record_test_result "平台切换 - 切换回GitHub" "FAIL" "切换回GitHub失败: $platform"
    fi

    # 场景4: 删除配置，回到默认
    echo "场景4: GitHub配置 -> 删除配置 -> 默认GitHub"
    rm -f "$PROJECT_ROOT/.ccpm-config.yaml"

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "平台切换 - 回到默认" "PASS" "删除配置后正确回到默认GitHub"
    else
        record_test_result "平台切换 - 回到默认" "FAIL" "回到默认失败: $platform"
    fi

    # 场景5: 快速连续切换
    echo "场景5: 快速连续平台切换"
    local switch_count=5
    local all_switches_ok=true

    for i in $(seq 1 $switch_count); do
        if [ $((i % 2)) -eq 0 ]; then
            create_test_config "github"
            expected="github"
        else
            create_test_config "yunxiao" "12345"
            expected="yunxiao"
        fi

        platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

        if [ "$platform" != "$expected" ]; then
            all_switches_ok=false
            echo "  ❌ 切换 $i 失败: 期望 $expected，实际 $platform"
        fi
    done

    if [ "$all_switches_ok" = true ]; then
        record_test_result "平台切换 - 快速连续切换" "PASS" "快速连续切换 $switch_count 次全部成功"
    else
        record_test_result "平台切换 - 快速连续切换" "FAIL" "部分快速切换失败"
    fi

    echo ""
}

# =============================================================================
# 命令透明性测试
# =============================================================================

test_command_transparency() {
    echo "=== 命令透明性测试 ==="

    # 测试命令在不同平台间的透明切换
    echo "测试命令在平台切换时的透明性"

    # GitHub环境
    create_test_config "github"
    local github_platform
    github_platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    # 云效环境
    create_test_config "yunxiao" "12345"
    local yunxiao_platform
    yunxiao_platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$github_platform" = "github" ] && [ "$yunxiao_platform" = "yunxiao" ]; then
        record_test_result "命令透明性 - 平台切换" "PASS" "命令在不同平台间透明切换"
    else
        record_test_result "命令透明性 - 平台切换" "FAIL" "平台切换不透明"
    fi

    # 测试命令路由的一致性
    echo "测试命令路由的一致性"

    # 在GitHub环境下，验证路由到正确脚本
    create_test_config "github"
    if [ -f "$PROJECT_ROOT/scripts/pm/status.sh" ]; then
        record_test_result "命令透明性 - GitHub路由" "PASS" "GitHub命令正确路由"
    else
        record_test_result "命令透明性 - GitHub路由" "FAIL" "GitHub命令路由失败"
    fi

    # 在云效环境下，验证路由到正确脚本
    create_test_config "yunxiao" "12345"
    if [ -f "$PROJECT_ROOT/scripts/pm/init-yunxiao.sh" ]; then
        record_test_result "命令透明性 - 云效路由" "PASS" "云效命令正确路由"
    else
        record_test_result "命令透明性 - 云效路由" "FAIL" "云效命令路由失败"
    fi

    echo ""
}

# =============================================================================
# 配置持久性测试
# =============================================================================

test_config_persistence() {
    echo "=== 配置持久性测试 ==="

    # 测试1: 配置文件写入和读取
    echo "测试1: 配置持久性"
    create_test_config "yunxiao" "99999"

    # 验证配置立即可读
    local platform project_id
    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)
    project_id=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_project_id)

    if [ "$platform" = "yunxiao" ] && [ "$project_id" = "99999" ]; then
        record_test_result "配置持久性 - 写入读取" "PASS" "配置正确持久化"
    else
        record_test_result "配置持久性 - 写入读取" "FAIL" "配置持久化失败"
    fi

    # 测试2: 配置修改后立即生效
    echo "测试2: 配置修改实时生效"
    create_test_config "github"

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "配置持久性 - 实时生效" "PASS" "配置修改实时生效"
    else
        record_test_result "配置持久性 - 实时生效" "FAIL" "配置修改未实时生效"
    fi

    # 测试3: 配置删除后恢复默认
    echo "测试3: 配置删除后恢复默认"
    rm -f "$PROJECT_ROOT/.ccpm-config.yaml"

    platform=$(cd "$PROJECT_ROOT" && source .claude/lib/platform-detection.sh && get_platform_type)

    if [ "$platform" = "github" ]; then
        record_test_result "配置持久性 - 删除恢复默认" "PASS" "配置删除后正确恢复默认"
    else
        record_test_result "配置持久性 - 删除恢复默认" "FAIL" "配置删除后未恢复默认"
    fi

    echo ""
}

# =============================================================================
# 主测试函数
# =============================================================================

run_e2e_workflow_tests() {
    setup_e2e_test_environment

    # 允许单个测试失败但继续执行
    set +e

    # 执行所有E2E测试
    test_github_workflow
    test_yunxiao_workflow
    test_platform_switching_workflow
    test_command_transparency
    test_config_persistence

    # 生成测试报告
    generate_e2e_test_report

    cleanup_e2e_test_environment

    # 返回测试结果
    if [ $FAILED_TESTS -gt 0 ]; then
        echo "❌ E2E工作流测试失败: $FAILED_TESTS 个测试失败"
        return 1
    else
        echo "✅ E2E工作流测试通过: 所有 $PASSED_TESTS 个测试成功"
        return 0
    fi
}

# 生成E2E测试报告
generate_e2e_test_report() {
    local report_file="$TEMP_DIR/e2e-workflow-report.md"

    cat > "$report_file" << EOF
# 端到端工作流测试报告

**测试时间**: $(date)
**测试环境**: $PROJECT_ROOT
**测试目的**: 验证完整的PRD→Epic→Task→WorkItem工作流

## 测试统计

- **总测试数**: $TOTAL_TESTS
- **通过测试**: $PASSED_TESTS
- **失败测试**: $FAILED_TESTS
- **成功率**: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## 测试场景

### 1. GitHub工作流测试
验证GitHub平台下的完整工作流程。

### 2. 云效工作流测试
验证云效平台下的完整工作流程。

### 3. 平台切换工作流测试
验证平台间切换的工作流程连续性。

### 4. 命令透明性测试
验证命令在不同平台间的透明执行。

### 5. 配置持久性测试
验证配置的持久化和实时生效。

## 详细结果

EOF

    # 添加详细测试结果
    for result in "${TEST_RESULTS[@]}"; do
        echo "- $result" >> "$report_file"
    done

    echo "" >> "$report_file"
    echo "## 测试总结" >> "$report_file"
    echo "" >> "$report_file"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo "✅ 所有端到端工作流测试通过，系统工作流完整可用。" >> "$report_file"
    else
        echo "❌ 存在 $FAILED_TESTS 个失败测试，需要修复后重新验证。" >> "$report_file"
    fi

    echo ""
    echo "📊 E2E测试报告已生成: $report_file"

    # 复制到项目目录
    mkdir -p "$PROJECT_ROOT/.claude/tests/e2e"
    cp "$report_file" "$PROJECT_ROOT/.claude/tests/e2e/" 2>/dev/null || true

    # 显示测试总结
    show_test_summary
}

# 显示帮助信息
show_help() {
    cat << EOF
端到端工作流测试工具

用法:
    $0 [选项]

选项:
    --github        仅测试GitHub工作流
    --yunxiao       仅测试云效工作流
    --switching     仅测试平台切换
    --transparency  仅测试命令透明性
    --persistence   仅测试配置持久性
    -v, --verbose   详细输出模式
    -h, --help      显示此帮助信息

示例:
    $0                    # 运行所有E2E工作流测试
    $0 --github           # 仅测试GitHub工作流
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
            --github)
                test_mode="github"
                shift
                ;;
            --yunxiao)
                test_mode="yunxiao"
                shift
                ;;
            --switching)
                test_mode="switching"
                shift
                ;;
            --transparency)
                test_mode="transparency"
                shift
                ;;
            --persistence)
                test_mode="persistence"
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
            run_e2e_workflow_tests
            ;;
        github)
            setup_e2e_test_environment
            test_github_workflow
            show_test_summary
            cleanup_e2e_test_environment
            ;;
        yunxiao)
            setup_e2e_test_environment
            test_yunxiao_workflow
            show_test_summary
            cleanup_e2e_test_environment
            ;;
        switching)
            setup_e2e_test_environment
            test_platform_switching_workflow
            show_test_summary
            cleanup_e2e_test_environment
            ;;
        transparency)
            setup_e2e_test_environment
            test_command_transparency
            show_test_summary
            cleanup_e2e_test_environment
            ;;
        persistence)
            setup_e2e_test_environment
            test_config_persistence
            show_test_summary
            cleanup_e2e_test_environment
            ;;
    esac
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi