package runtime

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"codexflow/internal/codex"
	"codexflow/internal/config"
	"codexflow/internal/store"
)

type Agent struct {
	cfg     config.Config
	logger  *slog.Logger
	client  *codex.Client
	store   *store.Store
	broker  *Broker
	started time.Time
}

func NewAgent(cfg config.Config, logger *slog.Logger) *Agent {
	localState, err := store.OpenLocalStateDB(cfg.StateDBPath)
	if err != nil {
		logger.Warn("failed to open local state db", "path", cfg.StateDBPath, "error", err)
	}

	sessionStore, err := store.New(localState)
	if err != nil {
		logger.Warn("failed to load persisted local state", "path", cfg.StateDBPath, "error", err)
		sessionStore, _ = store.New(nil)
	}

	return &Agent{
		cfg:     cfg,
		logger:  logger,
		client:  codex.NewClient(cfg.CodexPath, logger),
		store:   sessionStore,
		broker:  NewBroker(),
		started: time.Now(),
	}
}

func (a *Agent) Start(ctx context.Context) error {
	if err := a.client.Start(ctx); err != nil {
		return err
	}

	a.restoreManagedSessions(ctx)

	if err := a.Refresh(ctx); err != nil {
		a.logger.Warn("initial refresh failed", "error", err)
	}

	go a.consumeNotifications(ctx)
	go a.consumeServerRequests(ctx)
	go a.consumeStderr()
	go a.refreshLoop(ctx)

	return nil
}

func (a *Agent) restoreManagedSessions(ctx context.Context) {
	for _, threadID := range a.store.ManagedSessionIDs() {
		resumeCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
		_, err := a.ResumeSession(resumeCtx, threadID)
		cancel()
		if err != nil {
			a.logger.Warn("failed to restore managed session", "threadId", threadID, "error", err)
		}
	}
}

func (a *Agent) Subscribe() chan Event {
	return a.broker.Subscribe()
}

func (a *Agent) Unsubscribe(ch chan Event) {
	a.broker.Unsubscribe(ch)
}

func (a *Agent) Dashboard() Dashboard {
	summaries := a.ListSessions()
	approvals := a.PendingRequests()

	stats := DashboardStats{
		TotalSessions:    len(summaries),
		PendingApprovals: len(approvals),
	}
	for _, session := range summaries {
		if session.Loaded {
			stats.LoadedSessions++
		}
		if session.Status == "active" && !session.Ended {
			stats.ActiveSessions++
		}
	}

	return Dashboard{
		Agent: AgentSnapshot{
			Connected:       true,
			StartedAt:       a.started,
			ListenAddr:      a.cfg.ListenAddr,
			CodexBinaryPath: a.cfg.CodexPath,
		},
		Stats:     stats,
		Sessions:  summaries,
		Approvals: approvals,
	}
}

func (a *Agent) ListSessions() []SessionSummary {
	records := a.store.SnapshotSessions()
	pending := a.store.SnapshotPending()
	perThreadPending := make(map[string]int)
	for _, approval := range pending {
		perThreadPending[approval.ThreadID]++
	}

	summaries := make([]SessionSummary, 0, len(records))
	for _, record := range records {
		summaries = append(summaries, toSessionSummary(record, perThreadPending[record.Thread.ID]))
	}
	return summaries
}

func (a *Agent) SessionDetail(ctx context.Context, threadID string) (SessionDetail, error) {
	var response codex.ThreadReadResponse
	if err := a.client.Call(ctx, "thread/read", map[string]any{
		"threadId":     threadID,
		"includeTurns": true,
	}, &response); err != nil {
		if strings.Contains(err.Error(), "includeTurns is unavailable before first user message") {
			record, ok := a.store.SnapshotSession(threadID)
			if !ok {
				return SessionDetail{}, err
			}
			return toSessionDetail(record, pendingCountForThread(a.store.SnapshotPending(), threadID)), nil
		}
		return SessionDetail{}, err
	}

	a.store.UpsertThread(response.Thread)
	record, ok := a.store.SnapshotSession(threadID)
	if !ok {
		return SessionDetail{}, errors.New("session not found after refresh")
	}

	pendingCount := pendingCountForThread(a.store.SnapshotPending(), threadID)

	return toSessionDetail(record, pendingCount), nil
}

