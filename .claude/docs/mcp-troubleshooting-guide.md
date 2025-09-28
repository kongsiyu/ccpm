# 阿里云云效MCP连接故障排除指南

## 概述
本指南提供了阿里云云效MCP连接常见问题的诊断和解决方案，帮助用户快速解决连接、配置和使用过程中遇到的问题。

## 故障诊断流程

### 第一步：基础环境检查

#### 1.1 运行自动诊断
```bash
# Linux/macOS
bash .claude/scripts/mcp-yunxiao-check.sh

# Windows PowerShell
powershell -ExecutionPolicy Bypass -File .claude/scripts/mcp-yunxiao-quick-check.ps1
```

#### 1.2 手动环境检查
```bash
# 检查Node.js环境
node --version
npm --version

# 检查MCP服务器安装
which alibabacloud-devops-mcp-server
npm list -g alibabacloud-devops-mcp-server
```

### 第二步：配置文件验证

#### 2.1 Claude Code MCP配置检查
检查配置文件位置：
- **Windows**: `%USERPROFILE%\.config\claude-code\mcp.json`
- **macOS**: `~/.config/claude-code\mcp.json`
- **Linux**: `~/.config/claude-code\mcp.json`

#### 2.2 配置文件格式验证
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

### 第三步：连接测试

#### 3.1 基础连接测试
```bash
# 网络连接测试
ping devops.aliyuncs.com
curl -I https://devops.aliyuncs.com

# MCP服务器启动测试
timeout 5s alibabacloud-devops-mcp-server --help
```

## 常见问题及解决方案

### 问题1：MCP服务器未安装或找不到

**症状：**
- `which alibabacloud-devops-mcp-server` 返回未找到
- Claude Code提示MCP服务器连接失败

**解决方案：**

1. **全局安装MCP服务器**
   ```bash
   npm install -g alibabacloud-devops-mcp-server
   ```

2. **验证安装**
   ```bash
   alibabacloud-devops-mcp-server --version
   ```

3. **如果仍然找不到，检查PATH**
   ```bash
   # 查看npm全局安装路径
   npm config get prefix

   # 确保该路径在PATH环境变量中
   echo $PATH  # Linux/macOS
   echo $env:PATH  # Windows PowerShell
   ```

4. **使用npx作为替代**
   ```bash
   npx alibabacloud-devops-mcp-server --version
   ```

### 问题2：Claude Code配置文件问题

**症状：**
- Claude Code启动时提示MCP配置错误
- MCP工具不可用

**解决方案：**

1. **创建配置目录**
   ```bash
   # Linux/macOS
   mkdir -p ~/.config/claude-code

   # Windows
   mkdir "%USERPROFILE%\.config\claude-code"
   ```

2. **创建正确的配置文件**
   ```json
   {
     "mcpServers": {
       "alibabacloud-devops": {
         "command": "alibabacloud-devops-mcp-server",
         "args": [],
         "env": {
           "ALIBABA_CLOUD_ACCESS_KEY_ID": "your_access_key_id",
           "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "your_access_key_secret",
           "DEVOPS_ORG_ID": "your_organization_id"
         }
       }
     }
   }
   ```

3. **验证JSON格式**
   ```bash
   # 使用jq验证JSON格式
   cat ~/.config/claude-code/mcp.json | jq .
   ```

4. **重启Claude Code**

### 问题3：API认证失败

**症状：**
- MCP工具调用返回401 Unauthorized
- 提示访问密钥无效

**解决方案：**

1. **验证访问密钥**
   - 登录阿里云控制台
   - 检查AccessKey是否有效且未过期
   - 确认AccessKey权限包含云效API访问

2. **检查组织ID**
   ```bash
   # 在云效平台查看组织ID
   # 通常在URL中：https://devops.aliyun.com/organization/{ORG_ID}
   ```

3. **测试API访问**
   ```bash
   # 使用curl测试基础API访问
   curl -H "Authorization: acs your_access_key_id:signature" \
        "https://devops.aliyuncs.com/organization/{ORG_ID}/projects"
   ```

4. **更新配置并重启**

### 问题4：项目访问权限不足

**症状：**
- 可以连接但无法访问特定项目
- 提示403 Forbidden错误

**解决方案：**

1. **检查项目权限**
   - 确认账户在目标项目中有相应角色
   - 验证项目ID正确性

2. **验证项目配置**
   ```bash
   # 检查CCPM配置中的项目ID
   grep "project_id" .claude/ccpm.config
   ```

3. **联系项目管理员**
   - 请求必要的项目访问权限
   - 确认账户角色包含所需操作权限

### 问题5：网络连接问题

**症状：**
- 连接超时
- DNS解析失败
- 防火墙阻断

**解决方案：**

1. **检查网络连接**
   ```bash
   # 测试基础连通性
   ping devops.aliyuncs.com
   nslookup devops.aliyuncs.com
   ```

2. **检查防火墙设置**
   - 确保允许访问阿里云API端点
   - 检查企业防火墙规则

3. **配置代理（如需要）**
   ```bash
   # 设置HTTP代理
   export HTTP_PROXY=http://proxy.company.com:8080
   export HTTPS_PROXY=http://proxy.company.com:8080
   ```

4. **使用备用DNS**
   ```bash
   # 临时使用公共DNS
   echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
   ```

### 问题6：MCP工具调用失败

**症状：**
- 工具调用返回错误
- 参数验证失败
- 返回数据格式异常

**解决方案：**

1. **验证工具参数**
   ```javascript
   // 使用验证器检查工具调用
   node .claude/scripts/mcp-tools-validator.js
   ```

2. **检查工具可用性**
   - 确认所有5个核心工具都已正确安装
   - 验证工具版本兼容性

3. **查看详细错误日志**
   ```bash
   # 查看MCP日志
   tail -f ~/.claude/Cache/{project}/mcp-logs-ide/*.txt
   ```

4. **逐个测试工具**
   - 从简单的查询工具开始
   - 逐步测试写入和更新操作

## 预防性维护

### 定期检查清单

#### 每周检查
- [ ] MCP连接状态
- [ ] API密钥有效性
- [ ] 项目权限状态
- [ ] 日志文件大小

#### 每月检查
- [ ] MCP服务器版本更新
- [ ] 配置文件备份
- [ ] 性能指标回顾
- [ ] 安全审计

### 监控自动化

#### 健康检查脚本
```bash
#!/bin/bash
# 每日健康检查脚本

# 运行诊断
./claude/scripts/mcp-yunxiao-check.sh

# 检查结果
if [ $? -eq 0 ]; then
    echo "$(date): MCP连接健康" >> mcp-health.log
else
    echo "$(date): MCP连接异常" >> mcp-health.log
    # 发送告警通知
fi
```

## 支持资源

### 官方文档
- [阿里云云效文档](https://help.aliyun.com/product/153741.html)
- [Model Context Protocol规范](https://modelcontextprotocol.io/)
- [Claude Code用户指南](https://claude.com/claude-code)

### 社区支持
- 云效用户群
- GitHub Issues
- 技术论坛

### 联系支持
如果以上解决方案都无法解决问题，请：
1. 收集详细的错误日志
2. 记录重现步骤
3. 联系技术支持团队
4. 提供环境信息和配置详情