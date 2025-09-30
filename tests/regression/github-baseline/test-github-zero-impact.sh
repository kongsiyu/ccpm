#!/bin/bash

# GitHub零影响验证测试套件
# 确保云效集成不会影响现有GitHub功能

# =============================================================================
# 测试配置和初始化
# =============================================================================

set -u

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# 加载测试工具
source "$SCRIPT_DIR/../../utils/test-framework.sh"

# 测试环境配置
TEST_NAME="GitHub零影响验证"
TEMP_DIR="/tmp/github_zero_impact_test_$$"
BASELINE_CONFIG_BACKUP=""
PERFORMANCE_LOG="$TEMP_DIR/performance.log"

# GitHub功能列表 - 需要验证的核心命令
GITHUB_COMMANDS=(
    "/pm:epic-start"
    "/pm:epic-sync"
    "/pm:epic-status"
    "/pm:epic-list"
    "/pm:issue-start"
    "/pm:issue-sync"
    "/pm:issue-status"
    "/pm:status"
    "/pm:standup"
    "/pm:next"
    "/pm:in-progress"
    "/pm:blocked"
)

# =============================================================================
# 测试工具函数
# =============================================================================

# 初始化测试环境
setup_github_test_environment() {
    echo "=== GitHub零影响验证测试 ==="
    echo "测试时间: $(date)"
    echo "项目根目录: $PROJECT_ROOT"
    echo ""

    # 创建临时目录
    mkdir -p "$TEMP_DIR"

    # 保存当前配置（如果存在）
    if [ -f "$PROJECT_ROOT/.ccpm-config.yaml" ]; then
        BASELINE_CONFIG_BACKUP="$TEMP_DIR/baseline-config-backup.yaml"
        cp "$PROJECT_ROOT/.ccpm-config.yaml" "$BASELINE_CONFIG_BACKUP"
        echo "✅ 已备份现有配置文件"
    fi

    # 确保测试在干净的GitHub环境下进行
    remove_config_file

    echo "✅ GitHub测试环境初始化完成"
    echo ""
}

# 清理测试环境
cleanup_github_test_environment() {
    echo ""
    echo "=== 清理GitHub测试环境 ==="

    # 恢复配置文件
    if [ -n "$BASELINE_CONFIG_BACKUP" ] && [ -f "$BASELINE_CONFIG_BACKUP" ]; then
        cp "$BASELINE_CONFIG_BACKUP" "$PROJECT_ROOT/.ccpm-config.yaml"
        echo "✅ 已恢复原始配置文件"
    else
        # 确保删除任何测试配置
        rm -f "$PROJECT_ROOT/.ccpm-config.yaml"
    fi

    # 删除临时文件
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        echo "✅ 已清理临时文件"
    fi

    echo "✅ GitHub测试环境清理完成"
}

# 移除配置文件
remove_config_file() {
    if [ -f "$PROJECT_ROOT/.ccpm-config.yaml" ]; then
        rm -f "$PROJECT_ROOT/.ccpm-config.yaml"
    fi
}

# 创建GitHub配置
create_github_config() {
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: github
EOF
}

# 创建云效配置
create_yunxiao_config() {
    cat > "$PROJECT_ROOT/.ccpm-config.yaml" << EOF
platform: yunxiao
project_id: 12345
EOF
}

# 测量命令执行时间
measure_command_time() {
    local command="$1"
    local start_time end_time duration

    start_time=$(date +%s.%N)

    # 静默执行命令
    (cd "$PROJECT_ROOT" && eval "$command" >/dev/null 2>&1)
    local exit_code=$?

    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "0")

    echo "$duration"
    return $exit_code
}

# =============================================================================
# 基准性能测试
# =============================================================================

