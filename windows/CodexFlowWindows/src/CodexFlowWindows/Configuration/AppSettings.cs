using System.Text.Json.Serialization;

namespace CodexFlowWindows.Configuration;

public sealed record AppSettings
{
    public const string DefaultAgentBaseUrl = "http://127.0.0.1:4318";

    [JsonPropertyName("agentBaseUrl")]
    public string AgentBaseUrl { get; init; } = DefaultAgentBaseUrl;

    [JsonPropertyName("windowWidth")]
    public double WindowWidth { get; init; } = 1280;

    [JsonPropertyName("windowHeight")]
    public double WindowHeight { get; init; } = 820;

    [JsonPropertyName("lastSelectedSessionId")]
    public string LastSelectedSessionId { get; init; } = string.Empty;

    public AppSettings WithBaseUrl(string baseUrl) =>
        this with { AgentBaseUrl = string.IsNullOrWhiteSpace(baseUrl) ? DefaultAgentBaseUrl : baseUrl.Trim() };
}
