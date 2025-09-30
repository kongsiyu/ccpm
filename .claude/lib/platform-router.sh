#!/bin/bash
#
# 平台路由器 - 统一命令路由和平台检测
# 根据配置文件自动检测平台类型，并将命令路由到对应的实现脚本
#

# 获取当前脚本目录，确保路径解析正确
ROUTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$(dirname "$ROUTER_DIR")"

# 导入错误处理库
source "$CLAUDE_DIR/lib/error.sh"

#
# 平台检测函数
# 读取 .ccpm-config.yaml 文件确定目标平台
#
get_platform_type() {
    local config_file=".ccpm-config.yaml"

    # 如果配置文件不存在，默认使用GitHub
    if [[ ! -f "$config_file" ]]; then
        echo "github"
        return 0
    fi

    # 解析配置文件中的platform字段
    local platform=$(grep "^platform:" "$config_file" 2>/dev/null | awk '{print $2}' | tr -d ' \t\r\n')

    # 验证平台类型有效性
    case "$platform" in
        "yunxiao"|"github")
            echo "$platform"
            ;;
        "")
            # 配置文件存在但没有platform字段，默认GitHub
            echo "github"
            ;;
        *)
            # 无效的平台类型，默认GitHub并给出警告
            echo "警告: 不支持的平台类型 '$platform'，使用默认的 github 平台" >&2
            echo "github"
            ;;
    esac
}

#
# 获取云效项目ID（仅云效平台需要）
#
get_project_id() {
    local config_file=".ccpm-config.yaml"

    if [[ ! -f "$config_file" ]]; then
        return 1
    fi

    local project_id=$(grep "^project_id:" "$config_file" 2>/dev/null | awk '{print $2}' | tr -d ' \t\r\n')
    echo "$project_id"
}

#
# 验证平台配置
#
validate_platform_config() {
    local platform=$(get_platform_type)

    case "$platform" in
        "yunxiao")
            validate_yunxiao_config
            ;;
        "github")
            validate_github_config
            ;;
        *)
            error "不支持的平台类型: $platform"
            return 1
            ;;
    esac
}

#
# 验证云效平台配置
#
validate_yunxiao_config() {
    local project_id=$(get_project_id)

    if [[ -z "$project_id" ]]; then
        error "云效平台需要配置 project_id"
        error "请在 .ccpm-config.yaml 中添加："
        error "platform: yunxiao"
        error "project_id: <你的项目ID>"
        return 1
    fi

    # TODO: 后续可以添加MCP连接测试
    # if ! yunxiao_test_connection; then
    #     error "无法连接到云效MCP服务，请检查MCP服务器配置"
    #     return 1
    # fi

    return 0
}

#
# 验证GitHub平台配置
#
validate_github_config() {
    if ! command -v gh &> /dev/null; then
        error "GitHub CLI (gh) 未安装"
        error "请访问 https://cli.github.com/ 安装GitHub CLI"
        return 1
    fi

    if ! gh auth status &> /dev/null; then
        error "GitHub CLI 未认证，请运行 'gh auth login'"
        return 1
    fi

    return 0
}

#
# 统一命令路由函数
# 根据平台类型将命令路由到对应的脚本实现
#
route_pm_command() {
    local cmd_name="$1"
    shift

    # 获取平台类型
    local platform=$(get_platform_type)

    # 验证平台配置
    if ! validate_platform_config; then
        exit 1
    fi

    # 根据命令和平台进行路由
    case "$cmd_name" in
        "epic-sync")
            case "$platform" in
                "yunxiao")
                    exec bash "$CLAUDE_DIR/scripts/pm/epic-sync-yunxiao/sync-main.sh" "$@"
                    ;;
                "github")
                    # GitHub epic-sync 有多个脚本，使用主要的同步脚本
                    if [[ -f "$CLAUDE_DIR/scripts/pm/epic-sync/sync-github-issues.sh" ]]; then
                        exec bash "$CLAUDE_DIR/scripts/pm/epic-sync/sync-github-issues.sh" "$@"
                    else
                        error "GitHub epic-sync 脚本不存在"
                        exit 1
                    fi
                    ;;
                *)
                    error "不支持的平台类型: $platform"
                    exit 1
                    ;;
            esac
            ;;
        "issue-sync")
            case "$platform" in
                "yunxiao")
                    exec bash "$CLAUDE_DIR/scripts/pm/issue-sync-yunxiao/sync-main.sh" "$@"
                    ;;
                "github")
                    # GitHub issue-sync 有多个脚本，需要确定主入口
                    if [[ -f "$CLAUDE_DIR/scripts/pm/issue-sync/preflight-validation.sh" ]]; then
                        exec bash "$CLAUDE_DIR/scripts/pm/issue-sync/preflight-validation.sh" "$@"
                    else
                        error "GitHub issue-sync 脚本不存在"
                        exit 1
                    fi
                    ;;
                *)
                    error "不支持的平台类型: $platform"
                    exit 1
                    ;;
            esac
            ;;
        "init")
            case "$platform" in
                "yunxiao")
                    exec bash "$CLAUDE_DIR/scripts/pm/init-yunxiao.sh" "$@"
                    ;;
                "github")
                    exec bash "$CLAUDE_DIR/scripts/pm/init.sh" "$@"
                    ;;
                *)
                    error "不支持的平台类型: $platform"
                    exit 1
                    ;;
            esac
            ;;
        *)
            error "不支持的命令: $cmd_name"
            error "支持的命令: epic-sync, issue-sync, init"
            exit 1
            ;;
    esac
}

#
# 显示平台状态信息
#
show_platform_status() {
    local platform=$(get_platform_type)
    echo "当前平台: $platform"

    case "$platform" in
        "yunxiao")
            show_yunxiao_status
            ;;
        "github")
            show_github_status
            ;;
        *)
            error "不支持的平台类型: $platform"
            return 1
            ;;
    esac
}

#
# 显示云效平台状态
#
show_yunxiao_status() {
    local project_id=$(get_project_id)

    echo "云效配置:"
    if [[ -n "$project_id" ]]; then
        echo "  项目ID: $project_id"
    else
        echo "  项目ID: 未配置"
    fi

    # TODO: 添加MCP连接状态检查
    echo "  MCP连接: 待检查"
}

#
# 显示GitHub平台状态
#
show_github_status() {
    echo "GitHub配置:"

    if command -v gh &> /dev/null; then
        echo "  GitHub CLI: 已安装"
        if gh auth status &> /dev/null; then
            local user=$(gh api user --jq '.login' 2>/dev/null)
            echo "  认证状态: 已认证 (用户: $user)"
        else
            echo "  认证状态: 未认证"
        fi
    else
        echo "  GitHub CLI: 未安装"
    fi

    # 显示当前仓库信息
    if git rev-parse --is-inside-work-tree &> /dev/null; then
        local repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)
        if [[ -n "$repo" ]]; then
            echo "  当前仓库: $repo"
        fi
    fi
}