package runtime

import (
	"context"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"codexflow/internal/codex"
	"codexflow/internal/store"
	claudeagent "github.com/roasbeef/claude-agent-sdk-go"
)

func TestExtractClaudeSDKMessageSessionID(t *testing.T) {
	tests := []struct {
		name string
		msg  claudeagent.Message
		want string
	}{
		{
			name: "snake_case",
			msg:  claudeagent.SystemMessage{SessionID: "snake-session"},
			want: "snake-session",
		},
		{
			name: "missing",
			msg:  claudeagent.AssistantMessage{},
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := extractClaudeSDKMessageSessionID(tt.msg); got != tt.want {
				t.Fatalf("extractClaudeSDKMessageSessionID() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestExtractClaudeMessageTextHandlesStringContent(t *testing.T) {
	got := extractClaudeMessageText(map[string]any{
		"content": "hi",
	})
	if got != "hi" {
		t.Fatalf("extractClaudeMessageText() = %q, want %q", got, "hi")
	}
}

func TestFinishClaudeTurnMarksThreadIdle(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("store.New() error = %v", err)
	}

	startedAt := time.Now().Unix()
	threadID := claudeThreadID("session-1")
	sessionStore.UpsertThread(codex.Thread{
		ID:            threadID,
		ModelProvider: "Anthropic",
		CreatedAt:     startedAt,
		UpdatedAt:     startedAt,
		Status:        codex.ThreadStatus{Type: "active"},
		CWD:           "/tmp/project",
		Source:        []byte(`"claude"`),
	})
	sessionStore.RecordTurn(threadID, buildClaudePendingTurn("turn-1", "hello", startedAt))

	agent := &Agent{store: sessionStore, broker: NewBroker()}
	agent.finishClaudeTurn(threadID, "turn-1", claudeTurnExecutionResult{
		SessionID:     "session-1",
		AssistantText: "hi",
	}, nil)

	record, ok := sessionStore.SnapshotSession(threadID)
	if !ok {
		t.Fatalf("SnapshotSession() missing record")
	}
	if got := record.Thread.Status.Type; got != "idle" {
		t.Fatalf("thread status = %q, want %q", got, "idle")
	}
}

func TestClaudeThreadStatusFromTurns(t *testing.T) {
	completed := []codex.Turn{{ID: "turn-1", Status: "completed"}}
	if got := claudeThreadStatusFromTurns(completed); got != "idle" {
		t.Fatalf("completed turns status = %q, want %q", got, "idle")
	}

	running := []codex.Turn{{ID: "turn-1", Status: "inProgress"}}
	if got := claudeThreadStatusFromTurns(running); got != "active" {
		t.Fatalf("running turns status = %q, want %q", got, "active")
	}
}

func TestBuildClaudeApprovalQuestions(t *testing.T) {
	questions := []claudeagent.QuestionItem{
		{
			Header:   "Scope",
			Question: "Which scope should we use?",
			Options: []claudeagent.QuestionOption{
				{Label: "Session", Description: "Keep it for this session"},
				{Label: "Turn", Description: "Only this turn"},
			},
		},
	}

	got := buildClaudeApprovalQuestions(questions)
	if len(got) != 1 {
		t.Fatalf("len(buildClaudeApprovalQuestions()) = %d, want 1", len(got))
	}

	object, ok := got[0].(map[string]any)
	if !ok {
		t.Fatalf("question entry type = %T, want map[string]any", got[0])
	}
	if object["id"] != "q_0" {
		t.Fatalf("id = %v, want q_0", object["id"])
	}
	if object["question"] != "Which scope should we use?" {
		t.Fatalf("question = %v", object["question"])
	}
	options, ok := object["options"].([]any)
	if !ok || len(options) != 2 {
		t.Fatalf("options = %#v, want 2 entries", object["options"])
	}
}

func TestSummarizeClaudeToolResultBashStdout(t *testing.T) {
	item := map[string]any{
		"tool": "Bash",
	}
	raw := map[string]any{
		"stdout": "hello\n",
		"stderr": "",
	}

	got := summarizeClaudeToolResult(item, raw)
	if got != "hello\n" {
		t.Fatalf("summarizeClaudeToolResult() = %q, want %q", got, "hello\n")
	}
}

func TestDecodeClaudeAnswers(t *testing.T) {
	payload := map[string]any{
		"answers": map[string]any{
			"q_0": map[string]any{
				"answers": []any{"Session"},
			},
			"q_1": map[string]any{
				"answers": []any{"Need more context"},
			},
		},
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		t.Fatalf("json.Marshal() error = %v", err)
	}

	got, err := decodeClaudeAnswers(raw)
	if err != nil {
		t.Fatalf("decodeClaudeAnswers() error = %v", err)
	}
	if got["q_0"] != "Session" {
		t.Fatalf("q_0 = %q, want %q", got["q_0"], "Session")
	}
	if got["q_1"] != "Need more context" {
		t.Fatalf("q_1 = %q, want %q", got["q_1"], "Need more context")
	}
}

func TestNormalizeDynamicToolCallCarriesResultToAuxiliary(t *testing.T) {
	item := normalizeItem(map[string]any{
		"id":        "tool-1",
		"type":      "dynamicToolCall",
		"namespace": "claude",
		"tool":      "WebSearch",
		"status":    "completed",
		"summary":   "golang iter package",
		"result":    "{\"top\":\"result\"}",
	})

	if item.Body != "golang iter package" {
		t.Fatalf("Body = %q, want %q", item.Body, "golang iter package")
	}
	if item.Auxiliary != "{\"top\":\"result\"}" {
		t.Fatalf("Auxiliary = %q, want %q", item.Auxiliary, "{\"top\":\"result\"}")
	}
}

func TestResolveRequestForClaudeQuestion(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("store.New() error = %v", err)
	}

	threadID := claudeThreadID("session-1")
	pending := sessionStore.UpsertPending(
		"item/tool/requestUserInput",
		nil,
		map[string]any{
			"threadId": threadID,
			"turnId":   "turn-1",
			"itemId":   "tool-1",
			"questions": []any{
				map[string]any{
					"id":       "q_0",
					"question": "Which scope should we use?",
				},
			},
		},
		[]string{"answer"},
	)

	waiter := make(chan claudeQuestionResult, 1)
	session := &claudeSDKSession{
		ctx:              context.Background(),
		questionWaits:    map[string]chan claudeQuestionResult{"tool-1": waiter},
		questionRequests: map[string]string{"tool-1": pending.ID},
	}
	agent := &Agent{
		store:          sessionStore,
		broker:         NewBroker(),
		claudeSessions: map[string]*claudeSDKSession{threadID: session},
	}

	resultJSON, err := json.Marshal(map[string]any{
		"answers": map[string]any{
			"q_0": map[string]any{
				"answers": []any{"Session"},
			},
		},
	})
	if err != nil {
		t.Fatalf("json.Marshal() error = %v", err)
	}

	if err := agent.ResolveRequest(context.Background(), pending.ID, resultJSON); err != nil {
		t.Fatalf("ResolveRequest() error = %v", err)
	}

	select {
	case result := <-waiter:
		if result.err != nil {
			t.Fatalf("waiter err = %v", result.err)
		}
		if result.answers["q_0"] != "Session" {
			t.Fatalf("answer = %q, want %q", result.answers["q_0"], "Session")
		}
	default:
		t.Fatalf("expected claude question waiter to receive an answer")
	}
}

func TestBuildClaudeApprovalRequestForBash(t *testing.T) {
	raw := json.RawMessage(`{"command":"git status","description":"check repo"}`)
	method, params, choices := buildClaudeApprovalRequest("tool-1", "Bash", "thread-1", "turn-1", raw)

	if method != "item/commandExecution/requestApproval" {
		t.Fatalf("method = %q, want %q", method, "item/commandExecution/requestApproval")
	}
	if params["command"] != "git status" {
		t.Fatalf("command = %v, want %q", params["command"], "git status")
	}
	if len(choices) != 3 {
		t.Fatalf("len(choices) = %d, want 3", len(choices))
	}
}

func TestShouldIgnoreClaudeUserEntry(t *testing.T) {
	tests := []struct {
		name   string
		entry  map[string]any
		prompt string
		want   bool
	}{
		{
			name:   "meta caveat",
			entry:  map[string]any{"isMeta": true},
			prompt: "<local-command-caveat>ignore</local-command-caveat>",
			want:   true,
		},
		{
			name:   "resume command wrapper",
			entry:  map[string]any{},
			prompt: "<command-name>/resume</command-name>",
			want:   true,
		},
		{
			name:   "local stdout wrapper",
			entry:  map[string]any{},
			prompt: "<local-command-stdout>No conversations found to resume</local-command-stdout>",
			want:   true,
		},
		{
			name:   "real prompt",
			entry:  map[string]any{},
			prompt: "hi",
			want:   false,
		},
		{
			name:   "interrupt marker",
			entry:  map[string]any{},
			prompt: "[Request interrupted by user]",
			want:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := shouldIgnoreClaudeUserEntry(tt.entry, tt.prompt); got != tt.want {
				t.Fatalf("shouldIgnoreClaudeUserEntry() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestExtractClaudeSystemError(t *testing.T) {
	entry := map[string]any{
		"error": map[string]any{
			"error": map[string]any{
				"error": map[string]any{
					"message": "model_not_found",
				},
			},
		},
	}

	if got := extractClaudeSystemError(entry); got != "model_not_found" {
		t.Fatalf("extractClaudeSystemError() = %q, want %q", got, "model_not_found")
	}
}

func TestInspectClaudeSessionFileSkipsResumeOnlyTranscript(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "resume-only.jsonl")
	content := "" +
		"{\"type\":\"permission-mode\",\"sessionId\":\"session-1\"}\n" +
		"{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<command-name>/resume</command-name>\"},\"uuid\":\"u1\",\"timestamp\":\"2026-04-25T14:29:21.531Z\",\"cwd\":\"/tmp/project\",\"sessionId\":\"session-1\"}\n" +
		"{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"<local-command-stdout>No conversations found to resume</local-command-stdout>\"},\"uuid\":\"u2\",\"timestamp\":\"2026-04-25T14:29:21.531Z\",\"cwd\":\"/tmp/project\",\"sessionId\":\"session-1\"}\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("os.WriteFile() error = %v", err)
	}

	_, ok, err := inspectClaudeSessionFile(path)
	if err != nil {
		t.Fatalf("inspectClaudeSessionFile() error = %v", err)
	}
	if ok {
		t.Fatalf("inspectClaudeSessionFile() should skip resume-only transcript")
	}
}

func TestInspectClaudeSessionFileDetectsRealPrompt(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "real-session.jsonl")
	content := "" +
		"{\"type\":\"permission-mode\",\"sessionId\":\"session-2\"}\n" +
		"{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"hi\"},\"uuid\":\"u1\",\"timestamp\":\"2026-04-25T14:41:33.745Z\",\"cwd\":\"/tmp/project\",\"sessionId\":\"session-2\"}\n" +
		"{\"type\":\"system\",\"subtype\":\"api_error\",\"timestamp\":\"2026-04-25T14:41:34.925Z\",\"sessionId\":\"session-2\",\"cwd\":\"/tmp/project\"}\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatalf("os.WriteFile() error = %v", err)
	}

	item, ok, err := inspectClaudeSessionFile(path)
	if err != nil {
		t.Fatalf("inspectClaudeSessionFile() error = %v", err)
	}
	if !ok {
		t.Fatalf("inspectClaudeSessionFile() should keep real transcript")
	}
	if item.SessionID != "session-2" {
		t.Fatalf("item.SessionID = %q, want %q", item.SessionID, "session-2")
	}
	if item.Preview != "hi" {
		t.Fatalf("item.Preview = %q, want %q", item.Preview, "hi")
	}
	if item.CWD != normalizeClaudeComparablePath("/tmp/project") {
		t.Fatalf("item.CWD = %q, want normalized /tmp/project", item.CWD)
	}
}

func TestClaudeResumeBlockedReason(t *testing.T) {
	tests := []struct {
		name     string
		preview  string
		hasTurns bool
		analysis claudeTranscriptAnalysis
		want     string
	}{
		{
			name: "explicit resume failure",
			analysis: claudeTranscriptAnalysis{
				HasResumeFailure: true,
			},
			want: "Claude CLI 标记这个历史会话不可恢复。",
		},
		{
			name:    "session never initialized",
			preview: "hi",
			analysis: claudeTranscriptAnalysis{
				HasSystemError: true,
			},
			want: "这个 Claude 会话初始化失败，没有形成可恢复会话。",
		},
		{
			name:     "resume placeholder only",
			preview:  "/resume",
			hasTurns: false,
			want:     "这是一次失败的 /resume 尝试，没有形成可恢复会话。",
		},
		{
			name:     "valid history",
			preview:  "hi",
			hasTurns: true,
			analysis: claudeTranscriptAnalysis{
				HasAssistantOrResult: true,
			},
			want: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if got := claudeResumeBlockedReason(tt.preview, tt.hasTurns, tt.analysis); got != tt.want {
				t.Fatalf("claudeResumeBlockedReason() = %q, want %q", got, tt.want)
			}
		})
	}
}

func TestPreferredClaudeRuntimeModel(t *testing.T) {
	models := []claudeagent.ModelInfo{
		{Value: "default"},
		{Value: "sonnet[1m]"},
		{Value: "opus[1m]"},
	}

	if got := preferredClaudeRuntimeModel(models); got != "sonnet[1m]" {
		t.Fatalf("preferredClaudeRuntimeModel() = %q, want %q", got, "sonnet[1m]")
	}
}

func TestClaudeResumeAvailabilityAllowsRuntimeDiscoveredSession(t *testing.T) {
	record := store.SessionRecord{
		Thread: codex.Thread{
			ID:               "claude:session-runtime",
			RuntimeSessionID: stringPtr("runtime-session-1"),
			Status:           codex.ThreadStatus{Type: "idle", ActiveFlags: []string{"claudeRuntimeAvailable"}},
		},
	}

	ok, reason := claudeResumeAvailability(record)
	if !ok {
		t.Fatalf("claudeResumeAvailability() = false, want true, reason=%q", reason)
	}
}

func TestClaudeResumeAvailabilityAllowsHistoryImportedSession(t *testing.T) {
	record := store.SessionRecord{
		Thread: codex.Thread{
			ID:   "claude:session-history",
			Path: stringPtr("/tmp/transcript.jsonl"),
		},
	}

	ok, reason := claudeResumeAvailability(record)
	if !ok {
		t.Fatalf("claudeResumeAvailability() = false, want true, reason=%q", reason)
	}
}

func TestBindingClaudeSessionIDDoesNotFallbackToHistoricalThreadID(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("store.New() error = %v", err)
	}

	threadID := claudeThreadID("history-only-session")
	sessionStore.UpsertThread(codex.Thread{
		ID:     threadID,
		Status: codex.ThreadStatus{Type: "idle"},
	})

	agent := &Agent{store: sessionStore}
	if got := agent.bindingClaudeSessionID(threadID); got != "" {
		t.Fatalf("bindingClaudeSessionID() = %q, want empty", got)
	}
}

