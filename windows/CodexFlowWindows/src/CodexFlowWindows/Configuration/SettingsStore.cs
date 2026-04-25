using System.Text.Json;
using CodexFlowWindows.Data.Models;

namespace CodexFlowWindows.Configuration;

public interface ISettingsStore
{
    AppSettings Current { get; }
    string SettingsPath { get; }
    string LastError { get; }
    event EventHandler<AppSettings>? SettingsChanged;

    AppSettings Load();
    Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default);
}

public sealed class SettingsStore : ISettingsStore
{
    private readonly string _settingsDirectory;

    public SettingsStore(string? settingsDirectory = null)
    {
        _settingsDirectory = settingsDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "CodexFlow");
        SettingsPath = Path.Combine(_settingsDirectory, "settings.json");
    }

    public AppSettings Current { get; private set; } = new();
    public string SettingsPath { get; }
    public string LastError { get; private set; } = string.Empty;
    public event EventHandler<AppSettings>? SettingsChanged;

    public AppSettings Load()
    {
        LastError = string.Empty;
        try
        {
            if (!File.Exists(SettingsPath))
            {
                Current = new AppSettings();
                return Current;
            }

            var json = File.ReadAllText(SettingsPath);
            Current = JsonSerializer.Deserialize<AppSettings>(json, JsonOptions.Default) ?? new AppSettings();
            if (string.IsNullOrWhiteSpace(Current.AgentBaseUrl))
            {
                Current = Current with { AgentBaseUrl = AppSettings.DefaultAgentBaseUrl };
            }
            return Current;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            Current = new AppSettings();
            return Current;
        }
    }

    public async Task SaveAsync(AppSettings settings, CancellationToken cancellationToken = default)
    {
        Directory.CreateDirectory(_settingsDirectory);

        var normalized = settings.WithBaseUrl(settings.AgentBaseUrl);
        var tempPath = SettingsPath + ".tmp";
        var json = JsonSerializer.Serialize(normalized, JsonOptions.Default);
        await File.WriteAllTextAsync(tempPath, json, cancellationToken);
        File.Move(tempPath, SettingsPath, overwrite: true);

        Current = normalized;
        LastError = string.Empty;
        SettingsChanged?.Invoke(this, Current);
    }
}
