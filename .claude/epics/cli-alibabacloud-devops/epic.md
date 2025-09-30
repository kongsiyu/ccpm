---
name: cli-alibabacloud-devops
status: backlog
created: 2025-09-30T01:26:37Z
progress: 0%
prd: .claude/prds/cli-alibabacloud-devops.md
github: https://github.com/kongsiyu/ccpm/issues/1
---

# Epic: cli-alibabacloud-devops

## Overview

采用**最小改动原则**扩展CCPM系统以支持阿里云云效平台。通过并行文件结构方案，在完全不修改现有GitHub脚本的前提下，新增云效专用脚本文件，通过配置检测路由机制实现平台选择。核心技术路线：创建`*-yunxiao.sh`和`*-yunxiao/`目录与现有GitHub功能并行，通过MCP协议集成云效API，实现Issue↔WorkItem透明映射。

## Architecture Decisions

### 1. 并行文件架构模式
- **决策**：采用并行文件结构而非平台抽象层
- **原因**：避免与上游multi-CLI重构冲突，最小化合并风险
- **实现**：每个GitHub脚本对应创建yunxiao版本，保持接口一致

### 2. MCP协议集成策略
- **决策**：使用阿里云官方MCP服务器作为唯一云效API入口
- **原因**：标准化协议支持，官方维护稳定性高
- **实现**：封装MCP调用为统一函数库，处理认证和错误

### 3. 配置驱动路由机制
- **决策**：通过`.ccpm-config.yaml`简单配置实现平台路由
- **原因**：用户体验简单，实现复杂度低
- **配置**：仅`platform: yunxiao/github` + `project_id`（云效专用）

### 4. 数据映射策略
- **决策**：GitHub Issue ↔ 云效WorkItem直接映射，不做数据同步
- **原因**：避免复杂的双向同步逻辑，降低实现难度
- **实现**：每个平台独立管理，通过epic-sync重新生成issue

## Technical Approach

### 云效脚本并行化实现

#### 环境检测组件
- **init-yunxiao.sh**：检测MCP环境、云效连接、project_id配置
- **配置验证**：验证`.ccpm-config.yaml`格式和必需字段
- **依赖检查**：Node.js、MCP服务器可用性检测

