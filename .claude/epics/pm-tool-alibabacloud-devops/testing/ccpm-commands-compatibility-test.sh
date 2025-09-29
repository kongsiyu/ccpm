#!/bin/bash
# CCPM命令云效平台兼容性测试
# CCPM Commands Yunxiao Platform Compatibility Test

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TEST_DATA_DIR="$SCRIPT_DIR/data"
COMMANDS_TEST_DIR="$TEST_DATA_DIR/commands"

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

# 测试计数器
TOTAL_COMMANDS=0
COMPATIBLE_COMMANDS=0
INCOMPATIBLE_COMMANDS=0
UNTESTED_COMMANDS=0

# ==========================================
# CCPM命令清单和分类
# ==========================================

# 定义所有CCPM命令及其分类
declare -A CCPM_COMMANDS=(
    # Epic管理命令
    ["epic-list"]="epic-management"
    ["epic-decompose"]="epic-management"
    ["epic-close"]="epic-management"
    ["epic-edit"]="epic-management"
    ["epic-start-worktree"]="epic-management"
    ["epic-show"]="epic-management"
    ["epic-refresh"]="epic-management"
    ["epic-oneshot"]="epic-management"
    ["epic-merge"]="epic-management"
    ["epic-status"]="epic-management"
    ["epic-start"]="epic-management"
    ["epic-sync"]="epic-management"

    # Issue管理命令
    ["issue-status"]="issue-management"
    ["issue-start"]="issue-management"
    ["issue-show"]="issue-management"
    ["issue-reopen"]="issue-management"
    ["issue-edit"]="issue-management"
    ["issue-close"]="issue-management"
    ["issue-analyze"]="issue-management"
    ["issue-sync"]="issue-management"

    # PRD管理命令
    ["prd-status"]="prd-management"
    ["prd-parse"]="prd-management"
    ["prd-new"]="prd-management"
    ["prd-list"]="prd-management"
    ["prd-edit"]="prd-management"

    # 工作流程命令
    ["init"]="workflow"
    ["sync"]="workflow"
    ["status"]="workflow"
    ["standup"]="workflow"
    ["validate"]="workflow"

    # 查询和分析命令
    ["search"]="query-analysis"
    ["help"]="query-analysis"
    ["next"]="query-analysis"
    ["in-progress"]="query-analysis"
    ["blocked"]="query-analysis"

    # 工具命令
    ["clean"]="utility"
    ["import"]="utility"
    ["test-reference-update"]="utility"
)

# 云效平台兼容性预期评估
declare -A COMPATIBILITY_ASSESSMENT=(
    # Epic管理 - 高兼容性 (Epic → 父工作项)
    ["epic-list"]="high"
    ["epic-decompose"]="high"
    ["epic-close"]="high"
    ["epic-edit"]="high"
    ["epic-show"]="high"
    ["epic-refresh"]="high"
    ["epic-status"]="high"
    ["epic-start"]="high"
    ["epic-sync"]="high"

    # 需要适配的Epic命令
    ["epic-start-worktree"]="medium"  # 需要适配云效分支管理
    ["epic-oneshot"]="medium"         # 需要适配云效工作流
    ["epic-merge"]="medium"           # 需要适配云效合并机制

    # Issue管理 - 高兼容性 (Issue → 子工作项)
    ["issue-status"]="high"
    ["issue-start"]="high"
    ["issue-show"]="high"
    ["issue-reopen"]="high"
    ["issue-edit"]="high"
    ["issue-close"]="high"
    ["issue-analyze"]="high"
    ["issue-sync"]="high"

    # PRD管理 - 高兼容性 (无平台依赖)
    ["prd-status"]="high"
    ["prd-parse"]="high"
    ["prd-new"]="high"
    ["prd-list"]="high"
    ["prd-edit"]="high"

    # 工作流程 - 中高兼容性
    ["init"]="high"          # 已适配云效初始化
    ["sync"]="high"          # 已适配云效同步
    ["status"]="high"        # 状态查询通用
    ["standup"]="high"       # 基于本地数据
    ["validate"]="high"      # 验证逻辑通用

    # 查询分析 - 高兼容性 (基于本地数据)
    ["search"]="high"
    ["help"]="high"
    ["next"]="high"
    ["in-progress"]="high"
    ["blocked"]="high"

    # 工具命令 - 中等兼容性
    ["clean"]="high"                    # 本地清理操作
    ["import"]="medium"                 # 可能需要适配云效导入
    ["test-reference-update"]="low"     # 测试工具，低优先级
)

