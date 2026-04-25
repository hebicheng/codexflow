package runtime

import "time"

type AgentSnapshot struct {
	Connected       bool      `json:"connected"`
	StartedAt       time.Time `json:"startedAt"`
	ListenAddr      string    `json:"listenAddr"`
	CodexBinaryPath string    `json:"codexBinaryPath"`
}

type Dashboard struct {
	Agent     AgentSnapshot        `json:"agent"`
	Stats     DashboardStats       `json:"stats"`
	Sessions  []SessionSummary     `json:"sessions"`
	Approvals []PendingRequestView `json:"approvals"`
}

type DashboardStats struct {
	TotalSessions    int `json:"totalSessions"`
	LoadedSessions   int `json:"loadedSessions"`
	ActiveSessions   int `json:"activeSessions"`
	PendingApprovals int `json:"pendingApprovals"`
}

type SessionSummary struct {
	ID               string   `json:"id"`
	Name             string   `json:"name"`
	Preview          string   `json:"preview"`
	CWD              string   `json:"cwd"`
	Source           string   `json:"source"`
	Status           string   `json:"status"`
	ActiveFlags      []string `json:"activeFlags"`
	Loaded           bool     `json:"loaded"`
	UpdatedAt        int64    `json:"updatedAt"`
	CreatedAt        int64    `json:"createdAt"`
	ModelProvider    string   `json:"modelProvider"`
	Branch           string   `json:"branch"`
	PendingApprovals int      `json:"pendingApprovals"`
	LastTurnID       string   `json:"lastTurnId"`
	LastTurnStatus   string   `json:"lastTurnStatus"`
	AgentNickname    string   `json:"agentNickname"`
	AgentRole        string   `json:"agentRole"`
	Ended            bool     `json:"ended"`
}

type SessionDetail struct {
	Summary SessionSummary `json:"summary"`
	Turns   []TurnDetail   `json:"turns"`
}

type TurnDetail struct {
	ID              string     `json:"id"`
	Status          string     `json:"status"`
	StartedAt       int64      `json:"startedAt"`
	CompletedAt     int64      `json:"completedAt"`
	DurationMs      int64      `json:"durationMs"`
	Error           string     `json:"error"`
	Diff            string     `json:"diff"`
	PlanExplanation string     `json:"planExplanation"`
	Plan            []PlanStep `json:"plan"`
	Items           []TurnItem `json:"items"`
}

type PlanStep struct {
	Step   string `json:"step"`
	Status string `json:"status"`
}

type TurnItem struct {
	ID        string            `json:"id"`
	Type      string            `json:"type"`
	Title     string            `json:"title"`
	Body      string            `json:"body"`
	Status    string            `json:"status"`
	Auxiliary string            `json:"auxiliary"`
	Metadata  map[string]string `json:"metadata"`
}

type PendingRequestView struct {
	ID        string         `json:"id"`
	Method    string         `json:"method"`
	Kind      string         `json:"kind"`
	ThreadID  string         `json:"threadId"`
	TurnID    string         `json:"turnId"`
	ItemID    string         `json:"itemId"`
	Reason    string         `json:"reason"`
	Summary   string         `json:"summary"`
	Choices   []string       `json:"choices"`
	CreatedAt time.Time      `json:"createdAt"`
	Params    map[string]any `json:"params"`
}
