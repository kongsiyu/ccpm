# 云效平台适配器错误处理和故障排除指南

云效平台适配器框架的完整错误处理、故障诊断和恢复指南。

## 概述

此指南提供了云效平台适配器框架中各类错误的识别、处理和恢复机制，包括MCP工具调用失败、网络连接问题、数据同步冲突等常见故障场景。

## 错误分类体系

### 错误级别定义

```yaml
error_levels:
  FATAL:    # 致命错误，操作无法继续
    - 配置文件缺失或格式错误
    - MCP工具不可用
    - 认证完全失败

  ERROR:    # 重要错误，当前操作失败但可重试
    - 网络连接超时
    - API调用失败
    - 数据验证失败

  WARNING:  # 警告，操作部分失败但可继续
    - 字段映射失败
    - 非关键字段缺失
    - 同步延迟

  INFO:     # 信息提示，正常状态
    - 操作成功
    - 状态变更
    - 同步完成
```

### 错误来源分类

```bash
# 错误来源识别函数
identify_error_source() {
  local error_message="$1"
  local error_code="${2:-0}"
  local context="${3:-unknown}"

  case "$context" in
    "mcp_call")
      classify_mcp_error "$error_message" "$error_code"
      ;;
    "network")
      classify_network_error "$error_message" "$error_code"
      ;;
    "data_validation")
      classify_validation_error "$error_message" "$error_code"
      ;;
    "config")
      classify_config_error "$error_message" "$error_code"
      ;;
    "sync")
      classify_sync_error "$error_message" "$error_code"
      ;;
    *)
      echo "UNKNOWN_ERROR"
      ;;
  esac
}

# MCP错误分类
classify_mcp_error() {
  local error_message="$1"
  local error_code="$2"

  if echo "$error_message" | grep -qi "timeout"; then
    echo "MCP_TIMEOUT"
  elif echo "$error_message" | grep -qi "authentication\|unauthorized"; then
    echo "MCP_AUTH_FAILURE"
  elif echo "$error_message" | grep -qi "not found\|404"; then
    echo "MCP_RESOURCE_NOT_FOUND"
  elif echo "$error_message" | grep -qi "rate limit\|too many requests"; then
    echo "MCP_RATE_LIMIT"
  elif echo "$error_message" | grep -qi "invalid parameter\|bad request"; then
    echo "MCP_INVALID_PARAMETER"
  elif echo "$error_message" | grep -qi "server error\|internal error"; then
    echo "MCP_SERVER_ERROR"
  elif echo "$error_message" | grep -qi "connection refused\|connection failed"; then
    echo "MCP_CONNECTION_FAILED"
  else
    echo "MCP_UNKNOWN_ERROR"
  fi
}

# 网络错误分类
classify_network_error() {
  local error_message="$1"

  if echo "$error_message" | grep -qi "dns\|name resolution"; then
    echo "NETWORK_DNS_ERROR"
  elif echo "$error_message" | grep -qi "timeout"; then
    echo "NETWORK_TIMEOUT"
  elif echo "$error_message" | grep -qi "connection refused"; then
    echo "NETWORK_CONNECTION_REFUSED"
  elif echo "$error_message" | grep -qi "ssl\|tls\|certificate"; then
    echo "NETWORK_SSL_ERROR"
  else
    echo "NETWORK_UNKNOWN_ERROR"
  fi
}

# 数据验证错误分类
classify_validation_error() {
  local error_message="$1"

  if echo "$error_message" | grep -qi "missing.*field\|required.*field"; then
    echo "VALIDATION_MISSING_FIELD"
  elif echo "$error_message" | grep -qi "invalid.*format\|format.*error"; then
    echo "VALIDATION_FORMAT_ERROR"
  elif echo "$error_message" | grep -qi "type.*mismatch\|invalid.*type"; then
    echo "VALIDATION_TYPE_ERROR"
  elif echo "$error_message" | grep -qi "length.*exceeded\|too.*long"; then
    echo "VALIDATION_LENGTH_ERROR"
  else
    echo "VALIDATION_UNKNOWN_ERROR"
  fi
}
```

## MCP工具调用错误处理

### MCP连接和认证错误

