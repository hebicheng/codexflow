# CodexFlow Windows

CodexFlow Windows 是 CodexFlow 的桌面控制台。它只通过 Mac Agent 暴露的 HTTP API 与 SSE 事件流操作 session、turn、approval、diff、plan 和 timeline。

它不是新的 Agent，不直接调用 Codex CLI，不直接连接 codex app-server，不做 JSON-RPC、远程终端截图或 OCR。

## 工具链

- Visual Studio 2022 17.x
- Windows App SDK
- .NET SDK 8.0 或更高
- Windows 10 19041+ / Windows 11

当前项目 TargetFramework 使用：

```xml
net8.0-windows10.0.19041.0
```

原因：当前开发环境是 macOS，且没有安装 `dotnet`、`msbuild` 或 WinUI 3 模板，无法创建或验证 `net10.0-windows` WinUI 项目。后续在安装了 .NET 10 LTS 与 Windows App SDK 的 Windows 开发机上，可以将 app 和 tests retarget 到 `net10.0-windows10.0.19041.0`。

## 打开项目

用 Visual Studio 打开：

```text
windows/CodexFlowWindows/CodexFlowWindows.sln
```

启动项目选择 `CodexFlowWindows`，然后运行 Debug。

## 启动 Agent

在 Mac 的仓库根目录执行：

```bash
go run ./cmd/codexflow-agent
```

默认监听：

```text
127.0.0.1:4318
```

如果 Windows App 和 Agent 不在同一台机器，Mac Agent 必须监听局域网：

```bash
CODEXFLOW_LISTEN_ADDR=0.0.0.0:4318 go run ./cmd/codexflow-agent
```

然后在 Windows App 的 Settings 中填写 Mac 局域网地址，例如：

```text
http://192.168.1.10:4318
```

## 验证连接

在 Windows 机器上先用浏览器或 PowerShell 验证：

```powershell
curl http://127.0.0.1:4318/healthz
curl http://127.0.0.1:4318/api/v1/dashboard
```

跨机器时把地址替换为 Mac 局域网地址。

Windows App 内也可以在 Settings 页面点击“测试连接”，它会调用：

```text
GET /healthz
```

## 已支持

- 默认 Agent 地址 `http://127.0.0.1:4318`
- Settings 保存、恢复默认、测试连接
- Dashboard 显示真实 Agent stats、sessions、approvals
- 宽屏三栏布局，窄屏自动折叠
- 新建受控会话
- resume 历史会话
- end / archive 会话，带二次确认
- session detail 展示 turns、plan、diff、timeline
- composer 发送 startTurn / steerTurn
- interrupt 当前 turn
- approvals 处理 command、fileChange、permissions、userInput
- SSE 连接、业务事件刷新 dashboard/session detail、断线指数退避重连
- 快捷键：Ctrl+R、Ctrl+L、Ctrl+N、Ctrl+Enter、Esc
- 本地配置存储在 `%APPDATA%/CodexFlow/settings.json`

## 暂未支持

- 系统托盘 / 最小化到托盘
- diff 搜索
- 登录、relay、推送
- 自动审批策略
- 终端截图、OCR、远程 shell

## 常见问题

### Windows App 连接不到 Mac Agent

先确认 Windows 可以访问 Mac 的 4318 端口：

```powershell
curl http://192.168.1.10:4318/healthz
```

如果失败，检查 Mac IP、同一局域网、防火墙和 Agent 监听地址。

### 防火墙阻止 4318

允许 Mac 上的 Go/Agent 进程接受局域网入站连接，或临时放行 TCP 4318。

### base URL 填错

Settings 中必须填完整 URL，包括 `http://` 和端口，例如：

```text
http://192.168.1.10:4318
```

不要填写 `0.0.0.0`。`0.0.0.0` 只用于 Agent 监听，不是客户端连接地址。

### Agent 只监听 127.0.0.1

如果 Mac Agent 只监听 `127.0.0.1:4318`，局域网里的 Windows 机器无法访问。使用：

```bash
CODEXFLOW_LISTEN_ADDR=0.0.0.0:4318 go run ./cmd/codexflow-agent
```

### SSE 断线重连

客户端会自动重连 SSE：初始 1 秒，指数退避，最大 30 秒。Settings 中保存新的 base URL 后，SSE 会停止旧连接并重新连接。
