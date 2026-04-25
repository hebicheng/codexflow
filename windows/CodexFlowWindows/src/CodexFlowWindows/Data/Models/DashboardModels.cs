using System.Text.Json.Serialization;

namespace CodexFlowWindows.Data.Models;

public sealed record DashboardResponse
{
    [JsonPropertyName("agent")]
    public AgentSnapshot Agent { get; init; } = new();

    [JsonPropertyName("stats")]
    public DashboardStats Stats { get; init; } = new();

    [JsonPropertyName("sessions")]
    public IReadOnlyList<SessionSummary> Sessions { get; init; } = Array.Empty<SessionSummary>();

    [JsonPropertyName("approvals")]
    public IReadOnlyList<PendingRequestView> Approvals { get; init; } = Array.Empty<PendingRequestView>();

    public static DashboardResponse Empty { get; } = new();
}

public sealed record AgentSnapshot
{
    [JsonPropertyName("connected")]
    public bool Connected { get; init; }

    [JsonPropertyName("startedAt")]
    public string StartedAt { get; init; } = string.Empty;

    [JsonPropertyName("listenAddr")]
    public string ListenAddr { get; init; } = string.Empty;

    [JsonPropertyName("codexBinaryPath")]
    public string CodexBinaryPath { get; init; } = string.Empty;
}

public sealed record DashboardStats
{
    [JsonPropertyName("totalSessions")]
    public int TotalSessions { get; init; }

    [JsonPropertyName("loadedSessions")]
    public int LoadedSessions { get; init; }

    [JsonPropertyName("activeSessions")]
    public int ActiveSessions { get; init; }

    [JsonPropertyName("pendingApprovals")]
    public int PendingApprovals { get; init; }
}

public sealed record HealthResponse
{
    [JsonPropertyName("ok")]
    public bool Ok { get; init; }

    [JsonPropertyName("timestamp")]
    public string Timestamp { get; init; } = string.Empty;
}

public sealed record OkResponse
{
    [JsonPropertyName("ok")]
    public bool Ok { get; init; }
}
