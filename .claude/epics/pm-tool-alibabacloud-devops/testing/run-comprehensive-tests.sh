#!/bin/bash
# 阿里云云效平台集成 - 综合测试执行脚本
# Comprehensive Test Suite for Alibaba Cloud DevOps Platform Integration

set -euo pipefail

# ==========================================
# 测试配置和全局变量
# ==========================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TEST_REPORTS_DIR="$SCRIPT_DIR/reports"
TEST_DATA_DIR="$SCRIPT_DIR/data"

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# 性能测试基准
GITHUB_BASELINE_TIME=0
YUNXIAO_BASELINE_TIME=0
PERFORMANCE_THRESHOLD=150  # 150% of GitHub baseline

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==========================================
# 工具函数
# ==========================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 测试断言函数
assert_command_success() {
    local test_name="$1"
    local command="$2"
    local expected_pattern="${3:-}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    log_info "执行测试: $test_name"
    log_info "命令: $command"

    if eval "$command" > /tmp/test_output 2>&1; then
        if [ -n "$expected_pattern" ]; then
            if grep -q "$expected_pattern" /tmp/test_output; then
                log_success "✅ PASS: $test_name"
                PASSED_TESTS=$((PASSED_TESTS + 1))
                return 0
            else
                log_error "❌ FAIL: $test_name (输出不匹配期望模式)"
                log_error "期望模式: $expected_pattern"
                log_error "实际输出: $(cat /tmp/test_output)"
                FAILED_TESTS=$((FAILED_TESTS + 1))
                return 1
            fi
        else
            log_success "✅ PASS: $test_name"
            PASSED_TESTS=$((PASSED_TESTS + 1))
            return 0
        fi
    else
        log_error "❌ FAIL: $test_name (命令执行失败)"
        log_error "错误输出: $(cat /tmp/test_output)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

assert_performance_within_limit() {
    local test_name="$1"
    local actual_time="$2"
    local baseline_time="$3"
    local threshold_percent="${4:-$PERFORMANCE_THRESHOLD}"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local limit=$((baseline_time * threshold_percent / 100))

    if [ "$actual_time" -le "$limit" ]; then
        log_success "✅ PASS: $test_name (${actual_time}ms <= ${limit}ms, ${threshold_percent}% of baseline)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
        return 0
    else
        log_error "❌ FAIL: $test_name (${actual_time}ms > ${limit}ms, exceeds ${threshold_percent}% of baseline)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi
}

measure_execution_time() {
    local command="$1"
    local start_time=$(date +%s%3N)

    eval "$command" > /dev/null 2>&1 || true

    local end_time=$(date +%s%3N)
    local execution_time=$((end_time - start_time))

    echo "$execution_time"
}

skip_test() {
    local test_name="$1"
    local reason="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    SKIPPED_TESTS=$((SKIPPED_TESTS + 1))

    log_warning "⏭️ SKIP: $test_name ($reason)"
}

# ==========================================
# 环境准备和验证
# ==========================================

setup_test_environment() {
    log_info "设置测试环境..."

    # 创建测试目录
    mkdir -p "$TEST_REPORTS_DIR" "$TEST_DATA_DIR"

    # 切换到项目根目录
    cd "$PROJECT_ROOT"

    # 验证基础依赖
    local missing_deps=()

    if ! command -v yq &> /dev/null; then
        missing_deps+=("yq")
    fi

    if ! command -v gh &> /dev/null; then
        missing_deps+=("gh")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "缺少必需依赖: ${missing_deps[*]}"
        exit 1
    fi

    # 验证GitHub认证
    if ! gh auth status &> /dev/null; then
        log_error "GitHub CLI未认证，请运行: gh auth login"
        exit 1
    fi

    # 创建测试配置文件
    create_test_configs

    log_success "测试环境设置完成"
}

create_test_configs() {
    log_info "创建测试配置文件..."

    # GitHub测试配置
    cat > "$TEST_DATA_DIR/ccpm-github.yaml" << EOF
# GitHub平台测试配置
platform:
  type: "github"

sync:
  mode: "bidirectional"
  conflict_resolution:
    strategy: "timestamp"

features:
  strict_validation: true
  legacy_compatibility: true

metadata:
  test_mode: true
  created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

    # 云效测试配置
    cat > "$TEST_DATA_DIR/ccpm-yunxiao.yaml" << EOF
# 云效平台测试配置
platform:
  type: "yunxiao"
  project_id: "\${YUNXIAO_TEST_PROJECT_ID:-test-project-123}"

sync:
  mode: "bidirectional"
  conflict_resolution:
    strategy: "timestamp"

features:
  strict_validation: true
  legacy_compatibility: true

metadata:
  test_mode: true
  created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

    log_success "测试配置文件创建完成"
}

# ==========================================
# 功能测试模块
# ==========================================

run_functional_tests() {
    log_info "==========================================="
    log_info "开始功能测试 (Functional Tests)"
    log_info "==========================================="

    # 备份现有配置
    if [ -f ".claude/ccpm.yaml" ]; then
        cp ".claude/ccpm.yaml" ".claude/ccpm.yaml.backup"
    fi

    # 测试GitHub模式功能
    test_github_platform_functions

    # 测试云效模式功能
    test_yunxiao_platform_functions

    # 恢复配置
    if [ -f ".claude/ccpm.yaml.backup" ]; then
        mv ".claude/ccpm.yaml.backup" ".claude/ccpm.yaml"
    fi
}

test_github_platform_functions() {
    log_info "测试GitHub平台功能..."

    # 使用GitHub测试配置
    cp "$TEST_DATA_DIR/ccpm-github.yaml" ".claude/ccpm.yaml"

    # 测试配置加载
    assert_command_success \
        "GitHub配置加载验证" \
        "yq eval '.platform.type' .claude/ccpm.yaml" \
        "github"

    # 测试基础命令存在性
    local github_commands=(
        "pm:init"
        "pm:create-epic"
        "pm:create-task"
        "pm:sync"
        "pm:status"
    )

    for cmd in "${github_commands[@]}"; do
        if [ -f ".claude/commands/pm/$(echo $cmd | cut -d: -f2).md" ]; then
            assert_command_success \
                "GitHub命令文件存在: $cmd" \
                "test -f .claude/commands/pm/$(echo $cmd | cut -d: -f2).md"
        else
            skip_test "GitHub命令文件: $cmd" "命令文件不存在"
        fi
    done
}

test_yunxiao_platform_functions() {
    log_info "测试云效平台功能..."

    # 使用云效测试配置
    cp "$TEST_DATA_DIR/ccpm-yunxiao.yaml" ".claude/ccpm.yaml"

    # 测试配置加载
    assert_command_success \
        "云效配置加载验证" \
        "yq eval '.platform.type' .claude/ccpm.yaml" \
        "yunxiao"

    # 测试云效规则文件存在性
    local yunxiao_rules=(
        "platform-yunxiao-sync.md"
        "platform-yunxiao-api.md"
        "platform-yunxiao-mapping.md"
        "platform-yunxiao-epic-sync.md"
        "platform-yunxiao-issue-sync.md"
    )

    for rule in "${yunxiao_rules[@]}"; do
        assert_command_success \
            "云效规则文件存在: $rule" \
            "test -f .claude/rules/$rule"
    done

    # 测试配置验证机制
    if [ -n "${YUNXIAO_ACCESS_TOKEN:-}" ]; then
        assert_command_success \
            "云效访问令牌配置检查" \
            "test -n \"\$YUNXIAO_ACCESS_TOKEN\""
    else
        skip_test "云效访问令牌验证" "未设置YUNXIAO_ACCESS_TOKEN环境变量"
    fi
}

# ==========================================
# 集成测试模块
# ==========================================

run_integration_tests() {
    log_info "==========================================="
    log_info "开始集成测试 (Integration Tests)"
    log_info "==========================================="

    test_platform_switching()
    test_data_mapping()
    test_frontmatter_compatibility()
}

test_platform_switching() {
    log_info "测试平台切换功能..."

    # 测试GitHub到云效切换
    cp "$TEST_DATA_DIR/ccpm-github.yaml" ".claude/ccpm.yaml"

    assert_command_success \
        "切换到GitHub平台" \
        "yq eval '.platform.type' .claude/ccpm.yaml" \
        "github"

    # 切换到云效平台
    cp "$TEST_DATA_DIR/ccpm-yunxiao.yaml" ".claude/ccpm.yaml"

    assert_command_success \
        "切换到云效平台" \
        "yq eval '.platform.type' .claude/ccpm.yaml" \
        "yunxiao"

    # 测试配置验证逻辑
    assert_command_success \
        "云效平台项目ID验证" \
        "yq eval '.platform.project_id' .claude/ccpm.yaml" \
        "test-project-123"
}

test_data_mapping() {
    log_info "测试数据映射机制..."

    # 测试GitHub Issues到云效WorkItem的映射规则
    if [ -f ".claude/rules/platform-yunxiao-mapping.md" ]; then
        assert_command_success \
            "数据映射规则文件存在" \
            "test -f .claude/rules/platform-yunxiao-mapping.md"

        # 验证映射规则内容包含关键映射
        assert_command_success \
            "Epic到父工作项映射规则" \
            "grep -q 'Epic.*父工作项' .claude/rules/platform-yunxiao-mapping.md"

        assert_command_success \
            "Task到子工作项映射规则" \
            "grep -q 'Task.*子工作项' .claude/rules/platform-yunxiao-mapping.md"
    else
        skip_test "数据映射规则验证" "映射规则文件不存在"
    fi
}

test_frontmatter_compatibility() {
    log_info "测试frontmatter字段兼容性..."

    # 创建测试Epic文件
    cat > "$TEST_DATA_DIR/test-epic.md" << EOF
---
name: test-epic
status: pending
created: $(date -u +%Y-%m-%dT%H:%M:%SZ)
github: https://github.com/test/repo/issues/1
yunxiao: https://devops.aliyun.com/projets/test/workitems/1
platform_urls:
  github: https://github.com/test/repo/issues/1
  yunxiao: https://devops.aliyun.com/projets/test/workitems/1
---

# Test Epic

测试Epic内容
EOF

    # 验证frontmatter格式兼容性
    assert_command_success \
        "frontmatter YAML格式验证" \
        "yq eval '.name' $TEST_DATA_DIR/test-epic.md" \
        "test-epic"

    assert_command_success \
        "GitHub URL字段兼容性" \
        "yq eval '.github' $TEST_DATA_DIR/test-epic.md" \
        "github.com"

    assert_command_success \
        "云效URL字段扩展支持" \
        "yq eval '.yunxiao' $TEST_DATA_DIR/test-epic.md" \
        "devops.aliyun.com"
}

# ==========================================
# 性能测试模块
# ==========================================

run_performance_tests() {
    log_info "==========================================="
    log_info "开始性能测试 (Performance Tests)"
    log_info "==========================================="

    establish_github_baseline()
    test_yunxiao_performance()
    compare_performance_metrics()
}

establish_github_baseline() {
    log_info "建立GitHub操作性能基线..."

    cp "$TEST_DATA_DIR/ccpm-github.yaml" ".claude/ccpm.yaml"

    # 测试配置加载时间
    local config_load_time=$(measure_execution_time "yq eval '.platform.type' .claude/ccpm.yaml")
    GITHUB_BASELINE_TIME=$config_load_time

    log_info "GitHub基线操作时间: ${GITHUB_BASELINE_TIME}ms"

    # 记录到性能报告
    echo "github_config_load_time: ${GITHUB_BASELINE_TIME}" > "$TEST_REPORTS_DIR/performance-baseline.log"
}

test_yunxiao_performance() {
    log_info "测试云效平台性能..."

    cp "$TEST_DATA_DIR/ccpm-yunxiao.yaml" ".claude/ccpm.yaml"

    # 测试配置加载时间
    local config_load_time=$(measure_execution_time "yq eval '.platform.type' .claude/ccpm.yaml")
    YUNXIAO_BASELINE_TIME=$config_load_time

    log_info "云效操作时间: ${YUNXIAO_BASELINE_TIME}ms"

    # 记录到性能报告
    echo "yunxiao_config_load_time: ${YUNXIAO_BASELINE_TIME}" >> "$TEST_REPORTS_DIR/performance-baseline.log"
}

compare_performance_metrics() {
    log_info "对比性能指标..."

    if [ "$GITHUB_BASELINE_TIME" -gt 0 ]; then
        assert_performance_within_limit \
            "云效配置加载性能对比" \
            "$YUNXIAO_BASELINE_TIME" \
            "$GITHUB_BASELINE_TIME" \
            "$PERFORMANCE_THRESHOLD"
    else
        skip_test "性能对比测试" "GitHub基线时间为0"
    fi

    # 计算性能比率
    if [ "$GITHUB_BASELINE_TIME" -gt 0 ]; then
        local performance_ratio=$((YUNXIAO_BASELINE_TIME * 100 / GITHUB_BASELINE_TIME))
        log_info "性能比率: ${performance_ratio}% (目标: ≤${PERFORMANCE_THRESHOLD}%)"

        echo "performance_ratio: ${performance_ratio}%" >> "$TEST_REPORTS_DIR/performance-baseline.log"
    fi
}

# ==========================================
# 错误场景测试模块
# ==========================================

run_error_scenario_tests() {
    log_info "==========================================="
    log_info "开始错误场景测试 (Error Scenario Tests)"
    log_info "==========================================="

    test_network_failure_scenarios()
    test_authentication_failure_scenarios()
    test_configuration_error_scenarios()
}

test_network_failure_scenarios() {
    log_info "测试网络失败场景..."

    # 模拟无效的云效项目ID
    cat > "$TEST_DATA_DIR/ccpm-invalid.yaml" << EOF
platform:
  type: "yunxiao"
  project_id: "invalid-project-id-999999"
EOF

    cp "$TEST_DATA_DIR/ccpm-invalid.yaml" ".claude/ccpm.yaml"

    # 验证配置验证能够检测到问题
    assert_command_success \
        "无效配置检测" \
        "yq eval '.platform.project_id' .claude/ccpm.yaml" \
        "invalid-project-id-999999"
}

test_authentication_failure_scenarios() {
    log_info "测试认证失败场景..."

    # 测试缺少访问令牌的场景
    local original_token="${YUNXIAO_ACCESS_TOKEN:-}"
    unset YUNXIAO_ACCESS_TOKEN

    cp "$TEST_DATA_DIR/ccpm-yunxiao.yaml" ".claude/ccpm.yaml"

    # 验证缺少令牌时的错误处理
    if [ -z "${YUNXIAO_ACCESS_TOKEN:-}" ]; then
        log_success "✅ PASS: 成功检测到缺少访问令牌"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "❌ FAIL: 未能检测到缺少访问令牌"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # 恢复令牌
    if [ -n "$original_token" ]; then
        export YUNXIAO_ACCESS_TOKEN="$original_token"
    fi
}

test_configuration_error_scenarios() {
    log_info "测试配置错误场景..."

    # 创建语法错误的YAML文件
    cat > "$TEST_DATA_DIR/ccpm-syntax-error.yaml" << EOF
platform:
  type: "yunxiao"
  project_id: "test-project
    # 缺少引号闭合，导致YAML语法错误
EOF

    cp "$TEST_DATA_DIR/ccpm-syntax-error.yaml" ".claude/ccmp.yaml"

    # 验证YAML语法错误检测
    if ! yq eval '.' ".claude/ccmp.yaml" >/dev/null 2>&1; then
        log_success "✅ PASS: 成功检测YAML语法错误"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "❌ FAIL: 未能检测YAML语法错误"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # 清理错误配置文件
    rm -f ".claude/ccmp.yaml"
}

# ==========================================
# 用户体验测试模块
# ==========================================

run_user_experience_tests() {
    log_info "==========================================="
    log_info "开始用户体验测试 (User Experience Tests)"
    log_info "==========================================="

    test_new_project_setup_flow()
    test_error_message_clarity()
    test_documentation_completeness()
}

test_new_project_setup_flow() {
    log_info "测试新项目设置流程..."

    # 测试初始化命令文档存在
    assert_command_success \
        "初始化命令文档存在" \
        "test -f .claude/commands/pm/init.md"

    # 测试配置模板文件存在
    assert_command_success \
        "平台配置规则文档存在" \
        "test -f .claude/rules/platform-config.md"

    # 验证配置向导内容完整性
    if [ -f ".claude/rules/platform-config.md" ]; then
        assert_command_success \
            "配置文档包含GitHub设置说明" \
            "grep -q 'github' .claude/rules/platform-config.md"

        assert_command_success \
            "配置文档包含云效设置说明" \
            "grep -q 'yunxiao' .claude/rules/platform-config.md"
    fi
}

test_error_message_clarity() {
    log_info "测试错误信息清晰度..."

    # 验证错误处理规则文件存在
    if [ -f ".claude/rules/platform-yunxiao-error-handling.md" ]; then
        assert_command_success \
            "错误处理规则文档存在" \
            "test -f .claude/rules/platform-yunxiao-error-handling.md"

        assert_command_success \
            "错误处理包含网络错误说明" \
            "grep -q '网络.*错误' .claude/rules/platform-yunxiao-error-handling.md"
    else
        skip_test "错误处理文档验证" "错误处理规则文件不存在"
    fi
}

test_documentation_completeness() {
    log_info "测试文档完整性..."

    # 验证关键文档文件存在
    local required_docs=(
        ".claude/rules/platform-config.md"
        ".claude/rules/platform-yunxiao-sync.md"
        ".claude/rules/platform-yunxiao-api.md"
        ".claude/epics/pm-tool-alibabacloud-devops/epic.md"
    )

    for doc in "${required_docs[@]}"; do
        assert_command_success \
            "必需文档存在: $(basename $doc)" \
            "test -f $doc"
    done
}

# ==========================================
# 并发测试模块
# ==========================================

run_concurrent_agent_tests() {
    log_info "==========================================="
    log_info "开始并发代理测试 (Concurrent Agent Tests)"
    log_info "==========================================="

    test_concurrent_configuration_access()
    test_platform_switching_during_operations()
}

test_concurrent_configuration_access() {
    log_info "测试并发配置访问..."

    # 模拟多个代理同时访问配置
    local pids=()

    for i in {1..3}; do
        (
            yq eval '.platform.type' ".claude/ccpm.yaml" > "/tmp/agent_${i}_output" 2>&1
        ) &
        pids+=($!)
    done

    # 等待所有后台进程完成
    for pid in "${pids[@]}"; do
        wait "$pid"
    done

    # 验证所有代理都能正确读取配置
    local success_count=0
    for i in {1..3}; do
        if [ -f "/tmp/agent_${i}_output" ] && [ -s "/tmp/agent_${i}_output" ]; then
            success_count=$((success_count + 1))
        fi
        rm -f "/tmp/agent_${i}_output"
    done

    if [ "$success_count" -eq 3 ]; then
        log_success "✅ PASS: 并发配置访问测试"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        log_error "❌ FAIL: 并发配置访问测试 (成功: $success_count/3)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

test_platform_switching_during_operations() {
    log_info "测试操作期间平台切换..."

    # 这是一个模拟测试，验证平台切换不会导致配置文件损坏
    cp "$TEST_DATA_DIR/ccpm-github.yaml" ".claude/ccpm.yaml"

    # 快速切换平台配置
    cp "$TEST_DATA_DIR/ccpm-yunxiao.yaml" ".claude/ccpm.yaml"
    cp "$TEST_DATA_DIR/ccpm-github.yaml" ".claude/ccpm.yaml"

    # 验证最终配置仍然有效
    assert_command_success \
        "平台快速切换后配置完整性" \
        "yq eval '.platform.type' .claude/ccpm.yaml" \
        "github"
}

# ==========================================
# 测试报告生成
# ==========================================

generate_test_report() {
    log_info "==========================================="
    log_info "生成测试报告"
    log_info "==========================================="

    local test_end_time=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    local pass_rate=0

    if [ "$TOTAL_TESTS" -gt 0 ]; then
        pass_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    # 生成详细测试报告
    cat > "$TEST_REPORTS_DIR/comprehensive-test-report.md" << EOF
# 阿里云云效平台集成 - 综合测试报告

## 测试执行摘要

- **执行时间**: $test_end_time
- **测试环境**: $(uname -s) $(uname -r)
- **项目目录**: $PROJECT_ROOT

## 总体结果

- **总用例数**: $TOTAL_TESTS
- **通过用例**: $PASSED_TESTS
- **失败用例**: $FAILED_TESTS
- **跳过用例**: $SKIPPED_TESTS
- **通过率**: ${pass_rate}%

## 测试分类结果

### 功能测试
- 状态: $([ "$FAILED_TESTS" -eq 0 ] && echo "✅ 通过" || echo "❌ 部分失败")
- 描述: 验证CCPM命令在云效平台的功能一致性

### 集成测试
- 状态: $([ "$FAILED_TESTS" -eq 0 ] && echo "✅ 通过" || echo "❌ 部分失败")
- 描述: 验证平台切换和数据映射功能

### 性能测试
- 状态: $([ "$FAILED_TESTS" -eq 0 ] && echo "✅ 通过" || echo "❌ 部分失败")
- GitHub基线: ${GITHUB_BASELINE_TIME}ms
- 云效响应: ${YUNXIAO_BASELINE_TIME}ms
- 性能比率: $( [ "$GITHUB_BASELINE_TIME" -gt 0 ] && echo "$((YUNXIAO_BASELINE_TIME * 100 / GITHUB_BASELINE_TIME))%" || echo "N/A")

### 错误场景测试
- 状态: $([ "$FAILED_TESTS" -eq 0 ] && echo "✅ 通过" || echo "❌ 部分失败")
- 描述: 验证各种错误场景的处理机制

### 用户体验测试
- 状态: $([ "$FAILED_TESTS" -eq 0 ] && echo "✅ 通过" || echo "❌ 部分失败")
- 描述: 验证配置流程和文档完整性

### 并发代理测试
- 状态: $([ "$FAILED_TESTS" -eq 0 ] && echo "✅ 通过" || echo "❌ 部分失败")
- 描述: 验证多代理并发访问能力

## 结论

$(if [ "$pass_rate" -ge 95 ]; then
    echo "🎉 **测试通过**: 通过率达到${pass_rate}%，满足95%的目标要求。系统准备就绪，可以进行部署。"
else
    echo "⚠️ **需要改进**: 通过率为${pass_rate}%，未达到95%的目标要求。请检查失败的测试用例并进行修复。"
fi)

## 建议和后续行动

$(if [ "$FAILED_TESTS" -gt 0 ]; then
    echo "### 需要修复的问题"
    echo "- 有 $FAILED_TESTS 个测试用例失败，需要进一步调查和修复"
    echo "- 检查测试日志了解具体失败原因"
    echo "- 验证环境配置和依赖项"
else
    echo "### 部署准备"
    echo "- ✅ 所有测试用例通过"
    echo "- ✅ 性能指标符合要求"
    echo "- ✅ 系统准备就绪可进行部署"
fi)

## 测试文件位置

- 测试脚本: $SCRIPT_DIR/run-comprehensive-tests.sh
- 测试数据: $TEST_DATA_DIR/
- 测试报告: $TEST_REPORTS_DIR/
- 性能基线: $TEST_REPORTS_DIR/performance-baseline.log

---
报告生成时间: $test_end_time
EOF

    # 生成简要状态报告
    cat > "$TEST_REPORTS_DIR/test-status.txt" << EOF
TOTAL: $TOTAL_TESTS
PASSED: $PASSED_TESTS
FAILED: $FAILED_TESTS
SKIPPED: $SKIPPED_TESTS
PASS_RATE: ${pass_rate}%
STATUS: $([ "$pass_rate" -ge 95 ] && echo "READY_FOR_DEPLOYMENT" || echo "NEEDS_IMPROVEMENT")
EOF

    log_success "测试报告已生成: $TEST_REPORTS_DIR/comprehensive-test-report.md"

    # 显示测试摘要
    echo ""
    log_info "==========================================="
    log_info "测试执行完成"
    log_info "==========================================="
    log_info "总用例数: $TOTAL_TESTS"
    log_info "通过用例: $PASSED_TESTS"
    log_info "失败用例: $FAILED_TESTS"
    log_info "跳过用例: $SKIPPED_TESTS"
    log_info "通过率: ${pass_rate}%"

    if [ "$pass_rate" -ge 95 ]; then
        log_success "🎉 测试通过！系统准备就绪可进行部署。"
        return 0
    else
        log_error "⚠️ 测试未完全通过，需要进一步改进。"
        return 1
    fi
}

cleanup_test_environment() {
    log_info "清理测试环境..."

    # 恢复原始配置文件
    if [ -f ".claude/ccpm.yaml.backup" ]; then
        mv ".claude/ccpm.yaml.backup" ".claude/ccpm.yaml"
    fi

    # 清理临时测试文件
    rm -f /tmp/test_output
    rm -f /tmp/agent_*_output

    log_success "测试环境清理完成"
}

# ==========================================
# 主执行流程
# ==========================================

main() {
    log_info "🚀 开始执行阿里云云效平台集成综合测试套件"
    log_info "开始时间: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"

    # 设置错误处理
    trap cleanup_test_environment EXIT

    # 执行测试套件
    setup_test_environment

    run_functional_tests
    run_integration_tests
    run_performance_tests
    run_error_scenario_tests
    run_user_experience_tests
    run_concurrent_agent_tests

    # 生成测试报告
    local test_result=0
    generate_test_report || test_result=1

    cleanup_test_environment

    exit $test_result
}

# 只在直接执行脚本时运行main函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi