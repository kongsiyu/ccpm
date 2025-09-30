#!/bin/bash

# Yunxiao (阿里云云效) MCP Integration Library
# Provides MCP service detection, configuration management, and base integration functions

# Source required libraries
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/error.sh"

# =============================================================================
# MCP Service Detection Functions
# =============================================================================

# Check if Yunxiao MCP service is running and accessible
# Usage: check_yunxiao_mcp_service
# Returns: 0 if service available, 1 if not
check_yunxiao_mcp_service() {
    local service_name="yunxiao"

    # Try to check MCP service through Claude Code's MCP mechanism
    # This is a placeholder for the actual MCP check
    # TODO: Implement actual MCP service check when Claude Code MCP interface is known

    # For now, check if the MCP configuration is likely present in Claude Code
    if command -v npx >/dev/null 2>&1; then
        # Check if the MCP server package is available
        if npx --yes alibabacloud-devops-mcp-server --help >/dev/null 2>&1; then
            return 0
        else
            log_yunxiao_error "云效MCP服务包不可用，请确保安装了 alibabacloud-devops-mcp-server"
            return 1
        fi
    else
        log_yunxiao_error "npx 命令不可用，请安装 Node.js"
        return 1
    fi
}

# Validate Yunxiao MCP service availability with detailed diagnostics
# Usage: validate_yunxiao_mcp_service
# Returns: 0 if valid, exits with error if not
validate_yunxiao_mcp_service() {
    if check_yunxiao_mcp_service; then
        success "云效MCP服务运行正常"
        return 0
    else
        error_exit "云效MCP服务不可用。请参考配置指南配置Claude Code的MCP服务器。"
    fi
}

# =============================================================================
# Configuration Management Functions
# =============================================================================

# Get project ID from configuration file
# Usage: get_project_id
# Returns: Project ID string or empty if not found
get_project_id() {
    local config_file=".ccpm-config.yaml"

    if [ ! -f "$config_file" ]; then
        echo ""
        return 1
    fi

    # Extract project_id using grep and awk for better parsing
    local project_id
    project_id=$(grep "^project_id:" "$config_file" | awk '{print $2}' | tr -d '"' | tr -d "'")

    if [ -n "$project_id" ]; then
        echo "$project_id"
        return 0
    else
        echo ""
        return 1
    fi
}

# Get platform configuration
# Usage: get_platform_config
# Returns: Platform string or empty if not found
get_platform_config() {
    local config_file=".ccpm-config.yaml"

    if [ ! -f "$config_file" ]; then
        echo ""
        return 1
    fi

    local platform
    platform=$(grep "^platform:" "$config_file" | awk '{print $2}' | tr -d '"' | tr -d "'")

    if [ -n "$platform" ]; then
        echo "$platform"
        return 0
    else
        echo ""
        return 1
    fi
}

# Validate Yunxiao configuration file
# Usage: validate_yunxiao_config
# Returns: 0 if valid, 1 if invalid
validate_yunxiao_config() {
    local config_file=".ccpm-config.yaml"
    local validation_errors=0

    # Check if configuration file exists
    if [ ! -f "$config_file" ]; then
        log_yunxiao_error "配置文件不存在: $config_file"
        info "请创建配置文件并设置 platform: yunxiao 和 project_id"
        return 1
    fi

    # Validate platform setting
    local platform
    platform=$(get_platform_config)
    if [ "$platform" != "yunxiao" ]; then
        log_yunxiao_error "平台配置错误，当前值: '$platform'，应为: 'yunxiao'"
        validation_errors=1
    fi

    # Validate project_id
    local project_id
    project_id=$(get_project_id)
    if [ -z "$project_id" ]; then
        log_yunxiao_error "缺少project_id配置"
        validation_errors=1
    else
        # Validate project_id format (should be numeric)
        if ! [[ "$project_id" =~ ^[0-9]+$ ]]; then
            log_yunxiao_error "project_id格式错误，应为数字: '$project_id'"
            validation_errors=1
        fi
    fi

    if [ $validation_errors -eq 0 ]; then
        success "云效配置验证通过"
        info "Platform: $platform, Project ID: $project_id"

        # Also check MCP service
        check_yunxiao_mcp_service
        return $?
    else
        return 1
    fi
}

# Create or update Yunxiao configuration
# Usage: create_yunxiao_config "project_id"
# Returns: 0 on success, 1 on failure
create_yunxiao_config() {
    local project_id="$1"
    local config_file=".ccpm-config.yaml"

    if [ -z "$project_id" ]; then
        error_exit "Project ID is required"
    fi

    # Validate project_id format
    if ! [[ "$project_id" =~ ^[0-9]+$ ]]; then
        error_exit "Project ID must be numeric: '$project_id'"
    fi

    # Create configuration content
    local config_content="platform: yunxiao
project_id: $project_id"

    # Write configuration file
    echo "$config_content" > "$config_file"

    if [ $? -eq 0 ]; then
        success "云效配置文件已创建: $config_file"
        return 0
    else
        error_exit "创建配置文件失败: $config_file"
    fi
}

# =============================================================================
# MCP Communication Functions
# =============================================================================

