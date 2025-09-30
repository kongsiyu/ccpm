#!/bin/bash

# 平台检测库 - 统一的平台检测和配置管理
# 支持GitHub和云效(Yunxiao)两种平台的自动检测和路由

# Source required libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/error.sh"
source "$SCRIPT_DIR/yunxiao.sh"

# =============================================================================
# 平台检测核心函数
# =============================================================================

# 获取平台类型
# Usage: get_platform_type
# Returns: "github" | "yunxiao" (默认返回github)
get_platform_type() {
    local config_file=".ccpm-config.yaml"

    # 如果配置文件不存在，默认使用GitHub
    if [[ ! -f "$config_file" ]]; then
        echo "github"
        return 0
    fi

    # 从配置文件中读取平台配置
    local platform=$(grep "^platform:" "$config_file" | cut -d':' -f2 | xargs)

    # 验证平台类型并返回
    case "$platform" in
        "yunxiao"|"github")
            echo "$platform"
            ;;
        *)
            # 无效配置默认GitHub
            echo "github"
            ;;
    esac
}

# 获取项目ID (主要用于云效平台)
# Usage: get_project_id
# Returns: project_id string or empty if not found
get_project_id() {
    local config_file=".ccpm-config.yaml"

    if [[ ! -f "$config_file" ]]; then
        echo ""
        return 1
    fi

    # 从yunxiao.sh库中获取project_id
    get_project_id_from_config() {
        local project_id
        project_id=$(grep "^project_id:" "$config_file" | awk '{print $2}' | tr -d '"' | tr -d "'")

        if [[ -n "$project_id" ]]; then
            echo "$project_id"
            return 0
        else
            echo ""
            return 1
        fi
    }

    get_project_id_from_config
}

# =============================================================================
# 平台配置验证函数
# =============================================================================

# 验证平台配置
# Usage: validate_platform_config
# Returns: 0 if valid, 1 if invalid
validate_platform_config() {
    local platform=$(get_platform_type)

    case "$platform" in
        "yunxiao")
            validate_yunxiao_platform_config
            ;;
        "github")
            validate_github_platform_config
            ;;
        *)
            error "不支持的平台类型: $platform"
            return 1
            ;;
    esac
}

# 验证云效平台配置
# Usage: validate_yunxiao_platform_config
# Returns: 0 if valid, 1 if invalid
validate_yunxiao_platform_config() {
    local project_id=$(get_project_id)

    if [[ -z "$project_id" ]]; then
        error "云效平台需要配置project_id"
        info "请在 .ccpm-config.yaml 中添加: project_id: <您的项目ID>"
        return 1
    fi

    # 验证project_id格式
    if ! [[ "$project_id" =~ ^[0-9]+$ ]]; then
        error "project_id格式错误，应为数字: '$project_id'"
        return 1
    fi

    # 验证MCP连接
    if ! check_yunxiao_mcp_service; then
        error "无法连接到云效MCP服务，请检查MCP服务器配置"
        info "运行以下命令查看配置指南: source .claude/lib/yunxiao.sh && show_yunxiao_setup_guide"
        return 1
    fi

    success "云效平台配置验证通过 (Project ID: $project_id)"
    return 0
}

# 验证GitHub平台配置
# Usage: validate_github_platform_config
# Returns: 0 if valid, 1 if invalid
validate_github_platform_config() {
    # 检查GitHub CLI是否安装
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) 未安装"
        info "请安装GitHub CLI: https://cli.github.com/"
        return 1
    fi

    # 检查GitHub CLI是否已认证
    if ! gh auth status &> /dev/null; then
        error "GitHub CLI 未认证，请运行 'gh auth login'"
        return 1
    fi

    # 检查是否在git仓库中
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        error "当前目录不是Git仓库"
        return 1
    fi

    # 检查远程仓库配置
    local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
    if [[ -z "$remote_url" ]]; then
        error "未找到远程仓库配置"
        return 1
    fi

    success "GitHub平台配置验证通过"
    return 0
}

# =============================================================================
# 命令路由函数
# =============================================================================