func TestMergeClaudeTurnsPrefersLiveTurnState(t *testing.T) {
	startedAt := time.Now().Unix() - 5
	history := []codex.Turn{{
		ID:     "turn-1",
		Status: "completed",
		Items:  []map[string]any{{"type": "agentMessage", "text": "old"}},
	}}
	live := []codex.Turn{{
		ID:        "turn-1",
		Status:    "inProgress",
		StartedAt: &startedAt,
		Items:     []map[string]any{{"type": "agentMessage", "text": "live"}},
	}}

	merged := mergeClaudeTurns(history, live)
	if len(merged) != 1 {
		t.Fatalf("len(merged) = %d, want 1", len(merged))
	}
	if got := merged[0].Status; got != "inProgress" {
		t.Fatalf("merged[0].Status = %q, want %q", got, "inProgress")
	}
	if got := merged[0].Items[0]["text"]; got != "live" {
		t.Fatalf("merged[0].Items[0][text] = %v, want live", got)
	}
}

func TestMergeClaudeTurnsMatchesByPromptAndStartedAt(t *testing.T) {
	startedAt := time.Now().Unix()
	history := []codex.Turn{{
		ID:        "history-turn",
		Status:    "completed",
		StartedAt: &startedAt,
		Items:     []map[string]any{composeUserMessageItem("same prompt")},
	}}
	live := []codex.Turn{{
		ID:        "live-turn",
		Status:    "failed",
		StartedAt: &startedAt,
		Items:     []map[string]any{composeUserMessageItem("same prompt")},
		Error:     &codex.TurnError{Message: "interrupted by user"},
	}}

	merged := mergeClaudeTurns(history, live)
	if len(merged) != 1 {
		t.Fatalf("len(merged) = %d, want 1", len(merged))
	}
	if got := merged[0].Status; got != "failed" {
		t.Fatalf("merged[0].Status = %q, want %q", got, "failed")
	}
	if merged[0].Error == nil || merged[0].Error.Message != "interrupted by user" {
		t.Fatalf("merged[0].Error = %#v, want interrupted by user", merged[0].Error)
	}
}

