# 云效规则文件模板框架

云效平台集成规则文件的标准模板和框架，用于创建新的云效专用规则文件。

## 概述

此模板文件提供了创建云效平台规则文件的标准框架，确保所有云效相关规则文件的一致性和完整性。

## 文件命名规范

### 规则文件命名模式
```
platform-yunxiao-{功能模块}.md
```

### 已定义的功能模块
- `sync` - 基础同步规则和配置
- `workitem` - 工作项操作规则
- `api` - API调用和数据处理规则
- `webhooks` - Webhook集成规则
- `mapping` - 数据映射和转换规则
- `template` - 模板框架（本文件）

### 扩展模块示例
- `project` - 项目管理规则
- `users` - 用户和权限管理
- `reports` - 报告和统计规则
- `integration` - 第三方集成规则

## 标准文件模板

### 基础模板结构
```markdown
# 云效{功能名称}规则

{功能描述和用途说明}

## 概述

此规则文件定义了{具体功能描述}...

## 配置和参数

### 基础配置
{相关配置项}

### 环境变量
{所需环境变量}

## 核心功能

### 功能1
{函数定义和说明}

### 功能2
{函数定义和说明}

## 错误处理

### 异常情况处理
{错误处理逻辑}

### 重试机制
{重试策略}

## 使用示例

### 基本用法
{示例代码}

### 高级用法
{高级示例}

## 版本信息

- **规则版本**: v1.0.0
- **最后更新**: {日期}
- **依赖**: {依赖工具和规则}
```

## 通用代码模板

### 配置检查模板
```bash
# 检查云效平台配置
check_yunxiao_config() {
  local function_name="${1:-通用功能}"

  echo "检查云效平台配置 ($function_name)..."

  # 检查配置文件
  if [ ! -f ".claude/ccpm.config" ]; then
    echo "错误: 未找到配置文件 .claude/ccpm.config"
    return 1
  fi

  # 检查平台类型
  local platform=$(yq eval '.platform.type' .claude/ccpm.config 2>/dev/null)
  if [ "$platform" != "yunxiao" ]; then
    echo "错误: 平台类型必须为 'yunxiao'，当前为: $platform"
    return 1
  fi

  # 检查项目ID
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config 2>/dev/null)
  if [ -z "$project_id" ] || [ "$project_id" = "null" ]; then
    echo "错误: 必须配置 platform.project_id"
    return 1
  fi

  # 检查访问令牌
  if [ -z "$YUNXIAO_ACCESS_TOKEN" ]; then
    echo "错误: 必须设置环境变量 YUNXIAO_ACCESS_TOKEN"
    return 1
  fi

  echo "云效平台配置验证通过"
  return 0
}
```

### 错误处理模板
```bash
# 通用错误处理函数
handle_yunxiao_error() {
  local error_code="$1"
  local error_message="$2"
  local function_name="${3:-未知函数}"
  local context="${4:-}"

  echo "云效平台错误 [$function_name]:"
  echo "  错误代码: $error_code"
  echo "  错误信息: $error_message"

  if [ -n "$context" ]; then
    echo "  上下文: $context"
  fi

  # 记录错误日志
  local log_file="${YUNXIAO_LOG_FILE:-/tmp/yunxiao_errors.log}"
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] ERROR [$function_name] $error_code: $error_message ($context)" >> "$log_file"

  return 1
}

# 重试机制模板
retry_yunxiao_operation() {
  local max_attempts="${1:-3}"
  local delay="${2:-1}"
  local operation_name="${3:-操作}"
  shift 3

  local attempt=1
  while [ $attempt -le $max_attempts ]; do
    echo "尝试执行 $operation_name (第 $attempt 次)..."

    if "$@"; then
      echo "$operation_name 执行成功"
      return 0
    fi

    if [ $attempt -eq $max_attempts ]; then
      echo "$operation_name 执行失败，达到最大重试次数"
      return 1
    fi

    echo "等待 $delay 秒后重试..."
    sleep "$delay"
    delay=$((delay * 2))  # 指数退避
    attempt=$((attempt + 1))
  done
}
```

### 日志记录模板
```bash
# 统一日志记录函数
log_yunxiao_operation() {
  local level="$1"      # INFO, WARN, ERROR, DEBUG
  local operation="$2"  # 操作名称
  local message="$3"    # 日志消息
  local details="${4:-}" # 详细信息

  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local log_file="${YUNXIAO_LOG_FILE:-/tmp/yunxiao.log}"

  # 构建日志条目
  local log_entry="[$timestamp] [$level] [$operation] $message"

  if [ -n "$details" ]; then
    log_entry+=" | $details"
  fi

  # 写入日志文件
  echo "$log_entry" >> "$log_file"

  # 根据级别决定是否输出到控制台
  case "$level" in
    "ERROR"|"WARN")
      echo "$log_entry" >&2
      ;;
    "INFO")
      echo "$log_entry"
      ;;
    "DEBUG")
      if [ "${YUNXIAO_DEBUG:-false}" = "true" ]; then
        echo "$log_entry"
      fi
      ;;
  esac
}
```

