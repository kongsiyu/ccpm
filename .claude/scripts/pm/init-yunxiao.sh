#!/bin/bash

# 云效(Yunxiao)环境检测与初始化脚本
# 检测和设置阿里云云效集成的运行环境
# 验证MCP服务可用性、project_id配置，并提供配置指导

# Source required libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
LIB_DIR="$(cd "$SCRIPT_DIR/../../lib" && pwd)"
source "$LIB_DIR/error.sh"
source "$LIB_DIR/dependencies.sh"
source "$LIB_DIR/yunxiao.sh"

# =============================================================================
# 常量定义
# =============================================================================

CONFIG_FILE=".ccpm-config.yaml"
CACHE_DIR=".claude/cache/yunxiao"
LOG_DIR=".claude/logs"
LOG_FILE="$LOG_DIR/yunxiao.log"
SETTINGS_DIR=".claude"
SETTINGS_FILE="$SETTINGS_DIR/settings.local.json"

# MCP服务器配置模板
MCP_CONFIG_TEMPLATE='
{
  "mcpServers": {
    "yunxiao": {
      "command": "npx",
      "args": ["-y", "alibabacloud-devops-mcp-server"],
      "env": {
        "YUNXIAO_ACCESS_TOKEN": "<YOUR_ACCESS_TOKEN>"
      }
    }
  }
}'

# =============================================================================
# 横幅和欢迎界面
# =============================================================================

print_banner() {
    echo ""
    echo "=============================================="
    echo "   云效 (Yunxiao) 环境检测与初始化工具"
    echo "=============================================="
    echo ""
    echo "🔍 检测阿里云云效MCP集成环境"
    echo "⚙️  配置项目和MCP服务器"
    echo "📁 创建必要的目录结构"
    echo "🔧 提供故障排除指导"
    echo ""
}

print_success_summary() {
    echo ""
    echo "✅ 云效环境初始化完成！"
    echo "=========================="
    echo ""
    echo "📊 环境状态:"

    local project_id
    project_id=$(get_project_id)
    if [ -n "$project_id" ]; then
        echo "  项目ID: $project_id"
    fi

    local platform
    platform=$(get_platform_config)
    if [ -n "$platform" ]; then
        echo "  平台: $platform"
    fi

    if check_yunxiao_mcp_service; then
        echo "  MCP服务: ✅ 可用"
    else
        echo "  MCP服务: ❌ 需要配置"
    fi

    echo ""
    echo "🎯 后续步骤:"
    echo "  1. 检查配置: source .claude/lib/yunxiao.sh && show_yunxiao_config"
    echo "  2. 测试连接: source .claude/lib/yunxiao.sh && yunxiao_health_check"
    echo "  3. 查看日志: tail -f $LOG_FILE"
    echo ""
    echo "📚 配置指南: source .claude/lib/yunxiao.sh && show_yunxiao_setup_guide"
    echo ""
}

# =============================================================================
# 系统依赖检测
# =============================================================================

check_dependencies() {
    info "检查系统依赖..."

    local missing_deps=()
    local required_commands=("jq" "curl" "git")

    # Node.js和npm检查（MCP服务器需要）
    if ! command -v npx >/dev/null 2>&1; then
        if command -v npm >/dev/null 2>&1; then
            warning "发现npm但npx不可用，可能是版本问题"
        else
            missing_deps+=("npm/npx (Node.js)")
        fi
    else
        success "Node.js 运行时可用 ($(node --version 2>/dev/null || echo "未知版本"))"
    fi

    # 检查其他必需命令
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        else
            success "$cmd 可用"
        fi
    done

    # 检查bash版本（需要关联数组支持）
    if [ "${BASH_VERSION%%.*}" -lt 4 ]; then
        missing_deps+=("bash 4.0+ (当前版本: $BASH_VERSION)")
    else
        success "Bash版本支持 ($BASH_VERSION)"
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo ""
        warning "缺少以下依赖:"
        for dep in "${missing_deps[@]}"; do
            echo "  ❌ $dep"
        done
        echo ""
        echo "安装建议:"
        echo "  • Node.js: https://nodejs.org/ 或使用包管理器 (apt install nodejs npm)"
        echo "  • jq: apt install jq / brew install jq"
        echo "  • curl: 通常系统自带，或 apt install curl"
        echo ""
        if ! confirm "是否继续初始化（某些功能可能不可用）?"; then
            error_exit "用户取消初始化"
        fi
    else
        success "所有系统依赖检查通过"
    fi

    echo ""
}

# =============================================================================
# 现有配置检测
# =============================================================================

