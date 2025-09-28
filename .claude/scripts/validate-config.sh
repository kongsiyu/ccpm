#!/bin/bash
# CCPM 配置验证脚本
# CCPM Configuration Validation Script
#
# 此脚本用于验证 CCPM 配置文件的完整性和正确性

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置文件路径
YAML_CONFIG=".claude/ccpm.yaml"
BASH_CONFIG=".claude/ccpm.config"
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

# 检查依赖工具
check_dependencies() {
    log_info "检查系统依赖..."

    local missing_deps=()

    # 检查 yq (YAML 处理器)
    if ! command -v yq >/dev/null 2>&1; then
        missing_deps+=("yq")
        log_warning "yq 未安装 - YAML 配置验证将受限"
    fi

    # 检查 curl (网络连接测试)
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
        log_warning "curl 未安装 - 网络连接测试将跳过"
    fi

    # 检查 gh CLI (GitHub 操作)
    if ! command -v gh >/dev/null 2>&1; then
        missing_deps+=("gh")
        log_warning "GitHub CLI 未安装 - GitHub 平台验证将跳过"
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_warning "缺少依赖工具: ${missing_deps[*]}"
        log_info "建议安装方法:"
        for dep in "${missing_deps[@]}"; do
            case "$dep" in
                "yq")
                    echo "  yq: https://github.com/mikefarah/yq#install"
                    ;;
                "curl")
                    echo "  curl: 通常已预装，或通过包管理器安装"
                    ;;
                "gh")
                    echo "  GitHub CLI: https://cli.github.com/"
                    ;;
            esac
        done
        echo ""
    else
        log_success "所有依赖工具已安装"
    fi

    return 0
}

# 验证 YAML 配置文件
validate_yaml_config() {
    local config_file="$1"

    log_info "验证 YAML 配置文件: $config_file"

    # 检查文件存在性
    if [ ! -f "$config_file" ]; then
        log_warning "YAML 配置文件不存在: $config_file"
        return 1
    fi

    # 检查 yq 可用性
    if ! command -v yq >/dev/null 2>&1; then
        log_error "无法验证 YAML 配置：yq 工具未安装"
        return 1
    fi

    # 验证 YAML 语法
    if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
        log_error "YAML 语法错误: $config_file"
        return 1
    fi

    # 验证必需字段
    local platform_type
    platform_type=$(yq eval '.platform.type' "$config_file" 2>/dev/null || echo "null")

    if [ -z "$platform_type" ] || [ "$platform_type" = "null" ]; then
        log_error "缺少必需配置: platform.type"
        return 1
    fi

    log_success "YAML 语法验证通过"

    # 平台特定验证
    case "$platform_type" in
        "yunxiao")
            validate_yunxiao_config "$config_file"
            ;;
        "github")
            validate_github_config "$config_file"
            ;;
        *)
            log_error "不支持的平台类型: $platform_type"
            log_info "支持的平台: github, yunxiao"
            return 1
            ;;
    esac

    log_success "YAML 配置验证完成"
    return 0
}

# 验证云效平台配置
validate_yunxiao_config() {
    local config_file="$1"

    log_info "验证云效平台配置..."

    # 检查项目ID
    local project_id
    project_id=$(yq eval '.platform.project_id' "$config_file" 2>/dev/null || echo "null")

    if [ -z "$project_id" ] || [ "$project_id" = "null" ] || [ "$project_id" = "your-project-id" ]; then
        log_error "云效平台需要配置有效的 platform.project_id"
        log_info "请在配置文件中设置实际的云效项目 ID"
        return 1
    fi

    log_success "项目ID验证通过: $project_id"

    # 检查访问令牌环境变量
    local token_env
    token_env=$(yq eval '.platform.yunxiao.token_env' "$config_file" 2>/dev/null || echo "YUNXIAO_ACCESS_TOKEN")

    if [ -z "${!token_env:-}" ]; then
        log_error "缺少环境变量: $token_env"
        log_info "请设置云效访问令牌: export $token_env='your-token'"
        return 1
    fi

    log_success "访问令牌环境变量验证通过"

    # 测试网络连接（可选）
    if command -v curl >/dev/null 2>&1; then
        log_info "测试云效平台连接..."

        local base_url
        base_url=$(yq eval '.platform.yunxiao.api.base_url' "$config_file" 2>/dev/null || echo "https://devops.aliyun.com")

        if curl -s --max-time 5 "$base_url" >/dev/null 2>&1; then
            log_success "云效平台网络连接正常"
        else
            log_warning "无法连接到云效平台，请检查网络"
        fi

        # 测试API访问
        local api_url="${base_url}/api/v4/projects/${project_id}"
        local auth_header="Authorization: Bearer ${!token_env}"

        if curl -s --max-time 10 -H "$auth_header" "$api_url" >/dev/null 2>&1; then
            log_success "云效 API 访问验证通过"
        else
            log_warning "云效 API 访问失败，请检查项目ID和访问令牌"
        fi
    fi

    return 0
}

