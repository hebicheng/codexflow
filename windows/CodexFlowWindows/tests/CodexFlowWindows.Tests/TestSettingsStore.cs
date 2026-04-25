using CodexFlowWindows.Configuration;

namespace CodexFlowWindows.Tests;

internal sealed class TestSettingsStore : ISettingsStore
{
    public TestSettingsStore(string baseUrl = AppSettings.DefaultAgentBaseUrl)
    {
        Current = new AppSettings { AgentBaseUrl = baseUrl };
    }

    public AppSettings Current { get; private set; }
    public string SettingsPath => string.Empty;
    public string LastError => string.Empty;
    public event EventHandler<AppSettings>? SettingsChanged;

    public AppSettings Load() => Current;

    public Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        Current = settings;
        SettingsChanged?.Invoke(this, Current);
        return Task.CompletedTask;
    }
}
