package runtime

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"slices"
	"sort"
	"strings"
	"sync"
	"time"
	"unsafe"

	"codexflow/internal/codex"
	"codexflow/internal/store"
	"github.com/google/uuid"
	claudeagent "github.com/roasbeef/claude-agent-sdk-go"
)

const claudeThreadPrefix = "claude:"

type runningClaudeTurn struct {
	TurnID string
	Cancel context.CancelFunc
}

type claudeSDKSession struct {
	agent *Agent

	ctx    context.Context
	cancel context.CancelFunc
	client *claudeagent.Client
	stream *claudeagent.Stream

	mu        sync.Mutex
	threadID  string
	sessionID string
	cwd       string
	current   *claudeSDKTurnState
	closed    bool

	questionMu       sync.Mutex
	questionWaits    map[string]chan claudeQuestionResult
	questionRequests map[string]string

	approvalMu       sync.Mutex
	approvalWaits    map[string]chan claudePermissionDecision
	approvalRequests map[string]string
}

type claudeQuestionResult struct {
	answers claudeagent.Answers
	err     error
}

type claudePermissionDecision struct {
	Allow  bool
	Reason string
}

type claudeSDKTurnState struct {
	TurnID       string
	Prompt       string
	StartedAt    int64
	Result       claudeTurnExecutionResult
	Err          error
	sessionReady chan struct{}
	done         chan struct{}
	readyOnce    sync.Once
	doneOnce     sync.Once
}

func newClaudeSDKTurnState(turnID, prompt string, startedAt int64) *claudeSDKTurnState {
	return &claudeSDKTurnState{
		TurnID:       turnID,
		Prompt:       prompt,
		StartedAt:    startedAt,
		sessionReady: make(chan struct{}),
		done:         make(chan struct{}),
	}
}

func (t *claudeSDKTurnState) signalSessionReady() {
	t.readyOnce.Do(func() { close(t.sessionReady) })
}

func (t *claudeSDKTurnState) finish(result claudeTurnExecutionResult, err error) {
	t.Result = result
	t.Err = err
	t.signalSessionReady()
	t.doneOnce.Do(func() { close(t.done) })
}

type claudeSessionFile struct {
	Path                 string
	SessionID            string
	CWD                  string
	Preview              string
	CreatedAt            int64
	UpdatedAt            int64
	HasAssistantOrResult bool
	HasResumeFailure     bool
	HasSystemError       bool
}

type claudeRuntimeSession struct {
	PID        int    `json:"pid"`
	SessionID  string `json:"sessionId"`
	CWD        string `json:"cwd"`
	StartedAt  int64  `json:"startedAt"`
	Kind       string `json:"kind"`
	Entrypoint string `json:"entrypoint"`
}

func claudeThreadID(sessionID string) string {
	return claudeThreadPrefix + sessionID
}

func parseClaudeSessionID(threadID string) (string, bool) {
	if !strings.HasPrefix(threadID, claudeThreadPrefix) {
		return "", false
	}
	sessionID := strings.TrimSpace(strings.TrimPrefix(threadID, claudeThreadPrefix))
	if sessionID == "" {
		return "", false
	}
	return sessionID, true
}

func isClaudeThreadID(threadID string) bool {
	_, ok := parseClaudeSessionID(threadID)
	return ok
}

func claudeTimestampToSeconds(raw int64) int64 {
	if raw <= 0 {
		return time.Now().Unix()
	}
	if raw > 9_999_999_999 {
		return raw / 1000
	}
	return raw
}

func (a *Agent) detectClaudeCLI(ctx context.Context) bool {
	cmd := exec.CommandContext(ctx, a.cfg.ClaudePath, "--version")
	output, err := cmd.CombinedOutput()
	if err != nil {
		a.logger.Debug("claude binary check failed", "error", err, "output", strings.TrimSpace(string(output)))
		return false
	}
	return true
}

func (a *Agent) fetchClaudeThreads() ([]codex.Thread, error) {
	files, err := scanClaudeSessionFiles()
	if err != nil {
		return nil, err
	}
	runtimeSessions, err := scanClaudeRuntimeSessions()
	if err != nil {
		return nil, err
	}
	runtimeBySession := make(map[string]claudeRuntimeSession, len(runtimeSessions))
	for _, session := range runtimeSessions {
		runtimeBySession[strings.TrimSpace(session.SessionID)] = session
	}

	threads := make([]codex.Thread, 0, len(files)+len(runtimeSessions))
	seen := make(map[string]struct{}, len(files)+len(runtimeSessions))
	for _, entry := range files {
		preview := strings.TrimSpace(entry.Preview)
		cwd := strings.TrimSpace(entry.CWD)
		createdAt := claudeTimestampToSeconds(entry.CreatedAt)
		updatedAt := claudeTimestampToSeconds(entry.UpdatedAt)
		if createdAt == 0 {
			createdAt = updatedAt
		}
		if updatedAt == 0 {
			updatedAt = createdAt
		}
		activeFlags := []string{}
		if _, ok := runtimeBySession[strings.TrimSpace(entry.SessionID)]; ok {
			activeFlags = append(activeFlags, "claudeRuntimeAvailable")
		}
		thread := codex.Thread{
			ID:            claudeThreadID(entry.SessionID),
			Preview:       preview,
			Ephemeral:     false,
			ModelProvider: "Anthropic",
			CreatedAt:     createdAt,
			UpdatedAt:     updatedAt,
			Status:        codex.ThreadStatus{Type: "idle", ActiveFlags: activeFlags},
			Path:          stringPtr(entry.Path),
			RuntimeSessionID: stringPtr(func() string {
				if runtimeSession, ok := runtimeBySession[strings.TrimSpace(entry.SessionID)]; ok {
					return runtimeSession.SessionID
				}
				return ""
			}()),
			CWD:    cwd,
			Source: json.RawMessage(`"claude"`),
			Turns:  []codex.Turn{},
		}
		threads = append(threads, thread)
		seen[thread.ID] = struct{}{}
	}

	for _, runtimeSession := range runtimeSessions {
		threadID := claudeThreadID(runtimeSession.SessionID)
		if _, ok := seen[threadID]; ok {
			continue
		}
		createdAt := claudeTimestampToSeconds(runtimeSession.StartedAt)
		thread := codex.Thread{
			ID:               threadID,
			Preview:          "Claude live session",
			Ephemeral:        false,
			ModelProvider:    "Anthropic",
			CreatedAt:        createdAt,
			UpdatedAt:        createdAt,
			Status:           codex.ThreadStatus{Type: "idle", ActiveFlags: []string{"claudeRuntimeAvailable"}},
			RuntimeSessionID: stringPtr(runtimeSession.SessionID),
			CWD:              normalizeClaudeComparablePath(runtimeSession.CWD),
			Source:           json.RawMessage(`"claude"`),
			Turns:            []codex.Turn{},
		}
		threads = append(threads, thread)
		seen[threadID] = struct{}{}
	}

	sort.Slice(threads, func(i, j int) bool {
		if threads[i].UpdatedAt == threads[j].UpdatedAt {
			return threads[i].ID < threads[j].ID
		}
		return threads[i].UpdatedAt > threads[j].UpdatedAt
	})
	return threads, nil
}

func scanClaudeRuntimeSessions() ([]claudeRuntimeSession, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	root := filepath.Join(home, ".claude", "sessions")
	info, err := os.Stat(root)
	if err != nil {
		if os.IsNotExist(err) {
			return []claudeRuntimeSession{}, nil
		}
		return nil, err
	}
	if !info.IsDir() {
		return []claudeRuntimeSession{}, nil
	}

	entries, err := os.ReadDir(root)
	if err != nil {
		return nil, err
	}
	items := make([]claudeRuntimeSession, 0, len(entries))
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(root, entry.Name()))
		if err != nil {
			continue
		}
		var item claudeRuntimeSession
		if err := json.Unmarshal(raw, &item); err != nil {
			continue
		}
		item.SessionID = strings.TrimSpace(item.SessionID)
		item.CWD = normalizeClaudeComparablePath(item.CWD)
		if item.SessionID == "" || item.CWD == "" {
			continue
		}
		items = append(items, item)
	}
	return items, nil
}

func detectClaudeRuntimeSessionID(ctx context.Context, client *claudeagent.Client) string {
	if client == nil {
		return ""
	}
	info := client.InitializationInfo()
	if info.PID == nil || *info.PID <= 0 {
		return ""
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		sessions, err := scanClaudeRuntimeSessions()
		if err == nil {
			for _, session := range sessions {
				if session.PID == *info.PID {
					return strings.TrimSpace(session.SessionID)
				}
			}
		}
		if time.Now().After(deadline) {
			return ""
		}
		select {
		case <-ctx.Done():
			return ""
		case <-time.After(120 * time.Millisecond):
		}
	}
}

func scanClaudeSessionFiles() ([]claudeSessionFile, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}
	root := filepath.Join(home, ".claude", "projects")
	info, err := os.Stat(root)
	if err != nil {
		if os.IsNotExist(err) {
			return []claudeSessionFile{}, nil
		}
		return nil, err
	}
	if !info.IsDir() {
		return []claudeSessionFile{}, nil
	}

	items := make([]claudeSessionFile, 0)
	err = filepath.WalkDir(root, func(path string, d os.DirEntry, walkErr error) error {
		if walkErr != nil {
			return nil
		}
		if d == nil || d.IsDir() || filepath.Ext(path) != ".jsonl" {
			return nil
		}
		item, ok, err := inspectClaudeSessionFile(path)
		if err != nil {
			return nil
		}
		if !ok {
			return nil
		}
		items = append(items, item)
		return nil
	})
	if err != nil {
		return nil, err
	}

	sort.Slice(items, func(i, j int) bool {
		if items[i].UpdatedAt == items[j].UpdatedAt {
			return items[i].SessionID > items[j].SessionID
		}
		return items[i].UpdatedAt > items[j].UpdatedAt
	})
	return items, nil
}

