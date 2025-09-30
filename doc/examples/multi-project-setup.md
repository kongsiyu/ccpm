# CCPM 多项目配置指南

本文档介绍如何在多项目环境中配置和管理CCPM，支持不同平台（云效、GitHub）和不同团队的协作需求。

## 目录
- [多项目架构概述](#多项目架构概述)
- [配置文件管理](#配置文件管理)
- [混合平台环境](#混合平台环境)
- [团队隔离配置](#团队隔离配置)
- [环境分离配置](#环境分离配置)
- [最佳实践](#最佳实践)

---

## 多项目架构概述

### 典型多项目结构

```
企业组织结构
├── 前端团队/
│   ├── web-admin-portal/          # 云效项目
│   ├── mobile-app/                # 云效项目
│   └── component-library/         # GitHub项目
├── 后端团队/
│   ├── user-service/              # 云效项目
│   ├── order-service/             # 云效项目
│   └── common-utils/              # GitHub项目
└── 数据团队/
    ├── data-pipeline/             # 云效项目
    ├── analytics-platform/        # 云效项目
    └── ml-models/                 # GitHub项目
```

### 支持的配置场景

1. **单一平台多项目**: 所有项目都使用云效或GitHub
2. **混合平台配置**: 不同项目使用不同平台
3. **环境隔离配置**: 开发、测试、生产使用不同配置
4. **团队隔离配置**: 不同团队独立管理项目

---

## 配置文件管理

### 方式1：项目级配置文件

每个项目根目录都有独立的配置文件：

```bash
# 项目结构
workspace/
├── web-admin-portal/
│   └── .ccpm-config.yaml          # 云效配置
├── mobile-app/
│   └── .ccpm-config.yaml          # 云效配置
└── component-library/
    └── .ccpm-config.yaml          # GitHub配置
```

**web-admin-portal/.ccpm-config.yaml**:
```yaml
# 前端管理后台 - 云效配置
platform: yunxiao
project_id: 11111111

# 项目特定配置
team:
  name: "前端团队"
  lead: "frontend-lead"

workflow:
  branch_naming:
    epic_prefix: "epic/admin-"
    feature_prefix: "feature/admin-"

  review_required: true
  testing_required: true

# 性能配置
cache:
  enabled: true
  ttl: 600  # 10分钟缓存

logging:
  level: info
  file: .ccpm-admin.log
```

**mobile-app/.ccpm-config.yaml**:
```yaml
# 移动应用 - 云效配置
platform: yunxiao
project_id: 22222222

# 项目特定配置
team:
  name: "移动端团队"
  lead: "mobile-lead"

workflow:
  branch_naming:
    epic_prefix: "epic/mobile-"
    feature_prefix: "feature/mobile-"

  # 移动端需要更严格的测试
  testing_required: true
  performance_test_required: true

# 移动端特定集成
integrations:
  app_store_connect:
    enabled: true
  google_play:
    enabled: true
```

**component-library/.ccpm-config.yaml**:
```yaml
# 组件库 - GitHub配置
platform: github
repository: "frontend-team/component-library"

# 开源项目配置
team:
  name: "组件库维护团队"
  public: true

workflow:
  # 开源项目需要更严格的审查
  review_required: true
  multiple_reviewers: true
  documentation_required: true

# GitHub特定配置
github:
  auto_merge: false
  require_up_to_date: true
  dismiss_stale_reviews: true
```

### 方式2：全局配置文件

使用全局配置文件管理多个项目：

**~/.ccpm/global-config.yaml**:
```yaml
# CCPM全局多项目配置

# 默认配置
defaults:
  cache:
    enabled: true
    ttl: 300
  logging:
    level: info
  retry:
    max_attempts: 3

# 项目配置映射
projects:
  # 云效项目组
  yunxiao_projects:
    web-admin-portal:
      project_id: 11111111
      team: "前端团队"
      environment: "production"

    mobile-app:
      project_id: 22222222
      team: "移动端团队"
      environment: "production"

    user-service:
      project_id: 33333333
      team: "后端团队"
      environment: "production"

  # GitHub项目组
  github_projects:
    component-library:
      repository: "frontend-team/component-library"
      team: "前端团队"
      visibility: "public"

    common-utils:
      repository: "backend-team/common-utils"
      team: "后端团队"
      visibility: "internal"

# 团队配置
teams:
  前端团队:
    platform_preference: "yunxiao"
    default_reviewers: ["frontend-lead", "senior-dev-1"]
    notification_channels: ["dingtalk"]

  后端团队:
    platform_preference: "yunxiao"
    default_reviewers: ["backend-lead", "senior-dev-2"]
    notification_channels: ["wechat-work"]

  数据团队:
    platform_preference: "github"
    default_reviewers: ["data-lead", "ml-engineer"]
    notification_channels: ["email"]
```

### 使用全局配置

```bash
# 初始化项目时使用全局配置
/pm:init --global-config

# 切换项目
/pm:switch-project web-admin-portal

# 查看当前项目配置
/pm:config-show

# 更新全局配置
/pm:global-config-update
```

---

## 混合平台环境

### 场景：前端项目使用云效，后端项目使用GitHub

**项目配置策略**:

```yaml
# 前端项目 (云效)
# frontend-projects/.ccpm-config.yaml
platform: yunxiao
project_id: 44444444

sync:
  # 与后端项目同步配置
  backend_integration:
    enabled: true
    backend_projects:
      - name: "user-api"
        platform: "github"
        repository: "backend-team/user-api"
        sync_events: ["epic-start", "epic-complete"]

# 跨平台工作流
cross_platform:
  # 当前端Epic启动时，自动在GitHub创建相关Issue
  auto_create_backend_issues: true

  # 状态同步规则
  status_sync:
    frontend_completed: "backend_ready_for_integration"
    backend_completed: "frontend_ready_for_testing"
```

```yaml
# 后端项目 (GitHub)
# backend-projects/.ccpm-config.yaml
platform: github
repository: "backend-team/user-api"

sync:
  # 与前端项目同步配置
  frontend_integration:
    enabled: true
    frontend_projects:
      - name: "web-admin"
        platform: "yunxiao"
        project_id: 44444444
        sync_events: ["pull-request-merged", "release-created"]

# GitHub特定配置
github:
  webhook_events:
    - "pull_request"
    - "issues"
    - "release"
```

### 跨平台同步命令

```bash
# 启动跨平台Epic
/pm:epic-start user-profile-management --cross-platform

# 输出示例：
# ✅ 云效Epic已创建: user-profile-management
# ✅ GitHub Issue已创建: #123 Backend API for user profile
# 🔄 跨平台同步已启用

# 查看跨平台状态
/pm:cross-platform-status

# 同步所有相关项目
/pm:sync --all-related
```

---

## 团队隔离配置

### 按团队划分的配置结构

```bash
# 团队配置目录结构
.ccpm-teams/
├── frontend-team.yaml
├── backend-team.yaml
├── mobile-team.yaml
├── data-team.yaml
└── devops-team.yaml
```

**frontend-team.yaml**:
```yaml
# 前端团队配置
team_id: "frontend-team"
team_name: "前端开发团队"

# 团队默认配置
defaults:
  platform: yunxiao
  workflow:
    review_required: true
    ui_testing_required: true
    accessibility_testing_required: true

# 团队成员
members:
  - id: "frontend-lead"
    name: "前端负责人"
    role: "tech-lead"
    permissions: ["admin", "review", "merge"]

  - id: "senior-frontend-dev"
    name: "高级前端工程师"
    role: "senior-developer"
    permissions: ["review", "merge"]

  - id: "junior-frontend-dev"
    name: "初级前端工程师"
    role: "developer"
    permissions: ["create", "update"]

# 团队项目
projects:
  - name: "web-admin-portal"
    project_id: 11111111
    priority: "high"

  - name: "mobile-web-app"
    project_id: 55555555
    priority: "medium"

# 团队工作流
workflows:
  feature_development:
    steps:
      - "design_review"
      - "code_development"
      - "unit_testing"
      - "ui_testing"
      - "accessibility_testing"
      - "code_review"
      - "integration_testing"
      - "deployment"

# 通知配置
notifications:
  channels:
    - type: "dingtalk"
      webhook: "${FRONTEND_DINGTALK_WEBHOOK}"
    - type: "email"
      recipients: ["frontend-team@company.com"]

# 权限控制
permissions:
  can_create_epic: ["tech-lead", "senior-developer"]
  can_merge_epic: ["tech-lead"]
  can_deploy: ["tech-lead", "senior-developer"]
```

### 团队隔离命令

```bash
# 切换到特定团队环境
/pm:team-switch frontend-team

# 查看团队项目
/pm:team-projects

# 团队成员管理
/pm:team-members --list

# 团队权限检查
/pm:team-permissions frontend-lead

# 团队工作负载
/pm:team-workload
```

---

## 环境分离配置

### 开发、测试、生产环境配置

**环境配置目录结构**:
```bash
.ccpm-environments/
├── development.yaml
├── staging.yaml
└── production.yaml
```

**development.yaml**:
```yaml
# 开发环境配置
environment: "development"

# 云效开发项目
yunxiao:
  project_id: 66666666  # 开发环境项目ID
  api:
    endpoint: "https://dev-devops.aliyun.com"

# 开发环境特定配置
debug: true
verbose_logging: true

# 快速迭代配置
workflow:
  review_required: false  # 开发环境可以跳过代码审查
  testing_required: true
  auto_deploy: true

# 开发环境工具
development_tools:
  hot_reload: true
  debug_mode: true
  mock_data: true

# 宽松的缓存策略
cache:
  enabled: true
  ttl: 60  # 1分钟缓存，快速反映变更
```

**staging.yaml**:
```yaml
# 测试环境配置
environment: "staging"

# 云效测试项目
yunxiao:
  project_id: 77777777  # 测试环境项目ID
  api:
    endpoint: "https://staging-devops.aliyun.com"

# 接近生产的配置
debug: false
verbose_logging: false

# 严格的工作流
workflow:
  review_required: true
  testing_required: true
  performance_testing_required: true
  security_testing_required: true
  auto_deploy: false  # 测试环境需要手动部署

# 测试环境特定工具
testing_tools:
  load_testing: true
  security_scanning: true
  performance_monitoring: true

# 适中的缓存策略
cache:
  enabled: true
  ttl: 300  # 5分钟缓存
```

**production.yaml**:
```yaml
# 生产环境配置
environment: "production"

# 云效生产项目
yunxiao:
  project_id: 88888888  # 生产环境项目ID
  api:
    endpoint: "https://devops.aliyun.com"

# 生产环境严格配置
debug: false
verbose_logging: false

# 最严格的工作流
workflow:
  review_required: true
  multiple_reviewers_required: true
  testing_required: true
  performance_testing_required: true
  security_testing_required: true
  documentation_required: true
  auto_deploy: false
  deployment_approval_required: true

# 生产环境监控
monitoring:
  enabled: true
  alerts: true
  performance_tracking: true
  error_tracking: true

# 生产环境安全
security:
  audit_logging: true
  access_control: strict
  encryption: true

# 生产环境缓存策略
cache:
  enabled: true
  ttl: 600  # 10分钟缓存，稳定性优先
```

### 环境切换命令

```bash
# 切换到开发环境
/pm:env-switch development

# 切换到测试环境
/pm:env-switch staging

# 切换到生产环境
/pm:env-switch production

# 查看当前环境
/pm:env-current

# 查看环境配置差异
/pm:env-diff development production

# 环境配置验证
/pm:env-validate production
```

### 跨环境部署流程

```bash
# 开发环境完成后，部署到测试环境
/pm:deploy development staging

# 测试环境验证通过后，部署到生产环境
/pm:deploy staging production --require-approval

# 查看跨环境部署状态
/pm:deployment-status

# 回滚到上一个版本
/pm:rollback production --to-version=v1.2.3
```

---

## 最佳实践

### 1. 配置文件管理

```bash
# 使用版本控制管理配置文件
git add .ccpm-config.yaml
git add .ccpm-teams/
git add .ccpm-environments/

# 使用配置模板
cp .ccpm-config.yaml.template .ccpm-config.yaml

# 配置文件验证
/pm:config-validate

# 配置文件备份
/pm:config-backup
```

### 2. 敏感信息处理

```yaml
# 在配置文件中使用环境变量
api:
  token: "${YUNXIAO_ACCESS_TOKEN}"
  project_id: "${YUNXIAO_PROJECT_ID}"

# 或使用外部秘钥文件
secrets:
  file: ".ccpm-secrets.env"
  encrypted: true
```

```bash
# 设置环境变量
export YUNXIAO_ACCESS_TOKEN="your-secure-token"
export YUNXIAO_PROJECT_ID="12345678"

# 或使用.env文件
echo "YUNXIAO_ACCESS_TOKEN=your-secure-token" > .ccpm-secrets.env
echo "YUNXIAO_PROJECT_ID=12345678" >> .ccpm-secrets.env
```

### 3. 配置继承和覆盖

```yaml
# 基础配置 (base-config.yaml)
base_config: &base
  cache:
    enabled: true
    ttl: 300
  logging:
    level: info
  retry:
    max_attempts: 3

# 项目特定配置继承基础配置
<<: *base

# 覆盖特定配置
cache:
  ttl: 600  # 覆盖基础配置的TTL
```

### 4. 配置文档化

```bash
# 生成配置文档
/pm:config-docs

# 导出配置摘要
/pm:config-export --format=markdown

# 配置变更日志
/pm:config-changelog
```

### 5. 监控和告警

```yaml
# 配置监控
monitoring:
  config_drift_detection: true
  performance_monitoring: true
  error_rate_alerts: true

# 告警配置
alerts:
  config_validation_failed:
    enabled: true
    channels: ["dingtalk", "email"]

  cross_platform_sync_failed:
    enabled: true
    channels: ["wechat-work"]
```

### 6. 定期维护

```bash
# 定期配置健康检查
/pm:config-health-check

# 清理过期配置
/pm:config-cleanup

# 配置性能分析
/pm:config-performance-report

# 配置更新检查
/pm:config-update-check
```

---

> 💡 **提示**: 多项目配置需要根据团队规模和复杂度进行调整。建议从简单配置开始，逐步增加复杂性。定期审查和优化配置以确保最佳性能和可维护性。