```bash
# MCP连接诊断和修复
diagnose_mcp_connection() {
  echo "=== MCP连接诊断 ==="

  # 1. 检查MCP工具可用性
  if ! command -v mcp_client >/dev/null 2>&1; then
    echo "❌ MCP客户端工具未安装或不在PATH中"
    echo "解决方案:"
    echo "1. 安装MCP客户端工具"
    echo "2. 确保工具在系统PATH中"
    echo "3. 验证工具权限设置"
    return 1
  fi

  echo "✅ MCP客户端工具已安装"

  # 2. 检查配置文件
  local config_file=".claude/ccpm.config"
  if [ ! -f "$config_file" ]; then
    echo "❌ 配置文件不存在: $config_file"
    echo "解决方案: 运行配置初始化命令"
    return 1
  fi

  echo "✅ 配置文件存在"

  # 3. 验证云效配置
  local platform_type=$(yq eval '.platform.type' "$config_file" 2>/dev/null)
  local project_id=$(yq eval '.platform.project_id' "$config_file" 2>/dev/null)

  if [ "$platform_type" != "yunxiao" ]; then
    echo "⚠️  平台类型不是云效: $platform_type"
    echo "解决方案: 设置 platform.type = 'yunxiao'"
  fi

  if [ -z "$project_id" ] || [ "$project_id" = "null" ]; then
    echo "❌ 云效项目ID未配置"
    echo "解决方案: 设置 platform.project_id"
    return 1
  fi

  echo "✅ 云效配置有效"

  # 4. 检查环境变量
  if [ -z "$YUNXIAO_ACCESS_TOKEN" ]; then
    echo "❌ 云效访问令牌未设置"
    echo "解决方案:"
    echo "1. 设置环境变量: export YUNXIAO_ACCESS_TOKEN='your_token'"
    echo "2. 或在 .env 文件中配置"
    echo "3. 验证令牌有效性和权限"
    return 1
  fi

  echo "✅ 访问令牌已设置"

  # 5. 测试MCP连接
  echo ""
  echo "测试MCP连接..."
  if test_mcp_connectivity "$project_id"; then
    echo "✅ MCP连接测试成功"
    return 0
  else
    echo "❌ MCP连接测试失败"
    return 1
  fi
}

# MCP连接测试
test_mcp_connectivity() {
  local project_id="$1"

  echo "正在测试云效项目连接..."

  # 使用get_project_info进行连接测试
  local result=$(mcp_call "alibabacloud_devops_get_project_info" \
    --project-id "$project_id" 2>&1)

  local exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo "项目信息获取成功"
    echo "项目详情: $result"
    return 0
  else
    echo "项目信息获取失败"
    echo "错误信息: $result"

    # 分析错误原因并提供解决建议
    analyze_mcp_connection_failure "$result"
    return 1
  fi
}

# MCP连接失败分析
analyze_mcp_connection_failure() {
  local error_output="$1"

  echo ""
  echo "=== 错误分析和解决建议 ==="

  if echo "$error_output" | grep -qi "unauthorized\|authentication"; then
    echo "❌ 认证失败"
    echo "可能原因:"
    echo "1. 访问令牌无效或已过期"
    echo "2. 令牌权限不足"
    echo "3. 项目访问权限不够"
    echo ""
    echo "解决方案:"
    echo "1. 重新生成访问令牌"
    echo "2. 检查令牌权限设置"
    echo "3. 确认项目成员身份"

  elif echo "$error_output" | grep -qi "not found\|404"; then
    echo "❌ 项目不存在"
    echo "可能原因:"
    echo "1. 项目ID错误"
    echo "2. 项目已删除或迁移"
    echo "3. 访问权限不足"
    echo ""
    echo "解决方案:"
    echo "1. 验证项目ID是否正确"
    echo "2. 检查项目状态"
    echo "3. 联系项目管理员确认权限"

  elif echo "$error_output" | grep -qi "timeout\|connection"; then
    echo "❌ 网络连接问题"
    echo "可能原因:"
    echo "1. 网络连接不稳定"
    echo "2. 云效服务临时不可用"
    echo "3. 防火墙或代理问题"
    echo ""
    echo "解决方案:"
    echo "1. 检查网络连接"
    echo "2. 稍后重试"
    echo "3. 检查防火墙和代理设置"

  elif echo "$error_output" | grep -qi "rate limit"; then
    echo "❌ API调用频率限制"
    echo "解决方案:"
    echo "1. 等待一段时间后重试"
    echo "2. 减少并发调用数量"
    echo "3. 实施指数退避重试策略"

  else
    echo "❓ 未知错误"
    echo "建议:"
    echo "1. 检查云效服务状态"
    echo "2. 查看详细错误日志"
    echo "3. 联系技术支持"
  fi
}
```

### MCP工具调用重试机制

