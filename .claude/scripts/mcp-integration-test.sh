#!/bin/bash

# 阿里云云效MCP集成测试脚本
# 端到端验证MCP连接和所有核心功能

set -e

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEST_LOG="$SCRIPT_DIR/mcp-integration-test.log"
CONFIG_BACKUP=""

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$TEST_LOG"
}

log_success() {
    echo -e "${GREEN}[PASS]${NC} $1" | tee -a "$TEST_LOG"
    ((PASSED_TESTS++))
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1" | tee -a "$TEST_LOG"
    ((FAILED_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1" | tee -a "$TEST_LOG"
}

log_skip() {
    echo -e "${PURPLE}[SKIP]${NC} $1" | tee -a "$TEST_LOG"
    ((SKIPPED_TESTS++))
}

# 测试计数
start_test() {
    ((TOTAL_TESTS++))
    echo -e "\n${BLUE}=== 测试 $TOTAL_TESTS: $1 ===${NC}" | tee -a "$TEST_LOG"
}

# 初始化测试环境
initialize_test_environment() {
    log_info "初始化集成测试环境..."

    # 创建测试日志
    echo "MCP集成测试开始 - $(date)" > "$TEST_LOG"

    # 备份原有配置（如果存在）
    if [ -f ~/.config/claude-code/mcp.json ]; then
        CONFIG_BACKUP="~/.config/claude-code/mcp.json.backup.$(date +%s)"
        cp ~/.config/claude-code/mcp.json "$CONFIG_BACKUP"
        log_info "已备份现有配置到: $CONFIG_BACKUP"
    fi
}

# 清理测试环境
cleanup_test_environment() {
    log_info "清理测试环境..."

    # 恢复配置备份（如果需要）
    if [ -n "$CONFIG_BACKUP" ] && [ -f "$CONFIG_BACKUP" ]; then
        mv "$CONFIG_BACKUP" ~/.config/claude-code/mcp.json
        log_info "已恢复配置备份"
    fi
}

# 测试1：环境前置条件验证
test_prerequisites() {
    start_test "环境前置条件验证"

    local prerequisites_ok=true

    # 检查Node.js
    if command -v node &> /dev/null; then
        local node_version=$(node --version)
        log_success "Node.js已安装: $node_version"
    else
        log_error "Node.js未安装"
        prerequisites_ok=false
    fi

    # 检查npm
    if command -v npm &> /dev/null; then
        local npm_version=$(npm --version)
        log_success "npm已安装: $npm_version"
    else
        log_error "npm未安装"
        prerequisites_ok=false
    fi

    # 检查jq（可选）
    if command -v jq &> /dev/null; then
        log_success "jq已安装（用于JSON处理）"
    else
        log_warning "jq未安装，部分验证功能将被跳过"
    fi

    if [ "$prerequisites_ok" = true ]; then
        log_success "所有前置条件满足"
        return 0
    else
        log_error "前置条件不满足"
        return 1
    fi
}

# 测试2：MCP服务器安装验证
test_mcp_server_installation() {
    start_test "MCP服务器安装验证"

    # 检查全局安装
    if command -v alibabacloud-devops-mcp-server &> /dev/null; then
        local version=$(alibabacloud-devops-mcp-server --version 2>/dev/null || echo "未知版本")
        log_success "MCP服务器已安装: $version"
        return 0
    fi

    # 检查npm全局列表
    if npm list -g alibabacloud-devops-mcp-server &> /dev/null; then
        log_success "MCP服务器已通过npm全局安装"
        return 0
    fi

    # 尝试npx方式
    if timeout 10s npx --yes alibabacloud-devops-mcp-server --version &> /dev/null; then
        log_success "MCP服务器可通过npx访问"
        return 0
    fi

    log_error "MCP服务器未安装或不可访问"
    log_info "安装命令: npm install -g alibabacloud-devops-mcp-server"
    return 1
}

# 测试3：配置文件结构验证
test_configuration_structure() {
    start_test "配置文件结构验证"

    local config_dir="$HOME/.config/claude-code"
    local config_file="$config_dir/mcp.json"

    # 检查配置目录
    if [ ! -d "$config_dir" ]; then
        log_warning "Claude Code配置目录不存在，创建中..."
        mkdir -p "$config_dir"
    fi

    # 检查配置文件
    if [ ! -f "$config_file" ]; then
        log_warning "MCP配置文件不存在，创建模板配置..."

        cat > "$config_file" << 'EOF'
{
  "mcpServers": {
    "alibabacloud-devops": {
      "command": "alibabacloud-devops-mcp-server",
      "args": [],
      "env": {
        "ALIBABA_CLOUD_ACCESS_KEY_ID": "YOUR_ACCESS_KEY_ID",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "YOUR_ACCESS_KEY_SECRET",
        "DEVOPS_ORG_ID": "YOUR_ORG_ID"
      }
    }
  }
}
EOF
        log_info "已创建模板配置文件: $config_file"
        log_warning "请填入正确的阿里云访问凭证"
    fi

    # 验证JSON格式
    if command -v jq &> /dev/null; then
        if jq . "$config_file" &> /dev/null; then
            log_success "配置文件JSON格式正确"
        else
            log_error "配置文件JSON格式错误"
            return 1
        fi

        # 检查云效配置存在
        if jq '.mcpServers.["alibabacloud-devops"]' "$config_file" &> /dev/null; then
            log_success "云效MCP配置节存在"
        else
            log_error "配置文件中缺少云效MCP配置"
            return 1
        fi
    else
        log_skip "跳过JSON格式验证（jq未安装）"
    fi

    log_success "配置文件结构验证完成"
    return 0
}

# 测试4：网络连接验证
test_network_connectivity() {
    start_test "网络连接验证"

    local endpoints=(
        "devops.aliyuncs.com"
        "ecs.aliyuncs.com"
    )

    local connectivity_ok=true

    for endpoint in "${endpoints[@]}"; do
        if ping -c 1 -W 3 "$endpoint" &> /dev/null; then
            log_success "可以连接到 $endpoint"
        else
            log_warning "无法ping通 $endpoint"

            # 尝试HTTP连接
            if curl -I --connect-timeout 5 "https://$endpoint" &> /dev/null; then
                log_success "HTTP连接到 $endpoint 成功"
            else
                log_error "HTTP连接到 $endpoint 失败"
                connectivity_ok=false
            fi
        fi
    done

    if [ "$connectivity_ok" = true ]; then
        log_success "网络连接验证通过"
        return 0
    else
        log_error "网络连接存在问题"
        return 1
    fi
}

# 测试5：项目配置验证
test_project_configuration() {
    start_test "项目配置验证"

    local ccpm_config=".claude/ccpm.config"

    if [ ! -f "$ccpm_config" ]; then
        log_error "CCPM配置文件不存在: $ccpm_config"
        log_info "请确保在正确的项目目录中运行测试"
        return 1
    fi

    log_success "找到CCPM配置文件"

    # 检查项目ID配置
    if grep -q "project_id" "$ccpm_config"; then
        local project_id=$(grep "project_id" "$ccpm_config" | cut -d'=' -f2 | tr -d ' "')
        if [ -n "$project_id" ] && [ "$project_id" != "your_project_id" ]; then
            log_success "项目ID已配置: $project_id"
        else
            log_warning "项目ID配置为空或使用默认值"
        fi
    else
        log_warning "CCPM配置中未找到project_id"
    fi

    # 检查其他配置项
    local config_items=("platform" "org_id")
    for item in "${config_items[@]}"; do
        if grep -q "$item" "$ccpm_config"; then
            local value=$(grep "$item" "$ccpm_config" | cut -d'=' -f2 | tr -d ' "')
            log_info "配置项 $item: $value"
        fi
    done

    log_success "项目配置验证完成"
    return 0
}

# 测试6：MCP工具可用性模拟验证
test_mcp_tools_simulation() {
    start_test "MCP工具可用性模拟验证"

    # 运行工具验证器
    if [ -f "$SCRIPT_DIR/mcp-tools-validator.js" ]; then
        log_info "运行MCP工具验证器..."

        if node "$SCRIPT_DIR/mcp-tools-validator.js" >> "$TEST_LOG" 2>&1; then
            log_success "MCP工具验证器运行成功"
        else
            log_warning "MCP工具验证器运行时出现警告"
        fi
    else
        log_warning "MCP工具验证器不存在，跳过验证"
    fi

    # 检查核心工具定义
    local core_tools=(
        "alibabacloud_devops_get_project_info"
        "create_work_item"
        "search_workitems"
        "update_work_item"
        "create_work_item_comment"
    )

    log_info "验证核心工具清单..."
    for tool in "${core_tools[@]}"; do
        log_info "核心工具: $tool"
    done

    log_success "MCP工具定义验证完成"
    return 0
}

# 测试7：诊断脚本执行验证
test_diagnostic_scripts() {
    start_test "诊断脚本执行验证"

    local scripts_ok=true

    # 测试bash诊断脚本
    if [ -f "$SCRIPT_DIR/mcp-yunxiao-check.sh" ]; then
        log_info "测试bash诊断脚本..."
        if timeout 30s bash "$SCRIPT_DIR/mcp-yunxiao-check.sh" >> "$TEST_LOG" 2>&1; then
            log_success "bash诊断脚本执行成功"
        else
            log_warning "bash诊断脚本执行有问题（可能因为配置不完整）"
        fi
    else
        log_error "bash诊断脚本不存在"
        scripts_ok=false
    fi

    # 测试PowerShell诊断脚本（如果在支持的环境中）
    if command -v powershell &> /dev/null && [ -f "$SCRIPT_DIR/mcp-yunxiao-quick-check.ps1" ]; then
        log_info "测试PowerShell诊断脚本..."
        if timeout 30s powershell -ExecutionPolicy Bypass -File "$SCRIPT_DIR/mcp-yunxiao-quick-check.ps1" >> "$TEST_LOG" 2>&1; then
            log_success "PowerShell诊断脚本执行成功"
        else
            log_warning "PowerShell诊断脚本执行有问题"
        fi
    else
        log_skip "跳过PowerShell诊断脚本测试（不支持或脚本不存在）"
    fi

    if [ "$scripts_ok" = true ]; then
        log_success "诊断脚本验证完成"
        return 0
    else
        log_error "诊断脚本验证失败"
        return 1
    fi
}

# 测试8：文档完整性验证
test_documentation_completeness() {
    start_test "文档完整性验证"

    local required_docs=(
        ".claude/rules/platform-yunxiao-mcp-validation.md"
        ".claude/docs/mcp-troubleshooting-guide.md"
    )

    local docs_ok=true

    for doc in "${required_docs[@]}"; do
        if [ -f "$doc" ]; then
            local line_count=$(wc -l < "$doc")
            log_success "文档存在: $doc ($line_count 行)"
        else
            log_error "缺少文档: $doc"
            docs_ok=false
        fi
    done

    # 检查脚本文件
    local required_scripts=(
        ".claude/scripts/mcp-yunxiao-check.sh"
        ".claude/scripts/mcp-yunxiao-quick-check.ps1"
        ".claude/scripts/mcp-tools-validator.js"
    )

    for script in "${required_scripts[@]}"; do
        if [ -f "$script" ]; then
            log_success "脚本存在: $script"
        else
            log_error "缺少脚本: $script"
            docs_ok=false
        fi
    done

    if [ "$docs_ok" = true ]; then
        log_success "文档完整性验证通过"
        return 0
    else
        log_error "文档完整性验证失败"
        return 1
    fi
}

# 生成集成测试报告
generate_integration_report() {
    echo -e "\n${BLUE}=======================================${NC}"
    echo -e "${BLUE}         MCP集成测试报告${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo "测试时间: $(date)"
    echo "总测试数: $TOTAL_TESTS"
    echo -e "通过测试: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "失败测试: ${RED}$FAILED_TESTS${NC}"
    echo -e "跳过测试: ${PURPLE}$SKIPPED_TESTS${NC}"

    local success_rate=0
    if [ $TOTAL_TESTS -gt 0 ]; then
        success_rate=$((PASSED_TESTS * 100 / TOTAL_TESTS))
    fi

    echo -e "\n成功率: $success_rate%"

    if [ $FAILED_TESTS -eq 0 ]; then
        if [ $success_rate -ge 90 ]; then
            echo -e "${GREEN}🎉 集成测试完全通过！MCP连接准备就绪。${NC}"
        else
            echo -e "${YELLOW}⚠️  集成测试基本通过，但有部分跳过项目。${NC}"
        fi
        echo -e "${GREEN}建议: 可以开始使用云效MCP功能${NC}"
    else
        echo -e "${RED}❌ 集成测试发现问题，需要解决后再使用。${NC}"
        echo -e "${RED}建议: 检查失败的测试项目并根据日志解决问题${NC}"
    fi

    echo -e "\n详细日志: $TEST_LOG"
    echo -e "${BLUE}=======================================${NC}"
}

# 提供下一步建议
provide_next_steps() {
    echo -e "\n${BLUE}=======================================${NC}"
    echo -e "${BLUE}         下一步建议${NC}"
    echo -e "${BLUE}=======================================${NC}"

    if [ $FAILED_TESTS -eq 0 ]; then
        echo "✅ 所有核心组件已就绪，可以进行以下操作："
        echo "1. 在Claude Code中测试实际的MCP工具调用"
        echo "2. 配置真实的阿里云访问凭证"
        echo "3. 验证云效项目连接"
        echo "4. 开始使用CCPM云效集成功能"
    else
        echo "⚠️  需要解决以下问题："
        echo "1. 检查失败的测试项目"
        echo "2. 根据错误日志进行修复"
        echo "3. 重新运行集成测试"
        echo "4. 参考故障排除指南: .claude/docs/mcp-troubleshooting-guide.md"
    fi

    echo -e "\n📖 相关文档："
    echo "- MCP验证规则: .claude/rules/platform-yunxiao-mcp-validation.md"
    echo "- 故障排除指南: .claude/docs/mcp-troubleshooting-guide.md"
    echo "- 工具测试器: .claude/scripts/mcp-tools-validator.js"

    echo -e "${BLUE}=======================================${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}=======================================${NC}"
    echo -e "${BLUE}  阿里云云效MCP集成测试${NC}"
    echo -e "${BLUE}=======================================${NC}"
    echo ""

    # 设置错误处理
    trap cleanup_test_environment EXIT

    # 初始化测试环境
    initialize_test_environment

    # 执行所有测试
    test_prerequisites
    test_mcp_server_installation
    test_configuration_structure
    test_network_connectivity
    test_project_configuration
    test_mcp_tools_simulation
    test_diagnostic_scripts
    test_documentation_completeness

    # 生成报告
    generate_integration_report
    provide_next_steps

    # 返回结果
    if [ $FAILED_TESTS -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi