using System.Net.Http.Headers;
using CodexFlowWindows.Configuration;
using CodexFlowWindows.Data.Repository;

namespace CodexFlowWindows.Data.Api;

public sealed class SseClient
{
    private readonly HttpClient _httpClient;
    private readonly ISettingsStore _settingsStore;

    public SseClient(HttpClient httpClient, ISettingsStore settingsStore)
    {
        _httpClient = httpClient;
        _settingsStore = settingsStore;
    }

    public event EventHandler<SseEvent>? EventReceived;
    public event EventHandler<SseConnectionState>? ConnectionStateChanged;
    public event EventHandler<Exception>? Error;

    public async Task RunAsync(CancellationToken cancellationToken)
    {
        var delay = TimeSpan.FromSeconds(1);
        var reconnecting = false;

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                SetState(reconnecting ? SseConnectionState.Reconnecting : SseConnectionState.Connecting);
                await ConnectOnceAsync(cancellationToken);
                delay = TimeSpan.FromSeconds(1);
                reconnecting = true;
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                Error?.Invoke(this, ex);
                SetState(SseConnectionState.Error);
                reconnecting = true;
            }

            if (!cancellationToken.IsCancellationRequested)
            {
                await Task.Delay(delay, cancellationToken);
                delay = TimeSpan.FromSeconds(Math.Min(delay.TotalSeconds * 2, 30));
            }
        }

        SetState(SseConnectionState.Disconnected);
    }

    private async Task ConnectOnceAsync(CancellationToken cancellationToken)
    {
        var uri = AgentApiClient.BuildUri(_settingsStore.Current.AgentBaseUrl, "/api/v1/events");
        using var request = new HttpRequestMessage(HttpMethod.Get, uri);
        request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("text/event-stream"));

        using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        response.EnsureSuccessStatusCode();

        SetState(SseConnectionState.Connected);
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var reader = new StreamReader(stream);
        var parser = new SseParser();

        while (!reader.EndOfStream && !cancellationToken.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(cancellationToken);
            if (line is null)
            {
                break;
            }

            if (parser.ProcessLine(line) is { } evt)
            {
                EventReceived?.Invoke(this, evt);
            }
        }

        if (parser.Flush() is { } pendingEvent)
        {
            EventReceived?.Invoke(this, pendingEvent);
        }
    }

    private void SetState(SseConnectionState state)
    {
        ConnectionStateChanged?.Invoke(this, state);
    }
}

public sealed class SseParser
{
    private string _eventType = "message";
    private readonly List<string> _dataLines = new();

    public SseEvent? ProcessLine(string line)
    {
        if (line.Length == 0)
        {
            return Flush();
        }

        if (line.StartsWith(':'))
        {
            return null;
        }

        var separator = line.IndexOf(':');
        string field;
        string value;

        if (separator < 0)
        {
            field = line;
            value = string.Empty;
        }
        else
        {
            field = line[..separator];
            value = line[(separator + 1)..];
            if (value.StartsWith(' '))
            {
                value = value[1..];
            }
        }

        switch (field)
        {
            case "event":
                _eventType = string.IsNullOrWhiteSpace(value) ? "message" : value;
                break;
            case "data":
                _dataLines.Add(value);
                break;
        }

        return null;
    }

    public SseEvent? Flush()
    {
        if (_dataLines.Count == 0)
        {
            _eventType = "message";
            return null;
        }

        var evt = new SseEvent(_eventType, string.Join('\n', _dataLines));
        _eventType = "message";
        _dataLines.Clear();
        return evt;
    }
}