```bash
# 智能重试机制
mcp_call_with_smart_retry() {
  local tool_name="$1"
  shift
  local tool_args=("$@")

  local max_retries=3
  local base_delay=1
  local max_delay=30
  local attempt=1

  while [ $attempt -le $max_retries ]; do
    echo "MCP调用尝试 $attempt/$max_retries: $tool_name" >&2

    # 执行MCP调用
    local output
    local exit_code
    output=$(mcp_call "$tool_name" "${tool_args[@]}" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
      echo "$output"
      return 0
    fi

    # 分析错误类型，决定是否重试
    local error_type=$(identify_error_source "$output" "$exit_code" "mcp_call")

    case "$error_type" in
      "MCP_AUTH_FAILURE"|"MCP_INVALID_PARAMETER")
        # 认证失败和参数错误不适合重试
        echo "错误: $error_type - 不可重试的错误" >&2
        echo "$output" >&2
        return $exit_code
        ;;
      "MCP_TIMEOUT"|"MCP_CONNECTION_FAILED"|"MCP_SERVER_ERROR")
        # 这些错误适合重试
        if [ $attempt -lt $max_retries ]; then
          local delay=$((base_delay * 2**(attempt-1)))
          [ $delay -gt $max_delay ] && delay=$max_delay

          echo "错误: $error_type - 等待 ${delay}s 后重试..." >&2
          sleep $delay
        fi
        ;;
      "MCP_RATE_LIMIT")
        # 限流错误需要更长等待时间
        if [ $attempt -lt $max_retries ]; then
          local delay=$((base_delay * 3**attempt))
          [ $delay -gt $max_delay ] && delay=$max_delay

          echo "错误: 触发限流 - 等待 ${delay}s 后重试..." >&2
          sleep $delay
        fi
        ;;
      *)
        # 未知错误，保守重试
        if [ $attempt -lt $max_retries ]; then
          echo "错误: $error_type - 等待 ${base_delay}s 后重试..." >&2
          sleep $base_delay
        fi
        ;;
    esac

    ((attempt++))
  done

  echo "错误: MCP调用失败，已达到最大重试次数" >&2
  echo "最后错误: $output" >&2
  return 1
}

# MCP错误恢复策略
recover_from_mcp_error() {
  local error_type="$1"
  local context="$2"
  local failed_operation="$3"

  echo "=== MCP错误恢复 ==="
  echo "错误类型: $error_type"
  echo "上下文: $context"
  echo "失败操作: $failed_operation"

  case "$error_type" in
    "MCP_AUTH_FAILURE")
      echo "执行认证修复流程..."
      repair_mcp_authentication
      ;;
    "MCP_CONNECTION_FAILED")
      echo "执行连接修复流程..."
      repair_mcp_connection
      ;;
    "MCP_RATE_LIMIT")
      echo "执行限流恢复流程..."
      handle_rate_limit_recovery
      ;;
    "MCP_RESOURCE_NOT_FOUND")
      echo "执行资源恢复流程..."
      handle_resource_not_found "$context" "$failed_operation"
      ;;
    *)
      echo "执行通用恢复流程..."
      generic_mcp_recovery "$failed_operation"
      ;;
  esac
}

# 认证修复
repair_mcp_authentication() {
  echo "1. 检查访问令牌..."
  if [ -z "$YUNXIAO_ACCESS_TOKEN" ]; then
    echo "❌ 访问令牌未设置"
    echo "请设置环境变量: export YUNXIAO_ACCESS_TOKEN='your_token'"
    return 1
  fi

  echo "2. 测试令牌有效性..."
  # 使用简单的项目信息查询测试令牌
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  if mcp_call "alibabacloud_devops_get_project_info" --project-id "$project_id" >/dev/null 2>&1; then
    echo "✅ 令牌有效"
    return 0
  else
    echo "❌ 令牌无效或权限不足"
    echo "请检查:"
    echo "- 令牌是否正确"
    echo "- 令牌是否过期"
    echo "- 是否有项目访问权限"
    return 1
  fi
}

# 连接修复
repair_mcp_connection() {
  echo "1. 检查网络连接..."
  if ! ping -c 1 devops.aliyun.com >/dev/null 2>&1; then
    echo "❌ 无法连接到云效服务器"
    echo "请检查网络连接"
    return 1
  fi

  echo "2. 检查MCP服务状态..."
  diagnose_mcp_connection
}

# 限流恢复
handle_rate_limit_recovery() {
  echo "检测到API限流，建议:"
  echo "1. 等待60秒后重试"
  echo "2. 减少并发操作"
  echo "3. 分批处理大量数据"

  echo "等待限流解除..."
  sleep 60
  echo "限流等待完成，可以重试操作"
}

# 资源不存在处理
handle_resource_not_found() {
  local context="$1"
  local failed_operation="$2"

  case "$context" in
    "epic_sync")
      echo "Epic关联的WorkItem不存在，建议:"
      echo "1. 清除Epic的云效关联信息"
      echo "2. 重新创建WorkItem"
      echo "3. 检查WorkItem是否被误删"
      ;;
    "issue_sync")
      echo "Issue关联的WorkItem不存在，建议:"
      echo "1. 移除Issue的同步标签"
      echo "2. 重新执行Issue同步"
      echo "3. 检查WorkItem状态"
      ;;
    *)
      echo "资源不存在，建议重新创建或检查资源状态"
      ;;
  esac
}
```

