# 平台配置规则
# Platform Configuration Rules

CCPM（Cloud Code Project Management）平台配置系统规则和使用指南。

## 概述

CCPM 支持多平台项目管理，目前支持：
- **GitHub**: GitHub Issues 和 Projects
- **Yunxiao**: 阿里云云效工作项管理

平台配置系统采用**前置检查 + 规则分离**模式，确保最小化现有代码修改，实现平台无缝切换。

## 配置文件架构

### 配置文件优先级

配置系统支持双配置文件模式，优先级如下：

1. **`.claude/ccpm.yaml`** - 新的 YAML 配置（优先）
2. **`.claude/ccpm.config`** - 现有的 Bash 配置（后备）

当 YAML 配置存在时，平台选择从 YAML 读取；否则默认使用 GitHub 模式并应用 Bash 配置。

### 配置文件格式

#### YAML 配置格式（推荐）

```yaml
# 基础平台配置
platform:
  type: "github"        # "github" | "yunxiao"
  project_id: ""        # 云效项目ID（yunxiao模式必需）

# 同步配置
sync:
  mode: "bidirectional"              # 同步模式
  conflict_resolution:
    strategy: "timestamp"            # 冲突处理策略

# 功能开关
features:
  strict_validation: true            # 严格验证模式
  legacy_compatibility: true        # 向后兼容模式
```

#### Bash 配置格式（现有系统）

```bash
# GitHub 仓库自动检测逻辑
GITHUB_REPO=$(get_github_repo) || exit 1
export GH_REPO="$GITHUB_REPO"
```

## 平台检测机制

### 前置检查指令模板

在所有 sync 相关命令开头添加以下平台检测逻辑：

```bash
# ==========================================
# 平台配置检测 - Platform Configuration Detection
# ==========================================

# Step 1: 检测配置文件 - Detect Configuration Files
YAML_CONFIG=".claude/ccpm.yaml"
BASH_CONFIG=".claude/ccpm.config"

# Step 2: 读取平台配置 - Read Platform Configuration
if [ -f "$YAML_CONFIG" ]; then
    # 使用 YAML 配置
    PLATFORM_TYPE=$(yq eval '.platform.type' "$YAML_CONFIG" 2>/dev/null || echo "github")
    PROJECT_ID=$(yq eval '.platform.project_id' "$YAML_CONFIG" 2>/dev/null || echo "")
    SYNC_MODE=$(yq eval '.sync.mode' "$YAML_CONFIG" 2>/dev/null || echo "bidirectional")

    echo "📝 使用 YAML 配置：$YAML_CONFIG"
    echo "🎯 平台类型：$PLATFORM_TYPE"

elif [ -f "$BASH_CONFIG" ]; then
    # 使用现有 Bash 配置
    source "$BASH_CONFIG"
    PLATFORM_TYPE="github"
    SYNC_MODE="bidirectional"

    echo "📝 使用 Bash 配置：$BASH_CONFIG"
    echo "🎯 平台类型：GitHub (兼容模式)"

else
    # 默认配置
    PLATFORM_TYPE="github"
    SYNC_MODE="bidirectional"

    echo "⚠️ 未找到配置文件，使用默认 GitHub 模式"
fi

# Step 3: 加载平台特定规则 - Load Platform-specific Rules
case "$PLATFORM_TYPE" in
    "yunxiao")
        echo "🔄 加载云效平台规则..."

        # 验证云效配置
        if [ -z "$PROJECT_ID" ] || [ "$PROJECT_ID" = "null" ]; then
            echo "❌ 错误：云效模式需要配置 platform.project_id"
            exit 1
        fi

        # 检查访问令牌
        if [ -z "$YUNXIAO_ACCESS_TOKEN" ]; then
            echo "❌ 错误：未设置环境变量 YUNXIAO_ACCESS_TOKEN"
            echo "请运行: export YUNXIAO_ACCESS_TOKEN='your-token'"
            exit 1
        fi

        # 加载云效规则文件
        YUNXIAO_RULES_FILE=".claude/rules/platform-yunxiao-sync.md"
        if [ -f "$YUNXIAO_RULES_FILE" ]; then
            echo "✅ 云效规则文件已加载：$YUNXIAO_RULES_FILE"
        else
            echo "❌ 警告：云效规则文件不存在：$YUNXIAO_RULES_FILE"
        fi

        # 设置云效专用变量
        export YUNXIAO_PROJECT_ID="$PROJECT_ID"
        export PLATFORM_MODE="yunxiao"
        ;;

    "github")
        echo "🔄 加载 GitHub 平台规则..."

        # 应用现有 GitHub 配置逻辑
        if [ -f "$BASH_CONFIG" ]; then
            source "$BASH_CONFIG"
        fi

        # 验证 GitHub 配置
        if [ -z "$GITHUB_REPO" ] && [ -z "$GH_REPO" ]; then
            echo "❌ 错误：无法检测 GitHub 仓库信息"
            exit 1
        fi

        export PLATFORM_MODE="github"
        ;;

    *)
        echo "❌ 错误：不支持的平台类型：$PLATFORM_TYPE"
        echo "支持的平台: github, yunxiao"
        exit 1
        ;;
esac

# Step 4: 输出配置摘要 - Configuration Summary
echo ""
echo "🎛️ 平台配置摘要："
echo "   平台类型: $PLATFORM_TYPE"
echo "   同步模式: $SYNC_MODE"
echo "   项目标识: ${PROJECT_ID:-$GITHUB_REPO}"
echo ""

# ==========================================
# 继续执行原有命令逻辑...
# Continue with original command logic...
# ==========================================
```