func inspectClaudeSessionFile(path string) (claudeSessionFile, bool, error) {
	file, err := os.Open(path)
	if err != nil {
		return claudeSessionFile{}, false, err
	}
	defer file.Close()

	info, err := file.Stat()
	if err != nil {
		return claudeSessionFile{}, false, err
	}

	item := claudeSessionFile{
		Path:      path,
		UpdatedAt: info.ModTime().Unix(),
	}

	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		var raw map[string]any
		if err := json.Unmarshal([]byte(line), &raw); err != nil {
			continue
		}

		if item.SessionID == "" {
			item.SessionID = strings.TrimSpace(toString(raw["sessionId"]))
		}
		if item.CWD == "" {
			item.CWD = normalizeClaudeComparablePath(toString(raw["cwd"]))
		}

		ts := parseClaudeTimestamp(toString(raw["timestamp"]))
		if ts > 0 {
			if item.CreatedAt == 0 {
				item.CreatedAt = ts
			}
			if ts > item.UpdatedAt {
				item.UpdatedAt = ts
			}
		}

		switch strings.TrimSpace(toString(raw["type"])) {
		case "user":
			prompt := extractClaudeMessageText(raw["message"])
			lowerPrompt := strings.ToLower(strings.TrimSpace(prompt))
			if strings.Contains(lowerPrompt, "no conversations found to resume") ||
				strings.Contains(lowerPrompt, "no conversation found with session id") {
				item.HasResumeFailure = true
			}
			if shouldIgnoreClaudeUserEntry(raw, prompt) {
				continue
			}
			if item.Preview == "" {
				item.Preview = prompt
			}
		case "assistant", "result":
			item.HasAssistantOrResult = true
		case "system":
			if strings.TrimSpace(toString(raw["subtype"])) == "api_error" {
				item.HasSystemError = true
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return claudeSessionFile{}, false, err
	}
	if item.SessionID == "" || item.CWD == "" {
		return claudeSessionFile{}, false, nil
	}
	if strings.TrimSpace(item.Preview) == "" && !item.HasAssistantOrResult {
		return claudeSessionFile{}, false, nil
	}
	return item, true, nil
}

func claudeResumeAvailability(record store.SessionRecord) (bool, string) {
	if record.Loaded && !record.Runtime.Ended {
		return true, ""
	}
	if slices.Contains(record.Thread.Status.ActiveFlags, "claudeRuntimeAvailable") {
		return true, ""
	}
	if record.Thread.Path != nil && strings.TrimSpace(*record.Thread.Path) != "" {
		return true, ""
	}

	if _, ok := parseClaudeSessionID(record.Thread.ID); !ok {
		return false, "invalid Claude session id"
	}

	return false, "当前没有可接管的 Claude runtime。"
}

func (a *Agent) ensureClaudeThread(threadID string) error {
	if _, ok := a.store.SnapshotSession(threadID); ok {
		return nil
	}

	threads, err := a.fetchClaudeThreads()
	if err != nil {
		return err
	}
	for _, thread := range threads {
		if thread.ID == threadID {
			a.store.UpsertThread(thread)
			return nil
		}
	}
	return fmt.Errorf("claude session %s not found", threadID)
}

func (a *Agent) claudeSessionDetail(threadID string) (SessionDetail, error) {
	if err := a.ensureClaudeThread(threadID); err != nil {
		return SessionDetail{}, err
	}
	if _, ok := parseClaudeSessionID(threadID); !ok {
		return SessionDetail{}, errors.New("invalid claude session id")
	}

	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return SessionDetail{}, fmt.Errorf("session %s not found", threadID)
	}

	if record.Thread.Path != nil && strings.TrimSpace(*record.Thread.Path) != "" {
		turns, updatedAt, err := a.readClaudeTurns(record.Thread)
		if err != nil {
			a.logger.Debug("read claude turns failed", "threadId", threadID, "error", err)
		} else {
			record.Thread.Turns = mergeClaudeTurns(turns, record.Thread.Turns)
			if updatedAt > 0 {
				if updatedAt > record.Thread.UpdatedAt {
					record.Thread.UpdatedAt = updatedAt
				}
			}
			record.Thread.Status.Type = claudeThreadStatusFromTurns(turns)
			if record.Loaded && !record.Runtime.Ended {
				record.Thread.Status.Type = "active"
				record.Thread.Status.ActiveFlags = appendUniqueStrings(record.Thread.Status.ActiveFlags, "claudeRuntimeAvailable")
			}
			a.store.UpsertThread(record.Thread)
			record, _ = a.store.SnapshotSession(threadID)
		}
	}

	pendingCount := pendingCountForThread(a.store.SnapshotPending(), threadID)
	return toSessionDetail(record, pendingCount), nil
}

func (a *Agent) readClaudeTurns(thread codex.Thread) ([]codex.Turn, int64, error) {
	path, err := a.findClaudeTranscriptPath(thread)
	if err != nil {
		return nil, 0, err
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, 0, err
	}
	defer file.Close()

	var turns []codex.Turn
	var current *codex.Turn
	var lastUpdated int64
	turnCounter := 0

	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var entry map[string]any
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			continue
		}

		entryType := toString(entry["type"])
		ts := parseClaudeTimestamp(toString(entry["timestamp"]))
		if ts > lastUpdated {
			lastUpdated = ts
		}

		switch entryType {
		case "user":
			prompt := extractClaudeMessageText(entry["message"])
			if shouldIgnoreClaudeUserEntry(entry, prompt) {
				continue
			}
			if current != nil {
				turns = append(turns, *current)
			}
			turnCounter++
			turnID := toString(entry["uuid"])
			if turnID == "" {
				turnID = fmt.Sprintf("claude-turn-%d", turnCounter)
			}
			startedAt := ts
			current = &codex.Turn{
				ID:     turnID,
				Items:  []map[string]any{composeUserMessageItem(prompt)},
				Status: "inProgress",
			}
			if startedAt > 0 {
				current.StartedAt = &startedAt
			}
		case "assistant":
			if current == nil {
				continue
			}
			text := extractClaudeMessageText(entry["message"])
			if strings.TrimSpace(text) != "" {
				current.Items = append(current.Items, map[string]any{
					"id":   toString(entry["uuid"]),
					"type": "agentMessage",
					"text": text,
				})
			}
			current.Status = "completed"
			completedAt := ts
			if completedAt <= 0 {
				completedAt = time.Now().Unix()
			}
			current.CompletedAt = &completedAt
			if current.StartedAt != nil && completedAt >= *current.StartedAt {
				duration := (completedAt - *current.StartedAt) * 1000
				current.DurationMs = &duration
			}
		case "result":
			if current == nil {
				continue
			}
			resultText := strings.TrimSpace(toString(entry["result"]))
			if resultText != "" && !turnHasAgentMessage(current.Items) {
				current.Items = append(current.Items, map[string]any{
					"type": "agentMessage",
					"text": resultText,
				})
			}
			isError, _ := entry["is_error"].(bool)
			if isError {
				current.Status = "failed"
				if resultText == "" {
					resultText = "claude turn failed"
				}
				current.Error = &codex.TurnError{Message: resultText}
			} else if current.Status != "completed" {
				current.Status = "completed"
			}
			completedAt := ts
			if completedAt <= 0 {
				completedAt = time.Now().Unix()
			}
			current.CompletedAt = &completedAt
			if current.StartedAt != nil && completedAt >= *current.StartedAt {
				duration := (completedAt - *current.StartedAt) * 1000
				current.DurationMs = &duration
			}
		case "system":
			if current == nil {
				continue
			}
			if strings.TrimSpace(toString(entry["subtype"])) != "api_error" {
				continue
			}
			current.Status = "failed"
			errorText := extractClaudeSystemError(entry)
			if errorText == "" {
				errorText = "claude turn failed"
			}
			current.Error = &codex.TurnError{Message: errorText}
			completedAt := ts
			if completedAt <= 0 {
				completedAt = time.Now().Unix()
			}
			current.CompletedAt = &completedAt
			if current.StartedAt != nil && completedAt >= *current.StartedAt {
				duration := (completedAt - *current.StartedAt) * 1000
				current.DurationMs = &duration
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return nil, 0, err
	}
	if current != nil {
		// Claude transcript may end after a user entry without assistant/result yet.
		// When importing history (takeover), we treat this as a closed historical turn
		// instead of a live running turn to avoid false "in progress" UI state.
		if current.Status == "inProgress" {
			finishedAt := lastUpdated
			if finishedAt <= 0 {
				finishedAt = time.Now().Unix()
			}
			current.Status = "completed"
			current.CompletedAt = &finishedAt
			if current.StartedAt != nil && finishedAt >= *current.StartedAt {
				duration := (finishedAt - *current.StartedAt) * 1000
				current.DurationMs = &duration
			}
		}
		turns = append(turns, *current)
	}
	return turns, lastUpdated, nil
}

func (a *Agent) findClaudeTranscriptPath(thread codex.Thread) (string, error) {
	return claudeTranscriptPathForThread(thread)
}

func claudeTranscriptPathForThread(thread codex.Thread) (string, error) {
	if thread.Path != nil && strings.TrimSpace(*thread.Path) != "" {
		return strings.TrimSpace(*thread.Path), nil
	}
	sessionID, ok := parseClaudeSessionID(thread.ID)
	if !ok {
		return "", errors.New("invalid Claude session id")
	}
	return findClaudeTranscriptPathStatic(sessionID)
}

type claudeTranscriptAnalysis struct {
	HasAssistantOrResult bool
	HasSystemError       bool
	HasResumeFailure     bool
}

func analyzeClaudeTranscript(thread codex.Thread) (claudeTranscriptAnalysis, error) {
	path, err := claudeTranscriptPathForThread(thread)
	if err != nil {
		return claudeTranscriptAnalysis{}, err
	}
	file, err := os.Open(path)
	if err != nil {
		return claudeTranscriptAnalysis{}, err
	}
	defer file.Close()

	var analysis claudeTranscriptAnalysis
	scanner := bufio.NewScanner(file)
	scanner.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var entry map[string]any
		if err := json.Unmarshal([]byte(line), &entry); err != nil {
			continue
		}

		switch strings.TrimSpace(toString(entry["type"])) {
		case "assistant", "result":
			analysis.HasAssistantOrResult = true
		case "system":
			if strings.TrimSpace(toString(entry["subtype"])) == "api_error" {
				analysis.HasSystemError = true
			}
		case "user":
			prompt := strings.ToLower(strings.TrimSpace(extractClaudeMessageText(entry["message"])))
			if strings.Contains(prompt, "no conversations found to resume") ||
				strings.Contains(prompt, "no conversation found with session id") {
				analysis.HasResumeFailure = true
			}
		}
	}
	if err := scanner.Err(); err != nil {
		return claudeTranscriptAnalysis{}, err
	}
	return analysis, nil
}

func claudeResumeBlockedReason(preview string, hasTurns bool, analysis claudeTranscriptAnalysis) string {
	if analysis.HasResumeFailure {
		return "Claude CLI 标记这个历史会话不可恢复。"
	}
	if !analysis.HasAssistantOrResult && analysis.HasSystemError {
		return "这个 Claude 会话初始化失败，没有形成可恢复会话。"
	}
	if strings.TrimSpace(preview) == "/resume" && !hasTurns {
		return "这是一次失败的 /resume 尝试，没有形成可恢复会话。"
	}
	return ""
}

func findClaudeTranscriptPathStatic(sessionID string) (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	root := filepath.Join(home, ".claude", "projects")
	targetName := strings.TrimSpace(sessionID) + ".jsonl"
	var found string
	walkErr := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return nil
		}
		if d.IsDir() {
			return nil
		}
		if d.Name() != targetName {
			return nil
		}
		found = path
		return filepath.SkipAll
	})
	if walkErr != nil && !errors.Is(walkErr, filepath.SkipAll) {
		return "", walkErr
	}
	if strings.TrimSpace(found) == "" {
		return "", fmt.Errorf("transcript not found for session %s", sessionID)
	}
	return found, nil
}

func parseClaudeTimestamp(raw string) int64 {
	value := strings.TrimSpace(raw)
	if value == "" {
		return 0
	}
	t, err := time.Parse(time.RFC3339Nano, value)
	if err != nil {
		return 0
	}
	return t.Unix()
}

func normalizeClaudeComparablePath(path string) string {
	path = strings.TrimSpace(path)
	if path == "" {
		return ""
	}
	clean := filepath.Clean(path)
	if resolved, err := filepath.EvalSymlinks(clean); err == nil && strings.TrimSpace(resolved) != "" {
		clean = resolved
	}
	if abs, err := filepath.Abs(clean); err == nil && strings.TrimSpace(abs) != "" {
		clean = abs
	}
	return filepath.Clean(clean)
}

func stringPtr(value string) *string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return nil
	}
	return &trimmed
}

func composeUserMessageItem(text string) map[string]any {
	return map[string]any{
		"type": "userMessage",
		"content": []any{
			map[string]any{
				"type": "text",
				"text": strings.TrimSpace(text),
			},
		},
	}
}

func extractClaudeMessageText(message any) string {
	messageMap, ok := message.(map[string]any)
	if !ok {
		return ""
	}
	switch content := messageMap["content"].(type) {
	case string:
		return strings.TrimSpace(content)
	case []any:
		parts := make([]string, 0, len(content))
		for _, item := range content {
			itemMap, ok := item.(map[string]any)
			if !ok {
				continue
			}
			if strings.TrimSpace(toString(itemMap["type"])) != "text" {
				continue
			}
			text := strings.TrimSpace(toString(itemMap["text"]))
			if text != "" {
				parts = append(parts, text)
			}
		}
		return strings.TrimSpace(strings.Join(parts, "\n"))
	default:
		return ""
	}
}

func shouldIgnoreClaudeUserEntry(entry map[string]any, prompt string) bool {
	if meta, _ := entry["isMeta"].(bool); meta {
		return true
	}

	normalized := strings.ToLower(strings.TrimSpace(prompt))
	if normalized == "" {
		return true
	}
	if strings.Contains(normalized, "[request interrupted by user]") {
		return true
	}

	for _, needle := range []string{
		"<local-command-caveat>",
		"<command-name>",
		"<command-message>",
		"<command-args>",
		"<local-command-stdout>",
		"<local-command-stderr>",
	} {
		if strings.Contains(normalized, needle) {
			return true
		}
	}

	return false
}

func extractClaudeSystemError(entry map[string]any) string {
	errorObject, ok := entry["error"].(map[string]any)
	if !ok {
		return ""
	}

	if nested, ok := errorObject["error"].(map[string]any); ok {
		if nestedError, ok := nested["error"].(map[string]any); ok {
			if message := strings.TrimSpace(toString(nestedError["message"])); message != "" {
				return message
			}
		}
		if message := strings.TrimSpace(toString(nested["message"])); message != "" {
			return message
		}
	}

	if message := strings.TrimSpace(toString(errorObject["message"])); message != "" {
		return message
	}
	return ""
}

func toString(value any) string {
	if typed, ok := value.(string); ok {
		return typed
	}
	return ""
}

func turnHasAgentMessage(items []map[string]any) bool {
	for _, item := range items {
		if toString(item["type"]) == "agentMessage" && strings.TrimSpace(toString(item["text"])) != "" {
			return true
		}
	}
	return false
}

func flattenClaudeInput(input []map[string]any) string {
	parts := make([]string, 0, len(input))
	for _, item := range input {
		switch strings.TrimSpace(toString(item["type"])) {
		case "text":
			text := strings.TrimSpace(toString(item["text"]))
			if text != "" {
				parts = append(parts, text)
			}
		case "localImage":
			path := strings.TrimSpace(toString(item["path"]))
			if path != "" {
				parts = append(parts, fmt.Sprintf("[Attached image: %s]", path))
			}
		}
	}
	return strings.TrimSpace(strings.Join(parts, "\n\n"))
}

func (a *Agent) getClaudeSession(threadID string) (*claudeSDKSession, bool) {
	a.claudeSessionsMu.Lock()
	defer a.claudeSessionsMu.Unlock()
	session, ok := a.claudeSessions[strings.TrimSpace(threadID)]
	return session, ok
}

func (a *Agent) setClaudeSession(threadID string, session *claudeSDKSession) {
	a.claudeSessionsMu.Lock()
	defer a.claudeSessionsMu.Unlock()
	threadID = strings.TrimSpace(threadID)
	if threadID == "" || session == nil {
		return
	}
	a.claudeSessions[threadID] = session
}

func (a *Agent) clearClaudeSession(threadID string) {
	a.claudeSessionsMu.Lock()
	defer a.claudeSessionsMu.Unlock()
	delete(a.claudeSessions, strings.TrimSpace(threadID))
}

func (a *Agent) bindingClaudeSessionID(threadID string) string {
	if binding, ok := a.store.SessionBinding(threadID); ok && strings.EqualFold(strings.TrimSpace(binding.AgentID), "claude") {
		return strings.TrimSpace(binding.AgentSessionID)
	}
	if record, ok := a.store.SnapshotSession(threadID); ok {
		if record.Thread.RuntimeSessionID != nil && strings.TrimSpace(*record.Thread.RuntimeSessionID) != "" {
			return strings.TrimSpace(*record.Thread.RuntimeSessionID)
		}
	}
	return ""
}

func (a *Agent) openClaudeManagedSession(ctx context.Context, cwd, resumeSessionID string) (*claudeSDKSession, error) {
	parentCtx := a.runCtx
	if parentCtx == nil {
		parentCtx = context.Background()
	}
	runCtx, cancel := context.WithCancel(parentCtx)
	session := &claudeSDKSession{
		agent:            a,
		ctx:              runCtx,
		cancel:           cancel,
		sessionID:        strings.TrimSpace(resumeSessionID),
		cwd:              strings.TrimSpace(cwd),
		questionWaits:    make(map[string]chan claudeQuestionResult),
		questionRequests: make(map[string]string),
		approvalWaits:    make(map[string]chan claudePermissionDecision),
		approvalRequests: make(map[string]string),
	}
	client, stream, err := a.openClaudeSDKStreamWithToolHandler(runCtx, strings.TrimSpace(cwd), strings.TrimSpace(resumeSessionID), session.handleCanUseTool)
	if err != nil {
		cancel()
		return nil, err
	}
	if err := selectClaudeRuntimeModel(ctx, client, stream); err != nil {
		cancel()
		_ = stream.Close()
		_ = client.Close()
		return nil, err
	}
	if runtimeSessionID := detectClaudeRuntimeSessionID(ctx, client); runtimeSessionID != "" {
		session.sessionID = runtimeSessionID
		setClaudeSDKStreamSessionID(stream, runtimeSessionID)
	}
	session.client = client
	session.stream = stream
	go session.consume()
	return session, nil
}

func selectClaudeRuntimeModel(ctx context.Context, client *claudeagent.Client, stream *claudeagent.Stream) error {
	if client == nil || stream == nil {
		return errors.New("claude session not initialized")
	}
	candidate := preferredClaudeRuntimeModel(client.SupportedModelsFromInit())
	if candidate == "" {
		return nil
	}
	return stream.SetModel(ctx, candidate)
}

func preferredClaudeRuntimeModel(models []claudeagent.ModelInfo) string {
	for _, model := range models {
		candidate := strings.TrimSpace(model.Value)
		if candidate == "" || strings.EqualFold(candidate, "default") {
			continue
		}
		return candidate
	}
	return ""
}

func (a *Agent) getOrCreateClaudeManagedSession(ctx context.Context, threadID, cwd string) (*claudeSDKSession, error) {
	if session, ok := a.getClaudeSession(threadID); ok {
		session.mu.Lock()
		if strings.TrimSpace(cwd) != "" {
			session.cwd = strings.TrimSpace(cwd)
		}
		session.mu.Unlock()
		return session, nil
	}

	sessionID := a.bindingClaudeSessionID(threadID)
	if sessionID == "" {
		return nil, errors.New("missing claude session binding")
	}

	session, err := a.openClaudeManagedSession(ctx, cwd, sessionID)
	if err != nil {
		return nil, err
	}
	session.setThread(threadID, sessionID)

	a.claudeSessionsMu.Lock()
	defer a.claudeSessionsMu.Unlock()
	if existing, ok := a.claudeSessions[strings.TrimSpace(threadID)]; ok {
		_ = session.close()
		return existing, nil
	}
	a.claudeSessions[strings.TrimSpace(threadID)] = session
	return session, nil
}

func (a *Agent) attachClaudeManagedSession(ctx context.Context, threadID, cwd, resumeSessionID string) (*claudeSDKSession, error) {
	if existing, ok := a.getClaudeSession(threadID); ok {
		_ = existing.close()
		a.clearClaudeSession(threadID)
	}

	session, err := a.openClaudeManagedSession(ctx, cwd, resumeSessionID)
	if err != nil {
		return nil, err
	}
	session.setThread(threadID, strings.TrimSpace(resumeSessionID))

	a.claudeSessionsMu.Lock()
	defer a.claudeSessionsMu.Unlock()
	if existing, ok := a.claudeSessions[strings.TrimSpace(threadID)]; ok {
		_ = session.close()
		return existing, nil
	}
	a.claudeSessions[strings.TrimSpace(threadID)] = session
	return session, nil
}