## 数据同步错误处理

### 数据验证失败处理

```bash
# 数据验证错误修复
fix_data_validation_errors() {
  local data_type="$1"    # epic, issue, workitem
  local data_source="$2"  # 数据来源
  local validation_errors="$3"

  echo "=== 数据验证错误修复 ==="
  echo "数据类型: $data_type"
  echo "数据来源: $data_source"

  case "$data_type" in
    "epic")
      fix_epic_validation_errors "$data_source" "$validation_errors"
      ;;
    "issue")
      fix_issue_validation_errors "$data_source" "$validation_errors"
      ;;
    "workitem")
      fix_workitem_validation_errors "$data_source" "$validation_errors"
      ;;
    *)
      echo "未知数据类型: $data_type"
      return 1
      ;;
  esac
}

# Epic验证错误修复
fix_epic_validation_errors() {
  local epic_file="$1"
  local validation_errors="$2"

  echo "修复Epic验证错误: $epic_file"

  # 解析验证错误
  while IFS= read -r error; do
    if echo "$error" | grep -q "缺少必需字段: title"; then
      echo "修复: 添加默认标题"
      # 添加默认标题
      local basename=$(basename "$epic_file" .md)
      update_epic_frontmatter "$epic_file" --title "Epic: $basename"

    elif echo "$error" | grep -q "无效的状态值"; then
      echo "修复: 重置状态为pending"
      update_epic_frontmatter "$epic_file" --status "pending"

    elif echo "$error" | grep -q "无效的优先级"; then
      echo "修复: 重置优先级为medium"
      update_epic_frontmatter "$epic_file" --priority "medium"

    fi
  done <<< "$validation_errors"

  # 重新验证
  if validate_epic_data "$epic_file"; then
    echo "✅ Epic验证错误已修复"
    return 0
  else
    echo "❌ Epic验证错误修复失败"
    return 1
  fi
}

# Issue验证错误修复
fix_issue_validation_errors() {
  local issue_data="$1"
  local validation_errors="$2"

  echo "Issue数据验证错误无法自动修复"
  echo "建议手动检查Issue数据:"
  echo "$validation_errors"

  # 提供修复建议
  echo ""
  echo "可能的修复方案:"

  if echo "$validation_errors" | grep -q "缺少必需字段: title"; then
    echo "- Issue标题为空，请在GitHub中添加标题"
  fi

  if echo "$validation_errors" | grep -q "缺少必需字段: number"; then
    echo "- Issue编号缺失，请检查API响应"
  fi

  if echo "$validation_errors" | grep -q "无效的状态值"; then
    echo "- Issue状态异常，请检查GitHub Issue状态"
  fi

  return 1  # Issue验证错误需要手动修复
}

# WorkItem验证错误修复
fix_workitem_validation_errors() {
  local workitem_data="$1"
  local validation_errors="$2"

  echo "WorkItem数据验证错误修复建议:"
  echo "$validation_errors"

  # 提供详细的修复指导
  echo ""
  echo "修复指导:"

  if echo "$validation_errors" | grep -q "缺少必需字段: title"; then
    echo "- 确保WorkItem标题不为空"
  fi

  if echo "$validation_errors" | grep -q "缺少必需字段: workitem_type"; then
    echo "- 设置正确的工作项类型（任务/需求/缺陷/子任务）"
  fi

  if echo "$validation_errors" | grep -q "无效的工作项类型"; then
    echo "- 使用有效的工作项类型：任务、需求、缺陷、子任务"
  fi

  if echo "$validation_errors" | grep -q "无效的状态"; then
    echo "- 使用有效的状态：待处理、进行中、待验收、已完成、已关闭"
  fi

  return 1  # WorkItem验证错误需要手动修复
}
```

### 同步冲突处理

