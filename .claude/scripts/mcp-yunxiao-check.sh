#!/bin/bash

# 阿里云云效MCP连接检查脚本
# 用于诊断和验证alibabacloud-devops-mcp-server连接状态

set -e

# 颜色输出定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查结果统计
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((PASSED_CHECKS++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((FAILED_CHECKS++))
}

# 检查计数
check_counter() {
    ((TOTAL_CHECKS++))
}

# 1. MCP服务器安装检查
check_mcp_server_installation() {
    log_info "检查alibabacloud-devops-mcp-server安装状态..."
    check_counter

    if command -v alibabacloud-devops-mcp-server &> /dev/null; then
        local version=$(alibabacloud-devops-mcp-server --version 2>/dev/null || echo "未知版本")
        log_success "MCP服务器已安装 (版本: $version)"
        return 0
    elif npm list -g alibabacloud-devops-mcp-server &> /dev/null; then
        log_success "MCP服务器已通过npm全局安装"
        return 0
    else
        log_error "MCP服务器未安装"
        log_info "安装命令: npm install -g alibabacloud-devops-mcp-server"
        return 1
    fi
}

# 2. Claude Code配置文件检查
check_claude_code_config() {
    log_info "检查Claude Code MCP配置文件..."
    check_counter

    local config_paths=(
        "$HOME/.config/claude-code/mcp.json"
        "$APPDATA/claude-code/mcp.json"
        "/c/Users/$USER/.config/claude-code/mcp.json"
    )

    local config_found=false
    for config_path in "${config_paths[@]}"; do
        if [ -f "$config_path" ]; then
            log_success "找到MCP配置文件: $config_path"
            config_found=true

            # 检查配置文件格式
            if command -v jq &> /dev/null; then
                if jq '.mcpServers.["alibabacloud-devops"]' "$config_path" &> /dev/null; then
                    log_success "云效MCP配置存在"
                else
                    log_warning "配置文件中缺少alibabacloud-devops配置"
                fi
            else
                log_warning "jq未安装，无法验证配置格式"
            fi
            break
        fi
    done

    if [ "$config_found" = false ]; then
        log_error "未找到Claude Code MCP配置文件"
        log_info "请在以下路径创建配置: ~/.config/claude-code/mcp.json"
        return 1
    fi

    return 0
}

# 3. 环境变量检查
check_environment_variables() {
    log_info "检查必需的环境变量..."
    check_counter

    local env_vars=(
        "ALIBABA_CLOUD_ACCESS_KEY_ID"
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET"
        "DEVOPS_ORG_ID"
    )

    local missing_vars=()
    for var in "${env_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done

    if [ ${#missing_vars[@]} -eq 0 ]; then
        log_success "所有必需环境变量已设置"
        return 0
    else
        log_error "缺少环境变量: ${missing_vars[*]}"
        log_info "请在MCP配置文件的env部分设置这些变量"
        return 1
    fi
}

# 4. 网络连接检查
check_network_connectivity() {
    log_info "检查网络连接..."
    check_counter

    # 检查阿里云API端点连接
    local endpoints=(
        "devops.aliyuncs.com"
        "ecs.aliyuncs.com"
    )

    local connection_ok=true
    for endpoint in "${endpoints[@]}"; do
        if ping -c 1 -W 3 "$endpoint" &> /dev/null; then
            log_success "可以连接到 $endpoint"
        else
            log_warning "无法连接到 $endpoint"
            connection_ok=false
        fi
    done

    if [ "$connection_ok" = true ]; then
        return 0
    else
        log_error "网络连接存在问题"
        return 1
    fi
}

# 5. 项目配置检查
check_project_config() {
    log_info "检查项目配置..."
    check_counter

    local ccpm_config=".claude/ccpm.config"
    if [ -f "$ccpm_config" ]; then
        log_success "找到CCPM配置文件"

        # 检查项目ID配置
        if grep -q "project_id" "$ccpm_config"; then
            local project_id=$(grep "project_id" "$ccpm_config" | cut -d'=' -f2 | tr -d ' "')
            if [ -n "$project_id" ]; then
                log_success "项目ID已配置: $project_id"
            else
                log_warning "项目ID配置为空"
            fi
        else
            log_warning "CCPM配置中未找到project_id"
        fi
        return 0
    else
        log_error "未找到CCPM配置文件: $ccpm_config"
        return 1
    fi
}

# 6. MCP工具可用性快速检查
check_mcp_tools_availability() {
    log_info "检查MCP工具可用性..."
    check_counter

    # 这里只能做基础检查，实际工具测试需要在Claude Code环境中进行
    if command -v alibabacloud-devops-mcp-server &> /dev/null; then
        log_info "尝试启动MCP服务器进行快速检查..."

        # 短时间启动测试
        timeout 5s alibabacloud-devops-mcp-server --help &> /dev/null
        local exit_code=$?

        if [ $exit_code -eq 0 ] || [ $exit_code -eq 124 ]; then
            log_success "MCP服务器可以正常启动"
            return 0
        else
            log_error "MCP服务器启动失败"
            return 1
        fi
    else
        log_error "MCP服务器不可用"
        return 1
    fi
}

# 生成诊断报告
generate_report() {
    echo
    echo "========================================"
    echo "         MCP连接诊断报告"
    echo "========================================"
    echo "总检查项目: $TOTAL_CHECKS"
    echo -e "通过检查: ${GREEN}$PASSED_CHECKS${NC}"
    echo -e "失败检查: ${RED}$FAILED_CHECKS${NC}"
    echo

    local success_rate=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    if [ $success_rate -ge 80 ]; then
        echo -e "${GREEN}✓ 系统状态良好 (${success_rate}%)${NC}"
        echo "建议: 可以尝试使用云效MCP功能"
    elif [ $success_rate -ge 60 ]; then
        echo -e "${YELLOW}⚠ 系统状态一般 (${success_rate}%)${NC}"
        echo "建议: 解决警告项目后再使用"
    else
        echo -e "${RED}✗ 系统状态不佳 (${success_rate}%)${NC}"
        echo "建议: 需要解决主要问题才能使用云效功能"
    fi
    echo
}

# 提供解决方案建议
provide_solutions() {
    echo "========================================"
    echo "         常见问题解决方案"
    echo "========================================"
    echo
    echo "1. 安装MCP服务器:"
    echo "   npm install -g alibabacloud-devops-mcp-server"
    echo
    echo "2. 创建MCP配置文件 (~/.config/claude-code/mcp.json):"
    cat << 'EOF'
   {
     "mcpServers": {
       "alibabacloud-devops": {
         "command": "alibabacloud-devops-mcp-server",
         "args": [],
         "env": {
           "ALIBABA_CLOUD_ACCESS_KEY_ID": "your_access_key",
           "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "your_secret_key",
           "DEVOPS_ORG_ID": "your_org_id"
         }
       }
     }
   }
EOF
    echo
    echo "3. 配置项目ID (在.claude/ccpm.config中):"
    echo "   project_id=your_project_id"
    echo
    echo "4. 重启Claude Code使配置生效"
    echo
}

# 主函数
main() {
    echo "========================================"
    echo "  阿里云云效MCP连接诊断工具"
    echo "========================================"
    echo

    check_mcp_server_installation
    check_claude_code_config
    check_environment_variables
    check_network_connectivity
    check_project_config
    check_mcp_tools_availability

    generate_report

    if [ $FAILED_CHECKS -gt 0 ]; then
        provide_solutions
        exit 1
    else
        echo -e "${GREEN}🎉 所有检查通过！云效MCP连接应该可以正常工作。${NC}"
        exit 0
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi