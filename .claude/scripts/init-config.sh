#!/bin/bash
# CCPM 配置初始化脚本
# CCPM Configuration Initialization Script
#
# 此脚本用于快速初始化 CCPM 配置文件

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
YAML_CONFIG=".claude/ccpm.yaml"
TEMPLATES_DIR=".claude/templates"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 日志函数
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

# 显示欢迎信息
show_welcome() {
    echo ""
    echo "=========================================="
    echo "         CCPM 配置初始化向导"
    echo "=========================================="
    echo ""
    echo "此向导将帮助您配置 CCPM 项目管理工具。"
    echo "支持的平台："
    echo "  1. GitHub Issues & Projects"
    echo "  2. 阿里云云效工作项"
    echo ""
}

# 检查现有配置
check_existing_config() {
    if [ -f "$YAML_CONFIG" ]; then
        log_warning "发现现有配置文件: $YAML_CONFIG"
        echo ""
        read -p "是否要覆盖现有配置？(y/N): " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "保留现有配置，退出初始化"
            exit 0
        fi
    fi
}

# 平台选择
select_platform() {
    echo ""
    echo "请选择项目管理平台："
    echo "  1) GitHub (默认)"
    echo "  2) 阿里云云效"
    echo ""
    read -p "请输入选择 (1-2，默认为1): " -r platform_choice

    case "${platform_choice:-1}" in
        1)
            PLATFORM_TYPE="github"
            log_info "已选择 GitHub 平台"
            ;;
        2)
            PLATFORM_TYPE="yunxiao"
            log_info "已选择阿里云云效平台"
            ;;
        *)
            log_error "无效选择，使用默认 GitHub 平台"
            PLATFORM_TYPE="github"
            ;;
    esac
}

# 配置 GitHub 平台
configure_github() {
    log_info "配置 GitHub 平台设置..."

    # 检查 git remote
    if git remote get-url origin >/dev/null 2>&1; then
        local remote_url
        remote_url=$(git remote get-url origin)
        log_success "自动检测到 Git 仓库: $remote_url"
    else
        log_warning "未检测到 Git 仓库，请确保在 Git 项目目录中运行"
    fi

    # 检查 GitHub CLI
    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            log_success "GitHub CLI 已认证"
        else
            log_warning "GitHub CLI 未认证"
            echo "建议运行: gh auth login"
        fi
    else
        log_warning "GitHub CLI 未安装"
        echo "建议安装: https://cli.github.com/"
    fi

    # 复制 GitHub 模板
    if [ -f "$TEMPLATES_DIR/ccpm-github.yaml" ]; then
        cp "$TEMPLATES_DIR/ccpm-github.yaml" "$YAML_CONFIG"
        log_success "已创建 GitHub 配置文件"
    else
        log_error "GitHub 配置模板不存在: $TEMPLATES_DIR/ccpm-github.yaml"
        return 1
    fi
}

# 配置云效平台
configure_yunxiao() {
    log_info "配置阿里云云效平台设置..."

    # 获取项目ID
    echo ""
    read -p "请输入云效项目 ID: " -r project_id

    if [ -z "$project_id" ]; then
        log_error "项目 ID 不能为空"
        return 1
    fi

    # 检查访问令牌
    if [ -z "${YUNXIAO_ACCESS_TOKEN:-}" ]; then
        log_warning "未设置云效访问令牌环境变量"
        echo ""
        echo "请设置访问令牌:"
        echo "  export YUNXIAO_ACCESS_TOKEN='your-access-token'"
        echo ""
        read -p "是否现在输入访问令牌？(y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            read -s -p "请输入访问令牌: " access_token
            echo ""
            export YUNXIAO_ACCESS_TOKEN="$access_token"
            log_info "访问令牌已设置（当前会话有效）"
        fi
    else
        log_success "检测到云效访问令牌"
    fi

    # 复制云效模板并配置项目ID
    if [ -f "$TEMPLATES_DIR/ccpm-yunxiao.yaml" ]; then
        cp "$TEMPLATES_DIR/ccpm-yunxiao.yaml" "$YAML_CONFIG"

        # 替换项目ID
        if command -v yq >/dev/null 2>&1; then
            yq eval ".platform.project_id = \"$project_id\"" -i "$YAML_CONFIG"
            log_success "已创建云效配置文件，项目ID: $project_id"
        else
            log_warning "yq 未安装，请手动编辑配置文件中的项目 ID"
            log_info "将 'your-project-id' 替换为: $project_id"
        fi
    else
        log_error "云效配置模板不存在: $TEMPLATES_DIR/ccpm-yunxiao.yaml"
        return 1
    fi

    # 测试连接
    if [ -n "${YUNXIAO_ACCESS_TOKEN:-}" ] && command -v curl >/dev/null 2>&1; then
        log_info "测试云效平台连接..."
        local api_url="https://devops.aliyun.com/api/v4/projects/$project_id"

        if curl -s --max-time 10 -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" "$api_url" >/dev/null 2>&1; then
            log_success "云效平台连接测试成功"
        else
            log_warning "云效平台连接测试失败，请检查项目ID和访问令牌"
        fi
    fi
}

# 验证配置
validate_config() {
    log_info "验证配置文件..."

    if [ -f ".claude/scripts/validate-config.sh" ]; then
        if bash ".claude/scripts/validate-config.sh"; then
            log_success "配置验证通过"
        else
            log_warning "配置验证发现问题，请检查配置"
        fi
    else
        log_warning "配置验证脚本不存在，跳过验证"
    fi
}

# 显示完成信息
show_completion() {
    echo ""
    echo "=========================================="
    echo "           配置初始化完成"
    echo "=========================================="
    echo ""
    echo "配置文件位置: $YAML_CONFIG"
    echo "平台类型: $PLATFORM_TYPE"
    echo ""
    echo "下一步操作："
    case "$PLATFORM_TYPE" in
        "github")
            echo "1. 确保 GitHub CLI 已认证: gh auth login"
            echo "2. 测试同步功能: /pm:sync"
            ;;
        "yunxiao")
            echo "1. 设置访问令牌环境变量:"
            echo "   export YUNXIAO_ACCESS_TOKEN='your-token'"
            echo "2. 测试连接: bash .claude/scripts/validate-config.sh"
            echo "3. 测试同步功能: /pm:sync"
            ;;
    esac
    echo ""
    echo "帮助文档:"
    echo "- 平台配置规则: .claude/rules/platform-config.md"
    echo "- 配置验证: bash .claude/scripts/validate-config.sh"
    echo ""
}

# 主初始化流程
main() {
    # 切换到项目根目录
    cd "$PROJECT_ROOT"

    # 显示欢迎信息
    show_welcome

    # 检查现有配置
    check_existing_config

    # 平台选择
    select_platform

    # 平台特定配置
    case "$PLATFORM_TYPE" in
        "github")
            configure_github
            ;;
        "yunxiao")
            configure_yunxiao
            ;;
    esac

    # 验证配置
    validate_config

    # 显示完成信息
    show_completion
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi