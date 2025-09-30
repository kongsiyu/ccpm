# CCPM 云效平台工作流示例

本文档提供完整的工作流示例，展示如何使用CCPM与阿里云云效平台进行端到端的项目管理。

## 目录
- [完整开发周期示例](#完整开发周期示例)
- [敏捷开发工作流](#敏捷开发工作流)
- [Bug修复工作流](#bug修复工作流)
- [紧急热修复工作流](#紧急热修复工作流)
- [多人协作示例](#多人协作示例)
- [版本发布工作流](#版本发布工作流)

---

## 完整开发周期示例

这个示例展示从需求分析到上线部署的完整流程。

### 需求：用户认证系统

**背景**：需要为Web应用添加用户注册、登录、密码重置功能。

### 第1阶段：需求分析与规划

```bash
# 1. 创建PRD文档
/pm:prd-new user-authentication-system

# 2. 编辑PRD内容
/pm:prd-edit user-authentication-system
```

**PRD内容示例**：
```markdown
# 用户认证系统

## 功能需求
- 用户注册功能
- 用户登录功能
- 密码重置功能
- 账户安全管理

## 技术要求
- 使用JWT令牌认证
- 密码哈希存储
- 支持邮箱验证
- 集成短信验证码

## 验收标准
- 注册成功率 > 95%
- 登录响应时间 < 2秒
- 安全漏洞扫描通过
```

```bash
# 3. 启动Epic开发
/pm:epic-start user-authentication-system

# 4. 同步到云效平台
/pm:epic-sync

# 输出示例：
# ✅ Epic "user-authentication-system" 已创建
# ✅ 工作项已同步到云效项目 12345678
# ✅ 分支 epic/user-authentication-system 已创建
```

### 第2阶段：任务分解

```bash
# 5. 查看Epic状态
/pm:epic-status user-authentication-system

# 6. 分解Epic为具体任务（通过云效界面或命令）
# 这一步通常在云效平台上进行可视化操作
```

**任务分解示例**：
- Task 1: 设计数据库用户表结构
- Task 2: 实现用户注册API
- Task 3: 实现用户登录API
- Task 4: 实现密码重置功能
- Task 5: 前端用户界面开发
- Task 6: 集成测试
- Task 7: 安全测试

### 第3阶段：开发实施

```bash
# 7. 查看待完成任务
/pm:next

# 8. 开始开发第一个任务
/pm:issue-start 101  # 假设Task 1的ID是101

# 9. 切换到开发分支
git checkout -b feature/user-registration

# 进行开发工作...
# 提交代码...

# 10. 更新任务状态
/pm:issue-status 101 in-progress

# 11. 完成任务后
/pm:issue-status 101 completed
```

### 第4阶段：测试与合并

```bash
# 12. 查看Epic整体进度
/pm:epic-status user-authentication-system

# 13. 当所有任务完成后，准备合并
/pm:epic-merge user-authentication-system

# 输出示例：
# 🔍 检查Epic状态...
# ✅ 所有任务已完成
# ✅ 代码审查已通过
# ✅ 自动化测试通过
# 🚀 开始合并到主分支...
# ✅ Epic合并完成
```

### 第5阶段：发布和清理

```bash
# 14. 生成发布总结
/pm:epic-show user-authentication-system

# 15. 清理完成的Epic
/pm:clean

# 16. 同步最终状态
/pm:sync
```

---

## 敏捷开发工作流

适用于使用Scrum或看板方法的团队。

### Sprint规划

```bash
# 1. 查看当前Sprint状态
/pm:status

# 2. 查看积压工作
/pm:search status:open

# 3. 规划新Sprint的工作
/pm:standup
```

### 每日站会流程

```bash
# 生成每日站会报告
/pm:standup

# 输出示例：
# 📊 每日站会报告 - 2024年12月1日
#
# 🟢 昨日完成：
# - Issue #101: 用户注册API开发
# - Issue #102: 数据库表设计
#
# 🟡 今日计划：
# - Issue #103: 登录功能开发
# - Issue #104: 前端界面设计
#
# 🔴 阻塞问题：
# - Issue #105: 等待第三方服务API文档
#
# 📈 整体进度：65% (13/20 任务完成)
```

### Sprint回顾

```bash
# 生成Sprint总结报告
/pm:epic-status feature-name

# 查看团队效率指标
/pm:performance-report
```

---

## Bug修复工作流

处理生产环境bug的标准流程。

### Bug报告和分析

```bash
# 1. 创建Bug修复Epic
/pm:epic-start bugfix-login-error

# 2. 分析Bug影响范围
/pm:issue-analyze 201  # Bug Issue ID

# 输出示例：
# 🐛 Bug分析报告
#
# Bug ID: #201
# 优先级: 高
# 影响模块: 用户认证
# 影响用户: 约1000名活跃用户
# 预估修复时间: 4小时
#
# 🔍 相关Epic: user-authentication-system
# 📊 相似问题历史: 2个相关Bug已修复
```

### 修复实施

```bash
# 3. 启动Bug修复
/pm:issue-start 201

# 4. 创建修复分支
git checkout -b bugfix/login-timeout-issue

# 进行Bug修复...

# 5. 提交修复
git add .
git commit -m "fix: resolve login timeout issue"

# 6. 更新Bug状态
/pm:issue-status 201 testing
```

### 验证和部署

```bash
# 7. 运行测试验证
/testing:run --focus=auth

# 8. 如果测试通过，关闭Bug
/pm:issue-close 201

# 9. 部署到生产环境
/pm:epic-merge bugfix-login-error
```

---

## 紧急热修复工作流

处理生产环境紧急问题的快速流程。

### 紧急响应

```bash
# 1. 创建紧急修复Epic
/pm:epic-start hotfix-critical-security-issue

# 2. 设置高优先级
/pm:epic-edit hotfix-critical-security-issue
# 在编辑界面设置priority: critical

# 3. 立即启动修复
/pm:issue-start 301  # 紧急Issue ID

# 4. 创建热修复分支
git checkout -b hotfix/security-patch-v1.2.1
```

### 快速修复和验证

```bash
# 5. 进行紧急修复后，快速测试
/testing:run --critical-only

# 6. 如果测试通过，立即合并
/pm:epic-merge hotfix-critical-security-issue --fast-track

# 7. 通知相关人员
/pm:notify-team "紧急安全补丁已部署完成"
```

---

## 多人协作示例

展示团队成员之间的协作流程。

### 任务分配和协调

```bash
# 产品经理：创建Epic和任务分解
/pm:epic-start mobile-app-redesign

# 技术负责人：分配任务给团队成员
/pm:issue-assign 401 "developer-1"
/pm:issue-assign 402 "developer-2"
/pm:issue-assign 403 "designer-1"

# 开发人员：查看自己的任务
/pm:my-tasks

# 输出示例：
# 📋 我的任务列表
#
# 🟡 进行中：
# - Issue #401: 移动端主页重设计 (预计2天)
#
# ⏳ 待开始：
# - Issue #404: 用户体验优化 (预计3天)
# - Issue #405: 性能优化 (预计1天)
```

### 协作状态同步

```bash
# 团队成员定期同步状态
/pm:sync

# 查看团队整体进度
/pm:team-progress

# 输出示例：
# 👥 团队进度报告
#
# 📊 Epic: mobile-app-redesign
# 总体进度: 45%
#
# 👤 团队成员状态：
# - developer-1: 2个任务进行中, 1个已完成
# - developer-2: 1个任务进行中, 2个已完成
# - designer-1: 1个任务待开始, 3个已完成
#
# ⚠️ 需要关注：
# - Issue #403: 设计评审延期1天
```

### 代码审查协作

```bash
# 开发人员：提交代码审查请求
/pm:request-review 401

# 审查人员：进行代码审查
/pm:review 401 --approve

# 自动触发合并流程
/pm:auto-merge 401
```

---

## 版本发布工作流

管理版本发布的完整流程。

### 发布准备

```bash
# 1. 创建发布Epic
/pm:epic-start release-v2.1.0

# 2. 检查发布就绪状态
/pm:release-check v2.1.0

# 输出示例：
# 🚀 发布就绪检查 - v2.1.0
#
# ✅ 功能开发: 100% (15/15)
# ✅ 代码审查: 100% (15/15)
# ✅ 自动化测试: 通过
# ✅ 安全扫描: 通过
# ⚠️ 性能测试: 待执行
# ❌ 文档更新: 待完成
#
# 🎯 发布建议: 完成性能测试和文档更新后可发布
```

### 发布执行

```bash
# 3. 执行预发布测试
/testing:run --release

# 4. 生成发布说明
/pm:release-notes v2.1.0

# 5. 执行发布
/pm:release v2.1.0

# 输出示例：
# 🚀 正在发布 v2.1.0...
#
# ✅ 创建发布分支
# ✅ 构建生产包
# ✅ 部署到预发布环境
# ✅ 执行冒烟测试
# ✅ 部署到生产环境
# ✅ 健康检查通过
#
# 🎉 版本 v2.1.0 发布成功！
```

### 发布后跟踪

```bash
# 6. 监控发布状态
/pm:release-monitor v2.1.0

# 7. 如果发现问题，准备回滚
/pm:rollback v2.1.0

# 8. 发布总结
/pm:release-summary v2.1.0
```

---

## 最佳实践提示

### 命名规范

- **Epic命名**: 使用清晰的功能描述，如 `user-authentication-system`
- **分支命名**: 遵循前缀规范，如 `epic/`, `feature/`, `bugfix/`, `hotfix/`
- **任务标题**: 简洁明了，包含动作和目标

### 状态管理

- 及时更新任务状态，保持信息同步
- 使用 `/pm:sync` 定期同步云效平台状态
- 利用 `/pm:standup` 生成进度报告

### 团队协作

- 定期运行 `/pm:team-progress` 了解团队状态
- 使用 `/pm:blocked` 及时标记和解决阻塞问题
- 通过 `/pm:notify-team` 进行重要信息通知

### 质量保证

- 在合并前确保所有测试通过
- 使用 `/pm:validate` 验证Epic完整性
- 保持文档和代码同步更新

---

> 💡 **提示**: 这些工作流示例可以根据您的团队需求进行调整。建议在实际使用前，先在测试环境中熟悉各个命令的功能。