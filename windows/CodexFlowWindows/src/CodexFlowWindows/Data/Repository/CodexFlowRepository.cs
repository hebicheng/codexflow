using System.Collections.ObjectModel;
using System.Text.Json;
using CommunityToolkit.Mvvm.ComponentModel;
using CodexFlowWindows.Configuration;
using CodexFlowWindows.Data.Api;
using CodexFlowWindows.Data.Models;
using Microsoft.UI.Dispatching;

namespace CodexFlowWindows.Data.Repository;

public sealed partial class CodexFlowRepository : ObservableObject, IDisposable
{
    private readonly IAgentApiClient _apiClient;
    private readonly SseClient? _sseClient;
    private readonly ISettingsStore _settingsStore;
    private readonly SemaphoreSlim _refreshLock = new(1, 1);
    private readonly DispatcherQueue? _dispatcherQueue;
    private CancellationTokenSource? _sseCts;
    private Task? _sseTask;
    private string _lastSseBaseUrl;
    private bool _disposed;

    private string _errorMessage = string.Empty;
    private string _infoMessage = string.Empty;
    private bool _isActionRunning;
    private bool _isAgentHealthy;
    private SseConnectionState _sseState = SseConnectionState.Disconnected;

    public CodexFlowRepository(IAgentApiClient apiClient, SseClient? sseClient, ISettingsStore settingsStore)
    {
        _apiClient = apiClient;
        _sseClient = sseClient;
        _settingsStore = settingsStore;
        _dispatcherQueue = DispatcherQueue.GetForCurrentThread();

        Dashboard = new DashboardState();
        CurrentSession = new SessionState();
        Sessions = new ObservableCollection<SessionSummary>();
        Approvals = new ObservableCollection<PendingRequestView>();
        _lastSseBaseUrl = _settingsStore.Current.AgentBaseUrl;

        _settingsStore.SettingsChanged += OnSettingsChanged;
        if (_sseClient is not null)
        {
            _sseClient.EventReceived += OnSseEventReceived;
            _sseClient.ConnectionStateChanged += (_, state) => Dispatch(() => SseState = state);
            _sseClient.Error += (_, ex) => Dispatch(() => ErrorMessage = ex.Message);
        }
    }

    public DashboardState Dashboard { get; }
    public SessionState CurrentSession { get; }
    public ObservableCollection<SessionSummary> Sessions { get; }
    public ObservableCollection<PendingRequestView> Approvals { get; }

    public string AgentBaseUrl => _settingsStore.Current.AgentBaseUrl;

    public string ErrorMessage
    {
        get => _errorMessage;
        private set => SetProperty(ref _errorMessage, value);
    }

    public string InfoMessage
    {
        get => _infoMessage;
        private set => SetProperty(ref _infoMessage, value);
    }

    public bool IsActionRunning
    {
        get => _isActionRunning;
        private set => SetProperty(ref _isActionRunning, value);
    }

    public bool IsAgentHealthy
    {
        get => _isAgentHealthy;
        private set => SetProperty(ref _isAgentHealthy, value);
    }

    public SseConnectionState SseState
    {
        get => _sseState;
        private set => SetProperty(ref _sseState, value);
    }

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        try
        {
            await RefreshAsync(cancellationToken);
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        StartSse();
    }

    public async Task RefreshAsync(CancellationToken cancellationToken = default)
    {
        await _refreshLock.WaitAsync(cancellationToken);
        try
        {
            Dashboard.IsLoading = true;
            Dashboard.ErrorMessage = string.Empty;

            var dashboard = await _apiClient.GetDashboardAsync(cancellationToken);
            ApplyDashboard(dashboard);
            IsAgentHealthy = dashboard.Agent.Connected;
            ErrorMessage = string.Empty;
        }
        catch (Exception ex)
        {
            Dashboard.ErrorMessage = ex.Message;
            IsAgentHealthy = false;
            ErrorMessage = ex.Message;
            throw;
        }
        finally
        {
            Dashboard.IsLoading = false;
            _refreshLock.Release();
        }
    }

    public async Task LoadSessionAsync(string sessionId, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(sessionId))
        {
            return;
        }

