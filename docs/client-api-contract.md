# CodexFlow Client API Contract

本文档定义 CodexFlow 客户端（iOS、Android、Windows）与 Mac Agent 之间的稳定应用层 API 契约。客户端只能通过本文档中的 HTTP API 与 SSE 事件流操作会话、turn、审批、diff、plan 和 timeline。

Windows 客户端不是新的 Agent，不直接调用 Codex CLI，不直接连接 codex app-server，不使用 JSON-RPC，不做远程终端截图或 OCR。

## Base URL

默认地址：

```text
http://127.0.0.1:4318
```

跨机器访问时，Mac Agent 需要监听局域网地址：

```bash
CODEXFLOW_LISTEN_ADDR=0.0.0.0:4318 go run ./cmd/codexflow-agent
```

Windows App 中填写 Mac 局域网地址，例如：

```text
http://192.168.1.10:4318
```

客户端拼接 URL 时必须避免双斜杠，GET 请求不得带 body，POST 请求的 `Content-Type` 必须为 `application/json`。空 body 的 POST 使用 `{}`。

## Error Response

非 2xx 响应优先解析：

```json
{
  "error": "message"
}
```

客户端应将其转换为可展示的 API 错误。无法解析时，错误文案至少包含 HTTP status code。

## Endpoints

### `GET /healthz`

用于测试 Agent 是否可达。

Response:

```json
{
  "ok": true,
  "timestamp": "2026-04-25T12:00:00.000000+08:00"
}
```

### `GET /api/v1/dashboard`

返回 Agent 快照、统计、会话摘要和待审批请求。

Response: `DashboardResponse`

```json
{
  "agent": {
    "connected": true,
    "startedAt": "2026-04-25T12:00:00.000000+08:00",
    "listenAddr": "127.0.0.1:4318",
    "codexBinaryPath": "codex"
  },
  "stats": {
    "totalSessions": 12,
    "loadedSessions": 3,
    "activeSessions": 1,
    "pendingApprovals": 2
  },
  "sessions": [],
  "approvals": []
}
```

### `GET /api/v1/sessions`

Response:

```json
{
  "data": [
    {
      "id": "thread-id",
      "name": "CodexFlow",
      "preview": "first user prompt",
      "cwd": "/Users/me/repo",
      "source": "cli",
      "status": "active",
      "activeFlags": ["waitingOnApproval"],
      "loaded": true,
      "updatedAt": 1760000000,
      "createdAt": 1759990000,
      "modelProvider": "openai",
      "branch": "main",
      "pendingApprovals": 1,
      "lastTurnId": "turn-id",
      "lastTurnStatus": "inProgress",
      "agentNickname": "",
      "agentRole": "",
      "ended": false
    }
  ]
}
```

### `POST /api/v1/sessions`

#### Refresh Sessions

Request:

```json
{
  "action": "refresh"
}
```

Response:

```json
{
  "ok": true
}
```

#### Start Managed Session

`cwd` 必须是绝对路径，`prompt` 不能为空。

Request:

```json
{
  "action": "start",
  "cwd": "/Users/me/repo",
  "prompt": "首轮 prompt"
}
```

Response: `SessionSummary`

### `GET /api/v1/sessions/:id`

Response: `SessionDetail`

### `POST /api/v1/sessions/:id/resume`

Request:

```json
{}
```

Response: `SessionSummary`

### `POST /api/v1/sessions/:id/end`

Request:

```json
{}
```

Response:

```json
{
  "ok": true
}
```

### `POST /api/v1/sessions/:id/archive`

Request:

```json
{}
```

Response:

```json
{
  "ok": true
}
```

### `POST /api/v1/sessions/:id/turns/start`

Request:

```json
{
  "prompt": "继续下一步"
}
```

Response: `TurnDetail`

### `POST /api/v1/sessions/:id/turns/steer`

Request:

```json
{
  "turnId": "turn-id",
  "prompt": "补充当前 turn 的方向"
}
```

Response:

```json
{
  "ok": true
}
```

### `POST /api/v1/sessions/:id/turns/interrupt`

Request:

```json
{
  "turnId": "turn-id"
}
```

Response:

```json
{
  "ok": true
}
```

### `GET /api/v1/approvals`

Response:

```json
{
  "data": []
}
```

`data` 元素类型为 `PendingRequestView`。

### `POST /api/v1/approvals/:id/resolve`

Request:

```json
{
  "result": {}
}
```

`result` 是透明 JSON 值，具体结构见 Approval Resolve Body Rules。

Response:

```json
{
  "ok": true
}
```

### `GET /api/v1/events`

SSE 事件流。服务端会发送业务事件：

```text
event: turn.started
data: {"type":"turn.started","timestamp":"2026-04-25T12:00:00Z","payload":{"threadId":"...","turnId":"..."}}

```

也会发送 ping 注释行：

```text
: ping

```

客户端必须忽略以 `:` 开头的注释行。

## Models

客户端模型字段在各平台可使用本地命名规范，JSON 属性必须兼容 Agent 的 camelCase。

### DashboardResponse

```ts
{
  agent: AgentSnapshot
  stats: DashboardStats
  sessions: SessionSummary[]
  approvals: PendingRequestView[]
}
```

### AgentSnapshot

```ts
{
  connected: boolean
  startedAt: string
  listenAddr: string
  codexBinaryPath: string
}
```

`startedAt` 是 RFC3339/ISO-8601 时间字符串。客户端可以保存为字符串或 `DateTimeOffset?`。

### DashboardStats

