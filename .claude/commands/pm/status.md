---
allowed-tools: Bash, Read, Write, LS
---

# PM Status - Project Status Report

Display comprehensive project status across platforms.

## Usage
```
/pm:status
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
echo "🔄 检测到平台: $platform，正在路由到对应的status实现..."

case "$platform" in
    "yunxiao")
        # Route to Yunxiao status implementation
        if [[ -f ".claude/scripts/pm/status-yunxiao.sh" ]]; then
            exec ".claude/scripts/pm/status-yunxiao.sh" "$@"
        else
            echo "❌ 云效平台的status脚本不存在"
            echo "💡 请确保已完成云效集成的相关任务"
            exit 1
        fi
        ;;
    "github")
        echo "✅ 使用GitHub平台的status实现"
        # Continue with current GitHub implementation below
        ;;
    *)
        echo "❌ 不支持的平台类型: $platform"
        exit 1
        ;;
esac
```

## GitHub Platform Implementation

Execute GitHub platform status report:

```bash
!bash ccpm/scripts/pm/status.sh
```
