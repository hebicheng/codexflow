package runtime

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"strings"
	"sync"
	"time"

	"codexflow/internal/codex"
	"codexflow/internal/config"
	"codexflow/internal/store"
)

type Agent struct {
	cfg       config.Config
	logger    *slog.Logger
	client    *codex.Client
	store     *store.Store
	broker    *Broker
	started   time.Time
	runCtx    context.Context
	runCancel context.CancelFunc

	agentsMu        sync.RWMutex
	availableAgents []AgentOption
	defaultAgentID  string
	serviceByAgent  map[string]string

	claudeSessionsMu sync.Mutex
	claudeSessions   map[string]*claudeSDKSession
	claudeTurnsMu    sync.Mutex
	claudeRunning    map[string]runningClaudeTurn
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

	defaultAgents, defaultServiceMap, defaultAgentID := defaultAgentCatalog()

	return &Agent{
		cfg:             cfg,
		logger:          logger,
		client:          codex.NewClient(cfg.CodexPath, logger),
		store:           sessionStore,
		broker:          NewBroker(),
		started:         time.Now(),
		runCtx:          context.Background(),
		availableAgents: defaultAgents,
		defaultAgentID:  defaultAgentID,
		serviceByAgent:  defaultServiceMap,
		claudeSessions:  make(map[string]*claudeSDKSession),
		claudeRunning:   make(map[string]runningClaudeTurn),
	}
}