```bash
# 同步冲突检测和解决
resolve_sync_conflicts() {
  local sync_type="$1"     # epic, issue
  local local_file="$2"    # 本地文件路径
  local remote_id="$3"     # 远程资源ID

  echo "=== 同步冲突解决 ==="
  echo "同步类型: $sync_type"
  echo "本地文件: $local_file"
  echo "远程ID: $remote_id"

  case "$sync_type" in
    "epic")
      resolve_epic_sync_conflict "$local_file" "$remote_id"
      ;;
    "issue")
      resolve_issue_sync_conflict "$local_file" "$remote_id"
      ;;
    *)
      echo "未知同步类型: $sync_type"
      return 1
      ;;
  esac
}

# Epic同步冲突解决
resolve_epic_sync_conflict() {
  local epic_file="$1"
  local workitem_id="$2"

  echo "解决Epic同步冲突..."

  # 获取本地Epic信息
  local local_updated=$(yq eval '.updated // ""' "$epic_file")
  local local_status=$(yq eval '.status // ""' "$epic_file")

  # 获取云效WorkItem信息
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local workitem_data=$(mcp_call "alibabacloud_devops_get_workitem" \
    --project-id "$project_id" \
    --workitem-id "$workitem_id")

  if [ $? -ne 0 ]; then
    echo "❌ 无法获取云效WorkItem信息"
    return 1
  fi

  local remote_updated=$(echo "$workitem_data" | jq -r '.updated_at')
  local remote_status=$(echo "$workitem_data" | jq -r '.status')

  echo "本地更新时间: $local_updated"
  echo "云效更新时间: $remote_updated"

  # 冲突解决策略
  if [[ "$local_updated" > "$remote_updated" ]]; then
    echo "🔄 本地更新较新，将本地数据同步到云效"
    sync_epic_to_yunxiao "$epic_file" "$workitem_id"
  elif [[ "$remote_updated" > "$local_updated" ]]; then
    echo "🔄 云效更新较新，将云效数据同步到本地"
    sync_yunxiao_to_epic "$epic_file" "$workitem_data"
  else
    echo "📊 时间戳相同，比较数据内容..."
    compare_and_merge_epic_data "$epic_file" "$workitem_data"
  fi
}

# Epic数据比较和合并
compare_and_merge_epic_data() {
  local epic_file="$1"
  local workitem_data="$2"

  echo "比较Epic数据差异..."

  local local_status=$(yq eval '.status // ""' "$epic_file")
  local remote_status=$(echo "$workitem_data" | jq -r '.status')

  # 映射云效状态到Epic状态
  local mapped_remote_status
  case "$remote_status" in
    "待处理") mapped_remote_status="pending" ;;
    "进行中") mapped_remote_status="in_progress" ;;
    "已完成") mapped_remote_status="completed" ;;
    "已暂停") mapped_remote_status="blocked" ;;
    *) mapped_remote_status="pending" ;;
  esac

  if [ "$local_status" != "$mapped_remote_status" ]; then
    echo "⚠️  状态冲突: 本地($local_status) vs 云效($mapped_remote_status)"
    echo "请选择解决方案:"
    echo "1. 使用本地状态"
    echo "2. 使用云效状态"
    echo "3. 手动合并"

    read -p "请输入选择 (1-3): " choice
    case "$choice" in
      1)
        echo "使用本地状态，同步到云效"
        sync_epic_to_yunxiao "$epic_file" "$(echo "$workitem_data" | jq -r '.id')"
        ;;
      2)
        echo "使用云效状态，同步到本地"
        sync_yunxiao_to_epic "$epic_file" "$workitem_data"
        ;;
      3)
        echo "进入手动合并模式"
        manual_merge_epic_data "$epic_file" "$workitem_data"
        ;;
      *)
        echo "无效选择，保持现状"
        ;;
    esac
  else
    echo "✅ 数据一致，无需合并"
  fi
}

# 手动数据合并
manual_merge_epic_data() {
  local epic_file="$1"
  local workitem_data="$2"

  echo "=== 手动数据合并 ==="
  echo "请手动编辑Epic文件以解决冲突"
  echo "Epic文件: $epic_file"
  echo ""
  echo "云效WorkItem数据:"
  echo "$workitem_data" | jq .
  echo ""
  echo "建议使用外部编辑器打开Epic文件并进行合并"
  echo "合并完成后，请重新运行同步操作"
}
```

## 网络和连接错误处理

### 网络连接诊断