#### 工作项管理脚本
- **epic-sync-yunxiao/**：对应GitHub的epic-sync功能
  - `fetch-yunxiao-workitems.sh`：获取云效工作项
  - `sync-yunxiao-workitems.sh`：同步本地到云效
  - `post-yunxiao-comments.sh`：发布进度评论
- **issue-sync-yunxiao/**：对应GitHub的issue-sync功能
  - 创建、更新、查询工作项操作
  - 状态管理和优先级映射

#### MCP协议封装层
```bash
# .claude/lib/yunxiao.sh
yunxiao_create_workitem() {
    local project_id="$1"
    local title="$2"
    local body_file="$3"
    # MCP协议调用实现
}

yunxiao_get_workitem() {
    local project_id="$1"
    local workitem_id="$2"
    # 查询工作项详情
}
```

### 命令路由集成

#### 平台检测机制
```bash
# .claude/lib/platform-detection.sh
get_platform_type() {
    if [ -f ".ccpm-config.yaml" ]; then
        grep "platform:" .ccpm-config.yaml | cut -d' ' -f2
    else
        echo "github"  # 默认GitHub
    fi
}

get_project_id() {
    grep "project_id:" .ccpm-config.yaml | cut -d' ' -f2
}
```

#### 命令路由逻辑
```bash
# 在现有命令中添加路由
if [[ "$(get_platform_type)" == "yunxiao" ]]; then
    exec "$(dirname "$0")/scripts-yunxiao/epic-sync.sh" "$@"
else
    exec "$(dirname "$0")/scripts/epic-sync.sh" "$@"
fi
```

## Implementation Strategy

### 开发方法论
1. **测试驱动开发**：先创建云效环境测试，确保MCP连接可用
2. **接口优先设计**：确保yunxiao脚本与GitHub脚本输入输出完全一致
3. **增量验证**：每个脚本完成后立即测试GitHub功能无影响

### 风险缓解策略
- **上游冲突风险**：使用独立文件名（-yunxiao后缀），定期测试合并
- **MCP依赖风险**：实现降级机制，MCP不可用时提供明确错误信息
- **性能风险**：云效API调用增加缓存机制，避免重复请求

### 质量保证
- **零影响测试**：每次修改后验证GitHub工作流完全正常
- **功能对等测试**：确保yunxiao脚本功能与GitHub脚本完全对等
- **集成测试**：端到端测试PRD→Epic→Task→WorkItem完整流程

## Task Breakdown Preview

基于最小改动原则，将实现简化为8个核心任务：

- [ ] **Task 1**: 创建MCP基础设施和配置检测机制
- [ ] **Task 2**: 实现init-yunxiao.sh环境检测脚本
- [ ] **Task 3**: 创建yunxiao工作项CRUD操作脚本集
- [ ] **Task 4**: 实现epic-sync-yunxiao完整目录功能
- [ ] **Task 5**: 创建issue-sync-yunxiao工作项同步脚本
- [ ] **Task 6**: 实现命令路由和平台检测集成
- [ ] **Task 7**: 创建配置文档和使用示例
- [ ] **Task 8**: 完整功能测试和GitHub零影响验证

## Dependencies

### 关键外部依赖
- **阿里云MCP服务器**：https://github.com/aliyun/alibabacloud-devops-mcp-server
- **云效测试环境**：具有工作项操作权限的云效项目
- **Node.js 16+**：MCP协议运行环境

### 内部依赖
- **现有CCPM架构**：保持完全兼容，不做任何修改
- **现有脚本接口**：yunxiao脚本必须与GitHub脚本接口完全一致
- **文件结构约定**：遵循现有.claude/scripts/pm/目录结构

### 开发阶段依赖
1. **阶段1**：云效环境访问权限
2. **阶段2**：MCP协议调用测试
3. **阶段3**：GitHub环境回归测试
4. **阶段4**：端到端集成验证

## Success Criteria (Technical)

### 功能对等性
- 所有`/pm:*`命令在yunxiao平台功能完全对等
- PRD→Epic→Task→WorkItem完整工作流正常运行
- 并行AI执行在云效平台正常工作

### 性能基准
- MCP协议调用响应时间 < 3秒
- 云效命令成功率 > 98%
- GitHub功能完全无性能影响

### 质量门禁
- **零冲突**：与上游项目合并无冲突
- **零影响**：现有GitHub工作流完全不受影响
- **完整覆盖**：所有核心PM命令在云效平台可用

### 用户验收标准
- 用户可在5分钟内完成平台配置
- 平台切换对用户命令使用方式透明
- 配置错误时提供清晰的诊断信息

## Estimated Effort

### 总体时间线
- **开发周期**：4-6周
- **核心开发**：3-4周（8个任务）
- **测试验证**：1-2周
- **文档完善**：与开发并行

### 资源需求
- **主开发**：1名熟悉CCPM架构的开发者
- **云效专家**：1名了解云效API和MCP协议的技术专家
- **测试工程师**：0.5名进行回归测试

### 关键路径
1. **MCP基础设施**（1周）→ 云效脚本开发的前提
2. **核心脚本创建**（2-3周）→ 主要功能实现
3. **集成测试**（1周）→ 确保质量和兼容性

### 风险时间缓冲
- **MCP协议学习**：+1周（如果团队不熟悉）
- **云效API限制**：+0.5周（API调用优化）
- **上游变更适配**：+0.5周（如果上游有重大更新）

通过这个精心设计的技术方案，我们可以在最小化风险的前提下，为CCPM系统提供强大的云效平台支持能力。

## Tasks Created
- [ ] #2 - 创建MCP基础设施和配置检测机制 (parallel: false)
- [ ] #3 - 实现init-yunxiao.sh环境检测脚本 (parallel: true)
- [ ] #4 - 创建yunxiao工作项CRUD操作脚本集 (parallel: true)
- [ ] #5 - 实现epic-sync-yunxiao完整目录功能 (parallel: false)
- [ ] #6 - 创建issue-sync-yunxiao工作项同步脚本 (parallel: false)
- [ ] #10 - 实现命令路由和平台检测集成 (parallel: false)
- [ ] #11 - 创建配置文档和使用示例 (parallel: true)
- [ ] #9 - 完整功能测试和GitHub零影响验证 (parallel: true)

Total tasks: 8
Parallel tasks: 4
Sequential tasks: 4
Estimated total effort: 17.5天