        CurrentSession.SelectedSessionId = sessionId;
        await SaveLastSelectedSessionAsync(sessionId, cancellationToken);

        try
        {
            CurrentSession.IsLoading = true;
            CurrentSession.ErrorMessage = string.Empty;
            CurrentSession.Detail = await _apiClient.GetSessionDetailAsync(sessionId, cancellationToken);
            ErrorMessage = string.Empty;
        }
        catch (Exception ex)
        {
            CurrentSession.ErrorMessage = ex.Message;
            ErrorMessage = ex.Message;
            throw;
        }
        finally
        {
            CurrentSession.IsLoading = false;
        }
    }

    public async Task<SessionSummary> StartSessionAsync(string cwd, string prompt, CancellationToken cancellationToken = default)
    {
        return await RunSessionActionAsync(async () =>
        {
            var session = await _apiClient.StartSessionAsync(cwd.Trim(), prompt.Trim(), cancellationToken);
            InfoMessage = "会话已创建";
            await RefreshAsync(cancellationToken);
            await LoadSessionAsync(session.Id, cancellationToken);
            return session;
        });
    }

    public async Task ResumeSessionAsync(string sessionId, CancellationToken cancellationToken = default)
    {
        await RunSessionActionAsync(async () =>
        {
            await _apiClient.ResumeSessionAsync(sessionId, cancellationToken);
            InfoMessage = "会话已接管";
            await RefreshAsync(cancellationToken);
            await LoadSessionAsync(sessionId, cancellationToken);
            return true;
        });
    }

    public async Task ArchiveSessionAsync(string sessionId, CancellationToken cancellationToken = default)
    {
        await RunSessionActionAsync(async () =>
        {
            await _apiClient.ArchiveSessionAsync(sessionId, cancellationToken);
            InfoMessage = "会话已归档";
            if (CurrentSession.SelectedSessionId == sessionId)
            {
                CurrentSession.Detail = null;
                CurrentSession.SelectedSessionId = string.Empty;
            }
            await RefreshAsync(cancellationToken);
            return true;
        });
    }

    public async Task EndSessionAsync(string sessionId, CancellationToken cancellationToken = default)
    {
        await RunSessionActionAsync(async () =>
        {
            await _apiClient.EndSessionAsync(sessionId, cancellationToken);
            InfoMessage = "会话已结束";
            await RefreshAsync(cancellationToken);
            await LoadSessionAsync(sessionId, cancellationToken);
            return true;
        });
    }

    public async Task SubmitPromptAsync(SessionSummary session, string prompt, CancellationToken cancellationToken = default)
    {
        var trimmed = prompt.Trim();
        if (trimmed.Length == 0)
        {
            return;
        }

        await RunSessionActionAsync(async () =>
        {
            if (session.LastTurnStatus == "inProgress" && !string.IsNullOrWhiteSpace(session.LastTurnId))
            {
                await _apiClient.SteerTurnAsync(session.Id, session.LastTurnId, trimmed, cancellationToken);
                InfoMessage = "已发送 steer";
            }
            else
            {
                await _apiClient.StartTurnAsync(session.Id, trimmed, cancellationToken);
                InfoMessage = "已开始新 turn";
            }

            await RefreshAsync(cancellationToken);
            await LoadSessionAsync(session.Id, cancellationToken);
            return true;
        });
    }

    public async Task InterruptAsync(SessionSummary session, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(session.LastTurnId))
        {
            return;
        }

        await RunSessionActionAsync(async () =>
        {
            await _apiClient.InterruptTurnAsync(session.Id, session.LastTurnId, cancellationToken);
            InfoMessage = "已发送中断";
            await RefreshAsync(cancellationToken);
            await LoadSessionAsync(session.Id, cancellationToken);
            return true;
        });
    }

    public async Task ResolveApprovalAsync(PendingRequestView approval, JsonValue result, CancellationToken cancellationToken = default)
    {
        await RunSessionActionAsync(async () =>
        {
            await _apiClient.ResolveApprovalAsync(approval.Id, result, cancellationToken);
            InfoMessage = "审批已处理";
            await RefreshAsync(cancellationToken);
            if (!string.IsNullOrWhiteSpace(CurrentSession.SelectedSessionId) &&
                CurrentSession.SelectedSessionId == approval.ThreadId)
            {
                await LoadSessionAsync(approval.ThreadId, cancellationToken);
            }
            return true;
        });
    }

    public async Task<HealthResponse> TestConnectionAsync(string baseUrl, CancellationToken cancellationToken = default)
    {
        var health = await _apiClient.HealthAsync(baseUrl, cancellationToken);
        InfoMessage = health.Ok ? "连接测试成功" : "Agent 返回非健康状态";
        return health;
    }

    public void ReportError(string message)
    {
        ErrorMessage = message;
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _settingsStore.SettingsChanged -= OnSettingsChanged;
        StopSse();
        _refreshLock.Dispose();
    }

    private async Task<T> RunSessionActionAsync<T>(Func<Task<T>> action)
    {
        if (IsActionRunning)
        {
            throw new InvalidOperationException("已有操作正在执行，请稍后再试。");
        }

        try
        {
            IsActionRunning = true;
            ErrorMessage = string.Empty;
            return await action();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
            throw;
        }
        finally
        {
            IsActionRunning = false;
        }
    }

    private void ApplyDashboard(DashboardResponse dashboard)
    {
        Dashboard.Dashboard = dashboard;
        Replace(Sessions, dashboard.Sessions.OrderByDescending(session => session.UpdatedAt));
        Replace(Approvals, dashboard.Approvals.OrderBy(approval => approval.CreatedAt));
        OnPropertyChanged(nameof(AgentBaseUrl));
    }

    private static void Replace<T>(ObservableCollection<T> target, IEnumerable<T> source)
    {
        target.Clear();
        foreach (var item in source)
        {
            target.Add(item);
        }
    }

    private async Task SaveLastSelectedSessionAsync(string sessionId, CancellationToken cancellationToken)
    {
        var settings = _settingsStore.Current with { LastSelectedSessionId = sessionId };
        await _settingsStore.SaveAsync(settings, cancellationToken);
    }

    private void StartSse()
    {
        if (_sseClient is null)
        {
            return;
        }

        StopSse();
        _lastSseBaseUrl = _settingsStore.Current.AgentBaseUrl;
        _sseCts = new CancellationTokenSource();
        _sseTask = _sseClient.RunAsync(_sseCts.Token);
    }

    private void StopSse()
    {
        if (_sseCts is null)
        {
            return;
        }

        _sseCts.Cancel();
        _sseCts.Dispose();
        _sseCts = null;
        _sseTask = null;
        SseState = SseConnectionState.Disconnected;
    }

    private void OnSettingsChanged(object? sender, AppSettings settings)
    {
        OnPropertyChanged(nameof(AgentBaseUrl));
        if (!string.Equals(_lastSseBaseUrl, settings.AgentBaseUrl, StringComparison.OrdinalIgnoreCase))
        {
            StartSse();
            _ = RefreshAsync();
        }
    }

    private void OnSseEventReceived(object? sender, SseEvent evt)
    {
        if (string.IsNullOrWhiteSpace(evt.Data))
        {
            return;
        }

        _ = DispatchAsync(async () =>
        {
            try
            {
                _ = JsonSerializer.Deserialize<AgentEvent>(evt.Data, JsonOptions.Default);
                await RefreshAsync();
                if (!string.IsNullOrWhiteSpace(CurrentSession.SelectedSessionId))
                {
                    await LoadSessionAsync(CurrentSession.SelectedSessionId);
                }
            }
            catch (Exception ex)
            {
                ErrorMessage = ex.Message;
            }
        });
    }

    private void Dispatch(Action action)
    {
        if (_dispatcherQueue is null || _dispatcherQueue.HasThreadAccess)
        {
            action();
            return;
        }

        _dispatcherQueue.TryEnqueue(() => action());
    }

    private Task DispatchAsync(Func<Task> action)
    {
        if (_dispatcherQueue is null || _dispatcherQueue.HasThreadAccess)
        {
            return action();
        }

        var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        _dispatcherQueue.TryEnqueue(async () =>
        {
            try
            {
                await action();
                tcs.SetResult();
            }
            catch (Exception ex)
            {
                tcs.SetException(ex);
            }
        });
        return tcs.Task;
    }
}
