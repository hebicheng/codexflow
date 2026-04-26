package runtime

import (
	"testing"

	"codexflow/internal/codex"
)

func TestDetectClaudeServiceName(t *testing.T) {
	apps := []codex.AppInfo{
		{
			ID:           "codex.default",
			Name:         "Codex",
			IsAccessible: true,
			IsEnabled:    true,
		},
		{
			ID:           "com.anthropic.claude-code",
			Name:         "Claude Code",
			IsAccessible: true,
			IsEnabled:    true,
		},
	}

	got := detectClaudeServiceName(apps)
	if got != "com.anthropic.claude-code" {
		t.Fatalf("detectClaudeServiceName() = %q, want %q", got, "com.anthropic.claude-code")
	}
}

func TestDetectClaudeServiceNameAnthropicAlias(t *testing.T) {
	apps := []codex.AppInfo{
		{
			ID:                 "provider.anthropic.agent",
			Name:               "Anthropic Agent",
			IsAccessible:       true,
			IsEnabled:          false,
			PluginDisplayNames: []string{"Claude Code"},
			Labels:             map[string]string{"vendor": "Anthropic"},
		},
	}

	got := detectClaudeServiceName(apps)
	if got != "provider.anthropic.agent" {
		t.Fatalf("detectClaudeServiceName() = %q, want %q", got, "provider.anthropic.agent")
	}
}

func TestResolveAgentForStart(t *testing.T) {
	agent := &Agent{
		availableAgents: []AgentOption{
			{
				ID: "codex", Name: "Codex", Available: true, Default: true,
				Capabilities: AgentCapabilities{SupportsInterruptTurn: true, SupportsApprovals: true, SupportsArchive: true, SupportsResume: true},
			},
			{
				ID: "claude", Name: "Claude Code", Available: true,
				Capabilities: AgentCapabilities{SupportsInterruptTurn: true, SupportsApprovals: true, SupportsArchive: true, SupportsResume: true, SupportsHistoryImport: true},
			},
		},
		defaultAgentID: "codex",
		serviceByAgent: map[string]string{
			"codex":  "",
			"claude": "com.anthropic.claude-code",
		},
	}

	_, serviceName, err := agent.resolveAgentForStart("claude")
	if err != nil {
		t.Fatalf("resolveAgentForStart(\"claude\") error = %v", err)
	}
	if serviceName != "com.anthropic.claude-code" {
		t.Fatalf("serviceName = %q, want %q", serviceName, "com.anthropic.claude-code")
	}

	_, serviceName, err = agent.resolveAgentForStart("")
	if err != nil {
		t.Fatalf("resolveAgentForStart(\"\") error = %v", err)
	}
	if serviceName != "" {
		t.Fatalf("default codex serviceName = %q, want empty", serviceName)
	}
}