func (a *Agent) resumeClaudeManagedSession(ctx context.Context, threadID, cwd string) (*claudeSDKSession, error) {
	return a.attachClaudeManagedSession(ctx, threadID, cwd, a.bindingClaudeSessionID(threadID))
}

func (s *claudeSDKSession) setThread(threadID, sessionID string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if strings.TrimSpace(threadID) != "" {
		s.threadID = strings.TrimSpace(threadID)
	}
	if strings.TrimSpace(sessionID) != "" {
		s.sessionID = strings.TrimSpace(sessionID)
		setClaudeSDKStreamSessionID(s.stream, strings.TrimSpace(sessionID))
	}
}

func (s *claudeSDKSession) sessionIDValue() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return strings.TrimSpace(s.sessionID)
}

func (s *claudeSDKSession) currentTurnID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.current == nil {
		return ""
	}
	return s.current.TurnID
}

func (a *Agent) waitForClaudeTurnClear(ctx context.Context, threadID, turnID string) error {
	deadlineCtx, cancel := context.WithTimeout(ctx, 8*time.Second)
	defer cancel()

	ticker := time.NewTicker(80 * time.Millisecond)
	defer ticker.Stop()

	for {
		session, ok := a.getClaudeSession(threadID)
		if !ok {
			if running, runningOK := a.getRunningClaudeTurn(threadID); !runningOK || strings.TrimSpace(running.TurnID) != strings.TrimSpace(turnID) {
				return nil
			}
		} else if current := strings.TrimSpace(session.currentTurnID()); current == "" || current != strings.TrimSpace(turnID) {
			if running, runningOK := a.getRunningClaudeTurn(threadID); !runningOK || strings.TrimSpace(running.TurnID) != strings.TrimSpace(turnID) {
				return nil
			}
		}

		select {
		case <-deadlineCtx.Done():
			return deadlineCtx.Err()
		case <-ticker.C:
		}
	}
}

func (s *claudeSDKSession) startTurn(ctx context.Context, turnID, prompt string, startedAt int64) (*claudeSDKTurnState, error) {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return nil, errors.New("claude session closed")
	}
	if s.current != nil {
		s.mu.Unlock()
		return nil, errors.New("claude turn already running")
	}
	state := newClaudeSDKTurnState(turnID, prompt, startedAt)
	s.current = state
	stream := s.stream
	s.mu.Unlock()

	if err := stream.Send(ctx, prompt); err != nil {
		s.mu.Lock()
		if s.current == state {
			s.current = nil
		}
		s.mu.Unlock()
		state.finish(claudeTurnExecutionResult{}, err)
		return nil, err
	}
	return state, nil
}

func (s *claudeSDKSession) interrupt() error {
	s.cancelPendingQuestions("turn interrupted")
	s.cancelPendingApprovals("turn interrupted")
	s.mu.Lock()
	stream := s.stream
	s.mu.Unlock()
	if stream == nil {
		return errors.New("claude session not initialized")
	}
	return stream.Interrupt(context.Background())
}

func (s *claudeSDKSession) close() error {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return nil
	}
	s.closed = true
	cancel := s.cancel
	stream := s.stream
	client := s.client
	s.mu.Unlock()

	s.cancelPendingQuestions("claude session closed")
	s.cancelPendingApprovals("claude session closed")

	if cancel != nil {
		cancel()
	}
	if stream != nil {
		_ = stream.Close()
	}
	if client != nil {
		return client.Close()
	}
	return nil
}

func (s *claudeSDKSession) handleCanUseTool(ctx context.Context, req claudeagent.ToolPermissionRequest) claudeagent.PermissionResult {
	toolName := strings.TrimSpace(req.ToolName)
	if toolName != "AskUserQuestion" && !shouldRequireClaudeApproval(toolName) {
		return claudeagent.PermissionAllow{}
	}

	if shouldRequireClaudeApproval(toolName) {
		callID := strings.TrimSpace(req.Context.ToolUseID)
		if callID == "" {
			return claudeagent.PermissionDeny{Reason: "tool approval missing tool use id"}
		}

		threadID, turnID := s.currentThreadAndTurn()
		if strings.TrimSpace(threadID) == "" {
			return claudeagent.PermissionDeny{Reason: "claude session thread unavailable"}
		}

		requestID, decision, err := s.awaitToolApproval(ctx, callID, toolName, threadID, turnID, req.Arguments)
		if requestID != "" {
			defer s.clearApprovalRequest(callID, requestID)
		}
		if err != nil {
			return claudeagent.PermissionDeny{Reason: err.Error()}
		}
		if !decision.Allow {
			reason := strings.TrimSpace(decision.Reason)
			if reason == "" {
				reason = "user denied approval"
			}
			return claudeagent.PermissionDeny{Reason: reason}
		}
		return claudeagent.PermissionAllow{}
	}

	var input claudeagent.AskUserQuestionInput
	if err := json.Unmarshal(req.Arguments, &input); err != nil || len(input.Questions) == 0 {
		return claudeagent.PermissionAllow{}
	}

	callID := strings.TrimSpace(req.Context.ToolUseID)
	if callID == "" {
		return claudeagent.PermissionDeny{Reason: "ask user question missing tool use id"}
	}

	threadID, turnID := s.currentThreadAndTurn()
	if strings.TrimSpace(threadID) == "" {
		return claudeagent.PermissionDeny{Reason: "claude session thread unavailable"}
	}

	requestID, answers, err := s.awaitAskUserQuestion(ctx, callID, threadID, turnID, input)
	if requestID != "" {
		defer s.clearQuestionRequest(callID, requestID)
	}
	if err != nil {
		return claudeagent.PermissionDeny{Reason: err.Error()}
	}

	updatedInput := make(map[string]any)
	if err := json.Unmarshal(req.Arguments, &updatedInput); err != nil {
		updatedInput["questions"] = input.Questions
	}
	updatedInput["answers"] = map[string]string(answers)
	return claudeagent.PermissionAllow{UpdatedInput: updatedInput}
}

func shouldRequireClaudeApproval(toolName string) bool {
	switch strings.ToLower(strings.TrimSpace(toolName)) {
	case "bash", "edit", "multiedit", "write", "notebookedit":
		return true
	default:
		return false
	}
}

func (s *claudeSDKSession) currentThreadAndTurn() (string, string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	threadID := s.threadID
	if s.current == nil {
		return threadID, ""
	}
	return threadID, s.current.TurnID
}

func (s *claudeSDKSession) awaitAskUserQuestion(ctx context.Context, toolUseID, threadID, turnID string, input claudeagent.AskUserQuestionInput) (string, claudeagent.Answers, error) {
	waiter := make(chan claudeQuestionResult, 1)

	params := map[string]any{
		"threadId":  threadID,
		"turnId":    turnID,
		"itemId":    toolUseID,
		"reason":    "Claude needs structured input from you",
		"questions": buildClaudeApprovalQuestions(input.Questions),
		"agent":     "claude",
	}

	pending := s.agent.store.UpsertPending("item/tool/requestUserInput", nil, params, []string{"answer"})
	s.questionMu.Lock()
	s.questionWaits[toolUseID] = waiter
	s.questionRequests[toolUseID] = pending.ID
	s.questionMu.Unlock()

	s.agent.broker.Publish("approval.created", PendingRequestView{
		ID:        pending.ID,
		Method:    pending.Method,
		Kind:      requestKind(pending.Method),
		ThreadID:  pending.ThreadID,
		TurnID:    pending.TurnID,
		ItemID:    pending.ItemID,
		Reason:    pending.Reason,
		Summary:   pending.Summary,
		Choices:   cloneStrings(pending.Choices),
		CreatedAt: pending.CreatedAt,
		Params:    pending.Params,
	})

	select {
	case result := <-waiter:
		if result.err != nil {
			return pending.ID, nil, result.err
		}
		return pending.ID, result.answers, nil
	case <-ctx.Done():
		return pending.ID, nil, ctx.Err()
	}
}

func (s *claudeSDKSession) submitQuestionAnswer(requestID string, answers claudeagent.Answers) error {
	if len(answers) == 0 {
		return errors.New("answers required")
	}

	s.questionMu.Lock()
	var toolUseID string
	for key, value := range s.questionRequests {
		if value == requestID {
			toolUseID = key
			break
		}
	}
	waiter, ok := s.questionWaits[toolUseID]
	s.questionMu.Unlock()
	if !ok || toolUseID == "" {
		return errors.New("question is not pending")
	}

	select {
	case waiter <- claudeQuestionResult{answers: answers}:
		return nil
	case <-s.ctx.Done():
		return s.ctx.Err()
	}
}

func (s *claudeSDKSession) awaitToolApproval(ctx context.Context, toolUseID, toolName, threadID, turnID string, raw json.RawMessage) (string, claudePermissionDecision, error) {
	waiter := make(chan claudePermissionDecision, 1)

	method, params, choices := buildClaudeApprovalRequest(toolUseID, toolName, threadID, turnID, raw)
	if item := claudeApprovalItem(toolUseID, toolName, s.cwd, raw); item != nil {
		s.agent.upsertClaudeTurnItem(threadID, turnID, item)
	}
	pending := s.agent.store.UpsertPending(method, nil, params, choices)

	s.approvalMu.Lock()
	s.approvalWaits[toolUseID] = waiter
	s.approvalRequests[toolUseID] = pending.ID
	s.approvalMu.Unlock()

	s.agent.broker.Publish("approval.created", PendingRequestView{
		ID:        pending.ID,
		Method:    pending.Method,
		Kind:      requestKind(pending.Method),
		ThreadID:  pending.ThreadID,
		TurnID:    pending.TurnID,
		ItemID:    pending.ItemID,
		Reason:    pending.Reason,
		Summary:   pending.Summary,
		Choices:   cloneStrings(pending.Choices),
		CreatedAt: pending.CreatedAt,
		Params:    pending.Params,
	})

	select {
	case decision := <-waiter:
		return pending.ID, decision, nil
	case <-ctx.Done():
		return pending.ID, claudePermissionDecision{}, ctx.Err()
	}
}

func (s *claudeSDKSession) submitApprovalDecision(requestID string, decision claudePermissionDecision) error {
	s.approvalMu.Lock()
	var toolUseID string
	for key, value := range s.approvalRequests {
		if value == requestID {
			toolUseID = key
			break
		}
	}
	waiter, ok := s.approvalWaits[toolUseID]
	s.approvalMu.Unlock()
	if !ok || toolUseID == "" {
		return errors.New("approval is not pending")
	}

	threadID, turnID := s.currentThreadAndTurn()
	if strings.TrimSpace(threadID) != "" && strings.TrimSpace(turnID) != "" {
		s.agent.updateClaudeTurnItem(threadID, turnID, toolUseID, func(item map[string]any) {
			if decision.Allow {
				item["status"] = "running"
			} else {
				item["status"] = "failed"
				if strings.TrimSpace(decision.Reason) != "" {
					switch toString(item["type"]) {
					case "commandExecution":
						item["aggregatedOutput"] = strings.TrimSpace(decision.Reason)
					default:
						item["result"] = strings.TrimSpace(decision.Reason)
					}
				}
			}
		})
	}

	select {
	case waiter <- decision:
		return nil
	case <-s.ctx.Done():
		return s.ctx.Err()
	}
}

func (s *claudeSDKSession) clearApprovalRequest(toolUseID, requestID string) {
	s.approvalMu.Lock()
	delete(s.approvalWaits, strings.TrimSpace(toolUseID))
	delete(s.approvalRequests, strings.TrimSpace(toolUseID))
	s.approvalMu.Unlock()
	if strings.TrimSpace(requestID) != "" {
		s.agent.store.DeletePending(strings.TrimSpace(requestID))
	}
}

func (s *claudeSDKSession) clearQuestionRequest(toolUseID, requestID string) {
	s.questionMu.Lock()
	delete(s.questionWaits, strings.TrimSpace(toolUseID))
	delete(s.questionRequests, strings.TrimSpace(toolUseID))
	s.questionMu.Unlock()
	if strings.TrimSpace(requestID) != "" {
		s.agent.store.DeletePending(strings.TrimSpace(requestID))
	}
}

func (s *claudeSDKSession) cancelPendingQuestions(reason string) {
	s.questionMu.Lock()
	waiters := make(map[string]chan claudeQuestionResult, len(s.questionWaits))
	requests := make(map[string]string, len(s.questionRequests))
	for key, waiter := range s.questionWaits {
		waiters[key] = waiter
	}
	for key, requestID := range s.questionRequests {
		requests[key] = requestID
	}
	s.questionWaits = make(map[string]chan claudeQuestionResult)
	s.questionRequests = make(map[string]string)
	s.questionMu.Unlock()

	for _, waiter := range waiters {
		select {
		case waiter <- claudeQuestionResult{err: errors.New(reason)}:
		default:
		}
	}
	for _, requestID := range requests {
		if strings.TrimSpace(requestID) != "" {
			s.agent.store.DeletePending(strings.TrimSpace(requestID))
		}
	}
}

func (s *claudeSDKSession) cancelPendingApprovals(reason string) {
	s.approvalMu.Lock()
	waiters := make(map[string]chan claudePermissionDecision, len(s.approvalWaits))
	requests := make(map[string]string, len(s.approvalRequests))
	for key, waiter := range s.approvalWaits {
		waiters[key] = waiter
	}
	for key, requestID := range s.approvalRequests {
		requests[key] = requestID
	}
	s.approvalWaits = make(map[string]chan claudePermissionDecision)
	s.approvalRequests = make(map[string]string)
	s.approvalMu.Unlock()

	for _, waiter := range waiters {
		select {
		case waiter <- claudePermissionDecision{Allow: false, Reason: reason}:
		default:
		}
	}
	for _, requestID := range requests {
		if strings.TrimSpace(requestID) != "" {
			s.agent.store.DeletePending(strings.TrimSpace(requestID))
		}
	}
}

func (s *claudeSDKSession) consume() {
	var terminalErr error
	for msg := range s.stream.Messages() {
		s.handleMessage(msg)
	}
	terminalErr = errors.New("claude stream ended unexpectedly")

	s.mu.Lock()
	current := s.current
	threadID := s.threadID
	s.current = nil
	s.mu.Unlock()
	if current != nil {
		current.finish(current.Result, terminalErr)
		if strings.TrimSpace(threadID) != "" {
			s.agent.clearRunningClaudeTurn(threadID, current.TurnID)
			s.agent.finishClaudeTurn(threadID, current.TurnID, current.Result, terminalErr)
		}
	}
	if strings.TrimSpace(threadID) != "" {
		s.agent.clearClaudeSession(threadID)
	}
}

func (s *claudeSDKSession) handleMessage(msg claudeagent.Message) {
	s.mu.Lock()
	current := s.current
	sessionID := extractClaudeSDKMessageSessionID(msg)
	if sessionID != "" {
		s.sessionID = sessionID
		setClaudeSDKStreamSessionID(s.stream, sessionID)
	}
	threadID := s.threadID
	s.mu.Unlock()

	if current != nil && sessionID != "" {
		current.Result.SessionID = sessionID
		current.signalSessionReady()
	}

	switch m := msg.(type) {
	case claudeagent.PartialAssistantMessage:
		if current == nil {
			return
		}
		delta := claudeSDKPartialDeltaText(m.Event)
		if delta == "" {
			return
		}
		current.Result.AssistantText += delta
		if strings.TrimSpace(threadID) != "" {
			s.agent.updateClaudeTurnProgress(threadID, current.TurnID, current.Result.AssistantText)
		}
	case claudeagent.AssistantMessage:
		if current == nil {
			return
		}
		text := strings.TrimSpace(m.ContentText())
		if text == "" {
			return
		}
		if strings.TrimSpace(current.Result.AssistantText) == "" {
			current.Result.AssistantText = text
		} else if !strings.Contains(current.Result.AssistantText, text) {
			current.Result.AssistantText += "\n" + text
		}
		if strings.TrimSpace(threadID) != "" {
			s.agent.updateClaudeTurnProgress(threadID, current.TurnID, current.Result.AssistantText)
		}
		if strings.TrimSpace(threadID) != "" {
			for _, block := range m.Message.Content {
				if block.Type != "tool_use" || strings.TrimSpace(block.ID) == "" {
					continue
				}
				s.agent.upsertClaudeToolCall(threadID, current.TurnID, s.cwd, block)
			}
		}
	case claudeagent.ToolProgressMessage:
		if current == nil || strings.TrimSpace(threadID) == "" || strings.TrimSpace(m.ToolUseID) == "" {
			return
		}
		s.agent.updateClaudeToolProgress(threadID, current.TurnID, m.ToolUseID, m.ToolName, m.ElapsedTimeSeconds)
	case claudeagent.UserMessage:
		if current == nil || strings.TrimSpace(threadID) == "" || m.ParentToolUseID == nil || strings.TrimSpace(*m.ParentToolUseID) == "" {
			return
		}
		s.agent.completeClaudeToolCall(threadID, current.TurnID, strings.TrimSpace(*m.ParentToolUseID), m.ToolUseResult)
	case claudeagent.ResultMessage:
		if current == nil {
			return
		}
		current.Result.ResultText = strings.TrimSpace(m.Result)
		current.Result.IsError = m.IsError || strings.EqualFold(m.Status, "error") || strings.HasPrefix(strings.ToLower(strings.TrimSpace(m.Subtype)), "error")
		current.finish(current.Result, nil)
		s.mu.Lock()
		if s.current == current {
			s.current = nil
		}
		s.mu.Unlock()
		if strings.TrimSpace(threadID) != "" {
			s.agent.finalizeClaudeToolCalls(threadID, current.TurnID, current.Result.IsError || current.Err != nil)
			s.agent.clearRunningClaudeTurn(threadID, current.TurnID)
			s.agent.finishClaudeTurn(threadID, current.TurnID, current.Result, nil)
		}
	}
}

func setClaudeSDKStreamSessionID(stream *claudeagent.Stream, sessionID string) {
	if stream == nil || strings.TrimSpace(sessionID) == "" {
		return
	}
	value := reflect.ValueOf(stream)
	if value.Kind() != reflect.Ptr || value.IsNil() {
		return
	}
	elem := value.Elem()
	field := elem.FieldByName("sessionID")
	if !field.IsValid() || field.Kind() != reflect.String {
		return
	}
	reflect.NewAt(field.Type(), unsafe.Pointer(field.UnsafeAddr())).Elem().SetString(strings.TrimSpace(sessionID))
}

func (a *Agent) updateClaudeTurnProgress(threadID, turnID, assistantText string) {
	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return
	}

	for idx := range record.Thread.Turns {
		if record.Thread.Turns[idx].ID != turnID {
			continue
		}
		items := record.Thread.Turns[idx].Items
		updated := false
		for itemIdx := range items {
			if toString(items[itemIdx]["id"]) == turnID+"-assistant-live" {
				items[itemIdx]["text"] = assistantText
				updated = true
				break
			}
		}
		if !updated && strings.TrimSpace(assistantText) != "" {
			items = append(items, map[string]any{
				"id":   turnID + "-assistant-live",
				"type": "agentMessage",
				"text": assistantText,
			})
		}
		record.Thread.Turns[idx].Items = items
		a.store.RecordTurn(threadID, record.Thread.Turns[idx])
		return
	}
}

func (a *Agent) upsertClaudeToolCall(threadID, turnID, cwd string, block claudeagent.ContentBlock) {
	item := claudeToolItem(block, cwd)
	if item == nil {
		return
	}
	a.upsertClaudeTurnItem(threadID, turnID, item)
}

func (a *Agent) updateClaudeToolProgress(threadID, turnID, toolUseID, toolName string, elapsed float64) {
	a.updateClaudeTurnItem(threadID, turnID, toolUseID, func(item map[string]any) {
		item["status"] = "running"
		if elapsed > 0 {
			item["progress"] = fmt.Sprintf("%.1fs", elapsed)
		}
		if strings.TrimSpace(toString(item["tool"])) == "" && strings.TrimSpace(toolName) != "" {
			item["tool"] = toolName
		}
	})
}

func (a *Agent) completeClaudeToolCall(threadID, turnID, toolUseID string, raw any) {
	a.updateClaudeTurnItem(threadID, turnID, toolUseID, func(item map[string]any) {
		item["status"] = "completed"
		if output := summarizeClaudeToolResult(item, raw); output != "" {
			switch toString(item["type"]) {
			case "commandExecution":
				item["aggregatedOutput"] = output
			case "collabAgentToolCall":
				item["result"] = output
			default:
				item["result"] = output
			}
		}
	})
}

