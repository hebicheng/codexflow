using System.Text.Json.Serialization;

namespace CodexFlowWindows.Data.Models;

public sealed record ApprovalListEnvelope
{
    [JsonPropertyName("data")]
    public IReadOnlyList<PendingRequestView> Data { get; init; } = Array.Empty<PendingRequestView>();
}

public sealed record PendingRequestView
{
    [JsonPropertyName("id")]
    public string Id { get; init; } = string.Empty;

    [JsonPropertyName("method")]
    public string Method { get; init; } = string.Empty;

    [JsonPropertyName("kind")]
    public string Kind { get; init; } = string.Empty;

    [JsonPropertyName("threadId")]
    public string ThreadId { get; init; } = string.Empty;

    [JsonPropertyName("turnId")]
    public string TurnId { get; init; } = string.Empty;

    [JsonPropertyName("itemId")]
    public string ItemId { get; init; } = string.Empty;

    [JsonPropertyName("reason")]
    public string Reason { get; init; } = string.Empty;

    [JsonPropertyName("summary")]
    public string Summary { get; init; } = string.Empty;

    [JsonPropertyName("choices")]
    public IReadOnlyList<string> Choices { get; init; } = Array.Empty<string>();

    [JsonPropertyName("createdAt")]
    public string CreatedAt { get; init; } = string.Empty;

    [JsonPropertyName("params")]
    public IReadOnlyDictionary<string, JsonValue> Params { get; init; } = new Dictionary<string, JsonValue>();

    [JsonIgnore]
    public string KindTitle => Kind switch
    {
        "command" => "命令审批",
        "fileChange" => "文件变更审批",
        "permissions" => "权限审批",
        "userInput" => "需要回复",
        _ => "审批"
    };
}

public static class ApprovalResultBuilder
{
    public static JsonValue Build(PendingRequestView approval, string selectedChoice, string userInputText = "")
    {
        return approval.Kind switch
        {
            "command" or "fileChange" => JsonValue.Object(new Dictionary<string, JsonValue>
            {
                ["decision"] = JsonValue.String(selectedChoice)
            }),
            "permissions" => BuildPermissionsResult(approval, selectedChoice),
            "userInput" => BuildUserInputResult(approval, userInputText),
            _ => JsonValue.Object(new Dictionary<string, JsonValue>
            {
                ["decision"] = JsonValue.String(selectedChoice)
            })
        };
    }

    private static JsonValue BuildPermissionsResult(PendingRequestView approval, string selectedChoice)
    {
        var scoped = selectedChoice is "session" or "turn";
        var permissions = scoped
            ? approval.Params.TryGetValue("permissions", out var value)
                ? value
                : JsonValue.Object(new Dictionary<string, JsonValue>())
            : JsonValue.Object(new Dictionary<string, JsonValue>
                {
                    ["network"] = JsonValue.Null,
                    ["fileSystem"] = JsonValue.Null
                });

        return JsonValue.Object(new Dictionary<string, JsonValue>
        {
            ["permissions"] = permissions,
            ["scope"] = scoped ? JsonValue.String(selectedChoice) : JsonValue.Null
        });
    }

    private static JsonValue BuildUserInputResult(PendingRequestView approval, string userInputText)
    {
        var questionId = FirstQuestionId(approval.Params) ?? "reply";
        return JsonValue.Object(new Dictionary<string, JsonValue>
        {
            ["answers"] = JsonValue.Object(new Dictionary<string, JsonValue>
            {
                [questionId] = JsonValue.Object(new Dictionary<string, JsonValue>
                {
                    ["answers"] = JsonValue.Array(new[] { JsonValue.String(userInputText) })
                })
            })
        });
    }

    private static string? FirstQuestionId(IReadOnlyDictionary<string, JsonValue> parameters)
    {
        if (!parameters.TryGetValue("questions", out var questions) || questions.ArrayValue is null)
        {
            return null;
        }

        foreach (var question in questions.ArrayValue)
        {
            if (question.ObjectValue is null)
            {
                continue;
            }
            if (question.ObjectValue.TryGetValue("id", out var id) && !string.IsNullOrWhiteSpace(id.StringValue))
            {
                return id.StringValue;
            }
        }

        return null;
    }
}
