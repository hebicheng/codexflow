using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using CodexFlowWindows.Configuration;
using CodexFlowWindows.Data.Models;

namespace CodexFlowWindows.Data.Api;

public interface IAgentApiClient
{
    Task<HealthResponse> HealthAsync(CancellationToken cancellationToken = default);
    Task<HealthResponse> HealthAsync(string baseUrl, CancellationToken cancellationToken = default);
    Task<DashboardResponse> GetDashboardAsync(CancellationToken cancellationToken = default);
    Task<IReadOnlyList<SessionSummary>> GetSessionsAsync(CancellationToken cancellationToken = default);
    Task RefreshSessionsAsync(CancellationToken cancellationToken = default);
    Task<SessionSummary> StartSessionAsync(string cwd, string prompt, CancellationToken cancellationToken = default);
    Task<SessionDetail> GetSessionDetailAsync(string id, CancellationToken cancellationToken = default);
    Task<SessionSummary> ResumeSessionAsync(string id, CancellationToken cancellationToken = default);
    Task EndSessionAsync(string id, CancellationToken cancellationToken = default);
    Task ArchiveSessionAsync(string id, CancellationToken cancellationToken = default);
    Task<TurnDetail> StartTurnAsync(string sessionId, string prompt, CancellationToken cancellationToken = default);
    Task SteerTurnAsync(string sessionId, string turnId, string prompt, CancellationToken cancellationToken = default);
    Task InterruptTurnAsync(string sessionId, string turnId, CancellationToken cancellationToken = default);
    Task<IReadOnlyList<PendingRequestView>> GetApprovalsAsync(CancellationToken cancellationToken = default);
    Task ResolveApprovalAsync(string id, JsonValue result, CancellationToken cancellationToken = default);
}

public sealed class AgentApiClient : IAgentApiClient
{
    private static readonly IReadOnlyDictionary<string, object?> EmptyBody = new Dictionary<string, object?>();
    private readonly HttpClient _httpClient;
    private readonly ISettingsStore _settingsStore;

    public AgentApiClient(HttpClient httpClient, ISettingsStore settingsStore)
    {
        _httpClient = httpClient;
        _settingsStore = settingsStore;
    }

    public Task<HealthResponse> HealthAsync(CancellationToken cancellationToken = default) =>
        SendAsync<HealthResponse>(HttpMethod.Get, "/healthz", null, cancellationToken: cancellationToken);

    public Task<HealthResponse> HealthAsync(string baseUrl, CancellationToken cancellationToken = default) =>
        SendAsync<HealthResponse>(HttpMethod.Get, "/healthz", null, baseUrl, cancellationToken);

    public Task<DashboardResponse> GetDashboardAsync(CancellationToken cancellationToken = default) =>
        SendAsync<DashboardResponse>(HttpMethod.Get, "/api/v1/dashboard", null, cancellationToken: cancellationToken);

    public async Task<IReadOnlyList<SessionSummary>> GetSessionsAsync(CancellationToken cancellationToken = default)
    {
        var envelope = await SendAsync<SessionListEnvelope>(HttpMethod.Get, "/api/v1/sessions", null, cancellationToken: cancellationToken);
        return envelope.Data;
    }

    public Task RefreshSessionsAsync(CancellationToken cancellationToken = default) =>
        SendAsync<OkResponse>(HttpMethod.Post, "/api/v1/sessions", new { action = "refresh" }, cancellationToken: cancellationToken);

    public Task<SessionSummary> StartSessionAsync(string cwd, string prompt, CancellationToken cancellationToken = default) =>
        SendAsync<SessionSummary>(HttpMethod.Post, "/api/v1/sessions", new
        {
            action = "start",
            cwd,
            prompt
        }, cancellationToken: cancellationToken);

    public Task<SessionDetail> GetSessionDetailAsync(string id, CancellationToken cancellationToken = default) =>
        SendAsync<SessionDetail>(HttpMethod.Get, $"/api/v1/sessions/{Uri.EscapeDataString(id)}", null, cancellationToken: cancellationToken);

    public Task<SessionSummary> ResumeSessionAsync(string id, CancellationToken cancellationToken = default) =>
        SendAsync<SessionSummary>(HttpMethod.Post, $"/api/v1/sessions/{Uri.EscapeDataString(id)}/resume", EmptyBody, cancellationToken: cancellationToken);

    public Task EndSessionAsync(string id, CancellationToken cancellationToken = default) =>
        SendAsync<OkResponse>(HttpMethod.Post, $"/api/v1/sessions/{Uri.EscapeDataString(id)}/end", EmptyBody, cancellationToken: cancellationToken);

    public Task ArchiveSessionAsync(string id, CancellationToken cancellationToken = default) =>
        SendAsync<OkResponse>(HttpMethod.Post, $"/api/v1/sessions/{Uri.EscapeDataString(id)}/archive", EmptyBody, cancellationToken: cancellationToken);