func (a *Agent) finalizeClaudeToolCalls(threadID, turnID string, failed bool) {
	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return
	}
	for idx := range record.Thread.Turns {
		if record.Thread.Turns[idx].ID != turnID {
			continue
		}
		changed := false
		for itemIdx := range record.Thread.Turns[idx].Items {
			item := record.Thread.Turns[idx].Items[itemIdx]
			itemType := toString(item["type"])
			if itemType != "commandExecution" && itemType != "fileChange" && itemType != "dynamicToolCall" && itemType != "collabAgentToolCall" {
				continue
			}
			status := strings.TrimSpace(toString(item["status"]))
			if status == "" || status == "running" {
				if failed {
					item["status"] = "failed"
				} else {
					item["status"] = "completed"
				}
				record.Thread.Turns[idx].Items[itemIdx] = item
				changed = true
			}
		}
		if changed {
			a.store.RecordTurn(threadID, record.Thread.Turns[idx])
		}
		return
	}
}

func (a *Agent) upsertClaudeTurnItem(threadID, turnID string, item map[string]any) {
	itemID := strings.TrimSpace(toString(item["id"]))
	if itemID == "" {
		return
	}
	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return
	}
	for idx := range record.Thread.Turns {
		if record.Thread.Turns[idx].ID != turnID {
			continue
		}
		items := record.Thread.Turns[idx].Items
		for itemIdx := range items {
			if strings.TrimSpace(toString(items[itemIdx]["id"])) == itemID {
				items[itemIdx] = item
				record.Thread.Turns[idx].Items = items
				a.store.RecordTurn(threadID, record.Thread.Turns[idx])
				return
			}
		}
		record.Thread.Turns[idx].Items = append(items, item)
		a.store.RecordTurn(threadID, record.Thread.Turns[idx])
		return
	}
}

func (a *Agent) updateClaudeTurnItem(threadID, turnID, itemID string, mutate func(map[string]any)) {
	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return
	}
	for idx := range record.Thread.Turns {
		if record.Thread.Turns[idx].ID != turnID {
			continue
		}
		for itemIdx := range record.Thread.Turns[idx].Items {
			if strings.TrimSpace(toString(record.Thread.Turns[idx].Items[itemIdx]["id"])) != strings.TrimSpace(itemID) {
				continue
			}
			item := record.Thread.Turns[idx].Items[itemIdx]
			mutate(item)
			record.Thread.Turns[idx].Items[itemIdx] = item
			a.store.RecordTurn(threadID, record.Thread.Turns[idx])
			return
		}
		return
	}
}

func claudeToolItem(block claudeagent.ContentBlock, cwd string) map[string]any {
	name := strings.TrimSpace(block.Name)
	switch strings.ToLower(name) {
	case "bash":
		var payload claudeagent.BashInput
		if err := json.Unmarshal(block.Input, &payload); err != nil {
			return map[string]any{
				"id":     block.ID,
				"type":   "dynamicToolCall",
				"tool":   name,
				"status": "running",
			}
		}
		return map[string]any{
			"id":               block.ID,
			"type":             "commandExecution",
			"command":          strings.TrimSpace(payload.Command),
			"cwd":              cwd,
			"status":           "running",
			"tool":             name,
			"aggregatedOutput": "",
		}
	case "edit", "multiedit":
		var payload claudeagent.FileEditInput
		if err := json.Unmarshal(block.Input, &payload); err != nil {
			break
		}
		change := map[string]any{
			"path": strings.TrimSpace(payload.FilePath),
		}
		if payload.OldString != "" || payload.NewString != "" {
			change["oldText"] = payload.OldString
			change["newText"] = payload.NewString
		}
		return map[string]any{
			"id":      block.ID,
			"type":    "fileChange",
			"status":  "running",
			"tool":    name,
			"changes": []any{change},
		}
	case "write":
		var payload claudeagent.FileWriteInput
		if err := json.Unmarshal(block.Input, &payload); err != nil {
			break
		}
		change := map[string]any{
			"path":    strings.TrimSpace(payload.FilePath),
			"newText": payload.Content,
		}
		return map[string]any{
			"id":      block.ID,
			"type":    "fileChange",
			"status":  "running",
			"tool":    name,
			"changes": []any{change},
		}
	case "task":
		var payload claudeagent.TaskInput
		if err := json.Unmarshal(block.Input, &payload); err != nil {
			break
		}
		return map[string]any{
			"id":     block.ID,
			"type":   "collabAgentToolCall",
			"status": "running",
			"prompt": strings.TrimSpace(payload.Prompt),
			"title":  strings.TrimSpace(payload.Description),
			"tool":   name,
			"result": "",
		}
	default:
		summary := summarizeClaudeToolInput(name, block.Input)
		return map[string]any{
			"id":        block.ID,
			"type":      "dynamicToolCall",
			"namespace": "claude",
			"tool":      name,
			"status":    "running",
			"summary":   summary,
			"result":    "",
		}
	}

	summary := summarizeClaudeToolInput(name, block.Input)
	return map[string]any{
		"id":        block.ID,
		"type":      "dynamicToolCall",
		"namespace": "claude",
		"tool":      name,
		"status":    "running",
		"summary":   summary,
		"result":    "",
	}
}

func claudeApprovalItem(toolUseID, toolName, cwd string, raw json.RawMessage) map[string]any {
	item := claudeToolItem(claudeagent.ContentBlock{
		ID:    toolUseID,
		Type:  "tool_use",
		Name:  toolName,
		Input: raw,
	}, cwd)
	if item == nil {
		return nil
	}
	item["status"] = "waitingApproval"
	return item
}

func summarizeClaudeToolInput(name string, raw json.RawMessage) string {
	switch strings.ToLower(strings.TrimSpace(name)) {
	case "read":
		var payload claudeagent.FileReadInput
		if json.Unmarshal(raw, &payload) == nil {
			return strings.TrimSpace(payload.FilePath)
		}
	case "grep":
		var payload claudeagent.GrepInput
		if json.Unmarshal(raw, &payload) == nil {
			return strings.TrimSpace(payload.Pattern)
		}
	case "glob":
		var payload claudeagent.GlobInput
		if json.Unmarshal(raw, &payload) == nil {
			return strings.TrimSpace(payload.Pattern)
		}
	case "websearch":
		var payload claudeagent.WebSearchInput
		if json.Unmarshal(raw, &payload) == nil {
			return strings.TrimSpace(payload.Query)
		}
	case "askuserquestion":
		var payload claudeagent.AskUserQuestionInput
		if json.Unmarshal(raw, &payload) == nil && len(payload.Questions) > 0 {
			return strings.TrimSpace(payload.Questions[0].Question)
		}
	}
	return ""
}

func summarizeClaudeToolResult(item map[string]any, raw any) string {
	switch strings.ToLower(strings.TrimSpace(toString(item["tool"]))) {
	case "bash":
		var payload struct {
			Stdout string `json:"stdout"`
			Stderr string `json:"stderr"`
		}
		bytes, err := json.Marshal(raw)
		if err != nil {
			return ""
		}
		if err := json.Unmarshal(bytes, &payload); err != nil {
			return ""
		}
		switch {
		case strings.TrimSpace(payload.Stdout) != "":
			return payload.Stdout
		case strings.TrimSpace(payload.Stderr) != "":
			return payload.Stderr
		default:
			return ""
		}
	default:
		bytes, err := json.Marshal(raw)
		if err != nil {
			return ""
		}
		text := strings.TrimSpace(string(bytes))
		if text == "{}" || text == "null" {
			return ""
		}
		return text
	}
}

func buildClaudeApprovalQuestions(questions []claudeagent.QuestionItem) []any {
	items := make([]any, 0, len(questions))
	for index, question := range questions {
		options := make([]any, 0, len(question.Options))
		for _, option := range question.Options {
			options = append(options, map[string]any{
				"label":       option.Label,
				"description": option.Description,
			})
		}
		items = append(items, map[string]any{
			"id":          fmt.Sprintf("q_%d", index),
			"header":      question.Header,
			"question":    question.Question,
			"multiSelect": question.MultiSelect,
			"options":     options,
		})
	}
	return items
}

func buildClaudeApprovalRequest(toolUseID, toolName, threadID, turnID string, raw json.RawMessage) (string, map[string]any, []string) {
	switch strings.ToLower(strings.TrimSpace(toolName)) {
	case "bash":
		var payload claudeagent.BashInput
		command := ""
		if err := json.Unmarshal(raw, &payload); err == nil {
			command = strings.TrimSpace(payload.Command)
		}
		return "item/commandExecution/requestApproval", map[string]any{
			"threadId": threadID,
			"turnId":   turnID,
			"itemId":   toolUseID,
			"reason":   "Claude wants to execute a shell command",
			"command":  command,
			"tool":     toolName,
			"agent":    "claude",
		}, []string{"accept", "decline", "cancel"}
	case "edit", "multiedit":
		var payload claudeagent.FileEditInput
		change := map[string]any{}
		if err := json.Unmarshal(raw, &payload); err == nil {
			change["path"] = strings.TrimSpace(payload.FilePath)
			if payload.OldString != "" || payload.NewString != "" {
				change["oldText"] = payload.OldString
				change["newText"] = payload.NewString
			}
		}
		return "item/fileChange/requestApproval", map[string]any{
			"threadId": threadID,
			"turnId":   turnID,
			"itemId":   toolUseID,
			"reason":   "Claude wants to modify files",
			"changes":  []any{change},
			"tool":     toolName,
			"agent":    "claude",
		}, []string{"accept", "decline", "cancel"}
	case "write":
		var payload claudeagent.FileWriteInput
		change := map[string]any{}
		if err := json.Unmarshal(raw, &payload); err == nil {
			change["path"] = strings.TrimSpace(payload.FilePath)
			change["newText"] = payload.Content
		}
		return "item/fileChange/requestApproval", map[string]any{
			"threadId": threadID,
			"turnId":   turnID,
			"itemId":   toolUseID,
			"reason":   "Claude wants to create or overwrite a file",
			"changes":  []any{change},
			"tool":     toolName,
			"agent":    "claude",
		}, []string{"accept", "decline", "cancel"}
	case "notebookedit":
		return "item/fileChange/requestApproval", map[string]any{
			"threadId": threadID,
			"turnId":   turnID,
			"itemId":   toolUseID,
			"reason":   "Claude wants to modify a notebook",
			"changes":  []any{},
			"tool":     toolName,
			"agent":    "claude",
		}, []string{"accept", "decline", "cancel"}
	default:
		return "item/commandExecution/requestApproval", map[string]any{
			"threadId": threadID,
			"turnId":   turnID,
			"itemId":   toolUseID,
			"reason":   "Claude needs approval to use a tool",
			"command":  strings.TrimSpace(toolName),
			"tool":     toolName,
			"agent":    "claude",
		}, []string{"accept", "decline", "cancel"}
	}
}

func extractClaudeSDKMessageSessionID(msg claudeagent.Message) string {
	switch m := msg.(type) {
	case claudeagent.SystemMessage:
		return strings.TrimSpace(m.SessionID)
	case claudeagent.PartialAssistantMessage:
		return strings.TrimSpace(m.SessionID)
	case claudeagent.AssistantMessage:
		return strings.TrimSpace(m.SessionID)
	case claudeagent.ResultMessage:
		return strings.TrimSpace(m.SessionID)
	case claudeagent.ToolProgressMessage:
		return strings.TrimSpace(m.SessionID)
	default:
		return ""
	}
}

func claudeSDKPartialDeltaText(raw json.RawMessage) string {
	if len(raw) == 0 {
		return ""
	}
	var event map[string]any
	if err := json.Unmarshal(raw, &event); err != nil {
		return ""
	}
	if strings.TrimSpace(toString(event["type"])) != "content_block_delta" {
		return ""
	}
	delta, ok := event["delta"].(map[string]any)
	if !ok {
		return ""
	}
	if strings.TrimSpace(toString(delta["type"])) != "text_delta" {
		return ""
	}
	return toString(delta["text"])
}

func (a *Agent) startClaudeSession(ctx context.Context, cwd, prompt string) (SessionSummary, error) {
	trimmedPrompt := strings.TrimSpace(prompt)
	if trimmedPrompt == "" {
		return SessionSummary{}, errors.New("first prompt is required")
	}

	session, err := a.openClaudeManagedSession(ctx, strings.TrimSpace(cwd), "")
	if err != nil {
		return SessionSummary{}, err
	}

	startedAt := time.Now().Unix()
	turnID := uuid.NewString()
	state, err := session.startTurn(ctx, turnID, trimmedPrompt, startedAt)
	if err != nil {
		_ = session.close()
		return SessionSummary{}, err
	}

	var sessionID string
	select {
	case <-ctx.Done():
		_ = session.close()
		return SessionSummary{}, ctx.Err()
	case <-state.sessionReady:
		sessionID = strings.TrimSpace(state.Result.SessionID)
	}
	if sessionID == "" {
		_ = session.close()
		return SessionSummary{}, errors.New("claude did not return a session id")
	}

	threadID := claudeThreadID(sessionID)
	session.setThread(threadID, sessionID)
	a.setClaudeSession(threadID, session)

	thread := codex.Thread{
		ID:               threadID,
		Preview:          trimmedPrompt,
		Ephemeral:        false,
		ModelProvider:    "Anthropic",
		CreatedAt:        startedAt,
		UpdatedAt:        startedAt,
		Status:           codex.ThreadStatus{Type: "active", ActiveFlags: []string{"claudeRuntimeAvailable"}},
		RuntimeSessionID: stringPtr(sessionID),
		CWD:              strings.TrimSpace(cwd),
		Source:           json.RawMessage(`"claude"`),
		Turns:            []codex.Turn{},
	}
	a.store.UpsertThread(thread)
	a.store.SetSessionEnded(threadID, false)
	a.store.SetSessionManaged(threadID, true)
	a.store.SetSessionLoaded(threadID, true)
	a.store.SetRuntimeAttachMode(threadID, "new_session")
	a.store.SetSessionBinding(threadID, "claude", sessionID)
	a.store.RecordTurn(threadID, buildClaudePendingTurn(turnID, trimmedPrompt, startedAt))
	a.setRunningClaudeTurn(threadID, runningClaudeTurn{
		TurnID: turnID,
		Cancel: func() {
			_ = session.interrupt()
		},
	})

	record, _ := a.store.SnapshotSession(threadID)
	summary := toSessionSummary(record, 0)
	a.broker.Publish("session.created", summary)
	a.broker.Publish("turn.started", map[string]string{
		"threadId": threadID,
		"turnId":   turnID,
	})
	return summary, nil
}

func (a *Agent) resumeClaudeSession(ctx context.Context, threadID string) (SessionSummary, error) {
	if err := a.ensureClaudeThread(threadID); err != nil {
		return SessionSummary{}, err
	}
	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return SessionSummary{}, fmt.Errorf("session %s not found", threadID)
	}
	if available, reason := claudeResumeAvailability(record); !available {
		return SessionSummary{}, errors.New(reason)
	}

	runtimeSessionID := strings.TrimSpace(func() string {
		if record.Thread.RuntimeSessionID != nil {
			return strings.TrimSpace(*record.Thread.RuntimeSessionID)
		}
		return ""
	}())

	var session *claudeSDKSession
	var err error
	attachMode := "opened_from_history"
	if runtimeSessionID != "" {
		session, err = a.attachClaudeManagedSession(ctx, threadID, strings.TrimSpace(record.Thread.CWD), runtimeSessionID)
		if err != nil {
			a.logger.Warn("failed to resume claude runtime session; falling back to new runtime", "threadId", threadID, "runtimeSessionId", runtimeSessionID, "error", err)
			session, err = a.attachClaudeManagedSession(ctx, threadID, strings.TrimSpace(record.Thread.CWD), "")
			attachMode = "opened_from_history"
		} else {
			attachMode = "resumed_existing"
		}
	} else {
		session, err = a.attachClaudeManagedSession(ctx, threadID, strings.TrimSpace(record.Thread.CWD), "")
		attachMode = "opened_from_history"
	}
	if err != nil {
		return SessionSummary{}, fmt.Errorf("failed to take over Claude session: %w", err)
	}

	record.Thread.Status.ActiveFlags = appendUniqueStrings(record.Thread.Status.ActiveFlags, "claudeRuntimeAvailable")
	record.Thread.Status.Type = "idle"
	if runtimeSessionID != "" {
		record.Thread.RuntimeSessionID = stringPtr(runtimeSessionID)
	}
	if session != nil {
		session.mu.Lock()
		if strings.TrimSpace(session.sessionID) != "" {
			record.Thread.RuntimeSessionID = stringPtr(session.sessionID)
			a.store.SetSessionBinding(threadID, "claude", session.sessionID)
		}
		session.mu.Unlock()
	}
	a.store.SetSessionEnded(threadID, false)
	a.store.SetSessionManaged(threadID, true)
	a.store.SetSessionLoaded(threadID, true)
	a.store.SetRuntimeAttachMode(threadID, attachMode)
	a.store.UpsertThread(record.Thread)
	record, _ = a.store.SnapshotSession(threadID)
	summary := toSessionSummary(record, 0)
	a.broker.Publish("session.resumed", summary)
	return summary, nil
}

func (a *Agent) endClaudeSession(ctx context.Context, threadID string) error {
	running, ok := a.getRunningClaudeTurn(threadID)
	if ok {
		running.Cancel()
		if err := a.waitForClaudeTurnClear(ctx, threadID, running.TurnID); err != nil {
			a.logger.Warn("claude turn did not clear before session end; forcing local stop", "threadId", threadID, "turnId", running.TurnID, "error", err)
			a.forceStopClaudeTurn(threadID, running.TurnID, "session ended by user")
		}
	}
	if session, ok := a.getClaudeSession(threadID); ok {
		_ = session.close()
		a.clearClaudeSession(threadID)
	}
	a.store.UpdateThreadStatus(threadID, codex.ThreadStatus{Type: "idle"})
	a.store.SetSessionEnded(threadID, true)
	a.store.SetSessionManaged(threadID, false)
	a.store.SetSessionLoaded(threadID, false)
	a.broker.Publish("session.ended", map[string]string{
		"threadId": threadID,
	})
	return nil
}

func (a *Agent) archiveClaudeSession(threadID string) error {
	if session, ok := a.getClaudeSession(threadID); ok {
		_ = session.close()
		a.clearClaudeSession(threadID)
	}
	a.store.DeleteSessionLocalState(threadID)
	a.broker.Publish("session.archived", map[string]string{
		"threadId": threadID,
	})
	return nil
}

func (a *Agent) startClaudeTurn(ctx context.Context, threadID string, input []map[string]any) (TurnDetail, error) {
	if _, ok := parseClaudeSessionID(threadID); !ok {
		return TurnDetail{}, errors.New("invalid claude thread id")
	}
	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return TurnDetail{}, fmt.Errorf("session %s not found", threadID)
	}

	prompt := flattenClaudeInput(input)
	if prompt == "" {
		return TurnDetail{}, errors.New("turn input is required")
	}

	session, err := a.getOrCreateClaudeManagedSession(ctx, threadID, strings.TrimSpace(record.Thread.CWD))
	if err != nil {
		return TurnDetail{}, err
	}

	startedAt := time.Now().Unix()
	turnID := uuid.NewString()
	state, err := session.startTurn(ctx, turnID, prompt, startedAt)
	if err != nil {
		return TurnDetail{}, err
	}
	<-state.sessionReady
	startedSessionID := strings.TrimSpace(state.Result.SessionID)

	a.store.SetSessionEnded(threadID, false)
	record.Thread.Status = codex.ThreadStatus{Type: "active", ActiveFlags: []string{"claudeRuntimeAvailable"}}
	record.Thread.UpdatedAt = startedAt
	if record.Thread.CreatedAt == 0 {
		record.Thread.CreatedAt = startedAt
	}
	if strings.TrimSpace(record.Thread.Preview) == "" {
		record.Thread.Preview = prompt
	}
	a.store.UpsertThread(record.Thread)
	if startedSessionID != "" {
		a.store.SetSessionBinding(threadID, "claude", startedSessionID)
		record.Thread.RuntimeSessionID = stringPtr(startedSessionID)
	}
	a.store.RecordTurn(threadID, buildClaudePendingTurn(turnID, prompt, startedAt))
	a.setRunningClaudeTurn(threadID, runningClaudeTurn{
		TurnID: turnID,
		Cancel: func() {
			_ = session.interrupt()
		},
	})

	detail, err := a.claudeSessionDetail(threadID)
	if err != nil {
		return TurnDetail{}, err
	}
	var lastTurn TurnDetail
	found := false
	for _, item := range detail.Turns {
		if item.ID == turnID {
			lastTurn = item
			found = true
			break
		}
	}
	if !found {
		return TurnDetail{}, errors.New("turn not found after claude turn start")
	}
	a.broker.Publish("turn.started", map[string]string{
		"threadId": threadID,
		"turnId":   turnID,
	})
	return lastTurn, nil
}

