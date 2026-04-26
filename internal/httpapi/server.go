package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"codexflow/internal/runtime"
)

type Server struct {
	agent   *runtime.Agent
	logger  *slog.Logger
	mux     *http.ServeMux
	uploads *imageUploadStore
}

func NewServer(agent *runtime.Agent, logger *slog.Logger) *Server {
	server := &Server{
		agent:   agent,
		logger:  logger,
		mux:     http.NewServeMux(),
		uploads: newImageUploadStore(),
	}
	server.routes()
	return server
}

func (s *Server) Handler() http.Handler {
	return s.withLogging(s.withCORS(s.mux))
}

func (s *Server) routes() {
	s.mux.HandleFunc("/healthz", s.handleHealth)
	s.mux.HandleFunc("/api/v1/dashboard", s.handleDashboard)
	s.mux.HandleFunc("/api/v1/events", s.handleEvents)
	s.mux.HandleFunc("/api/v1/sessions", s.handleSessions)
	s.mux.HandleFunc("/api/v1/sessions/", s.handleSessionByID)
	s.mux.HandleFunc("/api/v1/approvals", s.handleApprovals)
	s.mux.HandleFunc("/api/v1/approvals/", s.handleApprovalByID)
	s.mux.HandleFunc("/api/v1/uploads/image", s.handleImageUpload)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":        true,
		"timestamp": time.Now(),
	})
}

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, s.agent.Dashboard())
}

func (s *Server) handleSessions(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, map[string]any{
			"data": s.agent.ListSessions(),
		})
	case http.MethodPost:
		var request struct {
			Action string `json:"action"`
			CWD    string `json:"cwd"`
			Prompt string `json:"prompt"`
			Agent  string `json:"agent"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()

		switch request.Action {
		case "refresh":
			if err := s.agent.Refresh(ctx); err != nil {
				writeError(w, http.StatusBadGateway, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		case "start":
			cwd := normalizeCWD(request.CWD)
			prompt := strings.TrimSpace(request.Prompt)

			if cwd == "" {
				writeErrorMessage(w, http.StatusBadRequest, "working directory is required")
				return
			}
			if !filepath.IsAbs(cwd) {
				writeErrorMessage(w, http.StatusBadRequest, "working directory must be an absolute path")
				return
			}
			if prompt == "" {
				writeErrorMessage(w, http.StatusBadRequest, "first prompt is required to materialize a managed session")
				return
			}
			session, err := s.agent.StartSession(ctx, cwd, prompt, request.Agent)
			if err != nil {
				writeError(w, http.StatusBadGateway, err)
				return
			}
			writeJSON(w, http.StatusCreated, session)
		default:
			writeErrorMessage(w, http.StatusBadRequest, "unsupported sessions action")
		}
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) handleSessionByID(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/sessions/")
	if path == "" {
		writeErrorMessage(w, http.StatusNotFound, "session not found")
		return
	}

	parts := strings.Split(strings.Trim(path, "/"), "/")
	sessionID := parts[0]

	if len(parts) == 1 {
		if r.Method != http.MethodGet {
			methodNotAllowed(w)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()

		detail, err := s.agent.SessionDetail(ctx, sessionID)
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, detail)
		return
	}

	action := strings.Join(parts[1:], "/")
	switch action {
	case "resume":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()
		session, err := s.agent.ResumeSession(ctx, sessionID)
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, session)
	case "end":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()
		if err := s.agent.EndSession(ctx, sessionID); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	case "archive":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()
		if err := s.agent.ArchiveSession(ctx, sessionID); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	case "turns/start":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		var request struct {
			Prompt string `json:"prompt"`
			Inputs []struct {
				Type     string `json:"type"`
				Text     string `json:"text"`
				UploadID string `json:"uploadId"`
			} `json:"inputs"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		input, err := s.buildTurnInput(request.Prompt, request.Inputs)
		if err != nil {
			writeErrorMessage(w, http.StatusBadRequest, err.Error())
			return
		}
		turn, err := s.agent.StartTurn(ctx, sessionID, input)
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusCreated, turn)
	case "turns/steer":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		var request struct {
			TurnID string `json:"turnId"`
			Prompt string `json:"prompt"`
			Inputs []struct {
				Type     string `json:"type"`
				Text     string `json:"text"`
				UploadID string `json:"uploadId"`
			} `json:"inputs"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		input, err := s.buildTurnInput(request.Prompt, request.Inputs)
		if err != nil {
			writeErrorMessage(w, http.StatusBadRequest, err.Error())
			return
		}
		if err := s.agent.SteerTurn(ctx, sessionID, request.TurnID, input); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	case "turns/interrupt":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		var request struct {
			TurnID string `json:"turnId"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
		defer cancel()
		if err := s.agent.InterruptTurn(ctx, sessionID, request.TurnID); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	default:
		writeErrorMessage(w, http.StatusNotFound, fmt.Sprintf("unsupported session action %q", action))
	}
}

func (s *Server) handleApprovals(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"data": s.agent.PendingRequests(),
	})
}