# ==========================================
# 测试环境设置
# ==========================================

setup_commands_test_environment() {
    log_info "设置CCPM命令兼容性测试环境..."

    cd "$PROJECT_ROOT"
    mkdir -p "$COMMANDS_TEST_DIR/results" "$COMMANDS_TEST_DIR/configs"

    # 创建测试配置
    create_test_configurations

    # 统计命令总数
    TOTAL_COMMANDS=${#CCPM_COMMANDS[@]}

    log_success "发现 $TOTAL_COMMANDS 个CCPM命令需要测试"
    log_success "命令兼容性测试环境设置完成"
}

create_test_configurations() {
    log_info "创建测试配置文件..."

    # GitHub测试配置
    cat > "$COMMANDS_TEST_DIR/configs/github-test.yaml" << EOF
# GitHub平台命令测试配置
platform:
  type: "github"

testing:
  mode: "command_compatibility"
  verify_platform_detection: true
  verify_command_execution: false  # 避免实际执行命令

metadata:
  test_suite: "ccpm_commands_compatibility"
  created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

    # 云效测试配置
    cat > "$COMMANDS_TEST_DIR/configs/yunxiao-test.yaml" << EOF
# 云效平台命令测试配置
platform:
  type: "yunxiao"
  project_id: "test-compatibility-project"

testing:
  mode: "command_compatibility"
  verify_platform_detection: true
  verify_command_execution: false  # 避免实际执行命令

metadata:
  test_suite: "ccpm_commands_compatibility"
  created_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EOF

    log_success "测试配置文件创建完成"
}

# ==========================================
# 命令兼容性分析
# ==========================================

analyze_command_compatibility() {
    local command="$1"
    local command_file=".claude/commands/pm/${command}.md"
    local compatibility_level="${COMPATIBILITY_ASSESSMENT[$command]:-unknown}"

    log_info "分析命令兼容性: $command"

    # 检查命令文件是否存在
    if [ ! -f "$command_file" ]; then
        log_warning "命令文件不存在: $command_file"
        return 2
    fi

    # 分析命令内容的平台兼容性
    analyze_command_platform_integration "$command" "$command_file" "$compatibility_level"
}

analyze_command_platform_integration() {
    local command="$1"
    local command_file="$2"
    local expected_compatibility="$3"

    local compatibility_score=0
    local compatibility_notes=()

    # 1. 检查是否包含平台检测逻辑
    if grep -q "平台配置检测\|Platform Configuration Detection" "$command_file"; then
        compatibility_score=$((compatibility_score + 20))
        compatibility_notes+=("✅ 包含平台检测逻辑")
    else
        compatibility_notes+=("⚠️ 缺少平台检测逻辑")
    fi

    # 2. 检查是否包含云效规则引用
    if grep -q "platform-yunxiao\|云效" "$command_file"; then
        compatibility_score=$((compatibility_score + 20))
        compatibility_notes+=("✅ 包含云效规则引用")
    else
        compatibility_notes+=("⚠️ 缺少云效规则引用")
    fi

    # 3. 检查GitHub依赖程度
    local github_dependency_count=$(grep -c "gh \|github\.com\|GitHub" "$command_file" || echo 0)
    if [ "$github_dependency_count" -le 2 ]; then
        compatibility_score=$((compatibility_score + 20))
        compatibility_notes+=("✅ GitHub依赖度较低")
    elif [ "$github_dependency_count" -le 5 ]; then
        compatibility_score=$((compatibility_score + 10))
        compatibility_notes+=("⚠️ GitHub依赖度中等")
    else
        compatibility_notes+=("❌ GitHub依赖度较高")
    fi

    # 4. 检查数据结构兼容性
    if grep -q "frontmatter\|\.md\|Epic\|Task" "$command_file"; then
        compatibility_score=$((compatibility_score + 20))
        compatibility_notes+=("✅ 使用兼容的数据结构")
    else
        compatibility_notes+=("⚠️ 数据结构兼容性不确定")
    fi

    # 5. 检查配置依赖
    if grep -q "ccpm\.config\|ccmp\.yaml" "$command_file"; then
        compatibility_score=$((compatibility_score + 20))
        compatibility_notes+=("✅ 使用配置系统")
    else
        compatibility_notes+=("⚠️ 可能未使用配置系统")
    fi

    # 评估兼容性级别
    local actual_compatibility
    if [ "$compatibility_score" -ge 80 ]; then
        actual_compatibility="high"
    elif [ "$compatibility_score" -ge 50 ]; then
        actual_compatibility="medium"
    else
        actual_compatibility="low"
    fi

    # 记录测试结果
    record_compatibility_result "$command" "$expected_compatibility" "$actual_compatibility" "$compatibility_score" "${compatibility_notes[@]}"

    return 0
}

record_compatibility_result() {
    local command="$1"
    local expected="$2"
    local actual="$3"
    local score="$4"
    shift 4
    local notes=("$@")

    local result_file="$COMMANDS_TEST_DIR/results/${command}-compatibility.md"

    cat > "$result_file" << EOF
# $command 命令兼容性分析结果

## 基本信息

- **命令名称**: $command
- **命令分类**: ${CCPM_COMMANDS[$command]:-unknown}
- **预期兼容性**: $expected
- **实际兼容性**: $actual
- **兼容性得分**: $score/100

## 兼容性分析

EOF

    # 写入分析结果
    for note in "${notes[@]}"; do
        echo "- $note" >> "$result_file"
    done

    cat >> "$result_file" << EOF

## 兼容性评估

$(case "$actual" in
    "high")
        echo "🟢 **高兼容性**: 该命令在云效平台上应能正常工作，无需或仅需少量修改。"
        ;;
    "medium")
        echo "🟡 **中等兼容性**: 该命令需要适配云效平台，但主要逻辑可复用。"
        ;;
    "low")
        echo "🔴 **低兼容性**: 该命令需要显著修改才能在云效平台正常工作。"
        ;;
    *)
        echo "⚪ **兼容性未知**: 需要进一步分析该命令的平台依赖性。"
        ;;