```ts
{
  totalSessions: number
  loadedSessions: number
  activeSessions: number
  pendingApprovals: number
}
```

### SessionSummary

```ts
{
  id: string
  name: string
  preview: string
  cwd: string
  source: string
  status: string
  activeFlags: string[]
  loaded: boolean
  updatedAt: number
  createdAt: number
  modelProvider: string
  branch: string
  pendingApprovals: number
  lastTurnId: string
  lastTurnStatus: string
  agentNickname: string
  agentRole: string
  ended: boolean
}
```

常见 `status`：`active`、`idle`、`completed`、`failed`、`systemError`、`notLoaded`。

常见 `lastTurnStatus`：`inProgress`、`completed`、`failed`。

常见 `activeFlags`：`waitingOnApproval`、`waitingOnUserInput`。

### SessionDetail

```ts
{
  summary: SessionSummary
  turns: TurnDetail[]
}
```

### TurnDetail

```ts
{
  id: string
  status: string
  startedAt: number
  completedAt: number
  durationMs: number
  error: string
  diff: string
  planExplanation: string
  plan: PlanStep[]
  items: TurnItem[]
}
```

### PlanStep

```ts
{
  step: string
  status: string
}
```

常见 `status`：`pending`、`in_progress`、`completed`。

### TurnItem

```ts
{
  id: string
  type: string
  title: string
  body: string
  status: string
  auxiliary: string
  metadata: Record<string, string>
}
```

常见 `type`：`userMessage`、`agentMessage`、`plan`、`reasoning`、`commandExecution`、`fileChange`、`mcpToolCall`、`dynamicToolCall`、`collabAgentToolCall`。

### PendingRequestView

```ts
{
  id: string
  method: string
  kind: string
  threadId: string
  turnId: string
  itemId: string
  reason: string
  summary: string
  choices: string[]
  createdAt: string
  params: Record<string, JsonValue>
}
```

常见 `kind`：

- `command`
- `fileChange`
- `permissions`
- `userInput`
- `generic`

常见 `method`：

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`
- `item/tool/requestUserInput`

### JsonValue

`JsonValue` 是可序列化/反序列化的 discriminated union 风格 JSON 值，必须支持：

- string
- number
- bool
- object
- array
- null

审批 resolve 时，客户端必须能把 `JsonValue` 转回 JSON，不得把对象或数组降级为字符串。

## Approval Resolve Body Rules

所有 resolve 请求外层 body 固定为：

```json
{
  "result": "<JsonValue>"
}
```

### command / fileChange

如果用户选择 `accept` 或 `reject`：

```json
{
  "decision": "accept"
}
```

```json
{
  "decision": "reject"
}
```

如果 `choices` 是其他值：

```json
{
  "decision": "用户选择值"
}
```

说明：当前 Agent 常见选择值为 `accept`、`acceptForSession`、`decline`、`cancel`。客户端应原样发送用户选择值；若 UI 显示为“拒绝”，应映射到该 approval 实际 choice（例如 `decline` 或 `reject`）。

### permissions

用户选择 `session`：

```json
{
  "permissions": "<approval.params.permissions 或 {}>",
  "scope": "session"
}
```

用户选择 `turn`：

```json
{
  "permissions": "<approval.params.permissions 或 {}>",
  "scope": "turn"
}
```

用户选择拒绝：

```json
{
  "permissions": {
    "network": null,
    "fileSystem": null
  },
  "scope": null
}
```

### userInput

从 `approval.params.questions[0].id` 获取 question id。没有则使用 `reply`。

```json
{
  "answers": {
    "<questionId>": {
      "answers": ["用户输入文本"]
    }
  }
}
```

### Other Kinds

```json
{
  "decision": "用户选择值"
}
```

## submitPrompt Rules

客户端提交 composer prompt 时：

1. 去除首尾空白；为空则不发送请求。
2. 如果 `session.lastTurnStatus == "inProgress"` 且 `session.lastTurnId` 非空，调用 `steerTurn`：

```http
POST /api/v1/sessions/:id/turns/steer
```

3. 否则调用 `startTurn`：

```http
POST /api/v1/sessions/:id/turns/start
```

4. 成功后刷新 dashboard。
5. 如果当前打开该 session，则刷新 session detail。

## SSE Event Consumption Rules

客户端连接：

```http
GET /api/v1/events
Accept: text/event-stream
```

解析规则：

- `event: xxx` 设置当前事件类型。
- `data: {...}` 追加当前事件数据。
- 多行 `data:` 需要用换行拼接。
- 空行表示一个事件结束并提交。
- 以 `:` 开头的行是注释或 ping，必须忽略。
- 收到任意业务事件后刷新 dashboard。
- 如果当前打开 session，收到业务事件后刷新当前 session detail。
- SSE 断线后自动重连：初始 1 秒，指数退避，最大 30 秒。
- Settings 中 base URL 改变后，停止旧连接并使用新 base URL 重新连接。
- App 窗口关闭时停止 SSE。

业务事件 data 结构：

```ts
{
  type: string
  timestamp: string
  payload: JsonValue
}
```

当前 Agent 可能发送的事件类型包括：

- `sessions.refreshed`
- `session.created`
- `session.resumed`
- `session.ended`
- `session.archived`
- `turn.started`
- `turn.steered`
- `turn.interrupted`
- `approval.created`
- `approval.resolved`
- `codex.notification`

客户端不应依赖事件 payload 的完整结构作为唯一数据源。收到业务事件后，以 HTTP API 重新拉取 dashboard/session detail 作为最终状态。