func TestForceStopClaudeTurnMarksTurnStopped(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("store.New() error = %v", err)
	}

	startedAt := time.Now().Unix() - 2
	threadID := claudeThreadID("session-2")
	sessionStore.UpsertThread(codex.Thread{
		ID:            threadID,
		ModelProvider: "Anthropic",
		CreatedAt:     startedAt,
		UpdatedAt:     startedAt,
		Status:        codex.ThreadStatus{Type: "active"},
		CWD:           "/tmp/project",
		Source:        []byte(`"claude"`),
	})
	sessionStore.RecordTurn(threadID, buildClaudePendingTurn("turn-2", "hello", startedAt))

	agent := &Agent{
		store:         sessionStore,
		broker:        NewBroker(),
		claudeRunning: map[string]runningClaudeTurn{threadID: {TurnID: "turn-2", Cancel: func() {}}},
		claudeSessions: map[string]*claudeSDKSession{
			threadID: &claudeSDKSession{
				ctx:    context.Background(),
				cancel: func() {},
			},
		},
	}

	agent.forceStopClaudeTurn(threadID, "turn-2", "interrupted by user")

	record, ok := sessionStore.SnapshotSession(threadID)
	if !ok {
		t.Fatalf("SnapshotSession() missing record")
	}
	if got := record.Thread.Status.Type; got != "idle" {
		t.Fatalf("thread status = %q, want %q", got, "idle")
	}
	if len(record.Thread.Turns) != 1 {
		t.Fatalf("len(record.Thread.Turns) = %d, want 1", len(record.Thread.Turns))
	}
	if got := record.Thread.Turns[0].Status; got != "failed" {
		t.Fatalf("turn status = %q, want %q", got, "failed")
	}
	if record.Thread.Turns[0].CompletedAt == nil {
		t.Fatalf("CompletedAt is nil, want timestamp")
	}
	if record.Thread.Turns[0].Error == nil || record.Thread.Turns[0].Error.Message != "interrupted by user" {
		t.Fatalf("turn error = %#v, want interrupted by user", record.Thread.Turns[0].Error)
	}
	if _, ok := agent.getRunningClaudeTurn(threadID); ok {
		t.Fatalf("running claude turn should be cleared")
	}
	if _, ok := agent.getClaudeSession(threadID); ok {
		t.Fatalf("claude session should be cleared")
	}
}