# 验证 GitHub 平台配置
validate_github_config() {
    local config_file="$1"

    log_info "验证 GitHub 平台配置..."

    # 检查 GitHub CLI 认证
    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            log_success "GitHub CLI 认证验证通过"
        else
            log_warning "GitHub CLI 未认证，请运行: gh auth login"
        fi
    fi

    # 检查 git remote 配置
    if git remote get-url origin >/dev/null 2>&1; then
        local remote_url
        remote_url=$(git remote get-url origin)
        log_success "Git remote 配置正常: $remote_url"

        # 验证仓库访问权限（如果 gh CLI 可用）
        if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
            local repo_name
            repo_name=$(echo "$remote_url" | sed -E 's#^https://github\.com/##' | sed -E 's#^git@github\.com:##' | sed 's#\.git$##')

            if gh repo view "$repo_name" >/dev/null 2>&1; then
                log_success "GitHub 仓库访问权限验证通过: $repo_name"
            else
                log_warning "无法访问 GitHub 仓库: $repo_name"
            fi
        fi
    else
        log_warning "未配置 git remote origin"
    fi

    return 0
}

# 验证 Bash 配置文件
validate_bash_config() {
    local config_file="$1"

    log_info "验证 Bash 配置文件: $config_file"

    if [ ! -f "$config_file" ]; then
        log_warning "Bash 配置文件不存在: $config_file"
        return 1
    fi

    # 检查配置文件语法
    if bash -n "$config_file" 2>/dev/null; then
        log_success "Bash 配置语法验证通过"
    else
        log_error "Bash 配置语法错误: $config_file"
        return 1
    fi

    # 检查关键变量定义
    if grep -q "GITHUB_REPO" "$config_file"; then
        log_success "发现 GitHub 仓库配置"
    else
        log_warning "未发现 GitHub 仓库配置变量"
    fi

    return 0
}

# 验证规则文件完整性
validate_rule_files() {
    log_info "验证规则文件完整性..."

    local rules_dir=".claude/rules"
    local required_files=(
        "platform-config.md"
        "platform-yunxiao-sync.md"
    )

    for rule_file in "${required_files[@]}"; do
        local file_path="$rules_dir/$rule_file"
        if [ -f "$file_path" ]; then
            log_success "规则文件存在: $rule_file"
        else
            log_warning "规则文件缺失: $rule_file"
        fi
    done

    return 0
}

# 生成配置报告
generate_config_report() {
    log_info "生成配置报告..."

    echo ""
    echo "=========================================="
    echo "           CCPM 配置验证报告"
    echo "=========================================="
    echo "时间: $(date)"
    echo "项目路径: $PROJECT_ROOT"
    echo ""

    # 配置文件状态
    echo "配置文件状态:"
    if [ -f "$YAML_CONFIG" ]; then
        echo "  ✅ YAML 配置: $YAML_CONFIG"
        if command -v yq >/dev/null 2>&1; then
            local platform_type
            platform_type=$(yq eval '.platform.type' "$YAML_CONFIG" 2>/dev/null || echo "unknown")
            echo "     平台类型: $platform_type"
        fi
    else
        echo "  ❌ YAML 配置: 不存在"
    fi

    if [ -f "$BASH_CONFIG" ]; then
        echo "  ✅ Bash 配置: $BASH_CONFIG"
    else
        echo "  ❌ Bash 配置: 不存在"
    fi

    echo ""

    # 依赖工具状态
    echo "依赖工具状态:"
    local tools=("yq" "curl" "gh" "git")
    for tool in "${tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "  ✅ $tool: 已安装"
        else
            echo "  ❌ $tool: 未安装"
        fi
    done

    echo ""
    echo "=========================================="
}

# 主验证流程
main() {
    echo "CCPM 配置验证脚本"
    echo "Version: 1.0.0"
    echo ""

    # 切换到项目根目录
    cd "$PROJECT_ROOT"

    # 验证流程
    local validation_passed=true

    # 1. 检查依赖
    check_dependencies

    # 2. 验证 YAML 配置
    if [ -f "$YAML_CONFIG" ]; then
        if ! validate_yaml_config "$YAML_CONFIG"; then
            validation_passed=false
        fi
    else
        log_info "YAML 配置文件不存在，跳过验证"
    fi

    # 3. 验证 Bash 配置
    if [ -f "$BASH_CONFIG" ]; then
        if ! validate_bash_config "$BASH_CONFIG"; then
            validation_passed=false
        fi
    else
        log_info "Bash 配置文件不存在，跳过验证"
    fi

    # 4. 验证规则文件
    validate_rule_files

    # 5. 生成报告
    generate_config_report

    # 总结
    if [ "$validation_passed" = "true" ]; then
        log_success "配置验证通过！"
        exit 0
    else
        log_error "配置验证失败，请检查上述错误信息"
        exit 1
    fi
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi