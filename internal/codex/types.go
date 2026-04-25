package codex

import (
	"encoding/json"
	"fmt"
	"strings"
)

type ThreadListResponse struct {
	Data            []Thread `json:"data"`
	NextCursor      *string  `json:"nextCursor"`
	BackwardsCursor *string  `json:"backwardsCursor"`
}

type ThreadLoadedListResponse struct {
	Data       []string `json:"data"`
	NextCursor *string  `json:"nextCursor"`
}

type ThreadReadResponse struct {
	Thread Thread `json:"thread"`
}

type ThreadStartResponse struct {
	Thread Thread `json:"thread"`
}

type ThreadResumeResponse struct {
	Thread Thread `json:"thread"`
}

type ThreadUnsubscribeResponse struct {
	Status string `json:"status"`
}

type TurnStartResponse struct {
	Turn Turn `json:"turn"`
}

type TurnSteerResponse struct{}

type TurnInterruptResponse struct{}

type Thread struct {
	ID            string          `json:"id"`
	ForkedFromID  *string         `json:"forkedFromId"`
	Preview       string          `json:"preview"`
	Ephemeral     bool            `json:"ephemeral"`
	ModelProvider string          `json:"modelProvider"`
	CreatedAt     int64           `json:"createdAt"`
	UpdatedAt     int64           `json:"updatedAt"`
	Status        ThreadStatus    `json:"status"`
	Path          *string         `json:"path"`
	CWD           string          `json:"cwd"`
	CLIVersion    string          `json:"cliVersion"`
	Source        json.RawMessage `json:"source"`
	AgentNickname *string         `json:"agentNickname"`
	AgentRole     *string         `json:"agentRole"`
	GitInfo       map[string]any  `json:"gitInfo"`
	Name          *string         `json:"name"`
	Turns         []Turn          `json:"turns"`
}

type ThreadStatus struct {
	Type        string   `json:"type"`
	ActiveFlags []string `json:"activeFlags,omitempty"`
}

type Turn struct {
	ID          string           `json:"id"`
	Items       []map[string]any `json:"items"`
	Status      string           `json:"status"`
	Error       *TurnError       `json:"error"`
	StartedAt   *int64           `json:"startedAt"`
	CompletedAt *int64           `json:"completedAt"`
	DurationMs  *int64           `json:"durationMs"`
}

type TurnError struct {
	Message           string  `json:"message"`
	AdditionalDetails *string `json:"additionalDetails"`
}

type InitializeResponse struct {
	UserAgent      string `json:"userAgent"`
	CodexHome      string `json:"codexHome"`
	PlatformOS     string `json:"platformOs"`
	PlatformFamily string `json:"platformFamily"`
}

type Notification struct {
	Method string
	Params json.RawMessage
}

type ServerRequest struct {
	ID     json.RawMessage
	Method string
	Params json.RawMessage
}

type ThreadStartedNotification struct {
	Thread Thread `json:"thread"`
}

type ThreadStatusChangedNotification struct {
	ThreadID string       `json:"threadId"`
	Status   ThreadStatus `json:"status"`
}

type TurnPlanUpdatedNotification struct {
	ThreadID    string     `json:"threadId"`
	TurnID      string     `json:"turnId"`
	Explanation *string    `json:"explanation"`
	Plan        []PlanStep `json:"plan"`
}

type PlanStep struct {
	Step   string `json:"step"`
	Status string `json:"status"`
}

type TurnDiffUpdatedNotification struct {
	ThreadID string `json:"threadId"`
	TurnID   string `json:"turnId"`
	Diff     string `json:"diff"`
}

type AgentMessageDeltaNotification struct {
	ThreadID string `json:"threadId"`
	TurnID   string `json:"turnId"`
	ItemID   string `json:"itemId"`
	Delta    string `json:"delta"`
}

type TurnCompletedNotification struct {
	ThreadID string `json:"threadId"`
	Turn     Turn   `json:"turn"`
}

type TurnStartedNotification struct {
	ThreadID string `json:"threadId"`
	Turn     Turn   `json:"turn"`
}

type ItemStartedNotification struct {
	ThreadID string         `json:"threadId"`
	TurnID   string         `json:"turnId"`
	Item     map[string]any `json:"item"`
}

type ItemCompletedNotification struct {
	ThreadID string         `json:"threadId"`
	TurnID   string         `json:"turnId"`
	Item     map[string]any `json:"item"`
}

func SourceLabel(raw json.RawMessage) string {
	if len(raw) == 0 {
		return "unknown"
	}

	var plain string
	if err := json.Unmarshal(raw, &plain); err == nil {
		return plain
	}

	var object map[string]any
	if err := json.Unmarshal(raw, &object); err != nil {
		return "unknown"
	}

	if len(object) == 0 {
		return "unknown"
	}

	for key, value := range object {
		switch typed := value.(type) {
		case string:
			return fmt.Sprintf("%s:%s", key, typed)
		default:
			return key
		}
	}

	return "unknown"
}

func GitBranch(gitInfo map[string]any) string {
	if gitInfo == nil {
		return ""
	}
	if branch, ok := gitInfo["branch"].(string); ok {
		return branch
	}
	return ""
}

func FirstUserText(items []map[string]any) string {
	for _, item := range items {
		if item["type"] != "userMessage" {
			continue
		}
		content, ok := item["content"].([]any)
		if !ok {
			continue
		}
		parts := make([]string, 0, len(content))
		for _, entry := range content {
			itemMap, ok := entry.(map[string]any)
			if !ok {
				continue
			}
			if itemMap["type"] == "text" {
				if text, ok := itemMap["text"].(string); ok && text != "" {
					parts = append(parts, text)
				}
			}
		}
		return strings.Join(parts, "\n")
	}
	return ""
}
