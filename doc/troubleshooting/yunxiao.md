# CCPM 云效平台故障排查指南

本文档提供CCPM与阿里云云效平台集成时常见问题的诊断和解决方案。

## 目录
- [快速诊断](#快速诊断)
- [连接问题](#连接问题)
- [认证和权限问题](#认证和权限问题)
- [配置问题](#配置问题)
- [同步问题](#同步问题)
- [性能问题](#性能问题)
- [数据一致性问题](#数据一致性问题)
- [调试工具和技巧](#调试工具和技巧)

---

## 快速诊断

### 一键健康检查

```bash
# 执行系统健康检查
/pm:health-check

# 详细诊断报告
/pm:diagnose --verbose

# 连接测试
/pm:connection-test
```

**健康检查输出示例**:
```
🔍 CCPM 健康检查报告
========================

✅ 配置文件: 有效
✅ MCP连接: 正常
✅ 云效API: 可访问
❌ 项目权限: 访问被拒绝
⚠️  缓存状态: 部分失效

🎯 建议操作:
1. 检查访问令牌权限
2. 清理过期缓存
```

### 常见问题快速检查清单

- [ ] MCP服务器是否正常运行？
- [ ] 访问令牌是否有效？
- [ ] 项目ID是否正确？
- [ ] 网络连接是否正常？
- [ ] 配置文件语法是否正确？
- [ ] 权限设置是否充足？

---

## 连接问题

### 问题1：MCP服务器连接失败

**症状**:
```
❌ 错误: 无法连接到云效MCP服务器
连接超时或拒绝连接
```

**可能原因**:
1. MCP服务器未启动
2. 网络连接问题
3. 防火墙阻挡
4. 端口配置错误

**诊断步骤**:

```bash
# 1. 检查MCP服务器状态
ps aux | grep devops-mcp-server

# 2. 检查端口占用
netstat -tlnp | grep :3000

# 3. 测试网络连接
ping devops.aliyun.com
telnet devops.aliyun.com 443

# 4. 检查MCP配置
/mcp:status
```

**解决方案**:

```bash
# 方案1: 重启MCP服务器
sudo systemctl restart devops-mcp-server

# 方案2: 检查并修复配置
nano ~/.config/claude-code/mcp-config.json

# 方案3: 重新安装MCP服务器
npm uninstall -g @alicloud/devops-mcp-server
npm install -g @alicloud/devops-mcp-server@latest

# 方案4: 检查防火墙设置
sudo ufw status
sudo iptables -L
```

### 问题2：API端点无法访问

**症状**:
```
❌ 错误: API请求失败
HTTP 503 Service Unavailable
```

**诊断步骤**:

```bash
# 1. 测试API端点可访问性
curl -I https://devops.aliyun.com

# 2. 检查DNS解析
nslookup devops.aliyun.com

# 3. 检查代理设置
echo $HTTP_PROXY
echo $HTTPS_PROXY

# 4. 测试具体API调用
curl -H "Authorization: Bearer $TOKEN" \
     https://devops.aliyun.com/api/v1/projects
```

**解决方案**:

```yaml
# 在配置文件中添加代理设置
api:
  endpoint: "https://devops.aliyun.com"
  proxy:
    http: "http://proxy.company.com:8080"
    https: "https://proxy.company.com:8080"
  timeout: 60000  # 增加超时时间
```

---

## 认证和权限问题

### 问题3：访问令牌无效

**症状**:
```
❌ 错误: 认证失败
HTTP 401 Unauthorized
Invalid or expired access token
```

**诊断步骤**:

```bash
# 1. 检查令牌格式
echo $YUNXIAO_ACCESS_TOKEN | wc -c

# 2. 验证令牌有效性
curl -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
     https://devops.aliyun.com/api/v1/user/info

# 3. 检查令牌权限范围
/pm:token-info
```

**解决方案**:

```bash
# 1. 重新生成访问令牌
# 登录云效控制台 → 个人设置 → 访问令牌 → 创建新令牌

# 2. 更新环境变量
export YUNXIAO_ACCESS_TOKEN="new-token-here"

# 3. 或更新配置文件
cat << EOF > .ccpm-secrets.env
YUNXIAO_ACCESS_TOKEN=new-token-here
YUNXIAO_PROJECT_ID=12345678
EOF

# 4. 验证新令牌
/pm:platform-status
```

### 问题4：项目权限不足

**症状**:
```
❌ 错误: 权限不足
您没有访问此项目的权限
```

**诊断步骤**:

```bash
# 1. 检查项目ID是否正确
/pm:config-show | grep project_id

# 2. 验证项目权限
curl -H "Authorization: Bearer $TOKEN" \
     https://devops.aliyun.com/api/v1/projects/12345678

# 3. 检查用户角色
/pm:user-permissions
```

**解决方案**:

1. **联系项目管理员添加权限**:
   - 登录云效控制台
   - 进入项目设置 → 成员管理
   - 添加用户并分配适当角色

2. **验证项目ID**:
   ```bash
   # 检查项目URL中的ID
   # https://devops.aliyun.com/projex/12345678/summary
   # 项目ID应为: 12345678
   ```

3. **使用正确的项目配置**:
   ```yaml
   platform: yunxiao
   project_id: 12345678  # 确保这是正确的项目ID
   ```

---

## 配置问题

### 问题5：配置文件语法错误

**症状**:
```
❌ 错误: 配置文件解析失败
YAML syntax error at line 15
```

**诊断步骤**:

```bash
# 1. 验证YAML语法
/pm:config-validate

# 2. 使用在线YAML验证器
# 复制配置内容到 https://yamlchecker.com/

# 3. 检查特殊字符
cat -A .ccpm-config.yaml | head -20
```

**解决方案**:

```bash
# 1. 备份当前配置
cp .ccpm-config.yaml .ccpm-config.yaml.backup

# 2. 使用配置模板重新创建
cp .claude/docs/examples/.ccpm-config.yaml.example .ccpm-config.yaml

# 3. 逐步添加自定义配置
# 每次添加后验证语法
/pm:config-validate

# 4. 常见语法问题修复
sed -i 's/\t/  /g' .ccpm-config.yaml  # 将tab替换为空格
sed -i 's/：/:/g' .ccpm-config.yaml   # 将中文冒号替换为英文冒号
```

### 问题6：环境变量未设置

**症状**:
```
❌ 错误: 配置变量未定义
YUNXIAO_ACCESS_TOKEN is not set
```

**解决方案**:

```bash
# 1. 设置必需的环境变量
export YUNXIAO_ACCESS_TOKEN="your-access-token"
export YUNXIAO_PROJECT_ID="12345678"

# 2. 持久化环境变量
echo 'export YUNXIAO_ACCESS_TOKEN="your-access-token"' >> ~/.bashrc
echo 'export YUNXIAO_PROJECT_ID="12345678"' >> ~/.bashrc
source ~/.bashrc

# 3. 或使用.env文件
cat << EOF > .ccpm-secrets.env
YUNXIAO_ACCESS_TOKEN=your-access-token
YUNXIAO_PROJECT_ID=12345678
EOF

# 4. 在配置文件中引用
cat << EOF >> .ccpm-config.yaml
api:
  token: "\${YUNXIAO_ACCESS_TOKEN}"
  project_id: "\${YUNXIAO_PROJECT_ID}"
EOF
```

---

## 同步问题

### 问题7：工作项同步失败

**症状**:
```
❌ 错误: 同步失败
部分工作项未能同步到云效平台
```

**诊断步骤**:

```bash
# 1. 检查同步状态
/pm:sync-status

# 2. 查看同步日志
tail -50 .ccpm.log | grep sync

# 3. 手动测试同步
/pm:sync --dry-run --verbose

# 4. 检查API限制
/pm:api-rate-limit
```

**解决方案**:

```bash
# 1. 重试失败的同步
/pm:sync --retry-failed

# 2. 分批同步
/pm:sync --batch-size=10

# 3. 清理并重新同步
/pm:sync --clean --full

# 4. 调整同步策略
cat << EOF >> .ccpm-config.yaml
sync:
  strategy: "incremental"  # 或 "full"
  batch_size: 20
  retry_attempts: 5
  backoff_delay: 2000
EOF
```

### 问题8：数据冲突处理

**症状**:
```
⚠️  警告: 检测到数据冲突
本地Epic状态与云效平台不一致
```

**诊断步骤**:

```bash
# 1. 查看冲突详情
/pm:conflict-report

# 2. 比较本地和远程状态
/pm:diff local remote

# 3. 检查最后同步时间
/pm:sync-history
```

**解决方案**:

```bash
# 1. 手动解决冲突
/pm:resolve-conflicts --interactive

# 2. 强制以本地为准
/pm:sync --force-local

# 3. 强制以远程为准
/pm:sync --force-remote

# 4. 备份后重置
/pm:backup current-state.json
/pm:reset --to-remote
```

---

## 性能问题

### 问题9：响应速度慢

**症状**:
```
⚠️  警告: API响应时间过长
平均响应时间: 15秒 (预期: <3秒)
```

**诊断步骤**:

```bash
# 1. 性能分析
/pm:performance-report

# 2. 网络延迟测试
ping devops.aliyun.com
traceroute devops.aliyun.com

# 3. 检查缓存状态
/pm:cache-stats

# 4. API调用频率分析
/pm:api-usage-report
```

**优化方案**:

```yaml
# 1. 启用缓存优化
cache:
  enabled: true
  ttl: 600
  strategy: "lru"
  max_size: 2000

# 2. 调整批处理设置
performance:
  batch_size: 100
  concurrent_requests: 10
  request_timeout: 30000

# 3. 启用压缩
api:
  compression: true
  keep_alive: true
  http2: true

# 4. 本地缓存策略
local_cache:
  enabled: true
  directory: ".ccpm-cache"
  max_age: 3600
```

### 问题10：内存使用过高

**症状**:
```
⚠️  警告: 内存使用率高
当前内存使用: 2.5GB (可用: 1GB)
```

**诊断和解决**:

```bash
# 1. 检查内存使用
/pm:memory-usage

# 2. 清理缓存
/pm:cache-clear

# 3. 减少批处理大小
cat << EOF >> .ccpm-config.yaml
performance:
  batch_size: 20  # 减少批处理大小
  max_concurrent: 3  # 减少并发数
EOF

# 4. 启用内存监控
/pm:memory-monitor --enable
```

---

## 数据一致性问题

### 问题11：Epic状态不一致

**症状**:
```
⚠️  警告: Epic状态不一致
本地状态: completed
云效状态: in-progress
```

**解决方案**:

```bash
# 1. 强制状态同步
/pm:force-sync epic-name

# 2. 手动校正状态
/pm:epic-status epic-name --set completed

# 3. 重建状态映射
/pm:rebuild-status-mapping

# 4. 验证数据一致性
/pm:validate-consistency
```

### 问题12：工作项丢失

**症状**:
```
❌ 错误: 工作项未找到
Issue #123 在云效平台中不存在
```

**恢复方案**:

```bash
# 1. 搜索丢失的工作项
/pm:search-missing-items

# 2. 从备份恢复
/pm:restore-from-backup backup-20241201.json

# 3. 重新创建丢失的工作项
/pm:recreate-missing --confirm

# 4. 验证恢复结果
/pm:validate-restore
```

---

## 调试工具和技巧

### 启用调试模式

```bash
# 1. 临时启用调试
/pm:debug --enable

# 2. 在配置文件中启用
cat << EOF >> .ccpm-config.yaml
debug:
  enabled: true
  verbose: true
  log_level: "debug"
  trace_api_calls: true
EOF

# 3. 查看详细日志
tail -f .ccpm.log
```

### 网络调试

```bash
# 1. 启用网络追踪
/pm:network-trace --enable

# 2. 使用curl模拟API调用
curl -v -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     https://devops.aliyun.com/api/v1/projects/12345678

# 3. 使用tcpdump监控网络流量
sudo tcpdump -i any host devops.aliyun.com
```

### 日志分析

```bash
# 1. 错误日志过滤
grep "ERROR" .ccpm.log | tail -20

# 2. API调用日志
grep "API_CALL" .ccpm.log | tail -10

# 3. 性能分析
grep "PERFORMANCE" .ccpm.log | awk '{print $3}' | sort -n

# 4. 生成日志报告
/pm:log-report --last-24h
```

### 配置调试

```bash
# 1. 配置文件验证
/pm:config-validate --verbose

# 2. 配置变量展开测试
/pm:config-expand-test

# 3. 权限测试
/pm:permission-test

# 4. 连接测试
/pm:connection-test --detailed
```

## 常见错误代码解释

| 错误代码 | 含义 | 解决方案 |
|---------|------|----------|
| CCPM_001 | 配置文件不存在 | 运行 `/pm:init` 创建配置 |
| CCPM_002 | MCP连接失败 | 检查MCP服务器状态 |
| CCPM_003 | API认证失败 | 检查访问令牌 |
| CCPM_004 | 项目权限不足 | 联系管理员添加权限 |
| CCPM_005 | 网络连接超时 | 检查网络和防火墙设置 |
| CCPM_006 | 数据同步冲突 | 运行冲突解决流程 |
| CCPM_007 | 配置语法错误 | 验证YAML语法 |
| CCPM_008 | 缓存损坏 | 清理并重建缓存 |

## 获取帮助

### 社区资源

- **官方文档**: [https://github.com/kongsiyu/ccpm](https://github.com/kongsiyu/ccpm)
- **问题反馈**: [https://github.com/kongsiyu/ccpm/issues](https://github.com/kongsiyu/ccpm/issues)
- **讨论社区**: [https://github.com/kongsiyu/ccpm/discussions](https://github.com/kongsiyu/ccpm/discussions)

### 支持命令

```bash
# 生成支持报告
/pm:support-report

# 收集诊断信息
/pm:collect-diagnostics

# 导出配置和日志
/pm:export-debug-info debug-package.tar.gz
```

### 联系支持

如果问题仍未解决，请：

1. 运行 `/pm:support-report` 生成详细报告
2. 在GitHub上创建Issue并附上报告
3. 提供问题复现步骤和环境信息

---

> 💡 **提示**: 定期运行 `/pm:health-check` 可以预防大多数问题。建议设置定时检查以及时发现和解决潜在问题。