---
stream: 命令路由系统 (Command Routing System)
agent: general-purpose
started: 2025-09-28T18:50:00Z
status: in_progress
---

# Stream B: 命令路由系统 (Command Routing System)

## 任务范围
- Files: `.claude/commands/pm/*sync*.md` - 同步相关命令文档
- Work: 在sync相关命令开头增加平台检测指令，实现智能命令路由逻辑

## 已完成
- ✅ 分析当前sync相关命令文档结构
  - sync.md: 双向同步命令
  - epic-sync.md: Epic到GitHub同步
  - issue-sync.md: 本地更新到GitHub同步
- ✅ 识别需要修改的命令文件

## 进行中
- 🔄 最终验证和提交

## 已完成 (新增)
- ✅ 设计灵活的平台检测前置指令逻辑
- ✅ 在sync.md开头增加平台检测前置指令
- ✅ 在epic-sync.md开头增加平台检测前置指令
- ✅ 在issue-sync.md开头增加平台检测前置指令
- ✅ 实现向后兼容的配置读取逻辑
- ✅ 添加智能命令路由机制
- ✅ 验证前置检查逻辑的向后兼容性

## 计划中
- 提交所有修改并更新进度文档

## 技术决策
1. **配置检测策略**: 支持多种配置格式
   - 优先检查 `.claude/ccpm.config` (当前bash格式)
   - 支持YAML格式 (如Stream A后续提供)
   - 提供默认GitHub兼容性

2. **前置指令设计**: 最小化对原有逻辑的修改
   - 仅在命令开头增加平台检测部分
   - 基于检测结果动态加载规则
   - 保持原有GitHub逻辑完全不变

3. **智能路由机制**:
   - 配置驱动的平台选择
   - 规则文件动态加载
   - 向后兼容的默认行为

## 障碍
- 等待Stream A提供标准配置格式定义

## 下步计划
1. 基于现有配置结构实现前置检查逻辑
2. 修改三个sync命令文档
3. 测试向后兼容性
4. 创建提交并更新文档