esac)

## 适配建议

$(case "$actual" in
    "high")
        echo "- 验证现有平台检测逻辑是否正确"
        echo "- 确认云效规则文件完整性"
        echo "- 进行端到端测试验证"
        ;;
    "medium")
        echo "- 添加或完善平台检测逻辑"
        echo "- 创建云效平台专用规则文件"
        echo "- 减少对GitHub特定API的依赖"
        ;;
    "low")
        echo "- 重新设计命令架构以支持多平台"
        echo "- 抽象平台相关操作到适配器层"
        echo "- 可能需要创建云效专用版本"
        ;;
    *)
        echo "- 需要深入分析命令的平台依赖"
        echo "- 评估改造成本和收益"
        ;;
esac)

---
测试时间: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

    # 更新计数器
    case "$actual" in
        "high"|"medium")
            COMPATIBLE_COMMANDS=$((COMPATIBLE_COMMANDS + 1))
            log_success "✅ $command: $actual 兼容性 (得分: $score/100)"
            ;;
        "low")
            INCOMPATIBLE_COMMANDS=$((INCOMPATIBLE_COMMANDS + 1))
            log_warning "⚠️ $command: $actual 兼容性 (得分: $score/100)"
            ;;
        *)
            UNTESTED_COMMANDS=$((UNTESTED_COMMANDS + 1))
            log_warning "❓ $command: 兼容性未知 (得分: $score/100)"
            ;;
    esac
}

# ==========================================
# 主测试流程
# ==========================================

run_ccpm_commands_compatibility_test() {
    log_info "==========================================="
    log_info "开始CCPM命令云效平台兼容性测试"
    log_info "==========================================="

    # 按类别测试命令
    test_epic_management_commands
    test_issue_management_commands
    test_prd_management_commands
    test_workflow_commands
    test_query_analysis_commands
    test_utility_commands

    generate_compatibility_summary_report
}

