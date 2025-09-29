#!/bin/bash

# Debug script to test YAML parsing logic

YAML_CONFIG=".claude/ccpm.yaml"

echo "🔍 YAML Parsing Debug"
echo "===================="
echo ""

if [ -f "$YAML_CONFIG" ]; then
    echo "📁 Configuration file found: $YAML_CONFIG"
    echo ""

    echo "📄 File contents:"
    echo "----------------"
    cat "$YAML_CONFIG"
    echo ""
    echo "----------------"
    echo ""

    echo "🔍 Platform detection process:"
    echo ""

    # Test with yq if available
    if command -v yq >/dev/null 2>&1; then
        echo "✅ yq available - using yq parsing:"
        PLATFORM_YQ=$(yq eval '.platform.type' "$YAML_CONFIG" 2>/dev/null || echo "github")
        echo "   Result: '$PLATFORM_YQ'"
        echo ""
    else
        echo "❌ yq not available"
        echo ""
    fi

    echo "🔧 Fallback parsing (current logic):"
    echo "   Step 1 - Find platform section:"
    grep -A 5 "^platform:" "$YAML_CONFIG"
    echo ""

    echo "   Step 2 - Extract type line:"
    grep -A 5 "^platform:" "$YAML_CONFIG" | grep "type:"
    echo ""

    echo "   Step 3 - Clean and extract value:"
    EXISTING_PLATFORM=$(grep -A 5 "^platform:" "$YAML_CONFIG" | grep "type:" | sed 's/.*type:[ ]*//g' | sed 's/[\"'\'']*//g' | sed 's/[ ]*#.*//g' | head -1)
    echo "   Final result: '$EXISTING_PLATFORM'"
    echo ""

    if [ -z "$EXISTING_PLATFORM" ]; then
        echo "⚠️ Empty result - will default to 'github'"
    else
        echo "✅ Successfully parsed platform: $EXISTING_PLATFORM"
    fi

else
    echo "❌ Configuration file not found: $YAML_CONFIG"
fi