func (a *Agent) PendingRequests() []PendingRequestView {
	pending := a.store.SnapshotPending()
	views := make([]PendingRequestView, 0, len(pending))
	for _, request := range pending {
		views = append(views, PendingRequestView{
			ID:        request.ID,
			Method:    request.Method,
			Kind:      requestKind(request.Method),
			ThreadID:  request.ThreadID,
			TurnID:    request.TurnID,
			ItemID:    request.ItemID,
			Reason:    request.Reason,
			Summary:   request.Summary,
			Choices:   cloneStrings(request.Choices),
			CreatedAt: request.CreatedAt,
			Params:    request.Params,
		})
	}
	return views
}

func (a *Agent) ResolveRequest(ctx context.Context, requestID string, result json.RawMessage) error {
	request, ok := a.store.DeletePending(requestID)
	if !ok {
		return fmt.Errorf("pending request %s not found", requestID)
	}

	var payload any
	if len(result) > 0 {
		if err := json.Unmarshal(result, &payload); err != nil {
			return fmt.Errorf("decode resolve payload: %w", err)
		}
	}

	if err := a.client.Reply(ctx, request.RawRPCRequestID, payload); err != nil {
		return err
	}

	a.broker.Publish("approval.resolved", PendingRequestView{
		ID:        request.ID,
		Method:    request.Method,
		Kind:      requestKind(request.Method),
		ThreadID:  request.ThreadID,
		TurnID:    request.TurnID,
		ItemID:    request.ItemID,
		Reason:    request.Reason,
		Summary:   request.Summary,
		Choices:   cloneStrings(request.Choices),
		CreatedAt: request.CreatedAt,
		Params:    request.Params,
	})
	return nil
}

func (a *Agent) Refresh(ctx context.Context) error {
	threads, err := a.fetchThreads(ctx)
	if err != nil {
		return err
	}

	loadedIDs, err := a.fetchLoadedThreadIDs(ctx)
	if err != nil {
		return err
	}

	loaded := make(map[string]bool, len(loadedIDs))
	for _, id := range loadedIDs {
		loaded[id] = true
	}

	a.store.ReplaceSessions(threads, loaded)
	a.broker.Publish("sessions.refreshed", a.ListSessions())
	return nil
}

func (a *Agent) StartSession(ctx context.Context, cwd, prompt string) (SessionSummary, error) {
	var threadResp codex.ThreadStartResponse
	if err := a.client.Call(ctx, "thread/start", map[string]any{
		"cwd":                    emptyToNil(cwd),
		"experimentalRawEvents":  true,
		"persistExtendedHistory": true,
	}, &threadResp); err != nil {
		return SessionSummary{}, err
	}

	a.store.UpsertThread(threadResp.Thread)
	a.store.SetSessionEnded(threadResp.Thread.ID, false)
	a.store.SetSessionManaged(threadResp.Thread.ID, true)
	a.store.SetSessionLoaded(threadResp.Thread.ID, true)

	if strings.TrimSpace(prompt) != "" {
		if _, err := a.StartTurn(ctx, threadResp.Thread.ID, prompt); err != nil {
			return SessionSummary{}, err
		}
	}

	record, _ := a.store.SnapshotSession(threadResp.Thread.ID)
	summary := toSessionSummary(record, 0)
	a.broker.Publish("session.created", summary)
	return summary, nil
}

func (a *Agent) ResumeSession(ctx context.Context, threadID string) (SessionSummary, error) {
	var response codex.ThreadResumeResponse
	if err := a.client.Call(ctx, "thread/resume", map[string]any{
		"threadId":               threadID,
		"persistExtendedHistory": true,
	}, &response); err != nil {
		return SessionSummary{}, err
	}

	a.store.UpsertThread(response.Thread)
	a.store.SetSessionEnded(threadID, false)
	a.store.SetSessionManaged(threadID, true)
	a.store.SetSessionLoaded(threadID, true)
	record, _ := a.store.SnapshotSession(threadID)
	summary := toSessionSummary(record, 0)
	a.broker.Publish("session.resumed", summary)
	return summary, nil
}

