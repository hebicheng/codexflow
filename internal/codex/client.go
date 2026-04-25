package codex

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
)

type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func (e *RPCError) Error() string {
	return fmt.Sprintf("json-rpc error %d: %s", e.Code, e.Message)
}

type responseEnvelope struct {
	Result json.RawMessage
	Err    *RPCError
}

type rpcEnvelope struct {
	JSONRPC string          `json:"jsonrpc,omitempty"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *RPCError       `json:"error,omitempty"`
}

type Client struct {
	binPath string
	logger  *slog.Logger

	cmd    *exec.Cmd
	stdin  io.WriteCloser
	writeM sync.Mutex

	pendingM sync.Mutex
	pending  map[string]chan responseEnvelope
	nextID   atomic.Int64

	notifications chan Notification
	serverReqs    chan ServerRequest
	stderrLines   chan string
}

func NewClient(binPath string, logger *slog.Logger) *Client {
	return &Client{
		binPath:       binPath,
		logger:        logger,
		pending:       make(map[string]chan responseEnvelope),
		notifications: make(chan Notification, 256),
		serverReqs:    make(chan ServerRequest, 128),
		stderrLines:   make(chan string, 64),
	}
}

func (c *Client) Start(ctx context.Context) error {
	if c.cmd != nil {
		return nil
	}

	cmd := exec.CommandContext(ctx, c.binPath, "app-server", "--listen", "stdio://")
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return fmt.Errorf("open stdout pipe: %w", err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		return fmt.Errorf("open stderr pipe: %w", err)
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("open stdin pipe: %w", err)
	}

	if err := cmd.Start(); err != nil {
		return fmt.Errorf("start codex app-server: %w", err)
	}

	c.cmd = cmd
	c.stdin = stdin

	go c.readLoop(stdout)
	go c.readStderr(stderr)
	go func() {
		if err := cmd.Wait(); err != nil {
			c.logger.Error("codex app-server exited", "error", err)
		} else {
			c.logger.Info("codex app-server exited")
		}
	}()

	var initResp InitializeResponse
	if err := c.Call(ctx, "initialize", map[string]any{
		"clientInfo": map[string]any{
			"name":    "CodexFlow Agent",
			"version": "0.1.0",
		},
		"capabilities": map[string]any{
			"experimentalApi": true,
		},
	}, &initResp); err != nil {
		return fmt.Errorf("initialize app-server: %w", err)
	}

	c.logger.Info("connected to codex app-server", "platform", initResp.PlatformOS, "userAgent", initResp.UserAgent)
	return nil
}

func (c *Client) Notifications() <-chan Notification {
	return c.notifications
}

func (c *Client) ServerRequests() <-chan ServerRequest {
	return c.serverReqs
}

func (c *Client) StderrLines() <-chan string {
	return c.stderrLines
}

func (c *Client) Call(ctx context.Context, method string, params any, result any) error {
	id := c.nextID.Add(1)
	key := strconv.FormatInt(id, 10)
	replyCh := make(chan responseEnvelope, 1)

	c.pendingM.Lock()
	c.pending[key] = replyCh
	c.pendingM.Unlock()

	defer func() {
		c.pendingM.Lock()
		delete(c.pending, key)
		c.pendingM.Unlock()
	}()

	payload := map[string]any{
		"jsonrpc": "2.0",
		"id":      id,
		"method":  method,
		"params":  params,
	}
	if err := c.writeJSON(payload); err != nil {
		return err
	}

	select {
	case <-ctx.Done():
		return ctx.Err()
	case reply := <-replyCh:
		if reply.Err != nil {
			return reply.Err
		}
		if result == nil || len(reply.Result) == 0 {
			return nil
		}
		if err := json.Unmarshal(reply.Result, result); err != nil {
			return fmt.Errorf("decode %s response: %w", method, err)
		}
		return nil
	}
}

func (c *Client) Reply(ctx context.Context, id json.RawMessage, result any) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	default:
	}

	return c.writeJSON(struct {
		JSONRPC string          `json:"jsonrpc"`
		ID      json.RawMessage `json:"id"`
		Result  any             `json:"result"`
	}{
		JSONRPC: "2.0",
		ID:      id,
		Result:  result,
	})
}

func (c *Client) writeJSON(value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return fmt.Errorf("marshal json-rpc payload: %w", err)
	}

	c.writeM.Lock()
	defer c.writeM.Unlock()

	if c.stdin == nil {
		return errors.New("codex app-server stdin is not ready")
	}

	if _, err := c.stdin.Write(append(data, '\n')); err != nil {
		return fmt.Errorf("write json-rpc payload: %w", err)
	}
	return nil
}

func (c *Client) readLoop(reader io.Reader) {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 1024*1024), 16*1024*1024)

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}

		var envelope rpcEnvelope
		if err := json.Unmarshal([]byte(line), &envelope); err != nil {
			c.logger.Warn("failed to decode app-server message", "error", err, "payload", line)
			continue
		}

		switch {
		case envelope.Method != "" && len(envelope.ID) > 0:
			c.serverReqs <- ServerRequest{ID: envelope.ID, Method: envelope.Method, Params: envelope.Params}
		case envelope.Method != "":
			c.notifications <- Notification{Method: envelope.Method, Params: envelope.Params}
		case len(envelope.ID) > 0:
			c.dispatchResponse(envelope)
		}
	}

	if err := scanner.Err(); err != nil {
		c.logger.Error("app-server stdout reader failed", "error", err)
	}
}

func (c *Client) readStderr(reader io.Reader) {
	scanner := bufio.NewScanner(reader)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		select {
		case c.stderrLines <- line:
		default:
		}
	}
}

func (c *Client) dispatchResponse(envelope rpcEnvelope) {
	key := normalizeID(envelope.ID)

	c.pendingM.Lock()
	replyCh, ok := c.pending[key]
	c.pendingM.Unlock()
	if !ok {
		return
	}

	replyCh <- responseEnvelope{Result: envelope.Result, Err: envelope.Error}
}

func normalizeID(raw json.RawMessage) string {
	var numeric int64
	if err := json.Unmarshal(raw, &numeric); err == nil {
		return strconv.FormatInt(numeric, 10)
	}

	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return text
	}

	return string(raw)
}
