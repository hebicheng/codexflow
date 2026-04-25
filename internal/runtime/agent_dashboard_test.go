package runtime

import (
	"testing"

	"codexflow/internal/codex"
	"codexflow/internal/store"
)

func TestDashboardLoadedSessionsExcludeEndedSessions(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("create session store: %v", err)
	}

	sessionStore.ReplaceSessions([]codex.Thread{
		{
			ID:            "ended-thread",
			ModelProvider: "OpenAI",
			CreatedAt:     100,
			UpdatedAt:     200,
			Status:        codex.ThreadStatus{Type: "idle"},
			CWD:           "/tmp/ended",
		},
		{
			ID:            "active-thread",
			ModelProvider: "OpenAI",
			CreatedAt:     101,
			UpdatedAt:     201,
			Status:        codex.ThreadStatus{Type: "active"},
			CWD:           "/tmp/active",
		},
	}, map[string]bool{
		"ended-thread":  true,
		"active-thread": true,
	})

	sessionStore.SetSessionEnded("ended-thread", true)

	agent := &Agent{store: sessionStore}
	dashboard := agent.Dashboard()

	if got, want := dashboard.Stats.LoadedSessions, 1; got != want {
		t.Fatalf("loaded sessions = %d, want %d", got, want)
	}

	if got, want := dashboard.Stats.ActiveSessions, 1; got != want {
		t.Fatalf("active sessions = %d, want %d", got, want)
	}

	summaries := dashboard.Sessions
	if len(summaries) != 2 {
		t.Fatalf("sessions count = %d, want 2", len(summaries))
	}

	for _, session := range summaries {
		if session.ID == "ended-thread" && session.Loaded {
			t.Fatalf("ended session should not be marked loaded in API summary")
		}
	}
}
