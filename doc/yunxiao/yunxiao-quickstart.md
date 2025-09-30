# CCPM 云效平台快速开始指南

本指南帮助您在5分钟内完成CCPM与阿里云云效平台的基础配置，快速上手项目管理功能。

## 前提条件

在开始之前，请确保您已经：

- ✅ 安装了Node.js 16+
- ✅ 安装了Claude Code
- ✅ 拥有阿里云云效项目的访问权限
- ✅ 获得了云效项目的访问令牌

## 5分钟快速配置

### 步骤1：安装云效MCP服务器 (2分钟)

```bash
# 安装阿里云云效MCP服务器
npm install -g @alicloud/devops-mcp-server

# 验证安装
devops-mcp-server --version
```

### 步骤2：配置Claude Code MCP连接 (2分钟)

在Claude Code的配置中添加云效MCP服务器：

```json
{
  "mcpServers": {
    "yunxiao": {
      "command": "devops-mcp-server",
      "env": {
        "YUNXIAO_ACCESS_TOKEN": "your-access-token-here",
        "YUNXIAO_PROJECT_ID": "your-project-id-here"
      }
    }
  }
}
```

**获取访问令牌方式：**
1. 登录阿里云云效控制台
2. 进入项目设置 → API访问
3. 创建个人访问令牌
4. 复制令牌并替换上述配置中的 `your-access-token-here`

### 步骤3：创建CCPM配置文件 (1分钟)

在您的项目根目录创建 `.ccpm-config.yaml`：

```yaml
# 基础配置
platform: yunxiao
project_id: 12345678  # 替换为您的云效项目ID

# 简化配置（其他选项使用默认值）
cache:
  enabled: true
  ttl: 300
```

**查找项目ID方式：**
- 在云效项目页面的URL中找到项目ID
- 例如：`https://devops.aliyun.com/projex/12345678/summary`
- 项目ID即为 `12345678`

## 验证配置

### 测试MCP连接

在Claude Code中运行：

```bash
# 测试云效MCP服务器连接
/mcp:status

# 预期输出：
# ✅ yunxiao MCP服务器连接正常
```

### 初始化CCPM

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

## 基本命令使用

### 创建第一个PRD

```bash
# 创建产品需求文档
/pm:prd-new my-first-feature

# 查看创建的PRD
/pm:prd-list
```

### 启动第一个Epic

```bash
# 启动Epic开发
/pm:epic-start my-first-feature

# 同步到云效平台
/pm:epic-sync

# 查看状态
/pm:status
```

### 查看帮助

```bash
# 查看所有可用命令
/pm:help

# 查看特定命令帮助
/pm:help epic-start
```

## 常见验证检查

如果遇到问题，请依次检查：

### 1. MCP服务器状态
```bash
# 检查MCP服务器是否正常运行
ps aux | grep devops-mcp-server

# 如果未运行，重启Claude Code
```

### 2. 访问令牌权限
```bash
# 在云效控制台验证令牌是否有效
# 检查令牌是否包含项目访问权限
```

### 3. 项目ID正确性
```bash
# 验证项目ID是否正确
/pm:platform-status

# 如果显示"项目不存在"，请检查project_id配置
```

### 4. 网络连接
```bash
# 测试到阿里云的网络连接
ping devops.aliyun.com
```

## 下一步建议

配置完成后，您可以：

1. **深入了解功能**
   - 阅读[完整集成指南](yunxiao-integration.md)
   - 查看[工作流示例](examples/workflow-examples.md)

2. **配置团队环境**
   - 设置[多项目配置](examples/multi-project-setup.md)
   - 配置团队协作规范

3. **优化使用体验**
   - 启用缓存和性能优化
   - 配置自动化工作流

4. **学习高级功能**
   - Epic分解和管理
   - 自动化状态同步
   - 进度报告生成

## 故障排查

如果快速配置遇到问题：

### MCP连接失败
**症状**: Claude Code无法连接到云效MCP服务器

**解决方案**:
1. 检查MCP服务器是否正确安装
2. 验证环境变量配置
3. 重启Claude Code

### 项目访问被拒绝
**症状**: 显示"无权限访问项目"

**解决方案**:
1. 检查访问令牌是否有效
2. 确认令牌包含项目访问权限
3. 验证项目ID是否正确

### 配置文件错误
**症状**: CCPM初始化失败

**解决方案**:
1. 检查YAML语法是否正确
2. 验证必需字段是否完整
3. 使用配置模板重新创建

### 更多问题
如果问题仍未解决，请查看[详细故障排查指南](troubleshooting/yunxiao.md)。

## 支持资源

- 📖 [完整文档](yunxiao-integration.md)
- 🔧 [故障排查](troubleshooting/yunxiao.md)
- 💡 [使用示例](examples/)
- 🐛 [问题反馈](https://github.com/kongsiyu/ccpm/issues)

---

> 🎉 **恭喜！** 您已成功完成CCPM云效平台的快速配置。现在可以开始使用CCPM管理您的项目了！