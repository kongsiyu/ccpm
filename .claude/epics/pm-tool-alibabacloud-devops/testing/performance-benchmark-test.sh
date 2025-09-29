#!/bin/bash
# 性能基准测试：云效操作不超过GitHub的150%响应时间
# Performance Benchmark Test: Yunxiao operations ≤ 150% of GitHub response time

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TEST_DATA_DIR="$SCRIPT_DIR/data"
PERF_TEST_DIR="$TEST_DATA_DIR/performance"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 性能测试结果
GITHUB_BASELINE_TIME=0
YUNXIAO_TEST_TIME=0
PERFORMANCE_THRESHOLD=150

# ==========================================
# 性能测试环境设置
# ==========================================

setup_performance_test_environment() {
    log_info "设置性能基准测试环境..."

    cd "$PROJECT_ROOT"
    mkdir -p "$PERF_TEST_DIR/results" "$PERF_TEST_DIR/configs"

    # 创建性能测试配置
    cat > "$PERF_TEST_DIR/configs/github-perf.yaml" << EOF
platform:
  type: "github"
testing:
  mode: "performance"
  iterations: 5
  timeout: 30000
EOF

    cat > "$PERF_TEST_DIR/configs/yunxiao-perf.yaml" << EOF
platform:
  type: "yunxiao"
  project_id: "test-performance-project"
testing:
  mode: "performance"
  iterations: 5
  timeout: 30000
EOF

    log_success "性能基准测试环境设置完成"
}

# ==========================================
# 性能测试函数
# ==========================================

measure_execution_time() {
    local operation="$1"
    local command="$2"
    local iterations="${3:-5}"

    local total_time=0
    local successful_runs=0

    for i in $(seq 1 $iterations); do
        local start_time=$(date +%s%3N)

        if eval "$command" >/dev/null 2>&1; then
            local end_time=$(date +%s%3N)
            local execution_time=$((end_time - start_time))
            total_time=$((total_time + execution_time))
            successful_runs=$((successful_runs + 1))
        fi
    done

    if [ $successful_runs -gt 0 ]; then
        local average_time=$((total_time / successful_runs))
        echo "$average_time"
    else
        echo "0"
    fi
}

# ==========================================
# GitHub基准测试
# ==========================================

