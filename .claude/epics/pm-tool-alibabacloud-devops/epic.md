---
name: pm-tool-alibabacloud-devops
status: backlog
created: 2025-09-28T07:52:39Z
progress: 0%
prd: .claude/prds/pm-tool-alibabacloud-devops.md
github: https://github.com/kongsiyu/ccpm/issues/1
---

# Epic: CCPM 阿里云云效平台集成

## Overview

扩展CCPM支持阿里云云效平台，通过配置驱动的适配器模式实现平台选择灵活性。核心策略是最大化复用现有GitHub工作流程，通过MCP协议集成云效服务，确保100%命令兼容性和frontmatter格式一致性。

## Architecture Decisions

### 1. 适配器模式设计
- **平台抽象层**: 统一GitHub和云效的操作接口，隐藏平台差异
- **配置驱动路由**: 通过`.claude/ccpm.config`文件决定平台选择，无需修改命令
- **MCP集成**: 利用现有Claude Code MCP能力，无需自建服务器

### 2. 最小侵入原则
- **复用现有命令**: 所有`/pm:*`命令保持完全不变，内部智能路由
- **保持frontmatter**: `github`字段语义扩展为"平台URL"，兼容云效链接
- **利用现有规则**: 扩展`.claude/rules/`系统而非创建新框架

### 3. 技术栈选择
- **MCP协议**: 使用`alibabacloud-devops-mcp-server`作为云效API桥接
- **配置管理**: YAML格式配置文件，支持项目级平台选择
- **状态映射**: GitHub Issues概念映射到云效WorkItem层级结构

## Technical Approach

### 前置检查模式
**配置系统**:
- `.claude/ccpm.config`: 项目级平台配置文件
- `.claude/rules/platform-config.md`: 平台配置规则文档

**命令增强策略**:
- 在command文档开头增加平台检测逻辑
- 根据配置读取对应的平台规则文件
- 云效逻辑完全独立在规则文件中，GitHub逻辑保持不变

**规则文件结构**:
- `.claude/rules/platform-yunxiao-sync.md`: 云效同步规则
- `.claude/rules/platform-yunxiao-epic-sync.md`: 云效Epic同步规则
- `.claude/rules/platform-yunxiao-issue-sync.md`: 云效Issue同步规则

**关键映射**:
```
GitHub Issues     ↔ 云效 WorkItem
Epic Issues       ↔ 父工作项 (epic类型)
Task Issues       ↔ 子工作项 (story/task类型)
Issue Comments    ↔ WorkItem Comments
Issue Status      ↔ WorkItem State
```

### MCP集成实现
**工具映射策略**:
- `gh issue create` → `create_work_item`
- `gh issue list` → `search_workitems`
- `gh issue comment` → `create_work_item_comment`
- `gh issue edit` → 更新工作项状态和内容

**项目关联处理**:
- 维护代码仓库ID与项目管理项目ID的关联
- 自动发现和配置工作项类型映射
- 处理云效独有的项目管理与代码管理分离架构

## Implementation Strategy

### Phase 1: 核心基础设施 (2-3天)
- 配置系统和平台检测
- 基础适配器框架
- MCP连接和验证

### Phase 2: 基础功能适配 (3-4天)
- Epic/Task创建和同步
- 基础状态管理
- 工作项类型映射

### Phase 3: 高级功能集成 (2-3天)
- 完整同步机制
- 父子关联处理
- 错误处理和验证

### Phase 4: 优化和验证 (1-2天)
- 性能优化
- 全流程测试
- 文档和示例

## Task Breakdown Preview

最终任务分类（5个任务）:
- [ ] **配置系统**: 平台配置文件、前置检查和命令路由机制
- [ ] **适配器框架**: 云效平台规则文件和MCP工具调用规范
- [ ] **MCP集成**: 云效MCP连接验证和诊断机制
- [ ] **初始化增强**: `/pm:init`云效环境检测和配置引导
- [ ] **测试验证**: 端到端测试和错误场景处理

## Dependencies

### 外部依赖
- **alibabacloud-devops-mcp-server**: 必须可用且稳定
- **Claude Code MCP支持**: 需要MCP协议完整支持
- **云效平台权限**: 测试和开发需要云效项目访问权限

### 内部依赖
- **现有CCPM架构**: 基于当前命令系统和工作流程
- **GitHub CLI功能**: 需要保持现有GitHub功能完整性
- **规则系统**: 依赖现有`.claude/rules/`继承机制

### 技术风险
- **MCP工具覆盖度**: 云效MCP工具可能无法完全对标GitHub API
- **企业网络环境**: 企业防火墙可能影响MCP连接
- **工作项模型差异**: 云效层级结构与GitHub Issues的映射复杂性

## Success Criteria (Technical)

### 功能完整性
- [ ] 95%以上现有CCPM命令在云效平台正常工作
- [ ] 完整的PRD→Epic→Task→WorkItem工作流程
- [ ] frontmatter字段100%兼容，支持云效URL

### 性能要求
- [ ] 云效操作响应时间不超过GitHub的150%
- [ ] 配置切换时间不超过30秒
- [ ] 并发代理支持不受影响

### 用户体验
- [ ] 命令语法和参数完全一致
- [ ] 错误信息清晰，提供解决方案
- [ ] 新项目配置引导流程顺畅

## Estimated Effort

**总体时间**: 5-7工作日
**资源需求**: 1名技术开发者 + 云效平台测试环境
**关键路径**: 配置系统 → MCP集成 → 规则框架 → 测试验证

**风险缓解时间**: 预留1-2天处理MCP工具差异和企业环境适配

## Tasks Created

- [ ] #2 - 配置系统和平台检测（含命令路由） (parallel: true)
- [ ] #3 - 平台适配器框架 (parallel: false)
- [ ] #4 - MCP集成和云效连接 (parallel: false)
- [ ] #5 - 初始化命令增强 (parallel: false)
- [ ] #6 - 端到端测试和验证 (parallel: false)

Total tasks: 5
Parallel tasks: 1 (2 can start immediately)
Sequential tasks: 4 (form dependency chain)
Estimated total effort: 45+ hours (5-7 working days)

## Notes

此Epic专注于"新项目平台选择"场景，不涉及现有项目迁移。设计原则是最小化代码变更，最大化现有功能复用，确保GitHub工作流程完全不受影响的前提下，为云效平台提供相同的用户体验。