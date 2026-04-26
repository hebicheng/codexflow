package store

import (
	"testing"

	"codexflow/internal/codex"
)

func TestSummarizeUserInputUsesQuestionText(t *testing.T) {
	params := map[string]any{
		"questions": []any{
			map[string]any{
				"id":       "q_0",
				"question": "Which scope should we use?",
			},
		},
	}

	got := summarize("item/tool/requestUserInput", params)
	if got != "Which scope should we use?" {
		t.Fatalf("summarize() = %q, want %q", got, "Which scope should we use?")
	}
}

func TestReplaceSessionsPreservesExistingTurnsWhenIncomingThreadHasNone(t *testing.T) {
	sessionStore, err := New(nil)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}

	existingTurn := codex.Turn{ID: "turn-1", Status: "completed"}
	sessionStore.UpsertThread(codex.Thread{
		ID:               "thread-1",
		Preview:          "existing preview",
		CWD:              "/tmp/existing",
		Path:             stringPtrForTest("/tmp/existing/session.jsonl"),
		RuntimeSessionID: stringPtrForTest("runtime-session-1"),
		CreatedAt:        100,
		UpdatedAt:        200,
		Turns:            []codex.Turn{existingTurn},
	})

	sessionStore.ReplaceSessions([]codex.Thread{
		{
			ID:        "thread-1",
			Preview:   "",
			CWD:       "",
			CreatedAt: 100,
			UpdatedAt: 201,
			Status:    codex.ThreadStatus{Type: "idle"},
			Turns:     nil,
		},
	}, map[string]bool{"thread-1": true})

	record, ok := sessionStore.SnapshotSession("thread-1")
	if !ok {
		t.Fatalf("SnapshotSession() missing thread")
	}
	if len(record.Thread.Turns) != 1 {
		t.Fatalf("len(record.Thread.Turns) = %d, want 1", len(record.Thread.Turns))
	}
	if record.Thread.Turns[0].ID != existingTurn.ID {
		t.Fatalf("record.Thread.Turns[0].ID = %q, want %q", record.Thread.Turns[0].ID, existingTurn.ID)
	}
	if record.Thread.Preview != "existing preview" {
		t.Fatalf("record.Thread.Preview = %q, want %q", record.Thread.Preview, "existing preview")
	}
	if record.Thread.CWD != "/tmp/existing" {
		t.Fatalf("record.Thread.CWD = %q, want %q", record.Thread.CWD, "/tmp/existing")
	}
	if record.Thread.Path == nil || *record.Thread.Path != "/tmp/existing/session.jsonl" {
		t.Fatalf("record.Thread.Path = %#v, want /tmp/existing/session.jsonl", record.Thread.Path)
	}
	if record.Thread.RuntimeSessionID == nil || *record.Thread.RuntimeSessionID != "runtime-session-1" {
		t.Fatalf("record.Thread.RuntimeSessionID = %#v, want runtime-session-1", record.Thread.RuntimeSessionID)
	}
}

func TestHasLocalSessionState(t *testing.T) {
	sessionStore, err := New(nil)
	if err != nil {
		t.Fatalf("New() error = %v", err)
	}

	sessionStore.SetSessionEnded("thread-ended", true)
	sessionStore.SetSessionManaged("thread-managed", true)

	if !sessionStore.HasLocalSessionState("thread-ended") {
		t.Fatalf("thread-ended should have local session state")
	}
	if !sessionStore.HasLocalSessionState("thread-managed") {
		t.Fatalf("thread-managed should have local session state")
	}
	if sessionStore.HasLocalSessionState("thread-none") {
		t.Fatalf("thread-none should not have local session state")
	}
}

func stringPtrForTest(value string) *string {
	return &value
}