## 平台选择逻辑

### 配置优先级决策树

```
是否存在 .claude/ccpm.yaml？
├─ 是 → 读取 platform.type
│   ├─ "yunxiao" → 云效模式
│   └─ "github" → GitHub模式
├─ 否 → 是否存在 .claude/ccpm.config？
    ├─ 是 → GitHub模式 (兼容)
    └─ 否 → GitHub模式 (默认)
```

### 平台切换流程

1. **从 GitHub 切换到云效**:
   ```bash
   # 修改 ccpm.yaml
   yq eval '.platform.type = "yunxiao"' -i .claude/ccpm.yaml
   yq eval '.platform.project_id = "your-project-id"' -i .claude/ccpm.yaml

   # 设置访问令牌
   export YUNXIAO_ACCESS_TOKEN="your-token"
   ```

2. **从云效切换到 GitHub**:
   ```bash
   # 修改 ccpm.yaml
   yq eval '.platform.type = "github"' -i .claude/ccpm.yaml
   ```

3. **完全禁用 YAML 配置（回到纯 GitHub 模式）**:
   ```bash
   # 重命名或删除 YAML 配置
   mv .claude/ccpm.yaml .claude/ccpm.yaml.bak
   ```

## 规则文件分离策略

### 文件组织结构

```
.claude/
├── ccpm.yaml                           # 新YAML配置
├── ccpm.config                         # 现有Bash配置
├── rules/
│   ├── platform-config.md             # 本文件：平台配置规则
│   ├── platform-yunxiao-sync.md       # 云效同步规则
│   ├── platform-yunxiao-api.md        # 云效API规则 (将来)
│   └── platform-yunxiao-webhooks.md   # 云效Webhook规则 (将来)
└── commands/
    └── pm/
        ├── sync.md                     # 添加平台检测前置逻辑
        ├── issue-sync.md               # 添加平台检测前置逻辑
        └── epic-sync.md                # 添加平台检测前置逻辑
```

### 规则分离原则

1. **GitHub 逻辑不变**：现有 GitHub 逻辑完全保持不变
2. **云效逻辑独立**：云效相关逻辑完全独立在专用规则文件中
3. **前置检查路由**：通过前置检查决定执行哪套逻辑
4. **向后兼容**：没有 YAML 配置时，完全按现有方式工作

## 配置验证规则

### 必需配置项检查

