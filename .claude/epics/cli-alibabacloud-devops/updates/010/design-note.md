# 设计调整说明

## 原设计问题
原计划在每个PM命令中添加平台路由逻辑，这样会导致：
- 代码重复
- 维护困难
- 不够优雅

## 新设计方案
创建统一的平台路由shell脚本：

```
.claude/lib/platform-router.sh
```

这个脚本负责：
1. 检测平台类型（GitHub/yunxiao）
2. 根据命令名路由到对应的脚本
3. 透明传递所有参数

## 命令集成方式
原有命令（如 `/pm:epic-sync`）只需简单调用路由器：

```bash
#!/bin/bash
source .claude/lib/platform-router.sh
route_pm_command "epic-sync" "$@"
```

这样：
- ✅ 代码简洁
- ✅ 易于维护
- ✅ 统一管理路由逻辑
- ✅ 不破坏现有结构
