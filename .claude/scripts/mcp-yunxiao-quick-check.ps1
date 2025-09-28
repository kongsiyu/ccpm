# 阿里云云效MCP连接快速检查脚本 (PowerShell)
# 适用于Windows环境的快速诊断工具

param(
    [switch]$Verbose = $false,
    [switch]$Fix = $false
)

# 颜色函数
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "✓ $Message" -Color "Green"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "⚠ $Message" -Color "Yellow"
}

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "✗ $Message" -Color "Red"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput "ℹ $Message" -Color "Cyan"
}

# 检查统计
$script:TotalChecks = 0
$script:PassedChecks = 0
$script:FailedChecks = 0

function Start-Check {
    $script:TotalChecks++
}

function Complete-Check {
    param([bool]$Success)
    if ($Success) {
        $script:PassedChecks++
    } else {
        $script:FailedChecks++
    }
}

# 1. 检查Node.js和npm
function Test-NodeEnvironment {
    Write-Info "检查Node.js和npm环境..."
    Start-Check

    try {
        $nodeVersion = node --version 2>$null
        $npmVersion = npm --version 2>$null

        if ($nodeVersion -and $npmVersion) {
            Write-Success "Node.js $nodeVersion, npm $npmVersion 已安装"
            Complete-Check $true
            return $true
        }
    } catch {
        Write-Error "Node.js或npm未安装或不可用"
        Write-Info "请访问 https://nodejs.org 下载安装Node.js"
        Complete-Check $false
        return $false
    }
}

# 2. 检查MCP服务器安装
function Test-McpServerInstallation {
    Write-Info "检查alibabacloud-devops-mcp-server安装..."
    Start-Check

    # 检查全局安装
    try {
        $globalList = npm list -g alibabacloud-devops-mcp-server --depth=0 2>$null
        if ($globalList -match "alibabacloud-devops-mcp-server") {
            Write-Success "MCP服务器已全局安装"
            Complete-Check $true
            return $true
        }
    } catch {}

    # 检查可执行文件
    $mcpCommand = Get-Command "alibabacloud-devops-mcp-server" -ErrorAction SilentlyContinue
    if ($mcpCommand) {
        Write-Success "MCP服务器可执行文件已找到"
        Complete-Check $true
        return $true
    }

    Write-Error "MCP服务器未安装"
    Write-Info "安装命令: npm install -g alibabacloud-devops-mcp-server"

    if ($Fix) {
        Write-Info "尝试自动安装..."
        try {
            npm install -g alibabacloud-devops-mcp-server
            Write-Success "MCP服务器安装成功"
            Complete-Check $true
            return $true
        } catch {
            Write-Error "自动安装失败: $_"
        }
    }

    Complete-Check $false
    return $false
}

# 3. 检查Claude Code配置
function Test-ClaudeCodeConfig {
    Write-Info "检查Claude Code配置文件..."
    Start-Check

    $configPaths = @(
        "$env:USERPROFILE\.config\claude-code\mcp.json",
        "$env:APPDATA\claude-code\mcp.json",
        "$env:LOCALAPPDATA\claude-code\mcp.json"
    )

    foreach ($configPath in $configPaths) {
        if (Test-Path $configPath) {
            Write-Success "找到配置文件: $configPath"

            try {
                $config = Get-Content $configPath | ConvertFrom-Json
                if ($config.mcpServers.'alibabacloud-devops') {
                    Write-Success "云效MCP配置存在"
                    Complete-Check $true
                    return $true
                } else {
                    Write-Warning "配置文件存在但缺少云效配置"
                }
            } catch {
                Write-Warning "配置文件格式错误: $_"
            }
        }
    }

    Write-Error "未找到有效的Claude Code MCP配置"
    Write-Info "请创建配置文件: $($configPaths[0])"
    Complete-Check $false
    return $false
}

