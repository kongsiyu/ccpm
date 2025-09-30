---
allowed-tools: Bash, Read, Write, LS
---

# PM Init - Project Initialization

Initialize project management structure with platform-specific configuration.

## Usage
```
/pm:init
```

## Platform Detection and Routing

```bash
# Load platform detection library
source ".claude/lib/platform-detection.sh"

# Perform smart platform detection
if ! smart_platform_detection; then
    echo "❌ 平台配置检测失败，请检查配置"
    exit 1
fi

# Route to platform-specific implementation
platform=$(get_platform_type)
echo "🔄 检测到平台: $platform，正在路由到对应的init实现..."

case "$platform" in
    "yunxiao")
        # Route to Yunxiao init implementation
        echo "🚀 路由到云效平台的init实现"
        route_to_platform_script "init" "$@"
        ;;
    "github")
        echo "✅ 使用GitHub平台的init实现"
        # Continue with current GitHub implementation below
        ;;
    *)
        echo "❌ 不支持的平台类型: $platform"
        exit 1
        ;;
esac
```

## GitHub Platform Implementation

Execute GitHub platform initialization:

```bash
!bash ccpm/scripts/pm/init.sh
```