# Base MCP call function for Yunxiao operations
# Usage: yunxiao_call_mcp "action" [additional_args...]
# Returns: 0 on success, 1 on failure
yunxiao_call_mcp() {
    local action="$1"
    shift # Remove action from arguments
    local additional_args=("$@")

    if [ -z "$action" ]; then
        log_yunxiao_error "MCP调用需要指定操作类型"
        return 1
    fi

    # Get project ID from configuration
    local project_id
    project_id=$(get_project_id)
    if [ -z "$project_id" ]; then
        log_yunxiao_error "无法获取project_id，请检查配置文件"
        return 1
    fi

    # Validate MCP service is available
    if ! check_yunxiao_mcp_service; then
        log_yunxiao_error "MCP服务不可用，无法执行操作: $action"
        return 1
    fi

    # TODO: Implement actual MCP call when Claude Code MCP interface is available
    # For now, this is a placeholder that logs the call
    log_yunxiao_debug "MCP调用: action=$action, project_id=$project_id, args=${additional_args[*]}"

    # Placeholder: simulate successful call for basic actions
    case "$action" in
        "health_check")
            log_yunxiao_debug "执行健康检查"
            return 0
            ;;
        "list_work_items")
            log_yunxiao_debug "获取工作项列表"
            return 0
            ;;
        *)
            log_yunxiao_debug "执行操作: $action"
            return 0
            ;;
    esac
}

# Health check for Yunxiao MCP service
# Usage: yunxiao_health_check
# Returns: 0 if healthy, 1 if not
yunxiao_health_check() {
    yunxiao_call_mcp "health_check"
}

# =============================================================================
# Error Handling and Logging Functions
# =============================================================================

# Log Yunxiao-specific error messages
# Usage: log_yunxiao_error "error message"
log_yunxiao_error() {
    local message="$1"
    echo "❌ [云效] $message" >&2
}

# Log Yunxiao-specific warning messages
# Usage: log_yunxiao_warning "warning message"
log_yunxiao_warning() {
    local message="$1"
    echo "⚠️  [云效] $message" >&2
}

# Log Yunxiao-specific info messages
# Usage: log_yunxiao_info "info message"
log_yunxiao_info() {
    local message="$1"
    echo "ℹ️  [云效] $message" >&2
}

# Log Yunxiao-specific debug messages (only if debug mode enabled)
# Usage: log_yunxiao_debug "debug message"
log_yunxiao_debug() {
    local message="$1"

    # Only log debug messages if YUNXIAO_DEBUG is set
    if [ -n "$YUNXIAO_DEBUG" ]; then
        echo "🔍 [云效调试] $message" >&2
    fi
}

# Log Yunxiao-specific success messages
# Usage: log_yunxiao_success "success message"
log_yunxiao_success() {
    local message="$1"
    echo "✅ [云效] $message" >&2
}

# =============================================================================
# Utility Functions
# =============================================================================

# Check if we're in a valid project directory with Yunxiao configuration
# Usage: require_yunxiao_project
# Returns: 0 if valid, exits if not
require_yunxiao_project() {
    if ! validate_yunxiao_config; then
        error_exit "当前目录不是有效的云效项目，或配置文件有误"
    fi
}

# Display Yunxiao configuration information
# Usage: show_yunxiao_config
show_yunxiao_config() {
    local config_file=".ccpm-config.yaml"

    if [ ! -f "$config_file" ]; then
        warning "配置文件不存在: $config_file"
        return 1
    fi

    echo "=== 云效配置信息 ==="
    echo "配置文件: $config_file"

    local platform
    platform=$(get_platform_config)
    echo "平台: ${platform:-未设置}"

    local project_id
    project_id=$(get_project_id)
    echo "项目ID: ${project_id:-未设置}"

    echo ""
    echo "=== MCP服务状态 ==="
    if check_yunxiao_mcp_service; then
        log_yunxiao_success "MCP服务可用"
    else
        log_yunxiao_error "MCP服务不可用"
    fi

    echo ""
}

# Show setup instructions for Yunxiao MCP configuration
# Usage: show_yunxiao_setup_guide
show_yunxiao_setup_guide() {
    echo "=== 云效MCP配置指南 ==="
    echo ""
    echo "1. 安装MCP服务器包:"
    echo "   npm install -g alibabacloud-devops-mcp-server"
    echo ""
    echo "2. 在Claude Code中配置MCP服务器 (settings.json):"
    echo '   {'
    echo '     "mcpServers": {'
    echo '       "yunxiao": {'
    echo '         "command": "npx",'
    echo '         "args": ["-y", "alibabacloud-devops-mcp-server"],'
    echo '         "env": {'
    echo '           "YUNXIAO_ACCESS_TOKEN": "<您的云效访问令牌>"'
    echo '         }'
    echo '       }'
    echo '     }'
    echo '   }'
    echo ""
    echo "3. 创建项目配置文件 .ccpm-config.yaml:"
    echo "   platform: yunxiao"
    echo "   project_id: <您的项目ID>"
    echo ""
    echo "4. 验证配置:"
    echo "   source .claude/lib/yunxiao.sh && validate_yunxiao_config"
    echo ""
}