func TestFinishClaudeTurnDoesNotOverwriteAlreadyStoppedTurn(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("store.New() error = %v", err)
	}

	completedAt := time.Now().Unix()
	threadID := claudeThreadID("session-3")
	sessionStore.UpsertThread(codex.Thread{
		ID:            threadID,
		ModelProvider: "Anthropic",
		CreatedAt:     completedAt - 5,
		UpdatedAt:     completedAt,
		Status:        codex.ThreadStatus{Type: "active"},
		CWD:           "/tmp/project",
		Source:        []byte(`"claude"`),
	})
	sessionStore.RecordTurn(threadID, codex.Turn{
		ID:          "turn-3",
		Status:      "failed",
		CompletedAt: &completedAt,
		Error:       &codex.TurnError{Message: "interrupted by user"},
	})

	agent := &Agent{store: sessionStore, broker: NewBroker()}
	agent.finishClaudeTurn(threadID, "turn-3", claudeTurnExecutionResult{
		SessionID:     "session-3",
		AssistantText: "should not be appended",
	}, nil)

	record, ok := sessionStore.SnapshotSession(threadID)
	if !ok {
		t.Fatalf("SnapshotSession() missing record")
	}
	if len(record.Thread.Turns) != 1 {
		t.Fatalf("len(record.Thread.Turns) = %d, want 1", len(record.Thread.Turns))
	}
	if got := record.Thread.Turns[0].Status; got != "failed" {
		t.Fatalf("turn status = %q, want %q", got, "failed")
	}
	if len(record.Thread.Turns[0].Items) != 0 {
		t.Fatalf("len(turn.Items) = %d, want 0", len(record.Thread.Turns[0].Items))
	}
}

func TestClaudeApprovalItemStartsWaitingApproval(t *testing.T) {
	item := claudeApprovalItem("tool-1", "Bash", "/tmp/project", json.RawMessage(`{"command":"git status"}`))
	if item == nil {
		t.Fatalf("claudeApprovalItem() returned nil")
	}
	if item["status"] != "waitingApproval" {
		t.Fatalf("status = %v, want waitingApproval", item["status"])
	}
}

func TestDecodeClaudePermissionDecision(t *testing.T) {
	raw := json.RawMessage(`{"decision":"accept"}`)
	decision, err := decodeClaudePermissionDecision(raw)
	if err != nil {
		t.Fatalf("decodeClaudePermissionDecision() error = %v", err)
	}
	if !decision.Allow {
		t.Fatalf("Allow = false, want true")
	}

	raw = json.RawMessage(`{"decision":"decline"}`)
	decision, err = decodeClaudePermissionDecision(raw)
	if err != nil {
		t.Fatalf("decodeClaudePermissionDecision() error = %v", err)
	}
	if decision.Allow {
		t.Fatalf("Allow = true, want false")
	}
}