func (a *Agent) EndSession(ctx context.Context, threadID string) error {
	record, ok := a.store.SnapshotSession(threadID)
	if ok && record.Loaded && len(record.Thread.Turns) > 0 {
		lastTurn := record.Thread.Turns[len(record.Thread.Turns)-1]
		if lastTurn.Status == "inProgress" {
			if err := a.InterruptTurn(ctx, threadID, lastTurn.ID); err != nil {
				return err
			}
		}
	}

	var response codex.ThreadUnsubscribeResponse
	if err := a.client.Call(ctx, "thread/unsubscribe", map[string]any{
		"threadId": threadID,
	}, &response); err != nil {
		return err
	}

	switch response.Status {
	case "", "unsubscribed", "notSubscribed", "notLoaded":
	default:
		return fmt.Errorf("unexpected unsubscribe status %q", response.Status)
	}

	a.store.SetSessionEnded(threadID, true)
	a.store.SetSessionManaged(threadID, false)
	a.store.SetSessionLoaded(threadID, false)
	_ = a.Refresh(ctx)
	a.broker.Publish("session.ended", map[string]string{
		"threadId": threadID,
	})
	return nil
}

func (a *Agent) ArchiveSession(ctx context.Context, threadID string) error {
	if err := a.client.Call(ctx, "thread/archive", map[string]any{
		"threadId": threadID,
	}, nil); err != nil {
		return err
	}

	a.store.DeleteSessionLocalState(threadID)
	_ = a.Refresh(ctx)
	a.broker.Publish("session.archived", map[string]string{
		"threadId": threadID,
	})
	return nil
}

func (a *Agent) StartTurn(ctx context.Context, threadID, prompt string) (TurnDetail, error) {
	var response codex.TurnStartResponse
	if err := a.client.Call(ctx, "turn/start", map[string]any{
		"threadId": threadID,
		"input":    []map[string]any{textInput(prompt)},
	}, &response); err != nil {
		return TurnDetail{}, err
	}

	a.store.SetSessionEnded(threadID, false)
	a.store.RecordTurn(threadID, response.Turn)
	a.broker.Publish("turn.started", map[string]string{
		"threadId": threadID,
		"turnId":   response.Turn.ID,
	})

	record, _ := a.store.SnapshotSession(threadID)
	for _, turn := range toSessionDetail(record, 0).Turns {
		if turn.ID == response.Turn.ID {
			return turn, nil
		}
	}
	return TurnDetail{}, errors.New("turn not found after start")
}

func (a *Agent) SteerTurn(ctx context.Context, threadID, turnID, prompt string) error {
	var response codex.TurnSteerResponse
	if err := a.client.Call(ctx, "turn/steer", map[string]any{
		"threadId":       threadID,
		"expectedTurnId": turnID,
		"input":          []map[string]any{textInput(prompt)},
	}, &response); err != nil {
		return err
	}

	a.broker.Publish("turn.steered", map[string]string{
		"threadId": threadID,
		"turnId":   turnID,
	})
	return nil
}

func (a *Agent) InterruptTurn(ctx context.Context, threadID, turnID string) error {
	var response codex.TurnInterruptResponse
	if err := a.client.Call(ctx, "turn/interrupt", map[string]any{
		"threadId": threadID,
		"turnId":   turnID,
	}, &response); err != nil {
		return err
	}
	a.broker.Publish("turn.interrupted", map[string]string{
		"threadId": threadID,
		"turnId":   turnID,
	})
	return nil
}

func (a *Agent) consumeNotifications(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case notification := <-a.client.Notifications():
			a.handleNotification(ctx, notification)
		}
	}
}

func (a *Agent) consumeServerRequests(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case request := <-a.client.ServerRequests():
			a.handleServerRequest(ctx, request)
		}
	}
}

func (a *Agent) consumeStderr() {
	for line := range a.client.StderrLines() {
		a.logger.Debug("codex app-server stderr", "line", line)
	}
}

func (a *Agent) refreshLoop(ctx context.Context) {
	ticker := time.NewTicker(a.cfg.RefreshInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := a.Refresh(ctx); err != nil {
				a.logger.Warn("periodic refresh failed", "error", err)
			}
		}
	}
}

func (a *Agent) fetchThreads(ctx context.Context) ([]codex.Thread, error) {
	var all []codex.Thread
	var cursor *string

	for {
		params := map[string]any{
			"useStateDbOnly": false,
		}
		if cursor != nil {
			params["cursor"] = *cursor
		}

		var response codex.ThreadListResponse
		if err := a.client.Call(ctx, "thread/list", params, &response); err != nil {
			return nil, err
		}

		all = append(all, response.Data...)
		if response.NextCursor == nil || *response.NextCursor == "" {
			break
		}
		cursor = response.NextCursor
	}

	return all, nil
}

