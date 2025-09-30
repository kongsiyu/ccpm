# CCPM 云效平台集成指南

本文档提供完整的阿里云云效平台集成配置指南，包括环境准备、详细配置步骤、使用示例和最佳实践。

## 概述

CCPM (Cloud Code Project Manager) 支持与阿里云云效平台的深度集成，允许用户：

- 将GitHub工作流迁移到云效平台
- 统一管理PRD、Epic、Task和WorkItem
- 通过Claude Code实现自动化项目管理
- 支持多平台混合开发环境

## 环境准备检查清单

### 必需组件

- [ ] **Node.js 16+** 已安装并配置
- [ ] **阿里云云效MCP服务器** 已按照[官方文档](https://www.alibabacloud.com/help/codeup/mcp-server)配置
- [ ] **Claude Code** 已安装并连接到云效MCP服务器
- [ ] **CCPM系统** 基础环境已就绪

### 可选组件

- [ ] **Docker环境** 用于隔离测试和部署
- [ ] **Git多worktree支持** 用于高级分支管理
- [ ] **IDE集成配置** (VS Code, JetBrains等)

### MCP服务验证

在开始配置前，请确认以下服务状态：

```bash
# 检查MCP服务器连接状态
# 在Claude Code中运行以下命令验证连接
/mcp:status

# 预期输出：云效MCP服务器连接正常
```

## 详细配置步骤

### 步骤1：配置MCP服务器

1. **安装阿里云云效MCP服务器**

   按照[阿里云官方MCP服务器文档](https://www.alibabacloud.com/help/codeup/mcp-server)进行安装和配置。

2. **配置Claude Code连接**

   在Claude Code的MCP配置中添加云效服务器：
   ```json
   {
     "mcpServers": {
       "yunxiao": {
         "command": "npx",
         "args": ["@alicloud/devops-mcp-server"],
         "env": {
           "YUNXIAO_ACCESS_TOKEN": "your-access-token",
           "YUNXIAO_PROJECT_ID": "your-project-id"
         }
       }
     }
   }
   ```

3. **验证MCP连接**

   在Claude Code中测试连接：
   ```bash
   # 检查MCP服务器状态
   /mcp:test-connection yunxiao
   ```

### 步骤2：创建CCPM配置文件

在项目根目录创建 `.ccpm-config.yaml` 文件：

```yaml
# CCPM 云效平台配置
platform: yunxiao
project_id: 12345678  # 替换为实际的云效项目ID

# API配置
api:
  endpoint: "https://devops.aliyun.com"
  timeout: 30000
  retry_attempts: 3

# 缓存配置
cache:
  enabled: true
  ttl: 300  # 5分钟缓存

# 重试策略
retry:
  max_attempts: 3
  backoff_ms: 1000
  exponential: true

# 日志配置
logging:
  level: info
  file: .ccpm.log
```

### 步骤3：初始化CCPM

```bash
# 初始化CCPM配置
/pm:init

# 验证平台配置
/pm:platform-status

# 预期输出：
# ✅ 云效平台连接正常
# ✅ 项目权限验证通过
# ✅ CCPM配置文件有效
```

### 步骤4：验证集成

运行以下命令验证集成是否成功：

```bash
# 查看当前平台状态
/pm:status

# 测试工作项同步
/pm:sync --dry-run

# 查看可用命令
/pm:help
```

## 基础使用示例

### 示例1：创建PRD并启动Epic

```bash
# 1. 创建产品需求文档
/pm:prd-new feature-user-authentication

# 2. 编辑PRD内容
/pm:prd-edit feature-user-authentication

# 3. 启动Epic
/pm:epic-start feature-user-authentication

# 4. 同步到云效平台
/pm:epic-sync

# 5. 查看工作项状态
/pm:status
```

### 示例2：管理开发进度

```bash
# 查看进行中的工作
/pm:in-progress

# 查看下一个任务
/pm:next

# 更新任务状态
/pm:issue-status 123 in-progress

# 生成每日站会报告
/pm:standup
```

### 示例3：Epic完成和合并

```bash
# 查看Epic状态
/pm:epic-status feature-user-authentication

# 执行Epic合并
/pm:epic-merge feature-user-authentication

# 清理完成的Epic
/pm:clean
```

## 高级配置

### 多项目环境配置

如果需要管理多个项目，可以为不同项目创建独立的配置：

```yaml
# 项目A：使用云效平台
# project-a/.ccpm-config.yaml
platform: yunxiao
project_id: 12345678
api:
  endpoint: "https://devops.aliyun.com"

---

# 项目B：使用GitHub
# project-b/.ccpm-config.yaml
platform: github
repository: "owner/repo"
api:
  endpoint: "https://api.github.com"
```

### 团队协作配置

```yaml
# 团队协作设置
team:
  members:
    - name: "张三"
      role: "product-manager"
      yunxiao_id: "user123"
    - name: "李四"
      role: "developer"
      yunxiao_id: "user456"

# 工作流配置
workflow:
  auto_assign: true
  review_required: true
  testing_required: true
```

### 性能优化配置

```yaml
# 性能优化设置
performance:
  # 批量操作设置
  batch_size: 50
  concurrent_requests: 5

  # 缓存优化
  cache:
    enabled: true
    strategy: "lru"
    max_size: 1000

  # 网络优化
  network:
    keep_alive: true
    timeout: 30000
    compression: true
```

## 迁移指南

### 从GitHub迁移到云效

1. **导出GitHub数据**
   ```bash
   # 导出当前项目状态
   /pm:export github-data.json
   ```

2. **配置云效平台**
   ```bash
   # 切换到云效平台
   /pm:platform-switch yunxiao

   # 验证配置
   /pm:platform-status
   ```

3. **导入数据**
   ```bash
   # 导入之前导出的数据
   /pm:import github-data.json

   # 验证导入结果
   /pm:validate
   ```

4. **同步工作项**
   ```bash
   # 执行全量同步
   /pm:sync --full

   # 检查同步状态
   /pm:sync-status
   ```

### 混合环境管理

对于需要同时使用GitHub和云效的团队：

```yaml
# 混合环境配置
environments:
  development:
    platform: github
    repository: "owner/repo"
    branch_prefix: "dev/"

  staging:
    platform: yunxiao
    project_id: 12345678
    branch_prefix: "staging/"

  production:
    platform: yunxiao
    project_id: 12345678
    branch_prefix: "release/"
```

## 安全配置

### 访问令牌管理

```bash
# 设置访问令牌（推荐使用环境变量）
export YUNXIAO_ACCESS_TOKEN="your-secure-token"
export YUNXIAO_PROJECT_ID="12345678"

# 或者使用配置文件（仅用于开发环境）
echo "YUNXIAO_ACCESS_TOKEN=your-secure-token" > .env
echo "YUNXIAO_PROJECT_ID=12345678" >> .env
```

### 权限配置

确保云效项目中配置了适当的权限：

- **项目管理员**：可以创建、修改、删除所有工作项
- **开发人员**：可以创建、修改自己的工作项
- **查看者**：只能查看工作项状态

### 审计日志

```yaml
# 审计配置
audit:
  enabled: true
  log_file: "ccpm-audit.log"
  log_level: "info"
  include_sensitive: false
```

## 监控和诊断

### 健康检查

```bash
# 系统健康检查
/pm:health-check

# 详细诊断
/pm:diagnose

# 性能分析
/pm:performance-report
```

### 日志管理

```bash
# 查看最近的日志
tail -f .ccpm.log

# 搜索特定错误
grep "ERROR" .ccpm.log

# 清理旧日志
/pm:log-rotate
```

## 最佳实践

### 命名规范

- **PRD文件名**：使用kebab-case格式，如 `user-authentication-system`
- **Epic分支**：使用前缀 `epic/`，如 `epic/user-authentication-system`
- **工作项标题**：简洁明了，包含功能描述

### 工作流程

1. **需求分析阶段**
   - 创建PRD文档
   - 需求评审和确认
   - 技术方案设计

2. **开发阶段**
   - 启动Epic
   - 分解任务
   - 开发和测试

3. **交付阶段**
   - 代码审查
   - 集成测试
   - 部署和验收

### 团队协作

- 定期执行 `/pm:standup` 生成进度报告
- 使用 `/pm:sync` 保持工作项状态同步
- 利用 `/pm:next` 规划每日工作

### 数据备份

```bash
# 定期备份配置和数据
/pm:backup backup-$(date +%Y%m%d).tar.gz

# 验证备份完整性
/pm:verify-backup backup-20241201.tar.gz
```

## 更新和维护

### 版本升级

```bash
# 检查当前版本
/pm:version

# 更新CCPM
npm update @ccpm/cli

# 重新初始化配置
/pm:re-init
```

### 配置维护

```bash
# 验证配置文件
/pm:validate-config

# 重新加载配置
/pm:reload-config

# 重置配置到默认值
/pm:reset-config
```

## 社区支持

- **官方文档**：[https://github.com/kongsiyu/ccpm](https://github.com/kongsiyu/ccpm)
- **问题反馈**：[https://github.com/kongsiyu/ccpm/issues](https://github.com/kongsiyu/ccpm/issues)
- **讨论社区**：[https://github.com/kongsiyu/ccpm/discussions](https://github.com/kongsiyu/ccpm/discussions)
- **更新日志**：[https://github.com/kongsiyu/ccpm/releases](https://github.com/kongsiyu/ccpm/releases)

---

> 💡 **提示**: 如果在配置过程中遇到问题，请参考[故障排查指南](troubleshooting/yunxiao.md)或查看[快速开始指南](yunxiao-quickstart.md)。