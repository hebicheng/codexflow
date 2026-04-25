# CodexFlow Android

CodexFlow Android 是面向 Mac Agent HTTP API + SSE 的原生 Android 客户端。App 不直接调用 Codex CLI、`codex app-server` 或 JSON-RPC，也不做 OCR、终端截图或远程 shell 控制。

## 打开 Android Studio

1. 打开 Android Studio。
2. 选择 `Open`。
3. 选择仓库内目录：

```text
android/CodexFlowAndroid
```

## 启动 Mac Agent

在仓库根目录启动默认本机监听：

```bash
go run ./cmd/codexflow-agent
```

真机调试时，让 Agent 监听局域网：

```bash
CODEXFLOW_LISTEN_ADDR=0.0.0.0:4318 go run ./cmd/codexflow-agent
```

## Base URL

Android Emulator 访问 Mac 本机 Agent 使用：

```text
http://10.0.2.2:4318
```

真机访问需要填写 Mac 的局域网地址，例如：

```text
http://192.168.1.10:4318
```

## 验证 Agent

在 Mac 上执行：

```bash
curl http://127.0.0.1:4318/healthz
curl http://127.0.0.1:4318/api/v1/dashboard
```

在 Android App 的 Settings 页面可以保存 base URL，并通过“测试连接”调用 `GET /healthz`。

## 当前支持

- Dashboard 展示 Agent 状态、SSE 状态、统计和真实会话列表。
- 新建受控会话：`POST /api/v1/sessions` with `{"action":"start",...}`。
- 会话详情展示 summary、turn、plan、diff、timeline、命令输出和状态。
- 历史/已结束会话可以 resume 接管。
- 支持 startTurn、steer 当前 inProgress turn、interrupt、end、archive。
- Approvals 页面支持 command、fileChange、permissions、userInput resolve。
- Settings 使用 DataStore Preferences 持久化 Agent base URL。
- 使用 SSE `GET /api/v1/events` 实时刷新 dashboard 和当前 session detail，断线后指数退避重连。

## 当前未支持

- 登录、设备配对、relay、APNs/FCM 推送。
- 自动审批策略。
- 直接远程终端、终端截图、OCR、远程 shell。
- Android 桌面小组件或通知前台服务。

## 构建

```bash
cd android/CodexFlowAndroid
./gradlew :app:testDebugUnitTest
./gradlew :app:assembleDebug
```
