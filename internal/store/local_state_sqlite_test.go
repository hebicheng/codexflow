package store

import (
	"path/filepath"
	"testing"
)

func TestLocalStateDBPersistsAgentBinding(t *testing.T) {
	dbPath := filepath.Join(t.TempDir(), "state.db")

	db, err := OpenLocalStateDB(dbPath)
	if err != nil {
		t.Fatalf("OpenLocalStateDB() error = %v", err)
	}

	state := PersistedSessionState{
		Ended:          false,
		Managed:        true,
		AgentID:        "claude",
		AgentSessionID: "session-123",
	}
	if err := db.SaveSessionState("claude:session-123", state); err != nil {
		t.Fatalf("SaveSessionState() error = %v", err)
	}

	reopened, err := OpenLocalStateDB(dbPath)
	if err != nil {
		t.Fatalf("reopen OpenLocalStateDB() error = %v", err)
	}

	states, err := reopened.LoadSessionStates()
	if err != nil {
		t.Fatalf("LoadSessionStates() error = %v", err)
	}

	got, ok := states["claude:session-123"]
	if !ok {
		t.Fatalf("saved session state missing")
	}
	if got.AgentID != "claude" {
		t.Fatalf("AgentID = %q, want %q", got.AgentID, "claude")
	}
	if got.AgentSessionID != "session-123" {
		t.Fatalf("AgentSessionID = %q, want %q", got.AgentSessionID, "session-123")
	}
	if !got.Managed {
		t.Fatalf("Managed = false, want true")
	}
}
