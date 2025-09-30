#!/bin/bash

# 测试框架工具
# 提供统一的测试工具函数和结果管理

# =============================================================================
# 全局变量
# =============================================================================

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
TEST_RESULTS=()

# 测试配置
TEST_TIMEOUT=30
DEBUG_MODE=${DEBUG_MODE:-0}

# 颜色输出
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# =============================================================================
# 日志和输出函数
# =============================================================================

# 记录测试结果
record_test_result() {
    local test_name="$1"
    local result="$2"  # "PASS", "FAIL", "SKIP"
    local details="${3:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    case "$result" in
        "PASS")
            PASSED_TESTS=$((PASSED_TESTS + 1))
            echo -e "${GREEN}✅ $test_name${NC}"
            ;;
        "FAIL")
            FAILED_TESTS=$((FAILED_TESTS + 1))
            echo -e "${RED}❌ $test_name${NC}"
            if [ -n "$details" ]; then
                echo -e "${RED}   错误: $details${NC}"
            fi
            ;;
        "SKIP")
            SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
            echo -e "${YELLOW}⏭️ $test_name (跳过)${NC}"
            ;;
    esac

    TEST_RESULTS+=("$result: $test_name - $details")

    # 调试模式下记录详细信息
    if [ "$DEBUG_MODE" = "1" ]; then
        echo "DEBUG: $(date): $result: $test_name - $details" >&2
    fi
}

# 显示测试总结
show_test_summary() {
    echo ""
    echo "=========================="
    echo -e "${BLUE}测试总结${NC}"
    echo "=========================="
    echo "总测试数: $TOTAL_TESTS"
    echo -e "${GREEN}通过: $PASSED_TESTS${NC}"
    echo -e "${RED}失败: $FAILED_TESTS${NC}"
    echo -e "${YELLOW}跳过: $SKIPPED_TESTS${NC}"

    if [ $TOTAL_TESTS -gt 0 ]; then
        echo "成功率: $(( PASSED_TESTS * 100 / TOTAL_TESTS ))%"
    fi
    echo ""

    # 显示失败的测试详情
    if [ $FAILED_TESTS -gt 0 ]; then
        echo -e "${RED}失败的测试:${NC}"
        for result in "${TEST_RESULTS[@]}"; do
            if [[ "$result" == FAIL:* ]]; then
                echo -e "${RED}  $result${NC}"
            fi
        done
        echo ""
    fi

    echo "=========================="
}

# =============================================================================
# 测试执行函数
# =============================================================================

# 运行命令并检查结果
run_test_command() {
    local test_name="$1"
    local command="$2"
    local expected_exit_code="${3:-0}"
    local timeout="${4:-$TEST_TIMEOUT}"

    if [ "$DEBUG_MODE" = "1" ]; then
        echo "DEBUG: 执行命令: $command" >&2
    fi

    local output
    local exit_code

    # 使用timeout执行命令
    if command -v timeout >/dev/null 2>&1; then
        output=$(timeout "$timeout" bash -c "$command" 2>&1)
        exit_code=$?

        # 检查是否超时
        if [ $exit_code -eq 124 ]; then
            record_test_result "$test_name" "FAIL" "命令执行超时 (${timeout}s)"
            return 1
        fi
    else
        # 如果没有timeout命令，直接执行
        output=$(bash -c "$command" 2>&1)
        exit_code=$?
    fi

    # 检查退出码
    if [ $exit_code -eq $expected_exit_code ]; then
        record_test_result "$test_name" "PASS" "退出码: $exit_code"
        return 0
    else
        local details="期望退出码: $expected_exit_code, 实际退出码: $exit_code"
        if [ "$DEBUG_MODE" = "1" ] && [ -n "$output" ]; then
            details="$details, 输出: $output"
        fi
        record_test_result "$test_name" "FAIL" "$details"
        return 1
    fi
}

# 断言函数
assert_success() {
    local test_name="$1"
    local exit_code="$2"

    if [ $exit_code -eq 0 ]; then
        record_test_result "$test_name" "PASS" "断言成功"
        return 0
    else
        record_test_result "$test_name" "FAIL" "断言失败: 退出码 $exit_code"
        return 1
    fi
}

assert_failure() {
    local test_name="$1"
    local exit_code="$2"

    if [ $exit_code -ne 0 ]; then
        record_test_result "$test_name" "PASS" "断言失败成功"
        return 0
    else
        record_test_result "$test_name" "FAIL" "断言失败失败: 期望非零退出码"
        return 1
    fi
}

