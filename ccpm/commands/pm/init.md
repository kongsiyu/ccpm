---
allowed-tools: Bash, Read, Write, LS
---

# PM Init - Project Initialization

Initialize project management structure with platform-specific configuration.

## Usage
```
/pm:init
```

## Instructions

Execute platform-aware initialization with automatic routing:

```bash
!bash -c 'source ".claude/lib/platform-detection.sh" && smart_platform_detection && platform=$(get_platform_type) && echo "🔄 检测到平台: $platform，正在路由到对应的init实现..." && route_to_platform_script "init"'
```