### API调用模板
```bash
# 标准API调用模板
yunxiao_api_call_template() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  local operation_name="${4:-API调用}"

  # 检查配置
  if ! check_yunxiao_config "$operation_name"; then
    return 1
  fi

  # 记录操作开始
  log_yunxiao_operation "INFO" "$operation_name" "开始API调用: $method $endpoint"

  # 执行API调用（使用重试机制）
  local response
  if response=$(retry_yunxiao_operation 3 1 "$operation_name" yunxiao_api_request "$method" "$endpoint" "$data"); then
    log_yunxiao_operation "INFO" "$operation_name" "API调用成功"
    echo "$response"
    return 0
  else
    log_yunxiao_operation "ERROR" "$operation_name" "API调用失败"
    return 1
  fi
}
```

## 文档规范

### 注释规范
```bash
# 函数注释模板
#
# 函数名称: function_name
# 功能描述: 简要说明函数功能
# 参数说明:
#   $1 - 参数1说明
#   $2 - 参数2说明（可选）
# 返回值:
#   0 - 成功
#   1 - 失败
# 使用示例:
#   function_name "param1" "param2"
#
function_name() {
  # 函数实现
}
```

### 变量命名规范
```bash
# 全局配置变量 - 全大写，下划线分隔
YUNXIAO_API_BASE="https://devops.aliyun.com/api/v4"
YUNXIAO_ACCESS_TOKEN=""

# 局部变量 - 小写，下划线分隔
local project_id=""
local workitem_data=""

# 函数参数变量 - 描述性命名
local workitem_title="$1"
local workitem_type="$2"
```

## 测试模板

### 单元测试模板
```bash
# 测试函数模板
test_yunxiao_function() {
  local function_name="$1"
  echo "测试云效函数: $function_name"

  # 设置测试环境
  setup_test_environment

  # 执行测试用例
  local test_cases=(
    "test_case_1"
    "test_case_2"
    "test_case_3"
  )

  local passed=0
  local failed=0

  for test_case in "${test_cases[@]}"; do
    echo "  执行测试用例: $test_case"

    if "$test_case"; then
      echo "    ✓ 通过"
      passed=$((passed + 1))
    else
      echo "    ✗ 失败"
      failed=$((failed + 1))
    fi
  done

  # 清理测试环境
  cleanup_test_environment

  # 输出测试结果
  echo "测试完成: $passed 通过, $failed 失败"

  if [ $failed -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

# 集成测试模板
test_yunxiao_integration() {
  echo "云效集成测试"

  # 检查测试环境
  if [ -z "$YUNXIAO_TEST_PROJECT_ID" ]; then
    echo "跳过集成测试: 未设置测试项目ID"
    return 0
  fi

  # 执行集成测试流程
  echo "1. 测试配置验证..."
  check_yunxiao_config "集成测试" || return 1

  echo "2. 测试API连接..."
  test_yunxiao_connection || return 1

  echo "3. 测试基本操作..."
  test_basic_operations || return 1

  echo "集成测试完成"
  return 0
}
```

## 部署和集成

