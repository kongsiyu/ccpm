# 路由范围明确

## 需要路由的命令（仅3个）

### 1. /pm:epic-sync
- **原因**: 直接调用GitHub API创建/更新issues
- **路由目标**: epic-sync/ → epic-sync-yunxiao/

### 2. /pm:issue-sync  
- **原因**: 直接调用GitHub API更新issue状态
- **路由目标**: issue-sync/ → issue-sync-yunxiao/

### 3. /pm:init
- **原因**: 检测环境（gh CLI vs 云效MCP）
- **路由目标**: init.sh → init-yunxiao.sh

## 不需要路由的命令

- **epic-start** - 本地启动agents，无平台API交互
- **epic-status** - 读取本地文件显示状态
- **epic-list** - 读取本地epic目录
- **epic-show** - 显示本地epic内容
- **epic-close** - 更新本地状态（同步由epic-sync负责）
- **prd-*** - PRD管理，纯本地操作
- 其他本地文件操作命令

## 设计原则

**只有直接调用平台API的命令才需要路由。**

本地工作流管理命令保持平台无关，通过epic-sync/issue-sync统一同步到平台。