```bash
# 网络连接综合诊断
diagnose_network_connectivity() {
  echo "=== 网络连接诊断 ==="

  # 1. 基础网络连接测试
  echo "1. 测试基础网络连接..."
  if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "✅ 基础网络连接正常"
  else
    echo "❌ 基础网络连接失败"
    echo "请检查网络设置和连接"
    return 1
  fi

  # 2. DNS解析测试
  echo "2. 测试DNS解析..."
  if nslookup devops.aliyun.com >/dev/null 2>&1; then
    echo "✅ DNS解析正常"
  else
    echo "❌ DNS解析失败"
    echo "建议检查DNS设置"
  fi

  # 3. 云效服务连接测试
  echo "3. 测试云效服务连接..."
  if curl -s --max-time 10 https://devops.aliyun.com >/dev/null; then
    echo "✅ 云效服务连接正常"
  else
    echo "❌ 云效服务连接失败"
    echo "可能的原因:"
    echo "- 防火墙阻止连接"
    echo "- 代理设置问题"
    echo "- 云效服务临时不可用"
  fi

  # 4. SSL证书验证
  echo "4. 测试SSL证书..."
  if openssl s_client -connect devops.aliyun.com:443 -verify_return_error </dev/null >/dev/null 2>&1; then
    echo "✅ SSL证书验证通过"
  else
    echo "⚠️  SSL证书验证失败"
    echo "可能需要更新CA证书包"
  fi
}

# 网络错误自动修复
auto_fix_network_issues() {
  echo "=== 网络问题自动修复 ==="

  # 1. 清理DNS缓存
  echo "1. 清理DNS缓存..."
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl restart systemd-resolved 2>/dev/null && echo "✅ DNS缓存已清理"
  elif command -v dscacheutil >/dev/null 2>&1; then
    sudo dscacheutil -flushcache && echo "✅ DNS缓存已清理"
  else
    echo "⚠️  无法自动清理DNS缓存"
  fi

  # 2. 检查代理设置
  echo "2. 检查代理设置..."
  if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
    echo "检测到代理设置:"
    [ -n "$http_proxy" ] && echo "  HTTP代理: $http_proxy"
    [ -n "$https_proxy" ] && echo "  HTTPS代理: $https_proxy"
    echo "如果连接有问题，请检查代理配置"
  else
    echo "✅ 未使用代理"
  fi

  # 3. 测试连接恢复
  echo "3. 测试连接恢复..."
  if ping -c 1 devops.aliyun.com >/dev/null 2>&1; then
    echo "✅ 网络连接已恢复"
    return 0
  else
    echo "❌ 网络连接仍有问题"
    return 1
  fi
}
```

## 数据恢复和备份

### 数据备份机制

