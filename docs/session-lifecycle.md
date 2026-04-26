# Session Lifecycle

## Goal

CodexFlow should treat "session history" and "live runtime" as separate concerns.

- History answers: "what happened before"
- Runtime answers: "what can CodexFlow control right now"

This is especially important for Claude, where transcript files and resumable
runtime sessions are not the same thing.

## Lifecycle Stages

Every session exposed by the agent should resolve to exactly one lifecycle
stage:

1. `managed`
   - CodexFlow currently owns the session/runtime
   - The user can start a turn, steer, interrupt, end, and process approvals

2. `runtime_available`
   - CodexFlow does not currently own the session/runtime
   - A live runtime is detectable on this machine
   - The user can attach CodexFlow to that runtime

3. `history_only`
   - History/transcript exists
   - No live runtime is currently detectable
   - The user can view history
   - For agents that support it, CodexFlow may open a new runtime based on the
     same history record

4. `ended`
   - CodexFlow previously managed this session, but the lifecycle was closed in
     CodexFlow
   - History must remain visible
   - The user may re-attach or open a new runtime later

5. `discovered`
   - Fallback bucket for partially discovered sessions
   - Should be rare
   - UI should treat this as read-only until more information is known

## New Session Flow

### Codex

1. User chooses agent = `codex`
2. User must provide:
   - absolute `cwd`
   - first prompt
3. Agent creates a managed runtime immediately
4. Session enters `managed`

### Claude

1. User chooses agent = `claude`
2. User must provide:
   - absolute `cwd`
   - first prompt
3. Agent opens a new Claude runtime
4. Agent stores:
   - transcript/history identity
   - runtime session id
   - attach mode = `opened`
5. Session enters `managed`

## Attach / Resume Flow

### Codex

- Resume means: attach CodexFlow back to the same Codex thread/runtime

### Claude

Resume must branch:

1. If a live runtime id is known and available:
   - attach to that runtime
   - attach mode = `resumed`

2. If no live runtime is available but history exists:
   - open a new Claude runtime for this thread representation
   - attach mode = `opened`

3. If runtime attach fails:
   - fallback to opening a new runtime
   - preserve the same history thread in UI

Claude must never treat transcript session ids as automatically resumable
runtime ids.

## End Flow

Ending a session means:

- CodexFlow stops managing the runtime
- Session moves to `ended`
- History stays visible

It does **not** mean:

- deleting transcript/history
- removing the session from the list
- archiving the session

## Archive Flow

Archiving means:

- remove the session from CodexFlow local surfaces
- clear local lifecycle state
- preserve upstream history if it exists

Archive is a UI/local-state cleanup action, not a runtime action.

## UI Rules

- `managed`: show compose, steer, interrupt, end
- `runtime_available`: show attach CTA
- `history_only`: show history-first UI and explain there is no live runtime
- `ended`: show ended state and re-attach CTA

Claude-specific UI should also show:

- `History` vs `Runtime`
- `resumed` vs `opened`

## Backend Rules

- Keep transcript path separate from runtime session id
- Persist runtime binding independently from display thread id
- Session detail should merge:
  - transcript history
  - live runtime turns
- Runtime availability should come from actual live detection, not from stale
  runtime ids alone