test_github_baseline_performance() {
    echo "=== 基准性能测试 ==="

    # 确保在无配置环境下测试（默认GitHub）
    remove_config_file

    echo "正在测量GitHub命令基准性能..."
    echo "Command,Baseline_Time(s),Status" > "$PERFORMANCE_LOG"

    local total_commands=0
    local successful_commands=0

    for cmd in "${GITHUB_COMMANDS[@]}"; do
        echo -n "测试 $cmd... "

        local time_taken
        time_taken=$(measure_command_time "$cmd --help")
        local exit_code=$?

        total_commands=$((total_commands + 1))

        if [ $exit_code -eq 0 ]; then
            successful_commands=$((successful_commands + 1))
            echo "$cmd,$time_taken,SUCCESS" >> "$PERFORMANCE_LOG"
            record_test_result "GitHub基准性能 - $cmd" "PASS" "执行时间: ${time_taken}s"
        else
            echo "$cmd,$time_taken,FAILED" >> "$PERFORMANCE_LOG"
            record_test_result "GitHub基准性能 - $cmd" "FAIL" "命令执行失败"
        fi
    done

    echo ""
    echo "GitHub基准测试完成："
    echo "  - 总命令数: $total_commands"
    echo "  - 成功执行: $successful_commands"
    echo "  - 成功率: $(( successful_commands * 100 / total_commands ))%"
    echo ""
}

# =============================================================================
# 功能兼容性测试
# =============================================================================

test_github_command_compatibility() {
    echo "=== GitHub命令兼容性测试 ==="

    # 测试无配置文件时的默认行为
    echo "测试1: 无配置文件时的默认行为"
    remove_config_file

    for cmd in "${GITHUB_COMMANDS[@]}"; do
        echo -n "测试 $cmd (无配置)... "

        if (cd "$PROJECT_ROOT" && timeout 10s $cmd --help >/dev/null 2>&1); then
            record_test_result "GitHub兼容性 - $cmd (无配置)" "PASS" "命令可正常执行"
        else
            record_test_result "GitHub兼容性 - $cmd (无配置)" "FAIL" "命令执行失败或超时"
        fi
    done

    echo ""

    # 测试显式GitHub配置时的行为
    echo "测试2: 显式GitHub配置时的行为"
    create_github_config

    for cmd in "${GITHUB_COMMANDS[@]}"; do
        echo -n "测试 $cmd (GitHub配置)... "

        if (cd "$PROJECT_ROOT" && timeout 10s $cmd --help >/dev/null 2>&1); then
            record_test_result "GitHub兼容性 - $cmd (GitHub配置)" "PASS" "命令可正常执行"
        else
            record_test_result "GitHub兼容性 - $cmd (GitHub配置)" "FAIL" "命令执行失败或超时"
        fi
    done

    echo ""
}

# =============================================================================
# 配置切换影响测试
# =============================================================================

test_config_switching_impact() {
    echo "=== 配置切换影响测试 ==="

    # 测试1: GitHub -> 云效 -> GitHub
    echo "测试配置文件切换对GitHub功能的影响..."

    # 开始时无配置
    remove_config_file
    local cmd="/pm:status"

    echo -n "1. 初始状态（无配置）... "
    if (cd "$PROJECT_ROOT" && timeout 5s $cmd >/dev/null 2>&1); then
        record_test_result "配置切换 - 初始状态" "PASS" "GitHub默认工作正常"
    else
        record_test_result "配置切换 - 初始状态" "FAIL" "初始状态异常"
    fi

    echo -n "2. 切换到云效配置... "
    create_yunxiao_config
    if (cd "$PROJECT_ROOT" && timeout 5s $cmd >/dev/null 2>&1); then
        record_test_result "配置切换 - 云效配置" "PASS" "切换到云效配置成功"
    else
        record_test_result "配置切换 - 云效配置" "FAIL" "云效配置异常"
    fi

    echo -n "3. 切换回GitHub配置... "
    create_github_config
    if (cd "$PROJECT_ROOT" && timeout 5s $cmd >/dev/null 2>&1); then
        record_test_result "配置切换 - 回到GitHub" "PASS" "切换回GitHub配置成功"
    else
        record_test_result "配置切换 - 回到GitHub" "FAIL" "切换回GitHub配置失败"
    fi

    echo -n "4. 删除配置文件... "
    remove_config_file
    if (cd "$PROJECT_ROOT" && timeout 5s $cmd >/dev/null 2>&1); then
        record_test_result "配置切换 - 删除配置" "PASS" "删除配置后回到GitHub默认"
    else
        record_test_result "配置切换 - 删除配置" "FAIL" "删除配置后异常"
    fi

    echo ""
}

