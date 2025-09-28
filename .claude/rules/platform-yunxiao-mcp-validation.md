# 阿里云云效平台MCP连接验证规则

## 概述
本文档定义了与阿里云云效平台集成的MCP (Model Context Protocol) 连接验证和故障排除规则，为CCPM工具提供标准化的云效平台连接诊断流程。

## MCP服务器环境检查

### 前置条件验证
在使用云效平台功能前，需要验证以下环境要求：

#### 1. MCP服务器安装检查
```bash
# 检查alibabacloud-devops-mcp-server是否已安装
which alibabacloud-devops-mcp-server

# 如果未安装，通过npm安装
npm install -g alibabacloud-devops-mcp-server

# 或通过npx使用
npx alibabacloud-devops-mcp-server --version
```

#### 2. Claude Code MCP配置检查
检查以下路径的MCP配置文件：
- Windows: `%APPDATA%\claude-code\mcp.json`
- macOS/Linux: `~/.config/claude-code/mcp.json`

**标准配置格式：**
```json
{
  "mcpServers": {
    "alibabacloud-devops": {
      "command": "alibabacloud-devops-mcp-server",
      "args": [],
      "env": {
        "ALIBABA_CLOUD_ACCESS_KEY_ID": "your_access_key",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "your_secret_key",
        "DEVOPS_ORG_ID": "your_org_id"
      }
    }
  }
}
```

## 核心工具可用性验证

### 必需MCP工具清单
以下工具必须在alibabacloud-devops-mcp-server中可用：

1. **alibabacloud_devops_get_project_info** - 获取项目信息
2. **create_work_item** - 创建工作项
3. **search_workitems** - 搜索工作项
4. **update_work_item** - 更新工作项
5. **create_work_item_comment** - 添加工作项评论

### 基础连接测试流程

#### 第一步：MCP服务器连接测试
```markdown
测试目标：验证MCP服务器能够正常启动和响应
期望结果：服务器启动无错误，能够接收和响应请求

故障排除：
- 检查网络连接
- 验证服务器安装完整性
- 确认端口未被占用
```

#### 第二步：API认证验证
```markdown
测试工具：alibabacloud_devops_get_project_info
测试参数：project_id (从项目配置获取)
期望结果：成功返回项目信息，无认证错误

故障排除：
- 验证ACCESS_KEY_ID和ACCESS_KEY_SECRET正确性
- 检查组织ID (ORG_ID) 配置
- 确认账户权限包含云效API访问
```

#### 第三步：工具调用响应测试
```markdown
逐一测试每个核心工具：
1. search_workitems - 验证搜索功能
2. create_work_item - 验证创建权限
3. update_work_item - 验证更新权限
4. create_work_item_comment - 验证评论权限

每个工具测试包含：
- 正常调用场景
- 错误参数场景
- 权限不足场景
```

## 连接诊断机制

### 自动诊断检查点

#### 1. 环境配置诊断
- [ ] MCP服务器安装状态
- [ ] Claude Code配置文件存在性
- [ ] 必需环境变量完整性
- [ ] 网络连接可达性

#### 2. API认证诊断
- [ ] 访问密钥有效性
- [ ] 组织ID正确性
- [ ] 账户权限范围
- [ ] API配额状态

#### 3. 工具功能诊断
- [ ] 核心工具可用性
- [ ] 工具响应时间
- [ ] 错误处理机制
- [ ] 数据返回完整性

### 故障排除指南

#### 常见问题及解决方案

**问题1：MCP服务器未找到**
```
症状：which alibabacloud-devops-mcp-server 返回未找到
解决方案：
1. 安装MCP服务器：npm install -g alibabacloud-devops-mcp-server
2. 检查PATH环境变量
3. 尝试使用npx运行
```

**问题2：认证失败**
```
症状：API调用返回认证错误
解决方案：
1. 验证ACCESS_KEY_ID和ACCESS_KEY_SECRET
2. 检查密钥是否已过期
3. 确认账户是否有云效API权限
4. 验证组织ID配置正确
```

**问题3：工具调用超时**
```
症状：MCP工具调用超时或无响应
解决方案：
1. 检查网络连接稳定性
2. 验证云效服务状态
3. 增加超时时间配置
4. 检查防火墙设置
```

**问题4：权限不足**
```
症状：能连接但无法执行特定操作
解决方案：
1. 检查账户在云效项目中的角色
2. 验证项目访问权限
3. 确认操作权限范围
4. 联系项目管理员分配权限
```

## 配置验证脚本

### 快速验证命令
```bash
# 环境检查
echo "检查MCP服务器安装..."
which alibabacloud-devops-mcp-server && echo "✓ MCP服务器已安装" || echo "✗ MCP服务器未安装"

# 配置文件检查
echo "检查Claude Code配置..."
if [ -f ~/.config/claude-code/mcp.json ]; then
    echo "✓ MCP配置文件存在"
    # 验证配置格式
    cat ~/.config/claude-code/mcp.json | jq '.mcpServers.["alibabacloud-devops"]' && echo "✓ 云效配置正确" || echo "✗ 云效配置缺失"
else
    echo "✗ MCP配置文件不存在"
fi
```

## 用户配置指导

### 初次配置步骤

1. **安装MCP服务器**
   ```bash
   npm install -g alibabacloud-devops-mcp-server
   ```

2. **获取阿里云API密钥**
   - 登录阿里云控制台
   - 访问AccessKey管理页面
   - 创建新的AccessKey对

3. **配置Claude Code**
   - 创建MCP配置文件
   - 填入API密钥和组织信息
   - 重启Claude Code

4. **验证连接**
   - 测试基础连接
   - 验证工具可用性
   - 确认权限正常

### 配置模板

#### 基础配置模板
```json
{
  "mcpServers": {
    "alibabacloud-devops": {
      "command": "alibabacloud-devops-mcp-server",
      "args": [],
      "env": {
        "ALIBABA_CLOUD_ACCESS_KEY_ID": "LTAI***",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "***",
        "DEVOPS_ORG_ID": "5f5a***"
      }
    }
  }
}
```

#### 项目特定配置
```json
{
  "mcpServers": {
    "alibabacloud-devops": {
      "command": "alibabacloud-devops-mcp-server",
      "args": [],
      "env": {
        "ALIBABA_CLOUD_ACCESS_KEY_ID": "LTAI***",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "***",
        "DEVOPS_ORG_ID": "5f5a***",
        "DEFAULT_PROJECT_ID": "project_id_from_ccpm_config"
      }
    }
  }
}
```

## 监控和维护

### 日志检查
定期检查MCP连接日志：
- 位置：`~/.claude/Cache/{project}/mcp-logs-ide/`
- 关注：连接错误、超时、认证失败

### 性能监控
监控以下指标：
- MCP工具响应时间
- API调用成功率
- 错误频率和类型
- 网络延迟

### 定期验证
建议每周进行：
- 连接状态检查
- 工具功能验证
- 配置有效性确认
- 日志清理

## 集成说明

本MCP验证规则与CCPM系统集成：
- 继承`.claude/ccpm.config`中的项目配置
- 与平台检测机制协调工作
- 支持多项目环境切换
- 提供统一的错误处理和用户反馈