assert_output_contains() {
    local test_name="$1"
    local output="$2"
    local expected_string="$3"

    if [[ "$output" == *"$expected_string"* ]]; then
        record_test_result "$test_name" "PASS" "输出包含期望字符串"
        return 0
    else
        record_test_result "$test_name" "FAIL" "输出不包含期望字符串: '$expected_string'"
        return 1
    fi
}

assert_file_exists() {
    local test_name="$1"
    local file_path="$2"

    if [ -f "$file_path" ]; then
        record_test_result "$test_name" "PASS" "文件存在: $file_path"
        return 0
    else
        record_test_result "$test_name" "FAIL" "文件不存在: $file_path"
        return 1
    fi
}

# =============================================================================
# 测试环境管理
# =============================================================================

# 创建临时测试目录
create_test_temp_dir() {
    local prefix="${1:-test}"
    local temp_dir="/tmp/${prefix}_$$"
    mkdir -p "$temp_dir"
    echo "$temp_dir"
}

# 清理临时目录
cleanup_test_temp_dir() {
    local temp_dir="$1"
    if [ -d "$temp_dir" ]; then
        rm -rf "$temp_dir"
    fi
}

# 备份文件
backup_file() {
    local file_path="$1"
    local backup_suffix="${2:-.bak}"

    if [ -f "$file_path" ]; then
        cp "$file_path" "${file_path}${backup_suffix}"
        echo "${file_path}${backup_suffix}"
    else
        echo ""
    fi
}

