using System.Text.Json.Serialization;

namespace CodexFlowWindows.Data.Models;

public sealed record AgentEvent
{
    [JsonPropertyName("type")]
    public string Type { get; init; } = string.Empty;

    [JsonPropertyName("timestamp")]
    public string Timestamp { get; init; } = string.Empty;

    [JsonPropertyName("payload")]
    public JsonValue Payload { get; init; } = JsonValue.Null;
}