detect_existing_config() {
    info "检测现有配置..."

    local config_exists=false
    local mcp_configured=false
    local issues_found=()

    # 检查项目配置文件
    if [ -f "$CONFIG_FILE" ]; then
        config_exists=true
        success "发现配置文件: $CONFIG_FILE"

        local platform
        platform=$(get_platform_config)
        if [ "$platform" = "yunxiao" ]; then
            success "平台设置正确: $platform"
        elif [ -n "$platform" ]; then
            warning "平台设置为: '$platform'，预期为: 'yunxiao'"
            issues_found+=("平台配置错误")
        else
            warning "未找到平台配置"
            issues_found+=("缺少平台配置")
        fi

        local project_id
        project_id=$(get_project_id)
        if [ -n "$project_id" ]; then
            if [[ "$project_id" =~ ^[0-9]+$ ]]; then
                success "项目ID配置正确: $project_id"
            else
                warning "项目ID格式错误: '$project_id'（应为数字）"
                issues_found+=("项目ID格式错误")
            fi
        else
            warning "未找到项目ID配置"
            issues_found+=("缺少项目ID")
        fi
    else
        info "未发现配置文件: $CONFIG_FILE"
    fi

    # 检查MCP服务器配置
    if [ -f "$SETTINGS_FILE" ]; then
        success "发现Claude Code设置文件: $SETTINGS_FILE"

        if grep -q '"yunxiao"' "$SETTINGS_FILE" 2>/dev/null; then
            mcp_configured=true
            success "发现云效MCP服务器配置"
        else
            info "未在设置文件中找到云效MCP配置"
        fi
    else
        info "未发现Claude Code设置文件: $SETTINGS_FILE"
    fi

    # 检查MCP服务可用性
    echo ""
    info "检测MCP服务状态..."
    if check_yunxiao_mcp_service; then
        success "云效MCP服务运行正常"
    else
        warning "云效MCP服务不可用"
        issues_found+=("MCP服务不可用")
    fi

    # 总结检测结果
    echo ""
    if [ ${#issues_found[@]} -eq 0 ] && [ "$config_exists" = true ] && [ "$mcp_configured" = true ]; then
        success "现有配置检查通过，无需重新配置"
        echo ""
        info "如需重新配置，请删除 $CONFIG_FILE 后重新运行"
        return 0
    else
        if [ ${#issues_found[@]} -gt 0 ]; then
            warning "发现以下问题:"
            for issue in "${issues_found[@]}"; do
                echo "  ❌ $issue"
            done
            echo ""
        fi
        info "将进入配置向导..."
        return 1
    fi
}

# =============================================================================
# 交互式配置向导
# =============================================================================

run_configuration_wizard() {
    echo ""
    echo "=== 配置向导 ==="
    echo ""

    # 获取当前配置（如果存在）
    local current_project_id
    current_project_id=$(get_project_id)

    local current_platform
    current_platform=$(get_platform_config)

    # 项目ID配置
    echo "📋 配置项目信息"
    echo ""

    local project_id=""
    while [ -z "$project_id" ]; do
        echo -n "请输入阿里云云效项目ID"
        if [ -n "$current_project_id" ]; then
            echo -n " (当前: $current_project_id)"
        fi
        echo -n ": "
        read -r input_project_id

        # 如果用户直接回车且有当前值，使用当前值
        if [ -z "$input_project_id" ] && [ -n "$current_project_id" ]; then
            project_id="$current_project_id"
        elif [ -n "$input_project_id" ]; then
            # 验证格式
            if [[ "$input_project_id" =~ ^[0-9]+$ ]]; then
                project_id="$input_project_id"
            else
                warning "项目ID必须是数字，请重新输入"
            fi
        else
            warning "项目ID不能为空，请输入有效的项目ID"
        fi
    done

    echo ""
    info "项目ID设置为: $project_id"

    # MCP服务器配置检查
    echo ""
    echo "🔌 MCP服务器配置"
    echo ""

    if check_yunxiao_mcp_service; then
        success "MCP服务器已配置且可用"
    else
        warning "MCP服务器未配置或不可用"
        echo ""
        echo "请按照以下步骤配置MCP服务器:"
        echo ""
        show_mcp_setup_instructions
        echo ""

        if confirm "是否已按照指示配置了MCP服务器?"; then
            info "验证MCP服务器配置..."
            if ! check_yunxiao_mcp_service; then
                warning "MCP服务器仍不可用，请检查配置"
                echo ""
                echo "常见问题排查:"
                echo "  1. 确认Claude Code已重启"
                echo "  2. 检查npm包是否正确安装: npm list -g alibabacloud-devops-mcp-server"
                echo "  3. 验证settings.json格式是否正确"
                echo "  4. 检查访问令牌是否有效"
                echo ""
            else
                success "MCP服务器配置验证成功"
            fi
        fi
    fi

    # 创建配置文件
    echo ""
    info "创建项目配置文件..."
    create_yunxiao_config "$project_id"

    echo ""
    success "配置向导完成"
}

show_mcp_setup_instructions() {
    echo "=== MCP服务器配置指南 ==="
    echo ""
    echo "1. 安装云效MCP服务器包:"
    echo "   npm install -g alibabacloud-devops-mcp-server"
    echo ""
    echo "2. 在Claude Code中配置MCP服务器:"
    echo "   打开Claude Code设置，在 settings.json 中添加:"
    echo ""
    echo "$MCP_CONFIG_TEMPLATE" | sed 's/^/   /'
    echo ""
    echo "3. 替换 <YOUR_ACCESS_TOKEN> 为您的阿里云云效访问令牌"
    echo "   获取访问令牌: https://devops.aliyun.com/"
    echo ""
    echo "4. 重启Claude Code以加载MCP服务器"
    echo ""
    echo "📖 详细文档: https://github.com/alibabacloud-devops/mcp-server"
}

# =============================================================================
# 配置验证
# =============================================================================

validate_final_setup() {
    echo ""
    info "验证最终配置..."

    local validation_passed=true

    # 验证配置文件
    if validate_yunxiao_config; then
        success "配置文件验证通过"
    else
        warning "配置文件验证失败"
        validation_passed=false
    fi

    # 验证目录结构
    if [ -d "$CACHE_DIR" ] && [ -d "$LOG_DIR" ]; then
        success "目录结构验证通过"
    else
        warning "目录结构不完整"
        validation_passed=false
    fi

    # 验证文件权限
    if [ -f "$CONFIG_FILE" ] && [ -r "$CONFIG_FILE" ]; then
        success "配置文件权限正确"
    else
        warning "配置文件权限问题"
        validation_passed=false
    fi

    if [ "$validation_passed" = true ]; then
        success "最终配置验证通过"
        return 0
    else
        warning "配置验证存在问题，请检查后重试"
        return 1
    fi
}

# =============================================================================
# 目录结构和权限设置
# =============================================================================

create_cache_directories() {
    info "创建缓存和日志目录..."

    # 创建缓存目录
    if ! mkdir -p "$CACHE_DIR"; then
        warning "无法创建缓存目录: $CACHE_DIR"
    else
        success "缓存目录创建成功: $CACHE_DIR"
    fi

    # 创建日志目录
    if ! mkdir -p "$LOG_DIR"; then
        warning "无法创建日志目录: $LOG_DIR"
    else
        success "日志目录创建成功: $LOG_DIR"
    fi

    # 创建设置目录
    if ! mkdir -p "$SETTINGS_DIR"; then
        warning "无法创建设置目录: $SETTINGS_DIR"
    else
        success "设置目录确认存在: $SETTINGS_DIR"
    fi

    # 初始化日志文件
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] 云效环境初始化开始" >> "$LOG_FILE"

    # 设置适当的权限
    chmod 755 "$CACHE_DIR" 2>/dev/null || true
    chmod 755 "$LOG_DIR" 2>/dev/null || true

    if [ -f "$CONFIG_FILE" ]; then
        chmod 644 "$CONFIG_FILE" 2>/dev/null || true
    fi

    success "目录结构和权限设置完成"
    echo ""
}

# =============================================================================
# 诊断和修复功能
# =============================================================================

run_diagnostics() {
    echo ""
    echo "=== 诊断信息 ==="
    echo ""

    # 系统信息
    echo "📱 系统信息:"
    echo "  操作系统: $(uname -s)"
    echo "  架构: $(uname -m)"
    if command -v node >/dev/null 2>&1; then
        echo "  Node.js: $(node --version)"
    fi
    if command -v npm >/dev/null 2>&1; then
        echo "  npm: $(npm --version)"
    fi
    echo ""

    # 配置状态
    echo "⚙️  配置状态:"
    if [ -f "$CONFIG_FILE" ]; then
        echo "  配置文件: ✅ 存在"
        echo "  平台: $(get_platform_config || echo "未设置")"
        echo "  项目ID: $(get_project_id || echo "未设置")"
    else
        echo "  配置文件: ❌ 不存在"
    fi
    echo ""

    # MCP服务状态
    echo "🔌 MCP服务状态:"
    if command -v npx >/dev/null 2>&1; then
        echo "  npx: ✅ 可用"
        if npx --yes alibabacloud-devops-mcp-server --help >/dev/null 2>&1; then
            echo "  云效MCP包: ✅ 已安装"
        else
            echo "  云效MCP包: ❌ 未安装或无法运行"
        fi
    else
        echo "  npx: ❌ 不可用"
    fi
    echo ""

    # 目录结构
    echo "📁 目录结构:"
    echo "  缓存目录: $([ -d "$CACHE_DIR" ] && echo "✅ 存在" || echo "❌ 不存在")"
    echo "  日志目录: $([ -d "$LOG_DIR" ] && echo "✅ 存在" || echo "❌ 不存在")"
    echo "  设置目录: $([ -d "$SETTINGS_DIR" ] && echo "✅ 存在" || echo "❌ 不存在")"
    echo ""

    # 文件权限
    echo "🔒 文件权限:"
    if [ -f "$CONFIG_FILE" ]; then
        echo "  配置文件: $(ls -l "$CONFIG_FILE" | awk '{print $1, $3, $4}')"
    fi
    if [ -f "$LOG_FILE" ]; then
        echo "  日志文件: $(ls -l "$LOG_FILE" | awk '{print $1, $3, $4}')"
    fi
    echo ""
}

auto_fix_common_issues() {
    info "自动修复常见问题..."

    local fixed_issues=()

    # 修复缺失的目录
    for dir in "$CACHE_DIR" "$LOG_DIR" "$SETTINGS_DIR"; do
        if [ ! -d "$dir" ]; then
            if mkdir -p "$dir" 2>/dev/null; then
                fixed_issues+=("创建目录: $dir")
            fi
        fi
    done

    # 修复配置文件权限
    if [ -f "$CONFIG_FILE" ] && [ ! -r "$CONFIG_FILE" ]; then
        if chmod 644 "$CONFIG_FILE" 2>/dev/null; then
            fixed_issues+=("修复配置文件权限")
        fi
    fi

    # 修复日志文件
    if [ ! -f "$LOG_FILE" ]; then
        if touch "$LOG_FILE" 2>/dev/null; then
            fixed_issues+=("创建日志文件")
        fi
    fi

    # 报告修复结果
    if [ ${#fixed_issues[@]} -gt 0 ]; then
        success "自动修复了以下问题:"
        for issue in "${fixed_issues[@]}"; do
            echo "  ✅ $issue"
        done
        echo ""
    else
        info "未发现可自动修复的问题"
        echo ""
    fi
}

# =============================================================================
# 故障排除指南
# =============================================================================

show_troubleshooting_guide() {
    echo ""
    echo "=== 故障排除指南 ==="
    echo ""

    echo "🔧 常见问题及解决方案:"
    echo ""

    echo "1. MCP服务不可用"
    echo "   • 检查Node.js安装: node --version"
    echo "   • 安装MCP包: npm install -g alibabacloud-devops-mcp-server"
    echo "   • 验证包安装: npm list -g alibabacloud-devops-mcp-server"
    echo "   • 重启Claude Code"
    echo ""

    echo "2. 项目ID配置错误"
    echo "   • 确认项目ID为纯数字"
    echo "   • 检查阿里云云效项目设置中的项目ID"
    echo "   • 重新运行: $0"
    echo ""

    echo "3. 权限问题"
    echo "   • 检查文件权限: ls -la $CONFIG_FILE"
    echo "   • 修复权限: chmod 644 $CONFIG_FILE"
    echo "   • 检查目录权限: ls -ld $CACHE_DIR"
    echo ""

    echo "4. 网络连接问题"
    echo "   • 检查网络连接: curl -I https://devops.aliyun.com"
    echo "   • 验证代理设置"
    echo "   • 检查防火墙设置"
    echo ""

    echo "📞 获取帮助:"
    echo "   • 查看日志: tail -f $LOG_FILE"
    echo "   • 检查配置: source .claude/lib/yunxiao.sh && show_yunxiao_config"
    echo "   • 重新初始化: rm $CONFIG_FILE && $0"
    echo ""
}

# =============================================================================
# 主函数
# =============================================================================

main() {
    # 设置错误处理
    set_strict_mode

    # 显示横幅
    print_banner

    # 1. 检查系统依赖
    check_dependencies

    # 2. 检测现有配置
    if detect_existing_config; then
        info "配置已存在且有效"

        # 确保目录结构存在
        create_cache_directories

        # 运行诊断（如果用户需要）
        if confirm "是否运行诊断检查?"; then
            run_diagnostics
            auto_fix_common_issues
        fi

        print_success_summary
        return 0
    fi

    # 3. 运行配置向导
    run_configuration_wizard

    # 4. 创建目录结构
    create_cache_directories

    # 5. 验证最终配置
    if ! validate_final_setup; then
        warning "配置验证失败"

        if confirm "是否查看故障排除指南?"; then
            show_troubleshooting_guide
        fi

        if confirm "是否运行自动修复?"; then
            auto_fix_common_issues
            validate_final_setup
        fi
    fi

    # 6. 显示成功摘要
    print_success_summary

    # 记录完成日志
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] 云效环境初始化完成" >> "$LOG_FILE"
}

# =============================================================================
# 脚本入口
# =============================================================================

# 如果直接运行脚本，执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi