# 云效平台同步规则

阿里云云效 (Yunxiao) 平台的同步规则和工作项映射配置。

## 概述

此规则文件定义了与阿里云云效平台的集成规则，包括工作项类型映射、状态同步和数据格式转换。云效平台使用与 GitHub 不同的工作项结构和工作流，需要专门的映射规则。

## 平台特性

### 云效工作项类型
- **需求 (Requirement)**: 对应业务需求和用户故事
- **任务 (Task)**: 具体的开发任务和技术实现
- **缺陷 (Bug)**: 缺陷和问题修复
- **子任务 (Subtask)**: 任务的细分项

### 云效状态流转
```
待处理 → 进行中 → 待验收 → 已完成
   ↓       ↓       ↓
  已关闭   已关闭   已关闭
```

## 映射规则定义

### GitHub到云效的工作项类型映射
```yaml
mapping:
  github_issue_to_yunxiao:
    issue: "任务"  # Task
    enhancement: "需求"  # Requirement
    bug: "缺陷"  # Bug
    subtask: "子任务"  # Subtask
```

### 状态映射规则
```yaml
status_mapping:
  github_to_yunxiao:
    open: "待处理"
    "in progress": "进行中"
    "in review": "待验收"
    closed: "已完成"

  yunxiao_to_github:
    "待处理": "open"
    "进行中": "in progress"
    "待验收": "in review"
    "已完成": "closed"
    "已关闭": "closed"
```

### 优先级映射
```yaml
priority_mapping:
  github_to_yunxiao:
    low: "低"
    medium: "中"
    high: "高"
    urgent: "紧急"

  yunxiao_to_github:
    "低": "low"
    "中": "medium"
    "高": "high"
    "紧急": "urgent"
```

## 数据格式规范

### 云效工作项数据结构
```json
{
  "id": "workitem_id",
  "type": "任务",
  "title": "工作项标题",
  "description": "详细描述",
  "status": "进行中",
  "priority": "高",
  "assignee": "user_id",
  "project_id": "project_id",
  "created_at": "2025-09-28T10:00:00Z",
  "updated_at": "2025-09-28T10:30:00Z",
  "labels": ["frontend", "feature"],
  "custom_fields": {}
}
```

### 标准字段映射
```yaml
field_mapping:
  title: "title"
  body: "description"
  state: "status"
  assignees: "assignee"
  labels: "labels"
  milestone: "project_milestone"
  created_at: "created_at"
  updated_at: "updated_at"
```

## 同步操作规则

### 创建工作项规则
1. **标题格式**: 保持原始标题，添加来源标识
   ```
   原标题 [来源: GitHub Issue #123]
   ```

2. **描述转换**: 保留 Markdown 格式，添加同步信息
   ```markdown
   ## 原始描述
   [GitHub Issue内容]

   ## 同步信息
   - 来源: GitHub Issue #123
   - 同步时间: 2025-09-28 10:30:00
   - 原始链接: https://github.com/user/repo/issues/123
   ```

3. **标签处理**:
   - 保留所有 GitHub 标签
   - 添加 "github-sync" 标签标识
   - 转换特殊标签 (bug → 缺陷, enhancement → 功能增强)

### 更新同步规则
1. **双向同步**: 支持 GitHub ↔ 云效双向状态同步
2. **冲突处理**: 最后修改时间优先原则
3. **字段过滤**: 仅同步关键字段，避免数据污染

### 删除处理规则
1. **软删除**: 云效工作项标记为"已关闭"而非删除
2. **关联清理**: 清除同步关联关系
3. **历史保留**: 保留同步历史记录

## API集成规范

### 云效 API 端点配置
```yaml
api_config:
  base_url: "https://devops.aliyun.com"
  version: "v4"
  endpoints:
    workitems: "/api/v4/projects/{project_id}/workitems"
    workitem: "/api/v4/projects/{project_id}/workitems/{workitem_id}"
    projects: "/api/v4/projects"
```

### 认证配置
```yaml
auth_config:
  type: "token"  # 使用访问令牌
  token_env: "YUNXIAO_ACCESS_TOKEN"
  headers:
    "Authorization": "Bearer {token}"
    "Content-Type": "application/json"
```

### 请求限制
```yaml
rate_limiting:
  max_requests_per_minute: 100
  retry_attempts: 3
  retry_delay: 1000  # ms
  timeout: 30000     # ms
```

## 错误处理规则

### 同步失败处理
1. **网络错误**: 自动重试机制，最多3次
2. **认证失败**: 提示用户检查访问令牌
3. **数据格式错误**: 记录错误详情，跳过该项
4. **配额超限**: 延迟重试，遵守限流规则

### 数据一致性保障
1. **事务性同步**: 确保相关数据同时更新
2. **回滚机制**: 同步失败时恢复到上一个稳定状态
3. **冲突检测**: 检测并处理并发修改冲突

## 配置验证规则

### 必需配置项检查
```bash
# 检查云效平台配置完整性
required_config_check() {
  local config_file=".claude/ccpm.config"

  # 检查平台类型
  platform=$(yq eval '.platform.type' "$config_file" 2>/dev/null)
  if [ "$platform" != "yunxiao" ]; then
    echo "错误: 平台类型必须设置为 'yunxiao'"
    return 1
  fi

  # 检查项目ID
  project_id=$(yq eval '.platform.project_id' "$config_file" 2>/dev/null)
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

### 连接性测试
```bash
# 测试云效平台连接
test_yunxiao_connection() {
  local project_id=$(yq eval '.platform.project_id' .claude/ccpm.config)
  local base_url="https://devops.aliyun.com/api/v4"

  # 测试项目访问权限
  response=$(curl -s -w "%{http_code}" \
    -H "Authorization: Bearer $YUNXIAO_ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    "$base_url/projects/$project_id")

  status_code=$(echo "$response" | tail -n1)

  if [ "$status_code" = "200" ]; then
    echo "云效平台连接测试成功"
    return 0
  else
    echo "云效平台连接测试失败，HTTP状态码: $status_code"
    return 1
  fi
}
```

## 扩展规则引用

此文件为云效平台同步的基础规则。更多专门规则请参考:

- `.claude/rules/platform-yunxiao-workitem.md` - 工作项操作专用规则
- `.claude/rules/platform-yunxiao-api.md` - API调用和数据处理规则
- `.claude/rules/platform-yunxiao-webhooks.md` - Webhook集成规则

## 使用示例

### 检查平台配置并加载规则
```bash
# 在命令开头添加此检查
if [ -f ".claude/ccpm.config" ]; then
  platform=$(yq eval '.platform.type' .claude/ccpm.config 2>/dev/null || echo "github")

  if [ "$platform" = "yunxiao" ]; then
    # 加载云效平台规则
    echo "使用云效平台模式"

    # 验证配置
    if ! required_config_check; then
      echo "云效平台配置验证失败，请检查配置"
      exit 1
    fi

    # 测试连接
    if ! test_yunxiao_connection; then
      echo "云效平台连接失败，请检查网络和认证"
      exit 1
    fi

    # 继续执行云效特定逻辑...
  fi
fi
```

## 版本信息

- **规则版本**: v1.0.0
- **支持的云效API版本**: v4
- **最后更新**: 2025-09-28
- **兼容性**: 兼容云效企业版和标准版