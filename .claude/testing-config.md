
---
framework: bash
test_command: bash
epic: cli-alibabacloud-devops
created: 2025-09-30T14:05:00Z
---

# Testing Configuration - Epic: cli-alibabacloud-devops

## Framework
- Type: Bash Shell Scripts
- Version: GNU bash 5.2+
- Test Framework: Custom (tests/utils/test-framework.sh)
- Config File: N/A (Bash-based testing)

## Test Structure
- Test Directory: `tests/`
- Test Files: 4 files found
  - 1 test framework utility
  - 3 test suites
- Naming Pattern: `test-*.sh`

### Test Organization
```
tests/
├── utils/
│   └── test-framework.sh          # Test framework utilities
├── integration/
│   └── yunxiao/
│       └── test-yunxiao-complete.sh    # 云效功能完整性测试
├── e2e/
│   └── test-workflow-complete.sh       # 端到端工作流测试
└── regression/
    └── github-baseline/
        └── test-github-zero-impact.sh  # GitHub零影响验证
```

## Test Suites

### 1. Integration Tests - 云效功能完整性
**File**: `tests/integration/yunxiao/test-yunxiao-complete.sh`
**Purpose**: 验证云效平台集成的所有核心功能
**Test Areas**:
- 平台检测功能测试 (4个用例)
- 配置验证功能测试 (3个用例)
- 命令路由功能测试 (3个用例)
- 云效工作项CRUD测试 (2个用例)
- Epic同步功能测试 (2个用例)
- 错误处理测试 (3个用例)

### 2. E2E Tests - 完整工作流
**File**: `tests/e2e/test-workflow-complete.sh`
**Purpose**: 验证完整的开发工作流程
**Test Scenarios**:
- GitHub工作流完整测试
- 云效工作流完整测试
- 平台切换工作流测试
- 命令透明性测试
- 配置持久性测试

### 3. Regression Tests - GitHub零影响验证
**File**: `tests/regression/github-baseline/test-github-zero-impact.sh`
**Purpose**: 确保云效集成不影响现有GitHub功能
**Validation**:
- 无配置时默认GitHub行为
- GitHub配置正常工作
- 现有脚本未被修改
- 现有工作流完全正常

## Commands

### Run All Tests
```bash
bash tests/integration/yunxiao/test-yunxiao-complete.sh
bash tests/e2e/test-workflow-complete.sh
bash tests/regression/github-baseline/test-github-zero-impact.sh
```

### Run Specific Suite
```bash
# 云效集成测试
bash tests/integration/yunxiao/test-yunxiao-complete.sh

# 端到端工作流测试
bash tests/e2e/test-workflow-complete.sh

# GitHub零影响验证
bash tests/regression/github-baseline/test-github-zero-impact.sh
```

### Run with Debugging
```bash
DEBUG_MODE=1 bash tests/integration/yunxiao/test-yunxiao-complete.sh
```

## Environment

### Required Tools
- ✅ bash (GNU bash 5.2+)
- ✅ gh (GitHub CLI)
- ⚠️ jq (JSON processor) - **需要安装**
- grep, awk, sed (标准Unix工具)

### Optional MCP Services
- 阿里云云效 MCP Server (用于实际云效API测试)
- 配置文件: 用户自行在Claude Code中配置

### Test Configuration Files
- `.ccpm-config.yaml` - 平台配置 (测试时创建)
- 测试fixture数据位于 `tests/fixtures/`

## Test Runner Agent Configuration

### Execution Rules
1. **使用自定义Bash测试框架**
   - 基于 `tests/utils/test-framework.sh`
   - 提供统一的断言和结果管理

2. **顺序执行**
   - 不使用并行执行
   - 每个测试套件独立运行

3. **详细输出**
   - 使用 `DEBUG_MODE=1` 启用调试输出
   - 捕获完整的错误栈

4. **真实环境**
   - 不使用mock服务
   - 实际检测系统环境
   - 需要MCP服务时会跳过相关测试

5. **测试隔离**
   - 每个测试清理自己的临时文件
   - 不修改实际的配置文件
   - 使用临时目录进行测试

## Pre-run Checklist

### ⚠️ Required Actions
1. **安装 jq** (JSON处理工具)
   ```bash
   # Windows (使用 Chocolatey)
   choco install jq

   # 或者从官网下载
   # https://jqlang.github.io/jq/download/
   ```

2. **验证 bash 可用**
   ```bash
   bash --version
   ```

3. **验证 GitHub CLI**
   ```bash
   gh --version
   ```

### Optional (用于完整测试)
4. **配置云效 MCP Server**
   - 参考: `doc/yunxiao/yunxiao-integration.md`
   - 仅在实际测试云效API时需要

## Common Issues

### Issue 1: jq not found
**Error**: `command not found: jq`
**Solution**: 安装 jq
```bash
# Windows
choco install jq

# Linux
sudo apt-get install jq  # Debian/Ubuntu
sudo yum install jq      # RHEL/CentOS

# macOS
brew install jq
```

### Issue 2: Permission denied
**Error**: `Permission denied: ./test-*.sh`
**Solution**: 添加执行权限
```bash
chmod +x tests/**/*.sh
```

### Issue 3: CRLF line endings (Windows)
**Error**: `$'\r': command not found`
**Solution**: 转换为LF格式
```bash
dos2unix tests/**/*.sh
# 或在 git 中配置
git config core.autocrlf false
```

### Issue 4: MCP not configured
**Behavior**: 云效相关测试会被跳过
**Solution**: 这是正常行为，测试会报告跳过的原因

## Testing Strategy

### 1. Unit-level Tests (Component Tests)
- **平台检测**: 验证 `platform-detection.sh`
- **配置验证**: 验证配置文件解析
- **MCP调用**: 验证MCP基础设施（需要MCP服务）

### 2. Integration Tests
- **命令路由**: 验证平台路由逻辑
- **脚本集成**: 验证各个云效脚本的集成

### 3. E2E Tests
- **完整工作流**: PRD → Epic → Task → 同步
- **平台切换**: GitHub ↔ 云效切换

### 4. Regression Tests
- **GitHub功能**: 确保现有功能不受影响
- **向后兼容**: 验证无配置时的行为

## Test Coverage

### Functional Coverage
- ✅ 平台检测和路由
- ✅ 配置管理
- ✅ 命令集成
- ⚠️ MCP API调用 (需要实际MCP服务)
- ✅ 错误处理
- ✅ GitHub兼容性

### Edge Cases
- ✅ 无配置文件
- ✅ 无效配置
- ✅ 平台切换
- ✅ 文件权限问题
- ⚠️ 网络错误 (需要实际环境)

## Notes

- **测试框架**: 自定义Bash测试框架，简单但有效
- **依赖最小**: 主要依赖标准Unix工具
- **环境限制**: 部分测试需要实际的云效MCP服务才能完整执行
- **Windows兼容**: 在Git Bash/WSL环境下运行
- **隔离性**: 测试不会修改实际项目配置

## Next Steps

1. ✅ 测试框架已配置
2. ⚠️ 安装缺失依赖 (jq)
3. ✅ 运行回归测试验证GitHub功能
4. ⏳ 配置云效MCP后运行完整测试