### 规则文件集成检查
```bash
# 检查云效规则文件完整性
check_yunxiao_rules_integrity() {
  echo "检查云效规则文件完整性..."

  local required_rules=(
    "platform-yunxiao-sync.md"
    "platform-yunxiao-workitem.md"
    "platform-yunxiao-api.md"
    "platform-yunxiao-mapping.md"
  )

  local optional_rules=(
    "platform-yunxiao-webhooks.md"
    "platform-yunxiao-template.md"
  )

  local missing_rules=()
  local rules_dir=".claude/rules"

  # 检查必需规则文件
  for rule in "${required_rules[@]}"; do
    if [ ! -f "$rules_dir/$rule" ]; then
      missing_rules+=("$rule")
    fi
  done

  # 报告检查结果
  if [ ${#missing_rules[@]} -eq 0 ]; then
    echo "✓ 所有必需的云效规则文件都存在"

    # 检查可选文件
    for rule in "${optional_rules[@]}"; do
      if [ -f "$rules_dir/$rule" ]; then
        echo "✓ 可选规则文件存在: $rule"
      else
        echo "- 可选规则文件缺失: $rule"
      fi
    done

    return 0
  else
    echo "✗ 缺少必需的云效规则文件:"
    printf '  - %s\n' "${missing_rules[@]}"
    return 1
  fi
}

# 验证规则文件语法
validate_yunxiao_rules_syntax() {
  echo "验证云效规则文件语法..."

  local rules_dir=".claude/rules"
  local yunxiao_rules=($(find "$rules_dir" -name "platform-yunxiao-*.md" -type f))

  local syntax_errors=0

  for rule_file in "${yunxiao_rules[@]}"; do
    echo "检查: $(basename "$rule_file")"

    # 检查文件是否可读
    if [ ! -r "$rule_file" ]; then
      echo "  ✗ 文件不可读"
      syntax_errors=$((syntax_errors + 1))
      continue
    fi

    # 检查基本结构
    if ! grep -q "^# 云效" "$rule_file"; then
      echo "  ✗ 缺少标准标题格式"
      syntax_errors=$((syntax_errors + 1))
    fi

    if ! grep -q "## 概述" "$rule_file"; then
      echo "  ✗ 缺少概述部分"
      syntax_errors=$((syntax_errors + 1))
    fi

    if ! grep -q "## 版本信息" "$rule_file"; then
      echo "  ✗ 缺少版本信息"
      syntax_errors=$((syntax_errors + 1))
    fi

    if [ $syntax_errors -eq 0 ]; then
      echo "  ✓ 语法检查通过"
    fi
  done

  if [ $syntax_errors -eq 0 ]; then
    echo "✓ 所有云效规则文件语法检查通过"
    return 0
  else
    echo "✗ 发现 $syntax_errors 个语法错误"
    return 1
  fi
}
```

## 规则文件创建向导

### 交互式规则文件生成器
```bash
# 创建新的云效规则文件
create_yunxiao_rule_file() {
  echo "云效规则文件创建向导"
  echo "========================"

  # 获取用户输入
  echo -n "请输入功能模块名称 (例如: project, users): "
  read -r module_name

  if [ -z "$module_name" ]; then
    echo "错误: 模块名称不能为空"
    return 1
  fi

  echo -n "请输入功能描述: "
  read -r function_description

  echo -n "请输入作者名称: "
  read -r author_name

  # 生成文件名
  local rule_file=".claude/rules/platform-yunxiao-${module_name}.md"

  if [ -f "$rule_file" ]; then
    echo "警告: 文件 $rule_file 已存在"
    echo -n "是否覆盖? (y/N): "
    read -r confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "取消创建"
      return 1
    fi
  fi

  # 生成文件内容
  cat > "$rule_file" <<EOF
# 云效${function_description}规则

${function_description}的云效平台专用规则和操作指南。

## 概述

此规则文件定义了${function_description}相关的云效平台集成规则...

## 配置和参数

### 基础配置
\`\`\`bash
# ${module_name}相关配置
YUNXIAO_${module_name^^}_CONFIG=""
\`\`\`

### 环境变量
- \`YUNXIAO_ACCESS_TOKEN\` - 云效访问令牌
- \`YUNXIAO_${module_name^^}_CONFIG\` - ${function_description}专用配置

## 核心功能

### 功能占位符
\`\`\`bash
# TODO: 实现${function_description}核心功能
${module_name}_function() {
  local param1="\$1"

  # 检查配置
  if ! check_yunxiao_config "${function_description}"; then
    return 1
  fi

  # 功能实现
  echo "执行${function_description}操作..."

  return 0
}
\`\`\`

## 错误处理

### 异常情况处理
\`\`\`bash
# ${function_description}错误处理
handle_${module_name}_error() {
  local error_message="\$1"
  handle_yunxiao_error "ERR_${module_name^^}" "\$error_message" "${function_description}"
}
\`\`\`

## 使用示例

### 基本用法
\`\`\`bash
# 使用${function_description}功能
${module_name}_function "参数1"
\`\`\`

## 版本信息

- **规则版本**: v1.0.0
- **最后更新**: $(date '+%Y-%m-%d')
- **作者**: ${author_name:-未知}
- **依赖**: platform-yunxiao-sync.md, platform-yunxiao-api.md
EOF

  echo "✓ 云效规则文件已创建: $rule_file"
  echo "请编辑文件以实现具体功能"
}
```

## 使用指南

### 快速开始
1. 使用 `create_yunxiao_rule_file` 创建新规则文件
2. 根据模板填充具体功能
3. 使用 `validate_yunxiao_rules_syntax` 验证语法
4. 使用 `check_yunxiao_rules_integrity` 检查完整性

### 最佳实践
- 遵循统一的命名规范
- 包含完整的错误处理
- 提供详细的使用示例
- 保持版本信息更新
- 添加适当的测试用例

## 版本信息

- **模板版本**: v1.0.0
- **最后更新**: 2025-09-28
- **用途**: 云效规则文件标准化模板
- **依赖**: jq, yq, bash