```bash
# 验证 YAML 配置完整性
validate_yaml_config() {
    local config_file="$1"

    # 检查文件存在性
    if [ ! -f "$config_file" ]; then
        echo "❌ 配置文件不存在：$config_file"
        return 1
    fi

    # 检查 YAML 语法
    if ! yq eval '.' "$config_file" >/dev/null 2>&1; then
        echo "❌ YAML 语法错误：$config_file"
        return 1
    fi

    # 检查必需字段
    platform_type=$(yq eval '.platform.type' "$config_file" 2>/dev/null)
    if [ -z "$platform_type" ] || [ "$platform_type" = "null" ]; then
        echo "❌ 缺少必需配置：platform.type"
        return 1
    fi

    # 平台特定验证
    case "$platform_type" in
        "yunxiao")
            project_id=$(yq eval '.platform.project_id' "$config_file" 2>/dev/null)
            if [ -z "$project_id" ] || [ "$project_id" = "null" ]; then
                echo "❌ 云效平台需要配置：platform.project_id"
                return 1
            fi
            ;;
        "github")
            # GitHub 配置验证（可选）
            ;;
        *)
            echo "❌ 不支持的平台类型：$platform_type"
            return 1
            ;;
    esac

    echo "✅ 配置验证通过"
    return 0
}
```

### 环境依赖检查

```bash
# 检查运行环境依赖
check_environment_dependencies() {
    local platform_type="$1"

    # 通用依赖检查
    if ! command -v yq >/dev/null 2>&1; then
        echo "❌ 缺少依赖：yq (YAML 处理工具)"
        echo "安装方法：https://github.com/mikefarah/yq#install"
        return 1
    fi

    # 平台特定依赖检查
    case "$platform_type" in
        "yunxiao")
            if [ -z "$YUNXIAO_ACCESS_TOKEN" ]; then
                echo "❌ 缺少环境变量：YUNXIAO_ACCESS_TOKEN"
                return 1
            fi

            # 检查网络连接（可选）
            if ! curl -s --max-time 5 https://devops.aliyun.com >/dev/null; then
                echo "⚠️ 警告：无法连接到云效平台，请检查网络"
            fi
            ;;

        "github")
            if ! command -v gh >/dev/null 2>&1; then
                echo "❌ 缺少依赖：gh (GitHub CLI)"
                echo "安装方法：https://cli.github.com/"
                return 1
            fi

            # 检查 GitHub 认证
            if ! gh auth status >/dev/null 2>&1; then
                echo "❌ GitHub CLI 未认证，请运行：gh auth login"
                return 1
            fi
            ;;
    esac

    echo "✅ 环境依赖检查通过"
    return 0
}
```

## 性能优化规则

### 配置缓存机制

```bash
# 配置缓存文件
CONFIG_CACHE_FILE=".claude/.config_cache"
CONFIG_CACHE_TTL=300  # 5分钟

# 读取缓存配置
load_cached_config() {
    if [ -f "$CONFIG_CACHE_FILE" ]; then
        local cache_time=$(stat -c %Y "$CONFIG_CACHE_FILE" 2>/dev/null || echo 0)
        local current_time=$(date +%s)

        if [ $((current_time - cache_time)) -lt $CONFIG_CACHE_TTL ]; then
            source "$CONFIG_CACHE_FILE"
            echo "🚀 使用缓存配置 (剩余 $((CONFIG_CACHE_TTL - (current_time - cache_time)))s)"
            return 0
        fi
    fi
    return 1
}

# 保存配置到缓存
save_config_cache() {
    cat > "$CONFIG_CACHE_FILE" << EOF
PLATFORM_TYPE="$PLATFORM_TYPE"
PROJECT_ID="$PROJECT_ID"
SYNC_MODE="$SYNC_MODE"
PLATFORM_MODE="$PLATFORM_MODE"
EOF
}
```

### 最小化检查模式

```bash
# 快速模式（跳过某些验证）
QUICK_MODE=${CCPM_QUICK_MODE:-false}

if [ "$QUICK_MODE" = "true" ]; then
    echo "⚡ 快速模式：跳过部分验证"
    SKIP_CONNECTIVITY_CHECK=true
    SKIP_VALIDATION=true
fi
```

## 错误处理和回退机制

### 配置错误回退

```bash
# 配置加载失败时的回退逻辑
fallback_to_legacy_config() {
    echo "⚠️ YAML配置加载失败，回退到传统配置模式"

    if [ -f ".claude/ccpm.config" ]; then
        source ".claude/ccpm.config"
        PLATFORM_TYPE="github"
        echo "✅ 已切换到 GitHub 兼容模式"
        return 0
    else
        echo "❌ 无可用配置，使用最小默认配置"
        PLATFORM_TYPE="github"
        GITHUB_REPO="unknown/unknown"
        return 1
    fi
}
```

