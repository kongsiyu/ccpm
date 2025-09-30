# 云效 Issue 同步脚本

本目录包含云效平台的工作项同步脚本，对应 GitHub 平台的 issue-sync 功能。这些脚本实现了与 GitHub issue-sync 完全一致的接口和功能。

## 脚本清单

### 核心同步脚本

- **`preflight-validation-yunxiao.sh`** - 预检验证脚本
  - 验证云效环境配置
  - 检查 GitHub Issue 存在性
  - 确认本地更新目录
  - 验证云效工作项关联

- **`update-frontmatter-yunxiao.sh`** - 前置元数据更新脚本
  - 更新 progress.md 的 frontmatter
  - 同步任务文件状态
  - 关联云效工作项 ID
  - 同步状态到云效平台

- **`post-comment-yunxiao.sh`** - 评论发布脚本
  - 发布评论到云效工作项
  - 支持双向同步到 GitHub
  - 格式化评论内容
  - 自动添加来源标识

- **`check-sync-timing-yunxiao.sh`** - 同步时机检查脚本
  - 防止频繁同步
  - 支持强制同步模式
  - API 限流保护
  - 时间间隔验证

- **`calculate-epic-progress-yunxiao.sh`** - Epic 进度计算脚本
  - 基于云效工作项状态计算进度
  - 支持加权进度计算
  - 更新 Epic frontmatter
  - 生成进度报告

## 使用方法

### 基本用法

```bash
# 预检验证
./preflight-validation-yunxiao.sh 123

# 检查同步时机
./check-sync-timing-yunxiao.sh 123

# 更新 frontmatter
./update-frontmatter-yunxiao.sh 123 75 456

# 发布评论
./post-comment-yunxiao.sh 123 /tmp/comment.md 456

# 计算 Epic 进度
./calculate-epic-progress-yunxiao.sh cli-alibabacloud-devops
```

### 参数说明

- `issue_number` - GitHub Issue 编号
- `completion` - 完成百分比 (0-100)
- `yunxiao_workitem_id` - 云效工作项 ID (可选)
- `temp_file` - 临时评论文件路径
- `epic_name` - Epic 名称

### 强制同步

```bash
# 跳过时间间隔检查
./check-sync-timing-yunxiao.sh 123 true
```

## 功能特性

### 状态映射

脚本支持以下状态映射：

| GitHub 状态 | 云效状态 | 进度百分比 |
|------------|---------|----------|
| open | 新建 | 0% |
| in_progress | 进行中 | 1-99% |
| closed | 已完成 | 100% |

### 进度计算逻辑

1. **基础进度**：基于本地任务完成状态
2. **云效加权进度**：结合云效工作项实时状态
3. **综合进度**：云效任务权重 70%，本地任务权重 30%

### 错误处理

- 自动重试机制 (最多 3 次)
- 指数退避策略
- 优雅降级处理
- 详细错误日志

## 依赖要求

### 必需依赖

- **jq** - JSON 处理工具
- **gh** - GitHub CLI (可选，用于双向同步)
- **date** - 时间戳处理

### 库依赖

- `.claude/lib/error.sh` - 错误处理库
- `.claude/lib/yunxiao.sh` - 云效操作库
- `.claude/lib/frontmatter.sh` - frontmatter 处理库
- `.claude/scripts/pm/yunxiao/workitem-common.sh` - 工作项通用库

### 配置要求

- `.ccpm-config.yaml` - 云效项目配置
- 云效 MCP 服务正常运行
- 阿里云云效项目访问权限

## 输出格式

所有脚本的输出格式与 GitHub 版本保持完全一致：

- ✅ 成功消息使用绿色勾号
- ❌ 错误消息使用红色叉号
- ⚠️ 警告消息使用黄色警告图标
- ℹ️ 信息消息使用蓝色信息图标
- 🔍 检查动作使用放大镜图标
- 🔄 同步动作使用刷新图标

## 故障排查

### 常见问题

1. **云效配置无效**
   - 检查 `.ccpm-config.yaml` 配置
   - 确认项目 ID 正确

2. **MCP 服务不可用**
   - 检查 MCP 服务状态
   - 重启 MCP 服务

3. **API 限流**
   - 减少同步频率
   - 使用强制同步时需谨慎

4. **工作项不存在**
   - 检查工作项 ID 正确性
   - 确认访问权限

### 调试模式

设置环境变量启用调试模式：

```bash
export YUNXIAO_DEBUG=1
./preflight-validation-yunxiao.sh 123
```

## 集成测试

脚本支持与现有测试框架集成：

```bash
# 运行完整测试套件
../yunxiao/test-workitem-crud.sh issue-sync-test
```

## 版本兼容性

- 与 GitHub issue-sync 脚本完全兼容
- 支持相同的命令行参数
- 输出格式保持一致
- 错误码含义相同

## 更新日志

- **v1.0.0** - 初始版本，实现基础同步功能
- 支持完整的工作项生命周期管理
- 实现与 GitHub 版本功能对等
- 提供完善的错误处理和重试机制