```bash
# 创建数据备份
create_data_backup() {
  local backup_type="$1"  # epic, issue, config
  local source_path="$2"
  local backup_reason="${3:-manual}"

  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_dir=".claude/backups/$backup_type"

  # 创建备份目录
  mkdir -p "$backup_dir"

  case "$backup_type" in
    "epic")
      backup_epic_data "$source_path" "$backup_dir" "$timestamp" "$backup_reason"
      ;;
    "config")
      backup_config_data "$source_path" "$backup_dir" "$timestamp" "$backup_reason"
      ;;
    "sync_state")
      backup_sync_state "$backup_dir" "$timestamp" "$backup_reason"
      ;;
    *)
      echo "未知备份类型: $backup_type"
      return 1
      ;;
  esac
}

# Epic数据备份
backup_epic_data() {
  local epic_file="$1"
  local backup_dir="$2"
  local timestamp="$3"
  local reason="$4"

  local epic_name=$(basename "$epic_file" .md)
  local backup_file="$backup_dir/${epic_name}_${timestamp}.md"

  cp "$epic_file" "$backup_file"

  # 添加备份元信息
  cat <<EOF >> "$backup_file"

<!-- 备份信息
备份时间: $(date)
备份原因: $reason
原始文件: $epic_file
-->
EOF

  echo "Epic备份已创建: $backup_file"
}

# 配置数据备份
backup_config_data() {
  local config_file="$1"
  local backup_dir="$2"
  local timestamp="$3"
  local reason="$4"

  local backup_file="$backup_dir/ccpm_config_${timestamp}.yaml"

  cp "$config_file" "$backup_file"

  echo "配置备份已创建: $backup_file"
}

# 同步状态备份
backup_sync_state() {
  local backup_dir="$1"
  local timestamp="$2"
  local reason="$3"

  local state_file="$backup_dir/sync_state_${timestamp}.json"

  # 收集当前同步状态
  local sync_state=$(cat <<EOF
{
  "backup_time": "$(date -Iseconds)",
  "backup_reason": "$reason",
  "platform_config": $(cat .claude/ccpm.config | yq eval -o=json),
  "epic_sync_status": []
}
EOF
)

  # 添加Epic同步状态
  if [ -d ".claude/epics" ]; then
    find .claude/epics -name "*.md" -type f | while read -r epic_file; do
      local yunxiao_id=$(yq eval '.yunxiao.id // ""' "$epic_file")
      local sync_status=$(yq eval '.yunxiao.sync_status // ""' "$epic_file")

      if [ -n "$yunxiao_id" ]; then
        local epic_state=$(cat <<EOF
{
  "epic_file": "$epic_file",
  "yunxiao_id": "$yunxiao_id",
  "sync_status": "$sync_status",
  "last_sync": "$(yq eval '.yunxiao.sync_time // ""' "$epic_file")"
}
EOF
)
        echo "$epic_state" >> "$state_file.tmp"
      fi
    done

    if [ -f "$state_file.tmp" ]; then
      # 合并Epic状态到主文件
      local epic_states=$(cat "$state_file.tmp" | jq -s .)
      echo "$sync_state" | jq --argjson epics "$epic_states" '.epic_sync_status = $epics' > "$state_file"
      rm "$state_file.tmp"
    else
      echo "$sync_state" > "$state_file"
    fi
  else
    echo "$sync_state" > "$state_file"
  fi

  echo "同步状态备份已创建: $state_file"
}

# 数据恢复
restore_from_backup() {
  local backup_type="$1"
  local backup_file="$2"
  local target_path="${3:-auto}"

  echo "=== 数据恢复 ==="
  echo "备份类型: $backup_type"
  echo "备份文件: $backup_file"

  if [ ! -f "$backup_file" ]; then
    echo "❌ 备份文件不存在: $backup_file"
    return 1
  fi

  case "$backup_type" in
    "epic")
      restore_epic_from_backup "$backup_file" "$target_path"
      ;;
    "config")
      restore_config_from_backup "$backup_file" "$target_path"
      ;;
    "sync_state")
      restore_sync_state_from_backup "$backup_file"
      ;;
    *)
      echo "未知恢复类型: $backup_type"
      return 1
      ;;
  esac
}

# Epic恢复
restore_epic_from_backup() {
  local backup_file="$1"
  local target_path="$2"

  if [ "$target_path" = "auto" ]; then
    # 从备份文件名推断目标路径
    local epic_name=$(basename "$backup_file" | sed 's/_[0-9]*_[0-9]*.md$//')
    target_path=".claude/epics/$epic_name.md"
  fi

  echo "恢复Epic到: $target_path"

  # 创建当前版本的安全备份
  if [ -f "$target_path" ]; then
    local safety_backup="${target_path}.safety_$(date +%Y%m%d_%H%M%S)"
    cp "$target_path" "$safety_backup"
    echo "当前版本已备份到: $safety_backup"
  fi

  # 执行恢复
  cp "$backup_file" "$target_path"

  # 移除备份元信息
  sed -i '/<!-- 备份信息/,$d' "$target_path"

  echo "✅ Epic恢复完成"
  echo "请验证恢复的数据是否正确"
}
```

## 故障排除命令集

### 综合诊断命令

