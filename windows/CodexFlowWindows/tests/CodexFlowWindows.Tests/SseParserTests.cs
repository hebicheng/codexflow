using CodexFlowWindows.Data.Api;
using Xunit;

namespace CodexFlowWindows.Tests;

public sealed class SseParserTests
{
    [Fact]
    public void ParsesEventAndData()
    {
        var parser = new SseParser();

        Assert.Null(parser.ProcessLine("event: turn.started"));
        Assert.Null(parser.ProcessLine("data: {\"ok\":true}"));
        var evt = parser.ProcessLine("");

        Assert.NotNull(evt);
        Assert.Equal("turn.started", evt!.EventType);
        Assert.Equal("{\"ok\":true}", evt.Data);
    }

    [Fact]
    public void IgnoresPingComments()
    {
        var parser = new SseParser();

        Assert.Null(parser.ProcessLine(": ping"));
        Assert.Null(parser.ProcessLine(""));
    }

    [Fact]
    public void SupportsMultilineData()
    {
        var parser = new SseParser();

        parser.ProcessLine("event: message");
        parser.ProcessLine("data: first");
        parser.ProcessLine("data: second");
        var evt = parser.ProcessLine("");

        Assert.Equal("first\nsecond", evt!.Data);
    }

    [Fact]
    public void EmptyLineSubmitsEvent()
    {
        var parser = new SseParser();

        parser.ProcessLine("data: payload");
        var evt = parser.ProcessLine("");

        Assert.Equal("message", evt!.EventType);
        Assert.Equal("payload", evt.Data);
    }
}