func (a *Agent) Start(ctx context.Context) error {
	if err := a.client.Start(ctx); err != nil {
		return err
	}

	a.runCtx, a.runCancel = context.WithCancel(context.Background())
	go func() {
		<-ctx.Done()
		if a.runCancel != nil {
			a.runCancel()
		}
	}()

	a.refreshAgentCatalog(ctx, true)
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
		Agents:       a.agentOptions(),
		DefaultAgent: a.defaultAgent(),
		Stats:        stats,
		Sessions:     summaries,
		Approvals:    approvals,
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
	if isClaudeThreadID(threadID) {
		return a.claudeSessionDetail(threadID)
	}

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

	if request.Method == "item/tool/requestUserInput" && len(request.RawRPCRequestID) == 0 {
		threadID := strings.TrimSpace(request.ThreadID)
		if isClaudeThreadID(threadID) {
			answers, err := decodeClaudeAnswers(result)
			if err != nil {
				return err
			}
			session, ok := a.getClaudeSession(threadID)
			if !ok {
				record, recordOK := a.store.SnapshotSession(threadID)
				if !recordOK {
					return errors.New("claude session not found")
				}
				session, err = a.getOrCreateClaudeManagedSession(ctx, threadID, strings.TrimSpace(record.Thread.CWD))
				if err != nil {
					return err
				}
			}
			if err := session.submitQuestionAnswer(requestID, answers); err != nil {
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
	}
	if (request.Method == "item/commandExecution/requestApproval" || request.Method == "item/fileChange/requestApproval") && len(request.RawRPCRequestID) == 0 {
		threadID := strings.TrimSpace(request.ThreadID)
		if isClaudeThreadID(threadID) {
			decision, err := decodeClaudePermissionDecision(result)
			if err != nil {
				return err
			}
			session, ok := a.getClaudeSession(threadID)
			if !ok {
				record, recordOK := a.store.SnapshotSession(threadID)
				if !recordOK {
					return errors.New("claude session not found")
				}
				session, err = a.getOrCreateClaudeManagedSession(ctx, threadID, strings.TrimSpace(record.Thread.CWD))
				if err != nil {
					return err
				}
			}
			if err := session.submitApprovalDecision(requestID, decision); err != nil {
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
	a.refreshAgentCatalog(ctx, false)

	threads, err := a.fetchThreads(ctx)
	if err != nil {
		return err
	}

	loadedIDs, err := a.fetchLoadedThreadIDs(ctx)
	if err != nil {
		return err
	}

	claudeThreads, err := a.fetchClaudeThreads()
	if err != nil {
		a.logger.Debug("failed to discover claude sessions", "error", err)
	} else if len(claudeThreads) > 0 {
		managedClaudeIDs := make(map[string]struct{})
		for _, threadID := range a.store.ManagedSessionIDs() {
			if isClaudeThreadID(threadID) {
				managedClaudeIDs[threadID] = struct{}{}
			}
		}
		filteredClaudeThreads := make([]codex.Thread, 0, len(claudeThreads))
		for idx := range claudeThreads {
			if _, managed := managedClaudeIDs[claudeThreads[idx].ID]; managed {
				continue
			}
			existing, ok := a.store.SnapshotSession(claudeThreads[idx].ID)
			if !ok {
				filteredClaudeThreads = append(filteredClaudeThreads, claudeThreads[idx])
				continue
			}
			if len(existing.Thread.Turns) > 0 {
				claudeThreads[idx].Turns = existing.Thread.Turns
			}
			if existing.Thread.UpdatedAt > claudeThreads[idx].UpdatedAt {
				claudeThreads[idx].UpdatedAt = existing.Thread.UpdatedAt
			}
			if strings.TrimSpace(existing.Thread.Preview) != "" {
				claudeThreads[idx].Preview = existing.Thread.Preview
			}
			filteredClaudeThreads = append(filteredClaudeThreads, claudeThreads[idx])
		}
		threads = append(threads, filteredClaudeThreads...)
	}

	// Keep locally managed Claude sessions even when history.jsonl/transcript
	// is temporarily missing or delayed, otherwise a just-created/taken-over
	// session can disappear after dashboard refresh.
	existingByID := make(map[string]store.SessionRecord)
	for _, record := range a.store.SnapshotSessions() {
		existingByID[record.Thread.ID] = record
	}
	present := make(map[string]struct{}, len(threads))
	for _, thread := range threads {
		present[thread.ID] = struct{}{}
	}
	for _, threadID := range a.store.ManagedSessionIDs() {
		if !isClaudeThreadID(threadID) {
			continue
		}
		if _, ok := present[threadID]; ok {
			continue
		}
		record, ok := existingByID[threadID]
		if !ok {
			continue
		}
		threads = append(threads, record.Thread)
		present[threadID] = struct{}{}
	}

	loaded := make(map[string]bool, len(loadedIDs))
	for _, id := range loadedIDs {
		loaded[id] = true
	}
	for _, threadID := range a.store.ManagedSessionIDs() {
		if isClaudeThreadID(threadID) {
			loaded[threadID] = true
		}
	}

	for idx := range threads {
		threadID := strings.TrimSpace(threads[idx].ID)
		if threadID == "" || isClaudeThreadID(threadID) {
			continue
		}
		if !(loaded[threadID] || a.store.HasLocalSessionState(threadID)) {
			continue
		}
		readCtx, cancel := context.WithTimeout(ctx, 6*time.Second)
		var detail codex.ThreadReadResponse
		err := a.client.Call(readCtx, "thread/read", map[string]any{
			"threadId":     threadID,
			"includeTurns": true,
		}, &detail)
		cancel()
		if err != nil {
			if strings.Contains(err.Error(), "includeTurns is unavailable before first user message") {
				continue
			}
			a.logger.Debug("failed to hydrate thread turns during refresh", "threadId", threadID, "error", err)
			continue
		}
		threads[idx] = detail.Thread
	}

	a.store.ReplaceSessions(threads, loaded)
	a.broker.Publish("sessions.refreshed", a.ListSessions())
	return nil
}

func (a *Agent) StartSession(ctx context.Context, cwd, prompt, requestedAgentID string) (SessionSummary, error) {
	agentID, serviceName, err := a.resolveAgentForStart(requestedAgentID)
	if err != nil {
		return SessionSummary{}, err
	}
	if agentID == "claude" {
		return a.startClaudeSession(ctx, cwd, prompt)
	}

	params := map[string]any{
		"cwd":                    emptyToNil(cwd),
		"experimentalRawEvents":  true,
		"persistExtendedHistory": true,
	}
	if serviceName != "" {
		params["serviceName"] = serviceName
	}

	var threadResp codex.ThreadStartResponse
	if err := a.client.Call(ctx, "thread/start", params, &threadResp); err != nil {
		return SessionSummary{}, err
	}

	a.store.UpsertThread(threadResp.Thread)
	a.store.SetSessionEnded(threadResp.Thread.ID, false)
	a.store.SetSessionManaged(threadResp.Thread.ID, true)
	a.store.SetSessionLoaded(threadResp.Thread.ID, true)

	if strings.TrimSpace(prompt) != "" {
		if _, err := a.StartTurnWithPrompt(ctx, threadResp.Thread.ID, prompt); err != nil {
			return SessionSummary{}, err
		}
	}

	record, _ := a.store.SnapshotSession(threadResp.Thread.ID)
	summary := toSessionSummary(record, 0)
	a.broker.Publish("session.created", summary)
	return summary, nil
}

func (a *Agent) ResumeSession(ctx context.Context, threadID string) (SessionSummary, error) {
	if isClaudeThreadID(threadID) {
		return a.resumeClaudeSession(ctx, threadID)
	}

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
	if isClaudeThreadID(threadID) {
		return a.endClaudeSession(ctx, threadID)
	}

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
	if isClaudeThreadID(threadID) {
		return a.archiveClaudeSession(threadID)
	}

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

func (a *Agent) StartTurnWithPrompt(ctx context.Context, threadID, prompt string) (TurnDetail, error) {
	return a.StartTurn(ctx, threadID, []map[string]any{textInput(prompt)})
}

func (a *Agent) StartTurn(ctx context.Context, threadID string, input []map[string]any) (TurnDetail, error) {
	if len(input) == 0 {
		return TurnDetail{}, errors.New("turn input is required")
	}
	if isClaudeThreadID(threadID) {
		return a.startClaudeTurn(ctx, threadID, input)
	}

	var response codex.TurnStartResponse
	if err := a.client.Call(ctx, "turn/start", map[string]any{
		"threadId": threadID,
		"input":    input,
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

func (a *Agent) SteerTurnWithPrompt(ctx context.Context, threadID, turnID, prompt string) error {
	return a.SteerTurn(ctx, threadID, turnID, []map[string]any{textInput(prompt)})
}

func (a *Agent) SteerTurn(ctx context.Context, threadID, turnID string, input []map[string]any) error {
	if len(input) == 0 {
		return errors.New("turn input is required")
	}
	if isClaudeThreadID(threadID) {
		if running, ok := a.getRunningClaudeTurn(threadID); ok {
			previousTurnID := running.TurnID
			running.Cancel()
			if err := a.waitForClaudeTurnClear(ctx, threadID, previousTurnID); err != nil {
				return err
			}
		}
		_, err := a.startClaudeTurn(ctx, threadID, input)
		return err
	}

	var response codex.TurnSteerResponse
	if err := a.client.Call(ctx, "turn/steer", map[string]any{
		"threadId":       threadID,
		"expectedTurnId": turnID,
		"input":          input,
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
	if isClaudeThreadID(threadID) {
		running, ok := a.getRunningClaudeTurn(threadID)
		if !ok {
			return errors.New("no running claude turn")
		}
		if strings.TrimSpace(turnID) != "" && running.TurnID != strings.TrimSpace(turnID) {
			return errors.New("turn is not running")
		}
		running.Cancel()
		if err := a.waitForClaudeTurnClear(ctx, threadID, running.TurnID); err != nil {
			a.logger.Warn("claude turn did not clear after interrupt; forcing local stop", "threadId", threadID, "turnId", running.TurnID, "error", err)
			a.forceStopClaudeTurn(threadID, running.TurnID, "interrupted by user")
		}
		a.broker.Publish("turn.interrupted", map[string]string{
			"threadId": threadID,
			"turnId":   running.TurnID,
		})
		return nil
	}

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

func decodeClaudeAnswers(result json.RawMessage) (map[string]string, error) {
	if len(result) == 0 {
		return nil, errors.New("answers required")
	}

	var payload map[string]any
	if err := json.Unmarshal(result, &payload); err != nil {
		return nil, fmt.Errorf("decode claude answers: %w", err)
	}

	rawAnswers, ok := payload["answers"].(map[string]any)
	if !ok || len(rawAnswers) == 0 {
		return nil, errors.New("answers required")
	}

	answers := make(map[string]string)
	for key, value := range rawAnswers {
		answerObject, ok := value.(map[string]any)
		if !ok {
			continue
		}
		rawList, ok := answerObject["answers"].([]any)
		if !ok || len(rawList) == 0 {
			continue
		}
		first, _ := rawList[0].(string)
		first = strings.TrimSpace(first)
		if first == "" {
			continue
		}
		answers[strings.TrimSpace(key)] = first
	}

	if len(answers) == 0 {
		return nil, errors.New("answers required")
	}
	return answers, nil
}

func decodeClaudePermissionDecision(result json.RawMessage) (claudePermissionDecision, error) {
	if len(result) == 0 {
		return claudePermissionDecision{}, errors.New("decision required")
	}

	var payload map[string]any
	if err := json.Unmarshal(result, &payload); err != nil {
		return claudePermissionDecision{}, fmt.Errorf("decode claude permission decision: %w", err)
	}

	rawDecision, ok := payload["decision"].(string)
	if !ok {
		return claudePermissionDecision{}, errors.New("decision required")
	}

	switch strings.TrimSpace(rawDecision) {
	case "accept", "acceptForSession":
		return claudePermissionDecision{Allow: true}, nil
	case "decline", "cancel":
		return claudePermissionDecision{Allow: false, Reason: rawDecision}, nil
	default:
		return claudePermissionDecision{}, fmt.Errorf("unsupported decision %q", rawDecision)
	}
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

func defaultAgentCatalog() ([]AgentOption, map[string]string, string) {
	return []AgentOption{
			{
				ID:        "codex",
				Name:      "Codex",
				Available: true,
				Default:   true,
				Capabilities: AgentCapabilities{
					SupportsInterruptTurn: true,
					SupportsApprovals:     true,
					SupportsArchive:       true,
					SupportsResume:        true,
					SupportsHistoryImport: false,
				},
			},
			{
				ID:        "claude",
				Name:      "Claude Code",
				Available: false,
				Default:   false,
				Capabilities: AgentCapabilities{
					SupportsInterruptTurn: true,
					SupportsApprovals:     true,
					SupportsArchive:       true,
					SupportsResume:        true,
					SupportsHistoryImport: true,
				},
			},
		}, map[string]string{
			"codex": "",
		}, "codex"
}

func (a *Agent) refreshAgentCatalog(ctx context.Context, withImport bool) {
	agents, serviceMap, defaultAgentID := defaultAgentCatalog()
	claudeAvailable := a.detectClaudeCLI(ctx)

	if withImport {
		a.importExternalAgentConfig(ctx)
	}

	for idx := range agents {
		if agents[idx].ID == "claude" {
			agents[idx].Available = claudeAvailable
			break
		}
	}

	a.setAgentCatalog(agents, serviceMap, defaultAgentID)
}

func (a *Agent) importExternalAgentConfig(ctx context.Context) {
	params := map[string]any{
		"includeHome": true,
	}

	var detectResp codex.ExternalAgentConfigDetectResponse
	if err := a.client.Call(ctx, "externalAgentConfig/detect", params, &detectResp); err != nil {
		a.logger.Debug("external agent config detect failed", "error", err)
		return
	}

	if len(detectResp.Items) == 0 {
		return
	}

	var importResp codex.ExternalAgentConfigImportResponse
	if err := a.client.Call(ctx, "externalAgentConfig/import", map[string]any{
		"migrationItems": detectResp.Items,
	}, &importResp); err != nil {
		a.logger.Debug("external agent config import failed", "error", err)
	}
}

func (a *Agent) fetchApps(ctx context.Context) ([]codex.AppInfo, error) {
	var apps []codex.AppInfo
	var cursor *string

	for {
		params := map[string]any{
			"limit": 100,
		}
		if cursor != nil && *cursor != "" {
			params["cursor"] = *cursor
		}

		var response codex.AppsListResponse
		if err := a.client.Call(ctx, "app/list", params, &response); err != nil {
			return nil, err
		}
		apps = append(apps, response.Data...)

		if response.NextCursor == nil || *response.NextCursor == "" {
			return apps, nil
		}
		cursor = response.NextCursor
	}
}

func detectClaudeServiceName(apps []codex.AppInfo) string {
	keywords := []string{"claude", "anthropic"}

	for _, app := range apps {
		if !app.IsAccessible {
			continue
		}

		candidates := []string{
			strings.ToLower(strings.TrimSpace(app.ID)),
			strings.ToLower(strings.TrimSpace(app.Name)),
		}
		if app.DistributionChannel != nil {
			candidates = append(candidates, strings.ToLower(strings.TrimSpace(*app.DistributionChannel)))
		}
		for _, name := range app.PluginDisplayNames {
			candidates = append(candidates, strings.ToLower(strings.TrimSpace(name)))
		}
		for _, value := range app.Labels {
			candidates = append(candidates, strings.ToLower(strings.TrimSpace(value)))
		}

		if containsAnyKeyword(candidates, keywords) {
			return app.ID
		}
	}
	return ""
}

func containsAnyKeyword(candidates []string, keywords []string) bool {
	for _, candidate := range candidates {
		if candidate == "" {
			continue
		}
		for _, keyword := range keywords {
			if strings.Contains(candidate, keyword) {
				return true
			}
		}
	}
	return false
}

func (a *Agent) setAgentCatalog(options []AgentOption, serviceByAgent map[string]string, defaultAgentID string) {
	a.agentsMu.Lock()
	defer a.agentsMu.Unlock()

	a.availableAgents = options
	a.serviceByAgent = serviceByAgent
	a.defaultAgentID = defaultAgentID
}

func (a *Agent) agentOptions() []AgentOption {
	a.agentsMu.RLock()
	defer a.agentsMu.RUnlock()
	return slices.Clone(a.availableAgents)
}

func (a *Agent) defaultAgent() string {
	a.agentsMu.RLock()
	defer a.agentsMu.RUnlock()
	return a.defaultAgentID
}

func (a *Agent) resolveAgentForStart(requestedAgentID string) (string, string, error) {
	a.agentsMu.RLock()
	defer a.agentsMu.RUnlock()

	agentID := strings.TrimSpace(strings.ToLower(requestedAgentID))
	if agentID == "" {
		agentID = a.defaultAgentID
	}

	for _, option := range a.availableAgents {
		if option.ID != agentID {
			continue
		}
		if !option.Available {
			return "", "", fmt.Errorf("agent %s is unavailable", option.Name)
		}
		return agentID, a.serviceByAgent[agentID], nil
	}

	return "", "", fmt.Errorf("unsupported agent: %s", requestedAgentID)
}