func (a *Agent) fetchLoadedThreadIDs(ctx context.Context) ([]string, error) {
	var all []string
	var cursor *string

	for {
		params := map[string]any{}
		if cursor != nil {
			params["cursor"] = *cursor
		}

		var response codex.ThreadLoadedListResponse
		if err := a.client.Call(ctx, "thread/loaded/list", params, &response); err != nil {
			return nil, err
		}

		all = append(all, response.Data...)
		if response.NextCursor == nil || *response.NextCursor == "" {
			break
		}
		cursor = response.NextCursor
	}

	return all, nil
}

func (a *Agent) handleNotification(ctx context.Context, notification codex.Notification) {
	switch notification.Method {
	case "thread/started":
		var payload codex.ThreadStartedNotification
		if json.Unmarshal(notification.Params, &payload) == nil {
			a.store.UpsertThread(payload.Thread)
		}
	case "thread/status/changed":
		var payload codex.ThreadStatusChangedNotification
		if json.Unmarshal(notification.Params, &payload) == nil {
			a.store.UpdateThreadStatus(payload.ThreadID, payload.Status)
		}
	case "turn/started":
		var payload codex.TurnStartedNotification
		if json.Unmarshal(notification.Params, &payload) == nil {
			a.store.RecordTurn(payload.ThreadID, payload.Turn)
		}
	case "turn/completed":
		var payload codex.TurnCompletedNotification
		if json.Unmarshal(notification.Params, &payload) == nil {
			a.store.RecordTurn(payload.ThreadID, payload.Turn)
		}
	case "turn/diff/updated":
		var payload codex.TurnDiffUpdatedNotification
		if json.Unmarshal(notification.Params, &payload) == nil {
			a.store.RecordDiff(payload.ThreadID, payload.TurnID, payload.Diff)
		}
	case "turn/plan/updated":
		var payload codex.TurnPlanUpdatedNotification
		if json.Unmarshal(notification.Params, &payload) == nil {
			a.store.RecordPlan(payload)
		}
	case "thread/closed":
		_ = a.Refresh(ctx)
	}

	a.broker.Publish("codex.notification", map[string]any{
		"method": notification.Method,
		"params": json.RawMessage(notification.Params),
	})
}

func (a *Agent) handleServerRequest(ctx context.Context, request codex.ServerRequest) {
	var params map[string]any
	if err := json.Unmarshal(request.Params, &params); err != nil {
		a.logger.Warn("failed to decode server request params", "method", request.Method, "error", err)
		return
	}

	choices := deriveChoices(request.Method, params)
	pending := a.store.UpsertPending(request.Method, request.ID, params, choices)
	a.broker.Publish("approval.created", PendingRequestView{
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
}

func deriveChoices(method string, params map[string]any) []string {
	switch method {
	case "item/commandExecution/requestApproval":
		if raw, ok := params["availableDecisions"].([]any); ok && len(raw) > 0 {
			var choices []string
			for _, item := range raw {
				switch value := item.(type) {
				case string:
					choices = append(choices, value)
				case map[string]any:
					for key := range value {
						choices = append(choices, key)
					}
				}
			}
			if len(choices) > 0 {
				return choices
			}
		}
		return []string{"accept", "acceptForSession", "decline", "cancel"}
	case "item/fileChange/requestApproval":
		return []string{"accept", "acceptForSession", "decline", "cancel"}
	case "item/permissions/requestApproval":
		return []string{"session", "turn", "decline"}
	case "item/tool/requestUserInput":
		return []string{"answer"}
	default:
		return []string{"accept", "decline"}
	}
}

func emptyToNil(value string) any {
	if strings.TrimSpace(value) == "" {
		return nil
	}
	return value
}

func textInput(prompt string) map[string]any {
	return map[string]any{
		"type":          "text",
		"text":          prompt,
		"text_elements": []any{},
	}
}

func pendingCountForThread(pending []store.PendingRequest, threadID string) int {
	count := 0
	for _, item := range pending {
		if item.ThreadID == threadID {
			count++
		}
	}
	return count
}
