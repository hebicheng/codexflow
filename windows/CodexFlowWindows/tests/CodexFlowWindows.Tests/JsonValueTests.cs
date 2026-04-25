using System.Text.Json;
using CodexFlowWindows.Data.Models;
using Xunit;

namespace CodexFlowWindows.Tests;

public sealed class JsonValueTests
{
    [Fact]
    public void String_EncodeDecode()
    {
        RoundTrips(JsonValue.String("hello"), "\"hello\"");
    }

    [Fact]
    public void Number_EncodeDecode()
    {
        RoundTrips(JsonValue.Number(42.5), "42.5");
    }

    [Fact]
    public void Bool_EncodeDecode()
    {
        RoundTrips(JsonValue.Bool(true), "true");
    }

    [Fact]
    public void Null_EncodeDecode()
    {
        RoundTrips(JsonValue.Null, "null");
    }

    [Fact]
    public void Object_EncodeDecode()
    {
        var value = JsonValue.Object(new Dictionary<string, JsonValue>
        {
            ["name"] = JsonValue.String("codex"),
            ["ok"] = JsonValue.Bool(true)
        });

        var decoded = JsonSerializer.Deserialize<JsonValue>(
            JsonSerializer.Serialize(value, JsonOptions.Default),
            JsonOptions.Default)!;

        Assert.Equal("codex", decoded.ObjectValue!["name"].StringValue);
        Assert.True(decoded.ObjectValue!["ok"].BoolValue);
    }

    [Fact]
    public void Array_EncodeDecode()
    {
        var value = JsonValue.Array(new[] { JsonValue.String("a"), JsonValue.Number(1) });
        var decoded = JsonSerializer.Deserialize<JsonValue>(
            JsonSerializer.Serialize(value, JsonOptions.Default),
            JsonOptions.Default)!;

        Assert.Equal("a", decoded.ArrayValue![0].StringValue);
        Assert.Equal(1, decoded.ArrayValue![1].NumberValue);
    }

    private static void RoundTrips(JsonValue value, string expectedJson)
    {
        var json = JsonSerializer.Serialize(value, JsonOptions.Default);
        Assert.Equal(expectedJson, json);
        Assert.Equal(value, JsonSerializer.Deserialize<JsonValue>(json, JsonOptions.Default));
    }
}