test_epic_management_commands() {
    log_info "测试Epic管理命令兼容性..."

    local epic_commands=(
        "epic-list" "epic-decompose" "epic-close" "epic-edit"
        "epic-start-worktree" "epic-show" "epic-refresh" "epic-oneshot"
        "epic-merge" "epic-status" "epic-start" "epic-sync"
    )

    for cmd in "${epic_commands[@]}"; do
        if [ -f ".claude/commands/pm/${cmd}.md" ]; then
            analyze_command_compatibility "$cmd"
        else
            log_warning "Epic命令文件不存在: $cmd"
            UNTESTED_COMMANDS=$((UNTESTED_COMMANDS + 1))
        fi
    done
}

test_issue_management_commands() {
    log_info "测试Issue管理命令兼容性..."

    local issue_commands=(
        "issue-status" "issue-start" "issue-show" "issue-reopen"
        "issue-edit" "issue-close" "issue-analyze" "issue-sync"
    )

    for cmd in "${issue_commands[@]}"; do
        if [ -f ".claude/commands/pm/${cmd}.md" ]; then
            analyze_command_compatibility "$cmd"
        else
            log_warning "Issue命令文件不存在: $cmd"
            UNTESTED_COMMANDS=$((UNTESTED_COMMANDS + 1))
        fi
    done
}

test_prd_management_commands() {
    log_info "测试PRD管理命令兼容性..."

    local prd_commands=(
        "prd-status" "prd-parse" "prd-new" "prd-list" "prd-edit"
    )

    for cmd in "${prd_commands[@]}"; do
        if [ -f ".claude/commands/pm/${cmd}.md" ]; then
            analyze_command_compatibility "$cmd"
        else
            log_warning "PRD命令文件不存在: $cmd"
            UNTESTED_COMMANDS=$((UNTESTED_COMMANDS + 1))
        fi
    done
}

test_workflow_commands() {
    log_info "测试工作流程命令兼容性..."

    local workflow_commands=(
        "init" "sync" "status" "standup" "validate"
    )

    for cmd in "${workflow_commands[@]}"; do
        if [ -f ".claude/commands/pm/${cmd}.md" ]; then
            analyze_command_compatibility "$cmd"
        else
            log_warning "工作流程命令文件不存在: $cmd"
            UNTESTED_COMMANDS=$((UNTESTED_COMMANDS + 1))
        fi
    done
}

test_query_analysis_commands() {
    log_info "测试查询分析命令兼容性..."

    local query_commands=(
        "search" "help" "next" "in-progress" "blocked"
    )

    for cmd in "${query_commands[@]}"; do
        if [ -f ".claude/commands/pm/${cmd}.md" ]; then
            analyze_command_compatibility "$cmd"
        else
            log_warning "查询分析命令文件不存在: $cmd"
            UNTESTED_COMMANDS=$((UNTESTED_COMMANDS + 1))
        fi
    done
}

test_utility_commands() {
    log_info "测试工具命令兼容性..."

    local utility_commands=(
        "clean" "import" "test-reference-update"
    )

    for cmd in "${utility_commands[@]}"; do
        if [ -f ".claude/commands/pm/${cmd}.md" ]; then
            analyze_command_compatibility "$cmd"
        else
            log_warning "工具命令文件不存在: $cmd"
            UNTESTED_COMMANDS=$((UNTESTED_COMMANDS + 1))
        fi
    done
}

# ==========================================
# 生成兼容性报告
# ==========================================