```bash
# 完整的故障诊断
ccpm_diagnose() {
  local component="${1:-all}"  # all, mcp, network, config, sync

  echo "========================================"
  echo "  CCPM 云效适配器故障诊断"
  echo "========================================"
  echo "诊断组件: $component"
  echo "诊断时间: $(date)"
  echo ""

  local overall_status=0

  case "$component" in
    "all"|"config")
      echo "🔧 配置诊断"
      echo "----------------------------------------"
      if ! diagnose_configuration; then
        overall_status=1
      fi
      echo ""
      ;;
  esac

  case "$component" in
    "all"|"network")
      echo "🌐 网络诊断"
      echo "----------------------------------------"
      if ! diagnose_network_connectivity; then
        overall_status=1
      fi
      echo ""
      ;;
  esac

  case "$component" in
    "all"|"mcp")
      echo "🔌 MCP连接诊断"
      echo "----------------------------------------"
      if ! diagnose_mcp_connection; then
        overall_status=1
      fi
      echo ""
      ;;
  esac

  case "$component" in
    "all"|"sync")
      echo "🔄 同步状态诊断"
      echo "----------------------------------------"
      if ! diagnose_sync_status; then
        overall_status=1
      fi
      echo ""
      ;;
  esac

  echo "========================================"
  if [ $overall_status -eq 0 ]; then
    echo "✅ 诊断完成，所有组件状态正常"
  else
    echo "⚠️  诊断完成，发现问题需要处理"
    echo ""
    echo "建议的修复操作:"
    echo "1. 根据上述诊断结果修复相关问题"
    echo "2. 运行 ccpm_auto_fix 尝试自动修复"
    echo "3. 如需帮助，请查看详细错误信息"
  fi
  echo "========================================"

  return $overall_status
}

# 自动修复功能
ccpm_auto_fix() {
  echo "=== CCPM 自动修复 ==="

  local fixes_applied=0

  echo "1. 尝试修复网络问题..."
  if auto_fix_network_issues; then
    echo "✅ 网络问题已修复"
    ((fixes_applied++))
  fi

  echo ""
  echo "2. 尝试修复MCP连接..."
  if repair_mcp_connection; then
    echo "✅ MCP连接已修复"
    ((fixes_applied++))
  fi

  echo ""
  echo "3. 检查和修复配置..."
  if auto_fix_configuration; then
    echo "✅ 配置问题已修复"
    ((fixes_applied++))
  fi

  echo ""
  echo "=== 修复完成 ==="
  echo "应用的修复: $fixes_applied"

  if [ $fixes_applied -gt 0 ]; then
    echo "建议重新运行诊断验证修复效果"
  else
    echo "未能自动修复问题，请手动检查"
  fi
}

# 配置自动修复
auto_fix_configuration() {
  local config_file=".claude/ccpm.config"
  local fixes=0

  echo "检查配置文件: $config_file"

  if [ ! -f "$config_file" ]; then
    echo "创建默认配置文件..."
    cat <<EOF > "$config_file"
platform:
  type: "yunxiao"
  project_id: ""
  base_url: "https://devops.aliyun.com"
  api_version: "v4"

sync:
  auto_sync: false
  batch_size: 10
  retry_count: 3
EOF
    echo "✅ 默认配置文件已创建"
    ((fixes++))
  fi

  # 检查必需字段
  local platform_type=$(yq eval '.platform.type // ""' "$config_file")
  if [ "$platform_type" != "yunxiao" ]; then
    echo "修复平台类型设置..."
    yq eval '.platform.type = "yunxiao"' -i "$config_file"
    ((fixes++))
  fi

  local project_id=$(yq eval '.platform.project_id // ""' "$config_file")
  if [ -z "$project_id" ]; then
    echo "⚠️  project_id未设置，需要手动配置"
  fi

  return $fixes
}
```

## 使用指南

### 错误处理最佳实践

1. **预防性检查**: 在执行操作前进行配置和连接检查
2. **分层错误处理**: 区分不同级别的错误，采用相应的处理策略
3. **自动重试**: 对于临时性错误实施智能重试机制
4. **数据备份**: 在关键操作前创建数据备份
5. **详细日志**: 记录错误详情和恢复过程以便分析

### 故障排除流程

```bash
# 标准故障排除流程
troubleshoot_standard_flow() {
  echo "=== 标准故障排除流程 ==="

  # 1. 基础诊断
  echo "步骤1: 基础诊断"
  ccpm_diagnose all

  # 2. 自动修复
  echo "步骤2: 自动修复"
  ccpm_auto_fix

  # 3. 验证修复
  echo "步骤3: 验证修复"
  ccpm_diagnose all

  # 4. 生成报告
  echo "步骤4: 生成诊断报告"
  generate_diagnostic_report
}

# 生成诊断报告
generate_diagnostic_report() {
  local report_file=".claude/logs/diagnostic_report_$(date +%Y%m%d_%H%M%S).md"

  mkdir -p "$(dirname "$report_file")"

  cat <<EOF > "$report_file"
# CCPM 诊断报告

**生成时间**: $(date)
**诊断版本**: v1.0.0

## 系统环境

- 操作系统: $(uname -s)
- Shell: $SHELL
- 工作目录: $(pwd)

## 配置状态

$(if [ -f ".claude/ccpm.config" ]; then
  echo "配置文件存在"
  yq eval . .claude/ccpm.config
else
  echo "配置文件不存在"
fi)

## 网络状态

$(diagnose_network_connectivity 2>&1 | head -20)

## MCP连接状态

$(diagnose_mcp_connection 2>&1 | head -20)

## 建议

基于诊断结果的建议和后续步骤。

EOF

  echo "诊断报告已生成: $report_file"
}
```

## 版本信息

- **规则版本**: v1.0.0
- **最后更新**: 2025-09-28
- **适用场景**: 云效平台适配器框架错误处理
- **依赖工具**: yq, jq, curl, ping, nslookup
- **相关规则**: platform-yunxiao-*.md 系列规则文件