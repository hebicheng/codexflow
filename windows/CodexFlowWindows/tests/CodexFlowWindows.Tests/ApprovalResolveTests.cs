using System.Text.Json;
using CodexFlowWindows.Data.Models;
using Xunit;

namespace CodexFlowWindows.Tests;

public sealed class ApprovalResolveTests
{
    [Theory]
    [InlineData("command", "accept", "{\"decision\":\"accept\"}")]
    [InlineData("command", "reject", "{\"decision\":\"reject\"}")]
    [InlineData("fileChange", "accept", "{\"decision\":\"accept\"}")]
    [InlineData("fileChange", "reject", "{\"decision\":\"reject\"}")]
    [InlineData("generic", "custom", "{\"decision\":\"custom\"}")]
    public void DecisionBodies(string kind, string choice, string expected)
    {
        var approval = new PendingRequestView { Kind = kind };
        var result = ApprovalResultBuilder.Build(approval, choice);

        Assert.Equal(expected, JsonSerializer.Serialize(result, JsonOptions.Default));
    }

    [Theory]
    [InlineData("session", "{\"permissions\":{\"network\":true},\"scope\":\"session\"}")]
    [InlineData("turn", "{\"permissions\":{\"network\":true},\"scope\":\"turn\"}")]
    public void PermissionsScopedBodies(string choice, string expected)
    {
        var approval = new PendingRequestView
        {
            Kind = "permissions",
            Params = new Dictionary<string, JsonValue>
            {
                ["permissions"] = JsonValue.Object(new Dictionary<string, JsonValue>
                {
                    ["network"] = JsonValue.Bool(true)
                })
            }
        };

        var result = ApprovalResultBuilder.Build(approval, choice);

        Assert.Equal(expected, JsonSerializer.Serialize(result, JsonOptions.Default));
    }

    [Fact]
    public void PermissionsRejectBody()
    {
        var approval = new PendingRequestView { Kind = "permissions" };
        var result = ApprovalResultBuilder.Build(approval, "decline");

        Assert.Equal(
            "{\"permissions\":{\"network\":null,\"fileSystem\":null},\"scope\":null}",
            JsonSerializer.Serialize(result, JsonOptions.Default));
    }

    [Fact]
    public void UserInputUsesQuestionId()
    {
        var approval = new PendingRequestView
        {
            Kind = "userInput",
            Params = new Dictionary<string, JsonValue>
            {
                ["questions"] = JsonValue.Array(new[]
                {
                    JsonValue.Object(new Dictionary<string, JsonValue>
                    {
                        ["id"] = JsonValue.String("next_step")
                    })
                })
            }
        };

        var result = ApprovalResultBuilder.Build(approval, "answer", "继续");

        Assert.Equal(
            "{\"answers\":{\"next_step\":{\"answers\":[\"继续\"]}}}",
            JsonSerializer.Serialize(result, JsonOptions.Default));
    }
}