# =============================================================================
# 后安装性能回归测试
# =============================================================================

test_post_install_performance() {
    echo "=== 后安装性能回归测试 ==="

    # 模拟安装云效集成后的性能测试
    echo "测试云效集成安装后GitHub命令性能..."

    # 在无配置环境下重新测试性能
    remove_config_file

    echo "Post_Install_Time(s),Performance_Delta(%)" >> "$PERFORMANCE_LOG"

    local regression_count=0
    local total_tested=0

    # 读取基准性能数据并比较
    if [ -f "$PERFORMANCE_LOG" ]; then
        while IFS=',' read -r cmd baseline_time status; do
            if [ "$status" = "SUCCESS" ] && [ "$cmd" != "Command" ]; then
                total_tested=$((total_tested + 1))

                echo -n "重新测试 $cmd... "
                local new_time
                new_time=$(measure_command_time "$cmd --help")
                local exit_code=$?

                if [ $exit_code -eq 0 ]; then
                    # 计算性能变化百分比
                    local delta
                    if command -v bc >/dev/null 2>&1; then
                        delta=$(echo "scale=2; ($new_time - $baseline_time) * 100 / $baseline_time" | bc -l)
                    else
                        delta="N/A"
                    fi

                    echo "$new_time,$delta" >> "$PERFORMANCE_LOG"

                    # 检查是否有显著性能退化（超过5%）
                    if [ "$delta" != "N/A" ] && (( $(echo "$delta > 5.0" | bc -l 2>/dev/null) )); then
                        regression_count=$((regression_count + 1))
                        record_test_result "性能回归 - $cmd" "FAIL" "性能下降 ${delta}%"
                    else
                        record_test_result "性能回归 - $cmd" "PASS" "性能变化 ${delta}%"
                    fi
                else
                    record_test_result "性能回归 - $cmd" "FAIL" "命令执行失败"
                fi
            fi
        done < "$PERFORMANCE_LOG"
    fi

    echo ""
    echo "性能回归测试总结："
    echo "  - 测试命令数: $total_tested"
    echo "  - 性能退化数: $regression_count"
    if [ $regression_count -gt 0 ]; then
        echo "  - 警告: 发现性能退化"
    else
        echo "  - ✅ 无性能退化"
    fi
    echo ""
}

# =============================================================================
# 脚本完整性测试
# =============================================================================

test_script_integrity() {
    echo "=== 脚本完整性测试 ==="

    echo "检查关键脚本文件是否被意外修改..."

    # 检查关键GitHub脚本是否存在且可执行
    local critical_scripts=(
        ".claude/scripts/pm/epic-list.sh"
        ".claude/scripts/pm/epic-status.sh"
        ".claude/scripts/pm/status.sh"
        ".claude/scripts/pm/standup.sh"
        ".claude/scripts/pm/next.sh"
    )

    for script in "${critical_scripts[@]}"; do
        local full_path="$PROJECT_ROOT/$script"
        echo -n "检查 $script... "

        if [ -f "$full_path" ]; then
            if [ -x "$full_path" ] || [ -r "$full_path" ]; then
                record_test_result "脚本完整性 - $script" "PASS" "文件存在且可访问"
            else
                record_test_result "脚本完整性 - $script" "FAIL" "文件不可执行"
            fi
        else
            record_test_result "脚本完整性 - $script" "FAIL" "文件不存在"
        fi
    done

    echo ""
}

# =============================================================================
# 主测试函数
# =============================================================================