# 执行平台特定的脚本
# Usage: route_to_platform_script "script_base_name" "$@"
# Example: route_to_platform_script "epic-sync" "$@"
route_to_platform_script() {
    local script_base="$1"
    shift # 移除第一个参数，保留其余参数

    local platform=$(get_platform_type)
    local claude_dir="$CLAUDE_DIR"

    # 如果CLAUDE_DIR未设置，尝试自动检测
    if [[ -z "$claude_dir" ]]; then
        if [[ -d ".claude" ]]; then
            claude_dir="$(pwd)/.claude"
        else
            error "无法找到.claude目录，请确保在正确的项目根目录下运行"
            return 1
        fi
    fi

    case "$platform" in
        "yunxiao")
            local yunxiao_script="$claude_dir/scripts/pm/${script_base}-yunxiao.sh"
            if [[ -f "$yunxiao_script" ]]; then
                info "路由到云效平台: $script_base"
                exec "$yunxiao_script" "$@"
            else
                error "云效平台脚本不存在: $yunxiao_script"
                return 1
            fi
            ;;
        "github")
            local github_script="$claude_dir/scripts/pm/${script_base}.sh"
            if [[ -f "$github_script" ]]; then
                info "路由到GitHub平台: $script_base"
                exec "$github_script" "$@"
            else
                error "GitHub平台脚本不存在: $github_script"
                return 1
            fi
            ;;
        *)
            error "不支持的平台类型: $platform"
            return 1
            ;;
    esac
}

# 执行平台特定的目录脚本
# Usage: route_to_platform_script_dir "script_dir_base" "main_script" "$@"
# Example: route_to_platform_script_dir "epic-sync" "sync-main.sh" "$@"
route_to_platform_script_dir() {
    local script_dir_base="$1"
    local main_script="$2"
    shift 2 # 移除前两个参数

    local platform=$(get_platform_type)
    local claude_dir="$CLAUDE_DIR"

    # 如果CLAUDE_DIR未设置，尝试自动检测
    if [[ -z "$claude_dir" ]]; then
        if [[ -d ".claude" ]]; then
            claude_dir="$(pwd)/.claude"
        else
            error "无法找到.claude目录，请确保在正确的项目根目录下运行"
            return 1
        fi
    fi

    case "$platform" in
        "yunxiao")
            local yunxiao_script_dir="$claude_dir/scripts/pm/${script_dir_base}-yunxiao"
            local yunxiao_main_script="$yunxiao_script_dir/$main_script"
            if [[ -f "$yunxiao_main_script" ]]; then
                info "路由到云效平台: $script_dir_base/$main_script"
                exec "$yunxiao_main_script" "$@"
            else
                error "云效平台脚本不存在: $yunxiao_main_script"
                return 1
            fi
            ;;
        "github")
            local github_script_dir="$claude_dir/scripts/pm/${script_dir_base}"
            local github_main_script="$github_script_dir/$main_script"
            if [[ -f "$github_main_script" ]]; then
                info "路由到GitHub平台: $script_dir_base/$main_script"
                exec "$github_main_script" "$@"
            else
                error "GitHub平台脚本不存在: $github_main_script"
                return 1
            fi
            ;;
        *)
            error "不支持的平台类型: $platform"
            return 1
            ;;
    esac
}

# =============================================================================
# 平台诊断函数
# =============================================================================

# 显示当前平台状态
# Usage: show_platform_status
show_platform_status() {
    local platform=$(get_platform_type)
    echo "=== 平台状态检查 ==="
    echo "当前平台: $platform"
    echo ""

    case "$platform" in
        "yunxiao")
            show_yunxiao_platform_status
            ;;
        "github")
            show_github_platform_status
            ;;
        *)
            error "未知的平台类型: $platform"
            ;;
    esac
}

# 显示云效平台状态
# Usage: show_yunxiao_platform_status
show_yunxiao_platform_status() {
    echo "=== 云效平台状态 ==="

    local project_id=$(get_project_id)
    if [[ -n "$project_id" ]]; then
        echo "✅ 项目ID: $project_id"
    else
        echo "❌ 项目ID: 未配置"
    fi

    if check_yunxiao_mcp_service; then
        echo "✅ MCP服务: 可用"
    else
        echo "❌ MCP服务: 不可用"
    fi

    echo ""
    if validate_yunxiao_platform_config; then
        echo "✅ 云效平台配置完整"
    else
        echo "❌ 云效平台配置有误"
        echo ""
        echo "💡 配置修复建议:"
        show_yunxiao_setup_guide
    fi
}