generate_compatibility_summary_report() {
    log_info "生成CCPM命令兼容性汇总报告..."

    local report_file="$COMMANDS_TEST_DIR/results/ccpm-commands-compatibility-report.md"
    local total_tested=$((COMPATIBLE_COMMANDS + INCOMPATIBLE_COMMANDS))
    local compatibility_rate=0

    if [ "$total_tested" -gt 0 ]; then
        compatibility_rate=$((COMPATIBLE_COMMANDS * 100 / total_tested))
    fi

    cat > "$report_file" << EOF
# CCPM命令云效平台兼容性测试报告

## 测试执行摘要

- **执行时间**: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
- **测试范围**: 全部CCPM命令云效平台兼容性
- **测试方法**: 静态代码分析 + 架构兼容性评估

## 总体兼容性结果

- **命令总数**: $TOTAL_COMMANDS
- **兼容命令**: $COMPATIBLE_COMMANDS (高/中等兼容性)
- **不兼容命令**: $INCOMPATIBLE_COMMANDS (低兼容性)
- **未测试命令**: $UNTESTED_COMMANDS
- **兼容性比率**: ${compatibility_rate}%

## 兼容性分布

### 按兼容性级别分类

| 兼容性级别 | 命令数量 | 百分比 | 说明 |
|------------|----------|--------|------|
| 高兼容性 | $(find "$COMMANDS_TEST_DIR/results" -name "*-compatibility.md" -exec grep -l "高兼容性" {} \; 2>/dev/null | wc -l) | | 无需或少量修改即可在云效平台工作 |
| 中等兼容性 | $(find "$COMMANDS_TEST_DIR/results" -name "*-compatibility.md" -exec grep -l "中等兼容性" {} \; 2>/dev/null | wc -l) | | 需要适配但主要逻辑可复用 |
| 低兼容性 | $(find "$COMMANDS_TEST_DIR/results" -name "*-compatibility.md" -exec grep -l "低兼容性" {} \; 2>/dev/null | wc -l) | | 需要显著修改才能在云效平台工作 |

### 按功能分类兼容性

| 功能分类 | 预期兼容性 | 实际兼容性 | 备注 |
|----------|------------|------------|------|
| Epic管理 | 90%+ | 待分析 | 核心功能，映射到父工作项 |
| Issue管理 | 90%+ | 待分析 | 核心功能，映射到子工作项 |
| PRD管理 | 95%+ | 待分析 | 无平台依赖，高兼容性 |
| 工作流程 | 85%+ | 待分析 | 部分需要平台适配 |
| 查询分析 | 95%+ | 待分析 | 基于本地数据，高兼容性 |
| 工具命令 | 70%+ | 待分析 | 部分工具需要适配 |

## 详细兼容性分析

### 高兼容性命令 (Ready for Yunxiao)

这些命令预期在云效平台上可以直接或几乎直接工作：

EOF

    # 列出高兼容性命令
    find "$COMMANDS_TEST_DIR/results" -name "*-compatibility.md" -exec grep -l "高兼容性" {} \; 2>/dev/null | while read -r file; do
        local cmd_name=$(basename "$file" "-compatibility.md")
        echo "- **$cmd_name**: $(grep "兼容性得分" "$file" | cut -d: -f2 | tr -d ' ')" >> "$report_file"
    done

    cat >> "$report_file" << EOF

### 中等兼容性命令 (Needs Adaptation)

这些命令需要适配云效平台，但主要逻辑可以复用：

EOF

    # 列出中等兼容性命令
    find "$COMMANDS_TEST_DIR/results" -name "*-compatibility.md" -exec grep -l "中等兼容性" {} \; 2>/dev/null | while read -r file; do
        local cmd_name=$(basename "$file" "-compatibility.md")
        echo "- **$cmd_name**: $(grep "兼容性得分" "$file" | cut -d: -f2 | tr -d ' ')" >> "$report_file"
    done

    cat >> "$report_file" << EOF

### 低兼容性命令 (Requires Redesign)

这些命令需要显著修改或重新设计：

EOF

    # 列出低兼容性命令
    find "$COMMANDS_TEST_DIR/results" -name "*-compatibility.md" -exec grep -l "低兼容性" {} \; 2>/dev/null | while read -r file; do
        local cmd_name=$(basename "$file" "-compatibility.md")
        echo "- **$cmd_name**: $(grep "兼容性得分" "$file" | cut -d: -f2 | tr -d ' ')" >> "$report_file"
    done

    cat >> "$report_file" << EOF

## 适配优先级建议

### 第一阶段 (P0 - 核心功能)
优先适配核心工作流程命令：
- init (初始化)
- sync (同步)
- status (状态查询)
- epic-* (Epic管理核心命令)
- issue-* (Issue管理核心命令)

### 第二阶段 (P1 - 扩展功能)
适配高频使用的扩展功能：
- prd-* (PRD管理命令)
- search (搜索功能)
- standup (站会功能)

### 第三阶段 (P2 - 工具功能)
适配工具和高级功能：
- 剩余的epic-*和issue-*命令
- 工具类命令
- 测试和验证命令

## 技术实施建议

### 高兼容性命令
- 验证平台检测逻辑正确性
- 确认云效规则文件完整性
- 进行端到端测试

### 中等兼容性命令
- 添加平台检测逻辑
- 创建云效专用规则文件
- 抽象平台相关操作

### 低兼容性命令
- 评估重构必要性
- 考虑创建云效专用版本
- 抽象核心逻辑到平台无关层

## 风险评估

### 兼容性风险
- **高风险**: 低兼容性命令可能需要大量开发工作
- **中风险**: 中等兼容性命令需要仔细设计适配方案
- **低风险**: 高兼容性命令主要是验证工作

### 用户影响
- **积极影响**: ${compatibility_rate}%的命令兼容性达到预期
- **注意事项**: $(echo "$((100 - compatibility_rate))")%的命令需要用户了解平台差异

## 结论和建议

$(if [ "$compatibility_rate" -ge 95 ]; then
    echo "🎉 **兼容性达标**: ${compatibility_rate}%的兼容性超过95%目标，云效平台集成已准备就绪。"
    echo ""
    echo "### 部署建议"
    echo "- ✅ 立即开始高兼容性命令的验证测试"
    echo "- ✅ 启动中等兼容性命令的适配开发"
    echo "- ✅ 制定低兼容性命令的重构计划"
elif [ "$compatibility_rate" -ge 85 ]; then
    echo "✅ **兼容性良好**: ${compatibility_rate}%的兼容性接近95%目标，需要少量优化。"
    echo ""
    echo "### 优化建议"
    echo "- 🔧 优先解决中等兼容性命令的适配问题"
    echo "- 🔧 完善平台检测逻辑覆盖"
    echo "- 🔧 增强云效规则文件完整性"
else
    echo "⚠️ **需要改进**: ${compatibility_rate}%的兼容性未达到95%目标，需要重点优化。"
    echo ""
    echo "### 改进计划"
    echo "- 🚧 重点分析低兼容性命令的适配方案"
    echo "- 🚧 加强平台抽象层设计"
    echo "- 🚧 考虑分阶段发布策略"
fi)

### 下一步行动

1. **立即行动**:
   - 对高兼容性命令进行实际测试验证
   - 开始中等兼容性命令的适配开发

2. **短期计划** (1-2周):
   - 完成核心命令的云效平台适配
   - 建立自动化兼容性测试流程

3. **中期计划** (1个月):
   - 完成所有目标命令的云效平台支持
   - 建立持续兼容性验证机制

---
测试执行者: CCPM命令兼容性分析系统
报告生成时间: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
详细结果: 查看 $COMMANDS_TEST_DIR/results/ 目录下的各命令分析报告
EOF

    log_success "CCPM命令兼容性汇总报告已生成: $report_file"

    # 显示测试摘要
    log_info "==========================================="
    log_info "CCPM命令兼容性测试完成"
    log_info "==========================================="
    log_info "命令总数: $TOTAL_COMMANDS"
    log_info "兼容命令: $COMPATIBLE_COMMANDS"
    log_info "不兼容命令: $INCOMPATIBLE_COMMANDS"
    log_info "未测试命令: $UNTESTED_COMMANDS"
    log_info "兼容性比率: ${compatibility_rate}%"

    if [ "$compatibility_rate" -ge 95 ]; then
        log_success "🎉 CCPM命令兼容性达标！"
        return 0
    else
        log_warning "⚠️ CCPM命令兼容性需要进一步优化"
        return 1
    fi
}

# ==========================================
# 清理测试环境
# ==========================================

cleanup_commands_test_environment() {
    log_info "清理CCPM命令测试环境..."

    # 保留测试结果，仅清理临时文件
    rm -f /tmp/command_analysis_*

    log_success "CCPM命令测试环境清理完成"
}

# ==========================================
# 主执行流程
# ==========================================

main() {
    log_info "🚀 开始执行CCPM命令云效平台兼容性测试"

    # 设置清理处理
    trap cleanup_commands_test_environment EXIT

    # 执行测试套件
    setup_commands_test_environment
    run_ccpm_commands_compatibility_test

    cleanup_commands_test_environment

    log_success "🎉 CCPM命令兼容性测试完成"
}

# 只在直接执行脚本时运行main函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi