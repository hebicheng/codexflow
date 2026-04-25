# CodexFlow

CodexFlow 是一个面向 Codex CLI 的控制台客户端。

它的目标不是“远程看终端”，而是把 Codex 的会话、turn、diff、审批、状态流，整理成一套适合手机和轻量客户端管理的控制平面。

当前仓库包含三部分：

- `Go Agent`：运行在本地电脑上的服务，负责接入 Codex CLI
- `iOS App`：运行在 iPhone 上的 SwiftUI 客户端，负责监控、审批和继续指挥
- `Flutter App`：新的跨平台客户端，负责 Android / Web / 桌面端接入同一套 Agent API

## 工作原理

CodexFlow 不依赖 OCR，也不是去截图识别终端。

它直接接在 `codex app-server` 之上，通过结构化协议拿到真实的会话和执行状态，再转成适合移动端消费的 API。

整体链路如下：

```text
Codex CLI / codex app-server
        │
        │ JSON-RPC over stdio
        ▼
Go Agent
  - 启动并持有本地 codex app-server
  - 发现已有 session / loaded session
  - 接收通知、diff、plan、审批请求
  - 暴露 HTTP API + SSE
        │
        │ HTTP / SSE
        ▼
Client Apps
  - iOS SwiftUI App
  - Flutter App
  - 会话总览 / 会话详情 / 审批中心
  - 继续下一步 / steer / interrupt
```

这套设计的核心点是：

- `Go Agent` 负责把 Codex 的原始协议适配成稳定的应用层接口
- 客户端不直接操纵终端，而是操纵会话本身
- “自动发现已有会话”和“受控管理新会话”可以同时存在

## 当前已实现的功能

### Go Agent

- 直接启动并连接本机 `codex app-server`
- 自动发现真实的 Codex 历史会话
- 读取 `thread/list`、`thread/read`、`thread/loaded/list`
- 支持新建受控会话
- 支持重新接管历史会话
- 支持开始新 turn、steer 当前 turn、interrupt 当前 turn
- 支持结束会话、归档会话
- 捕获命令审批、文件变更审批、权限审批、结构化用户输入请求
- 对外提供 HTTP API 和 SSE 事件流

### iOS App

- 会话总览页
- 已接管 / 已结束 / 历史会话分组
- 总会话、已加载、运行中、待审批统计
- 会话详情页
- plan / diff / timeline 展示
- 继续下一步、steer、interrupt
- 审批中心
- Agent 地址配置
- 只显示真实数据，不再回退 mock 数据

### Flutter App

- 复用同一套 Agent HTTP API
- 会话总览页
- 会话详情页
- 审批中心
- 设置页 / Agent 地址配置
- Android / Web / 桌面端 runner 已补齐
- 已适配浏览器跨域访问本地 Agent

## 当前支持的端

- `Go Agent`：Windows、Linux、macOS (go原生支持多端)
- `客户端支持平台`：Windows、Linux、macOS、iOS、Android、Web
- `iOS SwiftUI App`：iOS
- `Flutter App`：Windows、Linux、macOS、iOS、Android、Web

## 当前已验证可用的端

- `Go Agent`（macOS）
- `iOS SwiftUI App`
- `Flutter Web (Chrome)`
- `Flutter Android`（MuMu 模拟器）

## 发布产物

- Android 安装包已经发布在 GitHub Releases
- Web 构建产物也已经发布在 GitHub Releases
- 如果你只是想直接试用，可以优先从 GitHub Releases 下载对应版本

## 当前状态

项目已经能跑通真实链路：

- Agent 可以连上本机 Codex CLI
- `dashboard` API 能返回真实会话数据
- iOS 客户端可以消费真实数据并进行操作
- Flutter Web 客户端可以通过浏览器访问本地 Agent
- Flutter Android 客户端可以在模拟器中访问局域网 Agent

当前还没有做的部分：

- 远程 relay
- 登录与设备配对
- APNs 推送
- macOS 菜单栏 Launcher
- 自动审批策略引擎
- 完整的 SSE 实时刷新体验

## 快速开始

### 1. 环境要求

- Windows / Linux / macOS（运行 Agent）
- 已安装并可用的 `codex` CLI
- 已完成 Codex 登录
- Go 1.26+
- Xcode（仅在运行 iOS App 时需要）
- Flutter（仅在运行 Flutter App 时需要）

### 2. 启动 Go Agent

在仓库根目录执行：

```bash
go run ./cmd/codexflow-agent
```

默认监听地址：

```text
127.0.0.1:4318
```

可选环境变量：

- `CODEXFLOW_LISTEN_ADDR`
- `CODEXFLOW_CODEX_PATH`
- `CODEXFLOW_REFRESH_INTERVAL`
- `CODEXFLOW_STATE_DB_PATH`

如果你的 `codex` 不在系统 `PATH` 里，可以显式指定它：

```bash
CODEXFLOW_CODEX_PATH=/path/to/codex go run ./cmd/codexflow-agent
```

例如：

- macOS / Linux：`CODEXFLOW_CODEX_PATH=/usr/local/bin/codex`
- Windows：`CODEXFLOW_CODEX_PATH=C:\path\to\codex.exe`

如果你想先编译再运行：

```bash
go build -o codexflow-agent ./cmd/codexflow-agent
./codexflow-agent
```

在 Windows 上可执行文件会是：

```text
codexflow-agent.exe
```

### 3. Agent 多端使用方式

推荐的部署方式是：

1. 在安装了 `codex` CLI 的那台主机上运行 `Go Agent`
2. 让 Agent 暴露一个本机或局域网可访问的 HTTP 地址
3. 用 iOS / Android / Web / 桌面客户端去连接这个地址

同机使用：

```text
Agent: 127.0.0.1:4318
Client: http://127.0.0.1:4318
```

跨设备使用：

```bash
CODEXFLOW_LISTEN_ADDR=0.0.0.0:4318 go run ./cmd/codexflow-agent
```

然后在客户端里填写运行 Agent 那台机器的局域网 IP，例如：

```text
http://192.168.1.10:4318
```

#### 通过 Tailscale Service 远程访问（可选）

如果你希望在局域网外用 Android / iOS / Web 客户端访问 CodexFlow，可以把 Agent 和 Web 客户端只绑定到本机回环地址，再通过 Tailscale Service 暴露一个 tailnet 内部 HTTPS 入口。这样不需要把 CodexFlow 直接暴露到公网，也不需要在手机上记端口。

示例拓扑：

```text
https://codexflow.<tailnet>.ts.net/
  /healthz -> http://127.0.0.1:4318/healthz
  /api     -> http://127.0.0.1:4318/api
  /        -> http://127.0.0.1:8088
```

先启动 Agent：

```bash
CODEXFLOW_LISTEN_ADDR=127.0.0.1:4318 go run ./cmd/codexflow-agent
```

再启动一个静态文件服务承载 Flutter Web 构建产物，例如：

```bash
cd flutter/codexflow/build/web
python3 -m http.server 8088 --bind 127.0.0.1
```

然后配置 Tailscale Service。下面假设 service 名称是 `svc:codexflow`：

```bash
tailscale serve --service svc:codexflow --bg --https 443 http://127.0.0.1:8088
tailscale serve --service svc:codexflow --bg --https 443 --set-path /api http://127.0.0.1:4318/api
tailscale serve --service svc:codexflow --bg --https 443 --set-path /healthz http://127.0.0.1:4318/healthz
```

如果 Tailscale 提示需要管理员批准，需要先在 Tailscale 控制台批准这台机器作为 `svc:codexflow` 的 service proxy。批准后，在客户端里填写：

```text
https://codexflow.<tailnet>.ts.net
```

安全提醒：当前 CodexFlow Agent 还没有内置登录和设备配对机制。远程访问时建议只使用 tailnet 内部的 Tailscale Service，并配合 Tailscale ACL 限制可访问设备；不要用 Funnel 或公网反向代理直接公开 CodexFlow。

### 4. 验证 Agent 是否正常

```bash
curl http://127.0.0.1:4318/healthz
curl http://127.0.0.1:4318/api/v1/dashboard
```

如果正常，你会拿到健康检查结果和真实会话列表。

### 5. 运行 iOS App

用 Xcode 打开：

```text
ios/CodexFlow/CodexFlow.xcodeproj
```

然后运行 `CodexFlow` target。

### 6. 运行 Flutter App

Flutter 项目目录：

```text
flutter/codexflow
```

在该目录执行：

```bash
cd flutter/codexflow
flutter pub get
flutter run
```

如果要指定设备，例如：

```bash
flutter run -d chrome
flutter run -d emulator-5554
```

### 7. 运行 Web 版本

先构建 Web（已上传到release，可以直接下载使用）：

```bash
cd flutter/codexflow
flutter build web --release
```

构建产物目录：

```text
flutter/codexflow/build/web
```

本地运行最推荐直接用 Python：

```bash
cd flutter/codexflow/build/web
python3 -m http.server 8080
```

然后浏览器打开：

```text
http://127.0.0.1:8080
```

其他方式也可以，例如：

- `npx serve build/web`
- `busybox httpd`
- `Nginx / Caddy / Apache`
- 任意静态站点托管服务

### 8. 在 App 里配置 Agent 地址

如果是同一台 Mac 上跑模拟器：

```text
http://127.0.0.1:4318
```

如果是 `iPhone 真机`、`Android 模拟器`、`Android 真机`，或者你要给其他设备访问，建议让 Agent 监听局域网：

```bash
CODEXFLOW_LISTEN_ADDR=0.0.0.0:4318 go run ./cmd/codexflow-agent
```

然后在 App 的 `Settings` 页面填入你 Mac 的局域网 IP，例如：

```text
http://192.168.1.10:4318
```

补充说明：

- `Flutter Web / Chrome`：如果页面和 Agent 在同一台 Mac 上，通常可直接使用 `http://127.0.0.1:4318`
- `Android 模拟器 / 真机`：不要填 `127.0.0.1`，要填你 Mac 的局域网 IP
- 当前 Agent 已加入浏览器跨域支持，Flutter Web 可以直接访问本地 Agent
- 如果 Android release APK 报 `ClientException with SocketException: Failed host lookup`，请确认 `android/app/src/main/AndroidManifest.xml` 声明了 `android.permission.INTERNET`。Debug/Profile manifest 中的权限不会自动覆盖 release 包。

## 基本使用方式

1. 打开 `会话` 页面，查看当前真实会话。
2. 对历史会话点击“接管到 CodexFlow”，将其转为受控会话。
3. 在受控会话详情页查看 plan、diff、timeline。
4. 在受控会话详情页发送下一轮 prompt，或 steer 当前执行中的 turn。
5. 对正在执行的 turn，可以直接 interrupt。
6. 打开 `Approvals` 页面，处理等待中的审批请求。
7. 对不再需要的会话，可以结束或归档。

## API 概览

- `GET /healthz`
- `GET /api/v1/dashboard`
- `GET /api/v1/sessions`
- `POST /api/v1/sessions`
- `GET /api/v1/sessions/:id`
- `POST /api/v1/sessions/:id/resume`
- `POST /api/v1/sessions/:id/end`
- `POST /api/v1/sessions/:id/archive`
- `POST /api/v1/sessions/:id/turns/start`
- `POST /api/v1/sessions/:id/turns/steer`
- `POST /api/v1/sessions/:id/turns/interrupt`
- `GET /api/v1/approvals`
- `POST /api/v1/approvals/:id/resolve`
- `GET /api/v1/events`

## 仓库结构

```text
cmd/codexflow-agent        Go Agent 启动入口
internal/codex            Codex app-server 协议适配
internal/runtime          会话管理、统计、审批编排
internal/httpapi          HTTP API 与 SSE
internal/store            本地状态存储
ios/CodexFlow             iOS SwiftUI 客户端
flutter/codexflow         Flutter 跨平台客户端
docs                      架构与路线文档
assets                    README 截图资源
```

## 截图

### iOS

<table>
  <tr>
    <td><img src="assets/screenshot-01.jpeg" alt="Screenshot 01" width="240"></td>
    <td><img src="assets/screenshot-02.jpeg" alt="Screenshot 02" width="240"></td>
  </tr>
  <tr>
    <td><img src="assets/screenshot-03.jpeg" alt="Screenshot 03" width="240"></td>
    <td><img src="assets/screenshot-04.jpeg" alt="Screenshot 04" width="240"></td>
  </tr>
  <tr>
    <td><img src="assets/screenshot-05.jpeg" alt="Screenshot 05" width="240"></td>
    <td><img src="assets/screenshot-06.jpeg" alt="Screenshot 06" width="240"></td>
  </tr>
  <tr>
    <td><img src="assets/screenshot-07.jpeg" alt="Screenshot 07" width="240"></td>
    <td><img src="assets/screenshot-08.jpeg" alt="Screenshot 08" width="240"></td>
  </tr>
  <tr>
    <td><img src="assets/screenshot-09.jpeg" alt="Screenshot 09" width="240"></td>
    <td></td>
  </tr>
</table>

### Android

<table>
  <tr>
    <td><img src="assets/screenshot_android_01.png" alt="Android Screenshot 01" width="240"></td>
    <td><img src="assets/screenshot_android_02.png" alt="Android Screenshot 02" width="240"></td>
  </tr>
</table>

### Web

<table>
  <tr>
    <td><img src="assets/screenshot_web_01.png" alt="Web Screenshot 01" width="240"></td>
    <td><img src="assets/screenshot_web_02.png" alt="Web Screenshot 02" width="240"></td>
  </tr>
</table>

## 说明

下一阶段计划：

- SSE 实时刷新
- macOS Launcher
- 局域网外的安全 relay
- 推送通知
- 自动审批策略