### 平台切换失败处理

```bash
# 平台切换失败时的处理
handle_platform_switch_failure() {
    local target_platform="$1"
    local error_message="$2"

    echo "❌ 平台切换失败：$target_platform"
    echo "错误信息：$error_message"
    echo ""
    echo "建议解决方案："

    case "$target_platform" in
        "yunxiao")
            echo "1. 检查 platform.project_id 是否正确配置"
            echo "2. 验证 YUNXIAO_ACCESS_TOKEN 环境变量"
            echo "3. 确认网络可以访问 https://devops.aliyun.com"
            ;;
        "github")
            echo "1. 检查 git remote 配置"
            echo "2. 验证 GitHub CLI 认证状态：gh auth status"
            echo "3. 确认仓库访问权限"
            ;;
    esac

    echo ""
    echo "临时解决方案：删除 .claude/ccpm.yaml 回到默认模式"
}
```

## 命令集成示例

### 集成到现有 sync 命令

在 `.claude/commands/pm/sync.md` 文件开头添加：

```markdown
## Platform Detection Instructions

### 前置检查：平台配置检测
在执行任何同步操作前，必须先进行平台配置检测：

```bash
# 引入平台配置规则
source .claude/rules/platform-config.md

# 执行平台检测（复制上述前置检查指令模板）
# ... 平台检测逻辑 ...

# 根据平台类型选择执行逻辑
case "$PLATFORM_MODE" in
    "yunxiao")
        echo "🔄 执行云效平台同步逻辑..."
        # 引用云效同步规则
        # 详见：.claude/rules/platform-yunxiao-sync.md
        ;;
    "github")
        echo "🔄 执行 GitHub 平台同步逻辑..."
        # 继续原有 GitHub 同步逻辑...
        ;;
esac
```

### 原有指令保持不变
继续执行下面的原有同步指令...
```

## 扩展性设计

### 新平台支持

添加新平台支持的步骤：

1. **更新 YAML 配置模式**：在 `platform.type` 添加新值
2. **创建平台专用规则文件**：如 `.claude/rules/platform-{name}-sync.md`
3. **扩展前置检查逻辑**：在平台检测中添加新的 case 分支
4. **实现平台适配器**：按照现有 yunxiao 模式创建新的规则集

### 配置向前兼容

未来版本的配置向前兼容策略：

```yaml
# 版本标识
metadata:
  version: "1.0.0"    # 当前版本

# 向前兼容处理
compatibility:
  min_version: "1.0.0"    # 最小兼容版本
  deprecated_fields: []    # 已废弃字段列表
```

## 最佳实践

### 配置管理最佳实践

1. **版本控制**：
   - 将 `ccpm.yaml` 加入版本控制
   - 设置 `.claude/.config_cache` 到 `.gitignore`
   - 敏感信息（如 token）使用环境变量

2. **团队协作**：
   - 团队统一使用相同的平台配置
   - 通过 `features.strict_validation` 确保配置一致性
   - 在 CI/CD 中验证配置文件

3. **安全性**：
   - 不在配置文件中直接存储敏感信息
   - 使用环境变量管理访问令牌
   - 定期轮换访问令牌

4. **性能优化**：
   - 启用配置缓存减少重复解析
   - 在自动化脚本中使用快速模式
   - 合理设置超时和重试参数

## 故障排除

### 常见问题及解决方案

1. **YAML 语法错误**：
   ```bash
   # 验证 YAML 语法
   yq eval '.' .claude/ccpm.yaml
   ```

2. **平台检测失败**：
   ```bash
   # 调试模式运行
   CCPM_DEBUG=true /pm:sync
   ```

3. **权限问题**：
   ```bash
   # 检查访问权限
   case "$PLATFORM_TYPE" in
       "yunxiao") curl -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" https://devops.aliyun.com/api/v4/user ;;
       "github") gh auth status ;;
   esac
   ```

4. **配置冲突**：
   ```bash
   # 重置配置缓存
   rm -f .claude/.config_cache
   ```

## 版本历史

- **v1.0.0** (2025-09-28): 初始版本，支持 GitHub 和云效平台配置