func (s *Server) handleApprovalByID(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}

	path := strings.TrimPrefix(r.URL.Path, "/api/v1/approvals/")
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) != 2 || parts[1] != "resolve" {
		writeErrorMessage(w, http.StatusNotFound, "approval endpoint not found")
		return
	}

	var request struct {
		Result json.RawMessage `json:"result"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	if err := s.agent.ResolveRequest(ctx, parts[0], request.Result); err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErrorMessage(w, http.StatusInternalServerError, "streaming is not supported")
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	subscription := s.agent.Subscribe()
	defer s.agent.Unsubscribe(subscription)

	ticker := time.NewTicker(20 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-r.Context().Done():
			return
		case event := <-subscription:
			data, _ := json.Marshal(event)
			_, _ = fmt.Fprintf(w, "event: %s\n", event.Type)
			_, _ = fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		case <-ticker.C:
			_, _ = fmt.Fprint(w, ": ping\n\n")
			flusher.Flush()
		}
	}
}

func (s *Server) handleImageUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	if err := r.ParseMultipartForm(maxUploadImageBytes + (1 * 1024 * 1024)); err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "invalid multipart form payload")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "missing image file in multipart field 'file'")
		return
	}
	defer file.Close()

	payload, err := io.ReadAll(io.LimitReader(file, maxUploadImageBytes+1))
	if err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "failed to read uploaded image")
		return
	}
	if len(payload) == 0 {
		writeErrorMessage(w, http.StatusBadRequest, "uploaded image is empty")
		return
	}
	if len(payload) > maxUploadImageBytes {
		writeErrorMessage(w, http.StatusBadRequest, "image exceeds 15MB size limit")
		return
	}
	if !strings.HasPrefix(http.DetectContentType(payload), "image/") {
		writeErrorMessage(w, http.StatusBadRequest, "uploaded file must be an image")
		return
	}

	name := strings.TrimSpace(header.Filename)
	if name == "" {
		name = "upload-image"
	}
	item, err := s.uploads.Save(name, payload)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"id":   item.ID,
		"name": item.Name,
		"size": item.Size,
	})
}

func (s *Server) buildTurnInput(
	legacyPrompt string,
	inputs []struct {
		Type     string `json:"type"`
		Text     string `json:"text"`
		UploadID string `json:"uploadId"`
	},
) ([]map[string]any, error) {
	if len(inputs) == 0 {
		prompt := strings.TrimSpace(legacyPrompt)
		if prompt == "" {
			return nil, fmt.Errorf("prompt or inputs is required")
		}
		return []map[string]any{composeTextInput(prompt)}, nil
	}

	result := make([]map[string]any, 0, len(inputs))
	for _, input := range inputs {
		switch strings.TrimSpace(input.Type) {
		case "text":
			text := strings.TrimSpace(input.Text)
			if text == "" {
				return nil, fmt.Errorf("text input cannot be empty")
			}
			result = append(result, composeTextInput(text))
		case "image":
			path, err := s.uploads.Resolve(input.UploadID)
			if err != nil {
				return nil, err
			}
			result = append(result, map[string]any{
				"type": "localImage",
				"path": path,
			})
		default:
			return nil, fmt.Errorf("unsupported input type %q", input.Type)
		}
	}
	return result, nil
}

func composeTextInput(prompt string) map[string]any {
	return map[string]any{
		"type":          "text",
		"text":          prompt,
		"text_elements": []any{},
	}
}

func (s *Server) withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		s.logger.Info("http request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
	})
}

func (s *Server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if origin != "" && isAllowedOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, Cache-Control")
			w.Header().Set("Access-Control-Expose-Headers", "Content-Type")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func methodNotAllowed(w http.ResponseWriter) {
	writeErrorMessage(w, http.StatusMethodNotAllowed, "method not allowed")
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target interface{}) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(target); err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "invalid json body")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeErrorMessage(w, status, err.Error())
}

func writeErrorMessage(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{
		"error": message,
	})
}

func normalizeCWD(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}

	if trimmed == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			return home
		}
		return trimmed
	}

	if strings.HasPrefix(trimmed, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(trimmed, "~/"))
		}
	}

	return trimmed
}

func isAllowedOrigin(origin string) bool {
	override := strings.TrimSpace(os.Getenv("CODEXFLOW_ALLOWED_ORIGINS"))
	if override != "" {
		return matchesAllowedOrigins(origin, override)
	}

	return strings.HasPrefix(origin, "http://localhost:") ||
		strings.HasPrefix(origin, "http://127.0.0.1:") ||
		strings.HasPrefix(origin, "http://[::1]:") ||
		strings.HasPrefix(origin, "https://localhost:") ||
		strings.HasPrefix(origin, "https://127.0.0.1:") ||
		strings.HasPrefix(origin, "https://[::1]:") ||
		strings.HasPrefix(origin, "chrome-extension://")
}

func matchesAllowedOrigins(origin, raw string) bool {
	for _, entry := range strings.Split(raw, ",") {
		pattern := strings.TrimSpace(entry)
		if pattern == "" {
			continue
		}
		if pattern == "*" || pattern == origin {
			return true
		}
		if strings.HasSuffix(pattern, "*") {
			prefix := strings.TrimSuffix(pattern, "*")
			if strings.HasPrefix(origin, prefix) {
				return true
			}
		}
	}
	return false
}