    public Task<TurnDetail> StartTurnAsync(string sessionId, string prompt, CancellationToken cancellationToken = default) =>
        SendAsync<TurnDetail>(HttpMethod.Post, $"/api/v1/sessions/{Uri.EscapeDataString(sessionId)}/turns/start", new
        {
            prompt
        }, cancellationToken: cancellationToken);

    public Task SteerTurnAsync(string sessionId, string turnId, string prompt, CancellationToken cancellationToken = default) =>
        SendAsync<OkResponse>(HttpMethod.Post, $"/api/v1/sessions/{Uri.EscapeDataString(sessionId)}/turns/steer", new
        {
            turnId,
            prompt
        }, cancellationToken: cancellationToken);

    public Task InterruptTurnAsync(string sessionId, string turnId, CancellationToken cancellationToken = default) =>
        SendAsync<OkResponse>(HttpMethod.Post, $"/api/v1/sessions/{Uri.EscapeDataString(sessionId)}/turns/interrupt", new
        {
            turnId
        }, cancellationToken: cancellationToken);

    public async Task<IReadOnlyList<PendingRequestView>> GetApprovalsAsync(CancellationToken cancellationToken = default)
    {
        var envelope = await SendAsync<ApprovalListEnvelope>(HttpMethod.Get, "/api/v1/approvals", null, cancellationToken: cancellationToken);
        return envelope.Data;
    }

    public Task ResolveApprovalAsync(string id, JsonValue result, CancellationToken cancellationToken = default) =>
        SendAsync<OkResponse>(HttpMethod.Post, $"/api/v1/approvals/{Uri.EscapeDataString(id)}/resolve", new ApprovalResolveBody(result), cancellationToken: cancellationToken);

    internal static Uri BuildUri(string baseUrl, string path)
    {
        if (string.IsNullOrWhiteSpace(baseUrl))
        {
            throw new ApiException(null, "Agent base URL is empty.");
        }

        if (!Uri.TryCreate(baseUrl.Trim().TrimEnd('/') + "/", UriKind.Absolute, out var root))
        {
            throw new ApiException(null, $"Agent base URL is invalid: {baseUrl}");
        }

        return new Uri(root, path.TrimStart('/'));
    }

    private async Task<T> SendAsync<T>(
        HttpMethod method,
        string path,
        object? body,
        string? baseUrl = null,
        CancellationToken cancellationToken = default)
    {
        var uri = BuildUri(baseUrl ?? _settingsStore.Current.AgentBaseUrl, path);
        using var request = new HttpRequestMessage(method, uri);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

        if (method != HttpMethod.Get)
        {
            request.Content = CreateJsonContent(body ?? EmptyBody);
        }

        HttpResponseMessage response;
        try
        {
            response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseContentRead, cancellationToken);
        }
        catch (TaskCanceledException ex) when (!cancellationToken.IsCancellationRequested)
        {
            throw new ApiException(null, "Agent request timed out.", innerException: ex);
        }
        catch (HttpRequestException ex)
        {
            throw new ApiException(ex.StatusCode, ex.Message, innerException: ex);
        }

        using var responseScope = response;
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);

        if (!response.IsSuccessStatusCode)
        {
            throw CreateApiException(response.StatusCode, responseBody);
        }

        try
        {
            if (typeof(T) == typeof(OkResponse) && string.IsNullOrWhiteSpace(responseBody))
            {
                return (T)(object)new OkResponse { Ok = true };
            }

            return JsonSerializer.Deserialize<T>(responseBody, JsonOptions.Default)
                ?? throw new ApiException(response.StatusCode, "Agent returned an empty response.", responseBody);
        }
        catch (JsonException ex)
        {
            throw new ApiException(response.StatusCode, "Agent returned invalid JSON.", responseBody, ex);
        }
    }

    private static StringContent CreateJsonContent(object body)
    {
        var json = JsonSerializer.Serialize(body, JsonOptions.Default);
        return new StringContent(json, Encoding.UTF8, "application/json");
    }

    private static ApiException CreateApiException(HttpStatusCode statusCode, string responseBody)
    {
        try
        {
            var error = JsonSerializer.Deserialize<ErrorResponse>(responseBody, JsonOptions.Default);
            if (!string.IsNullOrWhiteSpace(error?.Error))
            {
                return new ApiException(statusCode, error.Error, responseBody);
            }
        }
        catch (JsonException)
        {
            // Fall back to a status-code based message below.
        }

        return new ApiException(statusCode, $"Agent request failed with status {(int)statusCode}.", responseBody);
    }

    private sealed record ErrorResponse
    {
        [JsonPropertyName("error")]
        public string Error { get; init; } = string.Empty;
    }

    private sealed record ApprovalResolveBody([property: JsonPropertyName("result")] JsonValue Result);
}