type claudeTurnExecutionResult struct {
	SessionID     string
	AssistantText string
	ResultText    string
	IsError       bool
}

func (a *Agent) openClaudeSDKStream(ctx context.Context, cwd, resumeSessionID string) (*claudeagent.Client, *claudeagent.Stream, error) {
	return a.openClaudeSDKStreamWithToolHandler(ctx, cwd, resumeSessionID, nil)
}

func (a *Agent) openClaudeSDKStreamWithToolHandler(ctx context.Context, cwd, resumeSessionID string, canUseTool claudeagent.CanUseToolFunc) (*claudeagent.Client, *claudeagent.Stream, error) {
	options := []claudeagent.Option{
		claudeagent.WithCwd(strings.TrimSpace(cwd)),
		claudeagent.WithCLIPath(a.cfg.ClaudePath),
		claudeagent.WithVerbose(true),
		claudeagent.WithIncludePartialMessages(true),
	}
	if canUseTool != nil {
		options = append(options, claudeagent.WithCanUseTool(canUseTool))
	}
	if strings.TrimSpace(resumeSessionID) != "" {
		options = append(options, claudeagent.WithResume(strings.TrimSpace(resumeSessionID)))
	}

	client, err := claudeagent.NewClient(options...)
	if err != nil {
		return nil, nil, err
	}
	stream, err := client.Stream(ctx)
	if err != nil {
		_ = client.Close()
		return nil, nil, err
	}
	return client, stream, nil
}

func (a *Agent) finishClaudeTurn(threadID, turnID string, result claudeTurnExecutionResult, runErr error) {
	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return
	}

	var target *codex.Turn
	for idx := range record.Thread.Turns {
		if record.Thread.Turns[idx].ID == turnID {
			target = &record.Thread.Turns[idx]
			break
		}
	}
	if target == nil {
		return
	}

	if strings.TrimSpace(target.Status) != "" && target.Status != "inProgress" {
		if strings.TrimSpace(result.SessionID) != "" {
			a.store.SetSessionBinding(threadID, "claude", strings.TrimSpace(result.SessionID))
		}
		record.Thread.Status = codex.ThreadStatus{Type: "idle"}
		a.store.UpsertThread(record.Thread)
		return
	}

	completedAt := time.Now().Unix()
	target.CompletedAt = &completedAt
	if target.StartedAt != nil && completedAt >= *target.StartedAt {
		duration := (completedAt - *target.StartedAt) * 1000
		target.DurationMs = &duration
	}

	assistantText := strings.TrimSpace(result.AssistantText)
	if assistantText == "" {
		assistantText = strings.TrimSpace(result.ResultText)
	}
	if assistantText != "" {
		target.Items = append(target.Items, map[string]any{
			"id":   uuid.NewString(),
			"type": "agentMessage",
			"text": assistantText,
		})
	}

	switch {
	case errors.Is(runErr, context.Canceled):
		target.Status = "failed"
		target.Error = &codex.TurnError{Message: "interrupted by user"}
	case runErr != nil:
		target.Status = "failed"
		target.Error = &codex.TurnError{Message: runErr.Error()}
	case result.IsError:
		target.Status = "failed"
		errorText := strings.TrimSpace(result.ResultText)
		if errorText == "" {
			errorText = "claude turn failed"
		}
		target.Error = &codex.TurnError{Message: errorText}
	default:
		target.Status = "completed"
	}

	record.Thread.UpdatedAt = completedAt
	record.Thread.Status = codex.ThreadStatus{Type: "idle", ActiveFlags: []string{"claudeRuntimeAvailable"}}
	if strings.TrimSpace(result.SessionID) != "" {
		a.store.SetSessionBinding(threadID, "claude", strings.TrimSpace(result.SessionID))
		record.Thread.RuntimeSessionID = stringPtr(strings.TrimSpace(result.SessionID))
	}
	a.store.UpsertThread(record.Thread)
	a.store.RecordTurn(threadID, *target)
	a.broker.Publish("turn.completed", map[string]string{
		"threadId": threadID,
		"turnId":   turnID,
	})
}

func (a *Agent) forceStopClaudeTurn(threadID, turnID, message string) {
	if session, ok := a.getClaudeSession(threadID); ok {
		_ = session.close()
		a.clearClaudeSession(threadID)
	}
	a.clearRunningClaudeTurn(threadID, turnID)

	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return
	}

	var target *codex.Turn
	for idx := range record.Thread.Turns {
		if record.Thread.Turns[idx].ID == turnID {
			target = &record.Thread.Turns[idx]
			break
		}
	}
	if target == nil {
		return
	}

	if target.Status == "inProgress" {
		completedAt := time.Now().Unix()
		target.Status = "failed"
		target.CompletedAt = &completedAt
		target.Error = &codex.TurnError{Message: strings.TrimSpace(message)}
		if target.StartedAt != nil && completedAt >= *target.StartedAt {
			duration := (completedAt - *target.StartedAt) * 1000
			target.DurationMs = &duration
		}
		a.store.RecordTurn(threadID, *target)
	}

	record.Thread.Status = codex.ThreadStatus{Type: "idle"}
	record.Thread.UpdatedAt = time.Now().Unix()
	a.store.UpsertThread(record.Thread)
}

func buildClaudePendingTurn(turnID, prompt string, startedAt int64) codex.Turn {
	turn := codex.Turn{
		ID:     turnID,
		Items:  []map[string]any{composeUserMessageItem(prompt)},
		Status: "inProgress",
	}
	turn.StartedAt = &startedAt
	return turn
}

func mergeClaudeTurns(history []codex.Turn, live []codex.Turn) []codex.Turn {
	if len(history) == 0 {
		return cloneClaudeTurns(live)
	}
	if len(live) == 0 {
		return cloneClaudeTurns(history)
	}

	merged := cloneClaudeTurns(history)
	indexByID := make(map[string]int, len(merged))
	for idx := range merged {
		indexByID[merged[idx].ID] = idx
	}
	for _, turn := range live {
		if idx, ok := indexByID[turn.ID]; ok {
			merged[idx] = mergeClaudeTurn(merged[idx], turn)
			continue
		}
		if idx, ok := findMatchingClaudeTurnIndex(merged, turn); ok {
			merged[idx] = mergeClaudeTurn(merged[idx], turn)
			continue
		}
		merged = append(merged, turn)
	}
	return merged
}

func cloneClaudeTurns(turns []codex.Turn) []codex.Turn {
	if len(turns) == 0 {
		return nil
	}
	data, _ := json.Marshal(turns)
	var cloned []codex.Turn
	_ = json.Unmarshal(data, &cloned)
	return cloned
}

func mergeClaudeTurn(historyTurn, liveTurn codex.Turn) codex.Turn {
	merged := historyTurn
	if strings.TrimSpace(liveTurn.Status) != "" {
		merged.Status = liveTurn.Status
	}
	if liveTurn.Error != nil {
		merged.Error = liveTurn.Error
	}
	if liveTurn.StartedAt != nil {
		merged.StartedAt = liveTurn.StartedAt
	}
	if liveTurn.CompletedAt != nil {
		merged.CompletedAt = liveTurn.CompletedAt
	}
	if liveTurn.DurationMs != nil {
		merged.DurationMs = liveTurn.DurationMs
	}
	if len(liveTurn.Items) > 0 {
		merged.Items = liveTurn.Items
	}
	return merged
}

func findMatchingClaudeTurnIndex(history []codex.Turn, liveTurn codex.Turn) (int, bool) {
	livePrompt := strings.TrimSpace(codex.FirstUserText(liveTurn.Items))
	if livePrompt == "" {
		return -1, false
	}
	liveStartedAt := derefClaudeTurnTime(liveTurn.StartedAt)
	for idx, historyTurn := range history {
		if strings.TrimSpace(codex.FirstUserText(historyTurn.Items)) != livePrompt {
			continue
		}
		historyStartedAt := derefClaudeTurnTime(historyTurn.StartedAt)
		if liveStartedAt == 0 || historyStartedAt == 0 {
			continue
		}
		diff := liveStartedAt - historyStartedAt
		if diff < 0 {
			diff = -diff
		}
		if diff <= 5 {
			return idx, true
		}
	}
	return -1, false
}

func derefClaudeTurnTime(value *int64) int64 {
	if value == nil {
		return 0
	}
	return *value
}

func appendUniqueStrings(existing []string, values ...string) []string {
	result := slices.Clone(existing)
	for _, value := range values {
		trimmed := strings.TrimSpace(value)
		if trimmed == "" || slices.Contains(result, trimmed) {
			continue
		}
		result = append(result, trimmed)
	}
	return result
}

func claudeThreadStatusFromTurns(turns []codex.Turn) string {
	if len(turns) == 0 {
		return "idle"
	}
	last := turns[len(turns)-1]
	if strings.TrimSpace(last.Status) == "inProgress" {
		return "active"
	}
	return "idle"
}

func (a *Agent) setRunningClaudeTurn(threadID string, turn runningClaudeTurn) {
	a.claudeTurnsMu.Lock()
	defer a.claudeTurnsMu.Unlock()
	if existing, ok := a.claudeRunning[threadID]; ok {
		existing.Cancel()
	}
	a.claudeRunning[threadID] = turn
}

func (a *Agent) clearRunningClaudeTurn(threadID, turnID string) {
	a.claudeTurnsMu.Lock()
	defer a.claudeTurnsMu.Unlock()
	existing, ok := a.claudeRunning[threadID]
	if !ok || existing.TurnID != turnID {
		return
	}
	delete(a.claudeRunning, threadID)
}

func (a *Agent) getRunningClaudeTurn(threadID string) (runningClaudeTurn, bool) {
	a.claudeTurnsMu.Lock()
	defer a.claudeTurnsMu.Unlock()
	turn, ok := a.claudeRunning[threadID]
	return turn, ok
}