# 显示GitHub平台状态
# Usage: show_github_platform_status
show_github_platform_status() {
    echo "=== GitHub平台状态 ==="

    if command -v gh &> /dev/null; then
        echo "✅ GitHub CLI: 已安装"

        if gh auth status &> /dev/null; then
            local user=$(gh api user --jq .login 2>/dev/null || echo "unknown")
            echo "✅ 认证状态: 已登录 ($user)"
        else
            echo "❌ 认证状态: 未登录"
        fi
    else
        echo "❌ GitHub CLI: 未安装"
    fi

    if git rev-parse --git-dir > /dev/null 2>&1; then
        echo "✅ Git仓库: 已初始化"

        local remote_url=$(git remote get-url origin 2>/dev/null || echo "")
        if [[ -n "$remote_url" ]]; then
            echo "✅ 远程仓库: $remote_url"
        else
            echo "❌ 远程仓库: 未配置"
        fi
    else
        echo "❌ Git仓库: 未初始化"
    fi

    echo ""
    if validate_github_platform_config; then
        echo "✅ GitHub平台配置完整"
    else
        echo "❌ GitHub平台配置有误"
        echo ""
        echo "💡 配置修复建议:"
        echo "1. 安装GitHub CLI: https://cli.github.com/"
        echo "2. 登录GitHub: gh auth login"
        echo "3. 初始化Git仓库: git init && git remote add origin <repo_url>"
    fi
}

# =============================================================================
# 错误处理和默认行为
# =============================================================================

# 处理配置错误的默认行为
# Usage: handle_config_error "error_message"
handle_config_error() {
    local error_message="$1"

    warning "平台配置错误: $error_message"
    warning "将使用默认的GitHub平台"
    info "要修复此问题，请:"
    info "1. 检查 .ccpm-config.yaml 文件"
    info "2. 确保平台设置正确: platform: github 或 platform: yunxiao"
    info "3. 如果使用云效，确保配置了有效的 project_id"
    echo ""
}

# 平台切换指导
# Usage: show_platform_switch_guide "target_platform"
show_platform_switch_guide() {
    local target_platform="$1"

    echo "=== 平台切换指南 ==="
    echo "目标平台: $target_platform"
    echo ""

    case "$target_platform" in
        "yunxiao")
            echo "切换到云效平台:"
            echo "1. 创建或编辑 .ccpm-config.yaml:"
            echo "   platform: yunxiao"
            echo "   project_id: <您的云效项目ID>"
            echo ""
            echo "2. 配置MCP服务器 (参考指南):"
            echo "   source .claude/lib/yunxiao.sh && show_yunxiao_setup_guide"
            ;;
        "github")
            echo "切换到GitHub平台:"
            echo "1. 创建或编辑 .ccpm-config.yaml:"
            echo "   platform: github"
            echo ""
            echo "2. 确保GitHub CLI已安装并认证:"
            echo "   gh auth login"
            ;;
        *)
            error "不支持的目标平台: $target_platform"
            ;;
    esac
    echo ""
}

# =============================================================================
# 工具函数
# =============================================================================

# 检查是否需要平台配置
# Usage: require_platform_config
# Returns: 0 if config exists and valid, exits if not
require_platform_config() {
    if ! validate_platform_config; then
        echo ""
        error "平台配置验证失败"
        show_platform_status
        echo ""
        error_exit "请修复配置问题后重试"
    fi
}

# 智能平台检测和提示
# Usage: smart_platform_detection
smart_platform_detection() {
    local platform=$(get_platform_type)
    local config_file=".ccpm-config.yaml"

    # 如果没有配置文件，提供创建建议
    if [[ ! -f "$config_file" ]]; then
        info "未找到平台配置文件，使用默认GitHub平台"
        info "要使用云效平台，请创建 .ccpm-config.yaml 文件:"
        echo "  platform: yunxiao"
        echo "  project_id: <您的项目ID>"
        echo ""
    fi

    # 验证当前平台配置
    if ! validate_platform_config; then
        warning "当前平台配置有问题，请检查并修复"
        return 1
    fi

    return 0
}