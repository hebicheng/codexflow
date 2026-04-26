# Claude 接入可行性结论（先验证版）

更新时间：2026-04-25

## 1) 结论先行

- `claude` CLI 本机可用，不等于可以通过 `codex app-server` 路由。
- 当前机器上 `codex app-server` 的 `app/list` 为空，`externalAgentConfig/detect` 也为空，所以现有 `serviceName` 路由方案无法接入 Claude。
- 可行路线是：在现有框架内新增 `ClaudeAdapter`（CLI/SDK 无头模式），并用 capability 分级保证不影响 Codex 现有功能。

## 2) 已完成的本机证据

### 2.1 Claude CLI 命令级探测

执行：

```bash
python3 scripts/claude_capability_probe.py
```

当前结果要点（本机）：

- `version`: `2.1.120 (Claude Code)`，已安装。
- `-p --output-format json`: 有结构化 JSON 返回。
- `-p --verbose --output-format stream-json`: 有流式事件返回（含 `system/init`、`assistant`、`result`）。
- 当前账号状态是 `Not logged in`（需要先 `/login`）。

结论：

- CLI 协议层可用（JSON 和 stream-json）。
- 认证未完成时只能返回错误事件，不能执行真实任务。

### 2.2 Codex app-server 侧探测

通过 JSON-RPC 直接调用（`initialize` / `app/list` / `externalAgentConfig/detect`）得到：

- `app/list.data = []`
- `externalAgentConfig/detect.items = []`

结论：

- 当前环境下不能依赖 `codex app-server` 去发现/路由 Claude。

## 3) 对 CodexFlow 的影响边界

在保持现有功能不受影响前提下，Claude 适配必须拆为独立后端路径：

- Codex：继续走现有 `codex app-server`（原样保留）。
- Claude：新增 `ClaudeAdapter`（基于 `claude -p` + `stream-json`）。
- 前端：仅通过 capability 控制展示，不强行假装“同能力”。

## 4) Capability 分级（必须）

建议 capability 字段（后端返回，前端只读）：

- `supportsSessionStart`
- `supportsStreaming`
- `supportsTextInput`
- `supportsImageInput`
- `supportsResume`
- `supportsInterrupt`
- `supportsApprovals`
- `supportsToolEventGranularity`

第一期目标：`start + text/image + streaming + basic history`

## 5) 分阶段实施计划

### Phase 0（本阶段，已完成）

- 本机协议可行性探针与证据固化。

### Phase 1（最小可用）

- 新增 `ClaudeAdapter` 骨架和 `AgentAdapter` 接口。
- `StartSession/StartTurn` 走 Claude CLI 无头调用并流式解析。
- 不改 Codex 现有路径。

### Phase 2（体验对齐）

- 会话恢复（`--resume` / `--session-id` 能力验证后接入）。
- 图片输入落地与临时文件管理策略。

### Phase 3（高级能力）

- 中断、审批、工具细粒度事件按 Claude CLI 实测能力逐项开放。
- 不可达能力保持禁用并显式说明。

## 6) 立即可执行命令

```bash
# 1. 探测本机 Claude CLI 能力
python3 scripts/claude_capability_probe.py

# 2. Claude CLI 登录（需要你本机完成）
claude
# 然后在 CLI 内执行 /login
```

登录后再次运行探针，若 `summary.logged_in=true`，即可进入 Phase 1 开发。
