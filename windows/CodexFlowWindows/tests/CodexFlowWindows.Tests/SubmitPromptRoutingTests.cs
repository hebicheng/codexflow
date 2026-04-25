using CodexFlowWindows.Data.Api;
using CodexFlowWindows.Data.Models;
using CodexFlowWindows.Data.Repository;
using Xunit;

namespace CodexFlowWindows.Tests;

public sealed class SubmitPromptRoutingTests
{
    [Fact]
    public async Task InProgressWithTurnId_CallsSteerTurn()
    {
        var api = new FakeApiClient();
        var repository = new CodexFlowRepository(api, null, new TestSettingsStore());
        var session = new SessionSummary
        {
            Id = "s1",
            LastTurnStatus = "inProgress",
            LastTurnId = "t1"
        };

        await repository.SubmitPromptAsync(session, "adjust");

        Assert.Equal(1, api.SteerCalls);
        Assert.Equal(0, api.StartTurnCalls);
        Assert.Equal("adjust", api.LastPrompt);
    }

    [Theory]
    [InlineData("", "")]
    [InlineData("completed", "t1")]
    [InlineData("inProgress", "")]
    public async Task Otherwise_CallsStartTurn(string status, string turnId)
    {
        var api = new FakeApiClient();
        var repository = new CodexFlowRepository(api, null, new TestSettingsStore());
        var session = new SessionSummary
        {
            Id = "s1",
            LastTurnStatus = status,
            LastTurnId = turnId
        };

        await repository.SubmitPromptAsync(session, "next");

        Assert.Equal(0, api.SteerCalls);
        Assert.Equal(1, api.StartTurnCalls);
        Assert.Equal("next", api.LastPrompt);
    }

    private sealed class FakeApiClient : IAgentApiClient
    {
        public int SteerCalls { get; private set; }
        public int StartTurnCalls { get; private set; }
        public string LastPrompt { get; private set; } = string.Empty;

        public Task<HealthResponse> HealthAsync(CancellationToken cancellationToken = default) => Task.FromResult(new HealthResponse { Ok = true });
        public Task<HealthResponse> HealthAsync(string baseUrl, CancellationToken cancellationToken = default) => Task.FromResult(new HealthResponse { Ok = true });
        public Task<DashboardResponse> GetDashboardAsync(CancellationToken cancellationToken = default) => Task.FromResult(DashboardResponse.Empty);
        public Task<IReadOnlyList<SessionSummary>> GetSessionsAsync(CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<SessionSummary>>(Array.Empty<SessionSummary>());
        public Task RefreshSessionsAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<SessionSummary> StartSessionAsync(string cwd, string prompt, CancellationToken cancellationToken = default) => Task.FromResult(new SessionSummary { Id = "s1" });
        public Task<SessionDetail> GetSessionDetailAsync(string id, CancellationToken cancellationToken = default) => Task.FromResult(new SessionDetail { Summary = new SessionSummary { Id = id } });
        public Task<SessionSummary> ResumeSessionAsync(string id, CancellationToken cancellationToken = default) => Task.FromResult(new SessionSummary { Id = id });
        public Task EndSessionAsync(string id, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task ArchiveSessionAsync(string id, CancellationToken cancellationToken = default) => Task.CompletedTask;

        public Task<TurnDetail> StartTurnAsync(string sessionId, string prompt, CancellationToken cancellationToken = default)
        {
            StartTurnCalls++;
            LastPrompt = prompt;
            return Task.FromResult(new TurnDetail { Id = "new-turn" });
        }

        public Task SteerTurnAsync(string sessionId, string turnId, string prompt, CancellationToken cancellationToken = default)
        {
            SteerCalls++;
            LastPrompt = prompt;
            return Task.CompletedTask;
        }

        public Task InterruptTurnAsync(string sessionId, string turnId, CancellationToken cancellationToken = default) => Task.CompletedTask;
        public Task<IReadOnlyList<PendingRequestView>> GetApprovalsAsync(CancellationToken cancellationToken = default) => Task.FromResult<IReadOnlyList<PendingRequestView>>(Array.Empty<PendingRequestView>());
        public Task ResolveApprovalAsync(string id, JsonValue result, CancellationToken cancellationToken = default) => Task.CompletedTask;
    }
}