# 恢复文件
restore_file() {
    local original_path="$1"
    local backup_path="$2"

    if [ -f "$backup_path" ]; then
        mv "$backup_path" "$original_path"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# 性能测试函数
# =============================================================================

# 测量命令执行时间
measure_execution_time() {
    local command="$1"
    local iterations="${2:-1}"

    local total_time=0
    local i

    for ((i=1; i<=iterations; i++)); do
        local start_time end_time duration

        start_time=$(date +%s.%N)
        eval "$command" >/dev/null 2>&1
        end_time=$(date +%s.%N)

        if command -v bc >/dev/null 2>&1; then
            duration=$(echo "$end_time - $start_time" | bc -l)
            total_time=$(echo "$total_time + $duration" | bc -l)
        else
            # 简单整数计算，精度较低
            duration=$(( ${end_time%.*} - ${start_time%.*} ))
            total_time=$(( total_time + duration ))
        fi
    done

    # 计算平均时间
    if command -v bc >/dev/null 2>&1; then
        echo "scale=3; $total_time / $iterations" | bc -l
    else
        echo $(( total_time / iterations ))
    fi
}

# 性能基准比较
compare_performance() {
    local test_name="$1"
    local baseline_time="$2"
    local current_time="$3"
    local threshold_percent="${4:-5.0}"  # 默认5%阈值

    if command -v bc >/dev/null 2>&1; then
        local delta_percent
        delta_percent=$(echo "scale=2; ($current_time - $baseline_time) * 100 / $baseline_time" | bc -l)

        if (( $(echo "$delta_percent > $threshold_percent" | bc -l) )); then
            record_test_result "$test_name" "FAIL" "性能退化 ${delta_percent}% (超过阈值 ${threshold_percent}%)"
            return 1
        else
            record_test_result "$test_name" "PASS" "性能变化 ${delta_percent}% (在阈值内)"
            return 0
        fi
    else
        # 简单比较，精度较低
        local ratio=$(( current_time * 100 / baseline_time ))
        if [ $ratio -gt 105 ]; then
            record_test_result "$test_name" "FAIL" "性能可能有退化"
            return 1
        else
            record_test_result "$test_name" "PASS" "性能无明显退化"
            return 0
        fi
    fi
}

# =============================================================================
# 配置管理函数
# =============================================================================

# 创建测试配置文件
create_test_config() {
    local config_path="$1"
    local platform="$2"
    local additional_content="${3:-}"

    cat > "$config_path" << EOF
platform: $platform
$additional_content
EOF
}

# 检查配置文件
check_config_file() {
    local config_path="$1"

    if [ -f "$config_path" ]; then
        echo "配置文件存在: $config_path"
        if [ "$DEBUG_MODE" = "1" ]; then
            echo "内容:"
            cat "$config_path"
        fi
        return 0
    else
        echo "配置文件不存在: $config_path"
        return 1
    fi
}

# =============================================================================
# 集成测试函数
# =============================================================================

# 等待条件满足
wait_for_condition() {
    local test_name="$1"
    local condition_command="$2"
    local timeout="${3:-30}"
    local interval="${4:-1}"

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition_command" >/dev/null 2>&1; then
            record_test_result "$test_name" "PASS" "条件在 ${elapsed}s 后满足"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
    done

    record_test_result "$test_name" "FAIL" "条件在 ${timeout}s 内未满足"
    return 1
}

# 模拟网络错误
simulate_network_error() {
    export SIMULATE_NETWORK_ERROR=1
}

# 恢复网络
restore_network() {
    unset SIMULATE_NETWORK_ERROR
}

# =============================================================================
# 报告生成函数
# =============================================================================

# 生成HTML测试报告
generate_html_report() {
    local output_file="$1"
    local test_suite_name="${2:-测试套件}"

    cat > "$output_file" << EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$test_suite_name - 测试报告</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .stats { display: flex; gap: 20px; margin: 20px 0; }
        .stat-box { padding: 15px; border-radius: 5px; flex: 1; text-align: center; }
        .pass { background-color: #d4edda; color: #155724; }
        .fail { background-color: #f8d7da; color: #721c24; }
        .skip { background-color: #fff3cd; color: #856404; }
        .results { margin-top: 20px; }
        .result-item { padding: 10px; margin: 5px 0; border-radius: 3px; }
        .result-pass { background-color: #d4edda; }
        .result-fail { background-color: #f8d7da; }
        .result-skip { background-color: #fff3cd; }
    </style>
</head>
<body>
    <div class="header">
        <h1>$test_suite_name</h1>
        <p>测试时间: $(date)</p>
        <p>总计: $TOTAL_TESTS 个测试</p>
    </div>

    <div class="stats">
        <div class="stat-box pass">
            <h3>$PASSED_TESTS</h3>
            <p>通过</p>
        </div>
        <div class="stat-box fail">
            <h3>$FAILED_TESTS</h3>
            <p>失败</p>
        </div>
        <div class="stat-box skip">
            <h3>$SKIPPED_TESTS</h3>
            <p>跳过</p>
        </div>
    </div>

    <div class="results">
        <h2>详细结果</h2>
EOF

    for result in "${TEST_RESULTS[@]}"; do
        local status
        local class
        if [[ "$result" == PASS:* ]]; then
            status="✅"
            class="result-pass"
        elif [[ "$result" == FAIL:* ]]; then
            status="❌"
            class="result-fail"
        else
            status="⏭️"
            class="result-skip"
        fi

        echo "        <div class=\"result-item $class\">$status $result</div>" >> "$output_file"
    done

    cat >> "$output_file" << EOF
    </div>
</body>
</html>
EOF
}

# 生成JSON测试报告
generate_json_report() {
    local output_file="$1"

    cat > "$output_file" << EOF
{
  "test_suite": "$(basename "${BASH_SOURCE[1]}")",
  "timestamp": "$(date -Iseconds)",
  "summary": {
    "total": $TOTAL_TESTS,
    "passed": $PASSED_TESTS,
    "failed": $FAILED_TESTS,
    "skipped": $SKIPPED_TESTS,
    "success_rate": $(( TOTAL_TESTS > 0 ? PASSED_TESTS * 100 / TOTAL_TESTS : 0 ))
  },
  "results": [
EOF

    local first=true
    for result in "${TEST_RESULTS[@]}"; do
        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$output_file"
        fi

        local status="${result%%:*}"
        local details="${result#*: }"
        echo -n "    {\"status\": \"$status\", \"details\": \"$details\"}" >> "$output_file"
    done

    cat >> "$output_file" << EOF

  ]
}
EOF
}

# =============================================================================
# 初始化函数
# =============================================================================

# 重置测试统计
reset_test_stats() {
    TOTAL_TESTS=0
    PASSED_TESTS=0
    FAILED_TESTS=0
    SKIPPED_TESTS=0
    TEST_RESULTS=()
}

# 测试框架初始化
init_test_framework() {
    reset_test_stats

    if [ "$DEBUG_MODE" = "1" ]; then
        echo "DEBUG: 测试框架已初始化" >&2
        echo "DEBUG: 工作目录: $(pwd)" >&2
        echo "DEBUG: 测试超时: ${TEST_TIMEOUT}s" >&2
    fi
}

# 自动初始化
init_test_framework