# 4. 检查项目配置
function Test-ProjectConfig {
    Write-Info "检查项目配置..."
    Start-Check

    $ccpmConfigPath = ".claude\ccpm.config"
    if (Test-Path $ccpmConfigPath) {
        Write-Success "找到CCPM配置文件"

        $config = Get-Content $ccpmConfigPath
        $projectIdLine = $config | Where-Object { $_ -match "project_id" }

        if ($projectIdLine) {
            $projectId = ($projectIdLine -split "=")[1].Trim(' "')
            if ($projectId) {
                Write-Success "项目ID已配置: $projectId"
                Complete-Check $true
                return $true
            } else {
                Write-Warning "项目ID配置为空"
            }
        } else {
            Write-Warning "未找到项目ID配置"
        }
    } else {
        Write-Error "未找到CCPM配置文件: $ccpmConfigPath"
    }

    Complete-Check $false
    return $false
}

# 5. 检查网络连接
function Test-NetworkConnectivity {
    Write-Info "检查网络连接..."
    Start-Check

    $endpoints = @("devops.aliyuncs.com", "ecs.aliyuncs.com")
    $allConnected = $true

    foreach ($endpoint in $endpoints) {
        try {
            $result = Test-NetConnection $endpoint -Port 443 -WarningAction SilentlyContinue
            if ($result.TcpTestSucceeded) {
                Write-Success "可以连接到 $endpoint"
            } else {
                Write-Warning "无法连接到 $endpoint"
                $allConnected = $false
            }
        } catch {
            Write-Warning "连接测试失败: $endpoint"
            $allConnected = $false
        }
    }

    Complete-Check $allConnected
    return $allConnected
}

# 生成报告
function Show-Report {
    Write-Host "`n========================================"
    Write-Host "         MCP连接诊断报告"
    Write-Host "========================================"
    Write-Host "总检查项目: $script:TotalChecks"
    Write-Success "通过检查: $script:PassedChecks"
    Write-Error "失败检查: $script:FailedChecks"

    $successRate = [math]::Round(($script:PassedChecks / $script:TotalChecks) * 100, 1)

    Write-Host "`n"
    if ($successRate -ge 80) {
        Write-Success "系统状态良好 ($successRate%)"
        Write-Info "建议: 可以尝试使用云效MCP功能"
    } elseif ($successRate -ge 60) {
        Write-Warning "系统状态一般 ($successRate%)"
        Write-Info "建议: 解决警告项目后再使用"
    } else {
        Write-Error "系统状态不佳 ($successRate%)"
        Write-Info "建议: 需要解决主要问题才能使用云效功能"
    }
}

# 提供解决方案
function Show-Solutions {
    Write-Host "`n========================================"
    Write-Host "         解决方案建议"
    Write-Host "========================================"

    Write-Info "1. 安装MCP服务器:"
    Write-Host "   npm install -g alibabacloud-devops-mcp-server"

    Write-Info "`n2. 创建MCP配置文件 ($env:USERPROFILE\.config\claude-code\mcp.json):"
    $configTemplate = @"
{
  "mcpServers": {
    "alibabacloud-devops": {
      "command": "alibabacloud-devops-mcp-server",
      "args": [],
      "env": {
        "ALIBABA_CLOUD_ACCESS_KEY_ID": "your_access_key",
        "ALIBABA_CLOUD_ACCESS_KEY_SECRET": "your_secret_key",
        "DEVOPS_ORG_ID": "your_org_id"
      }
    }
  }
}
"@
    Write-Host $configTemplate

    Write-Info "`n3. 配置项目ID (在.claude\ccpm.config中):"
    Write-Host "   project_id=your_project_id"

    Write-Info "`n4. 重启Claude Code使配置生效"
}

# 主函数
function Main {
    Write-Host "========================================"
    Write-Host "  阿里云云效MCP连接诊断工具 (Windows)"
    Write-Host "========================================"
    Write-Host ""

    Test-NodeEnvironment
    Test-McpServerInstallation
    Test-ClaudeCodeConfig
    Test-ProjectConfig
    Test-NetworkConnectivity

    Show-Report

    if ($script:FailedChecks -gt 0) {
        Show-Solutions
        exit 1
    } else {
        Write-Success "`n🎉 所有检查通过！云效MCP连接应该可以正常工作。"
        exit 0
    }
}

# 脚本入口
if ($MyInvocation.InvocationName -ne '.') {
    Main
}