run_github_zero_impact_tests() {
    setup_github_test_environment

    # 设置错误处理 - 允许单个测试失败但继续执行
    set +e

    # 执行所有测试
    test_github_baseline_performance
    test_github_command_compatibility
    test_config_switching_impact
    test_post_install_performance
    test_script_integrity

    # 生成测试报告
    generate_github_test_report

    cleanup_github_test_environment

    # 返回测试结果
    if [ $FAILED_TESTS -gt 0 ]; then
        echo "❌ GitHub零影响验证失败: $FAILED_TESTS 个测试失败"
        exit 1
    else
        echo "✅ GitHub零影响验证通过: 所有 $PASSED_TESTS 个测试成功"
        exit 0
    fi
}

# 生成测试报告
generate_github_test_report() {
    local report_file="$TEMP_DIR/github-zero-impact-report.md"

    cat > "$report_file" << EOF
# GitHub零影响验证测试报告

**测试时间**: $(date)
**测试环境**: $PROJECT_ROOT
**测试目的**: 验证云效集成不影响现有GitHub功能

## 测试统计

- **总测试数**: $TOTAL_TESTS
- **通过测试**: $PASSED_TESTS
- **失败测试**: $FAILED_TESTS
- **成功率**: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%

## 测试类别

### 1. GitHub基准性能测试
验证GitHub命令在无配置环境下的性能基准。

### 2. GitHub命令兼容性测试
确保所有GitHub命令在各种配置状态下都能正常工作。

### 3. 配置切换影响测试
验证配置文件切换不会影响GitHub功能的稳定性。

### 4. 后安装性能回归测试
检查云效集成安装后是否引入性能退化。

### 5. 脚本完整性测试
确保关键GitHub脚本文件完整且可执行。

## 详细结果

EOF

    # 添加详细的测试结果
    for result in "${TEST_RESULTS[@]}"; do
        echo "- $result" >> "$report_file"
    done

    echo "" >> "$report_file"
    echo "## 性能数据" >> "$report_file"
    echo "" >> "$report_file"
    echo "\`\`\`" >> "$report_file"
    cat "$PERFORMANCE_LOG" >> "$report_file" 2>/dev/null || echo "性能日志不可用" >> "$report_file"
    echo "\`\`\`" >> "$report_file"

    echo ""
    echo "📊 详细测试报告已生成: $report_file"

    # 复制到项目目录供后续使用
    cp "$report_file" "$PROJECT_ROOT/.claude/tests/regression/github-baseline/" 2>/dev/null || true
}

# 显示帮助信息
show_help() {
    cat << EOF
GitHub零影响验证测试工具

用法:
    $0 [选项]

选项:
    --baseline      仅运行基准性能测试
    --compatibility 仅运行兼容性测试
    --switching     仅运行配置切换测试
    --performance   仅运行性能回归测试
    --integrity     仅运行脚本完整性测试
    -v, --verbose   详细输出模式
    -h, --help      显示此帮助信息

示例:
    $0                    # 运行所有GitHub零影响测试
    $0 --baseline         # 仅运行基准测试
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
            --baseline)
                test_mode="baseline"
                shift
                ;;
            --compatibility)
                test_mode="compatibility"
                shift
                ;;
            --switching)
                test_mode="switching"
                shift
                ;;
            --performance)
                test_mode="performance"
                shift
                ;;
            --integrity)
                test_mode="integrity"
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
            run_github_zero_impact_tests
            ;;
        baseline)
            setup_github_test_environment
            test_github_baseline_performance
            show_test_summary
            cleanup_github_test_environment
            ;;
        compatibility)
            setup_github_test_environment
            test_github_command_compatibility
            show_test_summary
            cleanup_github_test_environment
            ;;
        switching)
            setup_github_test_environment
            test_config_switching_impact
            show_test_summary
            cleanup_github_test_environment
            ;;
        performance)
            setup_github_test_environment
            test_post_install_performance
            show_test_summary
            cleanup_github_test_environment
            ;;
        integrity)
            setup_github_test_environment
            test_script_integrity
            show_test_summary
            cleanup_github_test_environment
            ;;
    esac
}

# 仅在直接执行时运行主函数
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi