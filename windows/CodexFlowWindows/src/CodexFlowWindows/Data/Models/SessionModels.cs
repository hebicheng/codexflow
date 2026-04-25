using System.Globalization;
using System.Text.Json.Serialization;

namespace CodexFlowWindows.Data.Models;

public sealed record SessionListEnvelope
{
    [JsonPropertyName("data")]
    public IReadOnlyList<SessionSummary> Data { get; init; } = Array.Empty<SessionSummary>();
}

public sealed record SessionSummary
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;

    [JsonPropertyName("name")]
    public string Name { get; init; } = string.Empty;

    [JsonPropertyName("preview")]
    public string Preview { get; init; } = string.Empty;

    [JsonPropertyName("cwd")]
    public string Cwd { get; init; } = string.Empty;

    [JsonPropertyName("source")]
    public string Source { get; init; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; init; } = string.Empty;

    [JsonPropertyName("activeFlags")]
    public IReadOnlyList<string> ActiveFlags { get; init; } = Array.Empty<string>();

    [JsonPropertyName("loaded")]
    public bool Loaded { get; init; }

    [JsonPropertyName("updatedAt")]
    public long UpdatedAt { get; init; }

    [JsonPropertyName("createdAt")]
    public long CreatedAt { get; init; }

    [JsonPropertyName("modelProvider")]
    public string ModelProvider { get; init; } = string.Empty;

    [JsonPropertyName("branch")]
    public string Branch { get; init; } = string.Empty;

    [JsonPropertyName("pendingApprovals")]
    public int PendingApprovals { get; init; }

    [JsonPropertyName("lastTurnId")]
    public string LastTurnId { get; init; } = string.Empty;

    [JsonPropertyName("lastTurnStatus")]
    public string LastTurnStatus { get; init; } = string.Empty;

    [JsonPropertyName("agentNickname")]
    public string AgentNickname { get; init; } = string.Empty;

    [JsonPropertyName("agentRole")]
    public string AgentRole { get; init; } = string.Empty;

    [JsonPropertyName("ended")]
    public bool Ended { get; init; }

    [JsonIgnore]
    public string DisplayName =>
        FirstNonEmpty(Name, AgentNickname, DirectoryName, PreviewSummary) is { Length: > 0 } value
            ? Truncate(value, 48)
            : $"Session {ShortId}";

    [JsonIgnore]
    public string PreviewSummary => Preview
        .Replace('\t', ' ')
        .Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries)
        .Select(line => line.Trim())
        .FirstOrDefault(line => line.Length > 0) ?? string.Empty;

    [JsonIgnore]
    public string PreviewExcerpt => HeadTailTruncated(
        string.Join(" ", Preview.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)),
        220,
        140,
        72);

    [JsonIgnore]
    public string UpdatedAtDisplay => FormatEpochSeconds(UpdatedAt);

    [JsonIgnore]
    public bool HasWaitingState =>
        ActiveFlags.Contains("waitingOnApproval") || ActiveFlags.Contains("waitingOnUserInput") || PendingApprovals > 0;

    [JsonIgnore]
    public bool IsRunningTurn => LastTurnStatus == "inProgress";

    [JsonIgnore]
    public string ShortId => Id.Length <= 8 ? Id : Id[..8];

    [JsonIgnore]
    private string DirectoryName
    {
        get
        {
            var trimmed = Cwd.Trim();
            if (trimmed.Length == 0)
            {
                return string.Empty;
            }
            return trimmed.TrimEnd('\\', '/').Split('\\', '/').LastOrDefault() ?? string.Empty;
        }
    }

    private static string? FirstNonEmpty(params string[] values) =>
        values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim();

    private static string Truncate(string value, int maxLength) =>
        value.Length <= maxLength ? value : value[..maxLength] + "...";

    private static string HeadTailTruncated(string value, int maxLength, int head, int tail)
    {
        var trimmed = value.Trim();
        if (trimmed.Length <= maxLength || head <= 0 || tail <= 0 || head + tail >= trimmed.Length)
        {
            return trimmed;
        }
        return trimmed[..head] + " ... " + trimmed[^tail..];
    }

    private static string FormatEpochSeconds(long timestamp)
    {
        if (timestamp <= 0)
        {
            return "未知";
        }

        var dateTime = DateTimeOffset.FromUnixTimeSeconds(timestamp).ToLocalTime();
        var now = DateTimeOffset.Now;
        if (dateTime.Date == now.Date)
        {
            return "今天 " + dateTime.ToString("HH:mm", CultureInfo.GetCultureInfo("zh-CN"));
        }
        if (dateTime.Date == now.Date.AddDays(-1))
        {
            return "昨天 " + dateTime.ToString("HH:mm", CultureInfo.GetCultureInfo("zh-CN"));
        }
        if (dateTime.Year == now.Year)
        {
            return dateTime.ToString("MM-dd HH:mm", CultureInfo.GetCultureInfo("zh-CN"));
        }
        return dateTime.ToString("yyyy-MM-dd HH:mm", CultureInfo.GetCultureInfo("zh-CN"));
    }
}

public sealed record SessionDetail
{
    [JsonPropertyName("summary")]
    public SessionSummary Summary { get; init; } = new();

    [JsonPropertyName("turns")]
    public IReadOnlyList<TurnDetail> Turns { get; init; } = Array.Empty<TurnDetail>();
}

public sealed record TurnDetail
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; init; } = string.Empty;

    [JsonPropertyName("startedAt")]
    public long StartedAt { get; init; }

    [JsonPropertyName("completedAt")]
    public long CompletedAt { get; init; }

    [JsonPropertyName("durationMs")]
    public long DurationMs { get; init; }

    [JsonPropertyName("error")]
    public string Error { get; init; } = string.Empty;

    [JsonPropertyName("diff")]
    public string Diff { get; init; } = string.Empty;

    [JsonPropertyName("planExplanation")]
    public string PlanExplanation { get; init; } = string.Empty;

    [JsonPropertyName("plan")]
    public IReadOnlyList<PlanStep> Plan { get; init; } = Array.Empty<PlanStep>();

    [JsonPropertyName("items")]
    public IReadOnlyList<TurnItem> Items { get; init; } = Array.Empty<TurnItem>();

    [JsonIgnore]
    public string DurationDisplay => DurationMs > 0 ? $"{DurationMs / 1000.0:0.0}s" : string.Empty;
}

public sealed record PlanStep
{
    [JsonPropertyName("step")]
    public string Step { get; init; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; init; } = string.Empty;
}

public sealed record TurnItem
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;

    [JsonPropertyName("type")]
    public string Type { get; init; } = string.Empty;

    [JsonPropertyName("title")]
    public string Title { get; init; } = string.Empty;

    [JsonPropertyName("body")]
    public string Body { get; init; } = string.Empty;

    [JsonPropertyName("status")]
    public string Status { get; init; } = string.Empty;

    [JsonPropertyName("auxiliary")]
    public string Auxiliary { get; init; } = string.Empty;

    [JsonPropertyName("metadata")]
    public IReadOnlyDictionary<string, string> Metadata { get; init; } = new Dictionary<string, string>();
}
