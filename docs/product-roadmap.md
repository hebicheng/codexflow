# Product Roadmap

## Current Foundation

- local Mac agent with live Codex protocol integration
- session discovery across historical threads
- approval queue capture
- iOS client with dashboard, session detail, approval center, and settings
- Android client with dashboard, session detail, approval center, settings, and SSE refresh
- Windows WinUI 3 client with dashboard, session detail, approval center, settings, and SSE refresh
- shared client API contract for iOS, Android, and Windows

## Next Build Targets

### 1. Managed Session Launcher

- menu bar launcher on macOS
- map terminal windows and tabs to managed sessions
- one-click creation of isolated worktrees

### 2. Live Session Streaming

- wire the iOS app to the SSE stream
- surface live command output, diff updates, and plan changes
- add push notifications for approvals and turn completion across APNs, FCM, and Windows notifications

### 3. Approval Policies

- rules for safe auto-approval
- per-repo network permission presets
- per-session approval audit trail

### 4. Relay Service

- secure device pairing
- authenticated remote access outside the LAN
- APNs push fan-out and delivery receipts

### 5. Team Features

- shared approval inbox
- operator notes on sessions
- ownership and escalation workflows
