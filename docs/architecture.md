# Architecture

## Components

### 1. Mac Agent

Responsibilities:

- spawn and own a local `codex app-server`
- discover sessions with `thread/list` and `thread/loaded/list`
- subscribe to runtime notifications
- queue approval requests from Codex
- expose a client-friendly HTTP API and SSE event stream

### 2. Client Apps

The client layer currently includes:

- iOS SwiftUI app
- Android Jetpack Compose app
- Windows WinUI 3 app

Responsibilities:

- dashboard for all sessions
- approval center
- session timeline with plan, diff, and command output
- remote prompting, steering, and interrupt actions
- Agent base URL settings and connection testing

Android and Windows also consume the Agent SSE stream for event-triggered refreshes. iOS currently uses explicit refresh and detail polling.

### 3. Relay Layer

Planned later:

- remote APNs push delivery
- secure device pairing
- authenticated relay instead of exposing the local agent directly

## Data Flow

1. `CodexFlow Agent` starts `codex app-server --listen stdio://`
2. Agent initializes the JSON-RPC session
3. Agent refreshes thread inventory and listens for notifications
4. Client apps call the agent HTTP API
5. Approvals are sent back through JSON-RPC response messages

## Why This Shape

- `stdio` avoids an extra websocket dependency inside the local agent
- the agent becomes the single place that can later add policy, relay, push, and audit
- clients work against a stable app-specific API instead of speaking raw Codex protocol directly