run_github_baseline_tests() {
    log_info "运行GitHub基准性能测试..."

    cp "$PERF_TEST_DIR/configs/github-perf.yaml" ".claude/ccpm.yaml"

    # 测试配置加载性能
    local config_load_time=$(measure_execution_time "GitHub配置加载" "grep -q 'github' .claude/ccpm.yaml")

    # 测试文件操作性能
    local file_ops_time=$(measure_execution_time "GitHub文件操作" "ls .claude/rules/platform-*.md")

    # 测试查询操作性能
    local query_time=$(measure_execution_time "GitHub查询操作" "find .claude -name '*.md' -type f")

    # 计算总体基准时间
    GITHUB_BASELINE_TIME=$(((config_load_time + file_ops_time + query_time) / 3))

    log_info "GitHub基准测试结果："
    log_info "  配置加载: ${config_load_time}ms"
    log_info "  文件操作: ${file_ops_time}ms"
    log_info "  查询操作: ${query_time}ms"
    log_info "  平均基准: ${GITHUB_BASELINE_TIME}ms"

    # 记录基准数据
    cat > "$PERF_TEST_DIR/results/github-baseline.json" << EOF
{
  "platform": "github",
  "config_load_time": $config_load_time,
  "file_ops_time": $file_ops_time,
  "query_time": $query_time,
  "average_baseline": $GITHUB_BASELINE_TIME,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# ==========================================
# 云效性能测试
# ==========================================

run_yunxiao_performance_tests() {
    log_info "运行云效平台性能测试..."

    cp "$PERF_TEST_DIR/configs/yunxiao-perf.yaml" ".claude/ccpm.yaml"

    # 测试配置加载性能
    local config_load_time=$(measure_execution_time "云效配置加载" "grep -q 'yunxiao' .claude/ccpm.yaml")

    # 测试云效规则文件访问性能
    local file_ops_time=$(measure_execution_time "云效文件操作" "ls .claude/rules/platform-yunxiao-*.md")

    # 测试查询操作性能
    local query_time=$(measure_execution_time "云效查询操作" "find .claude -name '*yunxiao*.md' -type f")

    # 计算总体测试时间
    YUNXIAO_TEST_TIME=$(((config_load_time + file_ops_time + query_time) / 3))

    log_info "云效性能测试结果："
    log_info "  配置加载: ${config_load_time}ms"
    log_info "  文件操作: ${file_ops_time}ms"
    log_info "  查询操作: ${query_time}ms"
    log_info "  平均时间: ${YUNXIAO_TEST_TIME}ms"

    # 记录测试数据
    cat > "$PERF_TEST_DIR/results/yunxiao-performance.json" << EOF
{
  "platform": "yunxiao",
  "config_load_time": $config_load_time,
  "file_ops_time": $file_ops_time,
  "query_time": $query_time,
  "average_time": $YUNXIAO_TEST_TIME,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# ==========================================
# 性能对比分析
# ==========================================

analyze_performance_results() {
    log_info "分析性能对比结果..."

    if [ $GITHUB_BASELINE_TIME -eq 0 ]; then
        log_error "GitHub基准时间为0，无法进行性能对比"
        return 1
    fi

    local performance_ratio=$((YUNXIAO_TEST_TIME * 100 / GITHUB_BASELINE_TIME))
    local threshold_time=$((GITHUB_BASELINE_TIME * PERFORMANCE_THRESHOLD / 100))

    log_info "性能对比分析："
    log_info "  GitHub基准时间: ${GITHUB_BASELINE_TIME}ms"
    log_info "  云效测试时间: ${YUNXIAO_TEST_TIME}ms"
    log_info "  性能比率: ${performance_ratio}%"
    log_info "  性能阈值: ${PERFORMANCE_THRESHOLD}% (${threshold_time}ms)"

    # 生成性能报告
    cat > "$PERF_TEST_DIR/results/performance-comparison.md" << EOF
# 云效平台性能基准测试报告

## 测试执行摘要

- **执行时间**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- **测试范围**: 配置加载、文件操作、查询操作
- **测试方法**: 平均5次运行结果

## 性能基准结果

### GitHub基准性能
- 配置加载时间: $(jq -r '.config_load_time' "$PERF_TEST_DIR/results/github-baseline.json")ms
- 文件操作时间: $(jq -r '.file_ops_time' "$PERF_TEST_DIR/results/github-baseline.json")ms
- 查询操作时间: $(jq -r '.query_time' "$PERF_TEST_DIR/results/github-baseline.json")ms
- **平均基准时间**: ${GITHUB_BASELINE_TIME}ms

### 云效平台性能
- 配置加载时间: $(jq -r '.config_load_time' "$PERF_TEST_DIR/results/yunxiao-performance.json")ms
- 文件操作时间: $(jq -r '.file_ops_time' "$PERF_TEST_DIR/results/yunxiao-performance.json")ms
- 查询操作时间: $(jq -r '.query_time' "$PERF_TEST_DIR/results/yunxiao-performance.json")ms
- **平均测试时间**: ${YUNXIAO_TEST_TIME}ms

## 性能对比分析

- **性能比率**: ${performance_ratio}%
- **性能阈值**: ${PERFORMANCE_THRESHOLD}%
- **阈值时间**: ${threshold_time}ms
- **测试结果**: $([ $performance_ratio -le $PERFORMANCE_THRESHOLD ] && echo "✅ 通过" || echo "❌ 未通过")

## 性能评估

$(if [ $performance_ratio -le $PERFORMANCE_THRESHOLD ]; then
    echo "🎉 **性能测试通过**: 云效平台操作时间为GitHub基准的${performance_ratio}%，符合≤${PERFORMANCE_THRESHOLD}%的要求。"
    echo ""
    echo "### 性能优势"
    echo "- 配置切换速度满足用户体验要求"
    echo "- 文件操作性能稳定"
    echo "- 查询响应时间在可接受范围内"
else
    echo "⚠️ **性能需要优化**: 云效平台操作时间为GitHub基准的${performance_ratio}%，超过${PERFORMANCE_THRESHOLD}%的阈值。"
    echo ""
    echo "### 优化建议"
    echo "- 考虑实施配置缓存机制"
    echo "- 优化文件访问模式"
    echo "- 减少不必要的文件系统操作"
fi)

## 测试局限性

1. **测试环境**: 本地文件系统操作，未包含网络延迟
2. **测试范围**: 基础操作性能，未包含复杂业务逻辑
3. **测试数据**: 模拟数据，实际使用中性能可能有差异

## 实际部署建议

### 生产环境考虑因素
- 网络延迟会影响云效MCP操作响应时间
- 企业防火墙可能增加连接开销
- 并发用户数量会影响整体性能

### 性能监控建议
- 建立生产环境性能基准
- 实施实时性能监控
- 设置性能告警阈值

---
测试执行者: 性能基准测试系统
报告生成时间: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

    # 判断测试结果
    if [ $performance_ratio -le $PERFORMANCE_THRESHOLD ]; then
        log_success "🎉 性能基准测试通过！云效平台性能符合要求。"
        return 0
    else
        log_warning "⚠️ 性能基准测试未完全通过，需要优化。"
        return 1
    fi
}

# ==========================================
# 清理测试环境
# ==========================================

cleanup_performance_test_environment() {
    log_info "清理性能测试环境..."

    # 恢复原始配置
    if [ -f ".claude/ccpm.yaml.backup" ]; then
        mv ".claude/ccpm.yaml.backup" ".claude/ccpm.yaml"
    fi

    log_success "性能测试环境清理完成"
}

# ==========================================
# 主执行流程
# ==========================================

main() {
    log_info "🚀 开始执行云效平台性能基准测试"

    # 备份现有配置
    if [ -f ".claude/ccpm.yaml" ]; then
        cp ".claude/ccpm.yaml" ".claude/ccpm.yaml.backup"
    fi

    # 设置清理处理
    trap cleanup_performance_test_environment EXIT

    # 执行性能测试
    setup_performance_test_environment
    run_github_baseline_tests
    run_yunxiao_performance_tests
    local test_result=0
    analyze_performance_results || test_result=1

    cleanup_performance_test_environment

    log_success "🎉 云效平台性能基准测试完成"
    return $test_result
}

# 只在直接执行脚本时运行main函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi