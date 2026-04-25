using CodexFlowWindows.Configuration;
using Xunit;

namespace CodexFlowWindows.Tests;

public sealed class SettingsStoreTests
{
    [Fact]
    public void MissingSettings_UsesDefaultBaseUrl()
    {
        using var directory = new TempDirectory();
        var store = new SettingsStore(directory.Path);

        var settings = store.Load();

        Assert.Equal(AppSettings.DefaultAgentBaseUrl, settings.AgentBaseUrl);
    }

    [Fact]
    public async Task SavesAndReadsBaseUrl()
    {
        using var directory = new TempDirectory();
        var store = new SettingsStore(directory.Path);

        await store.SaveAsync(new AppSettings { AgentBaseUrl = "http://192.168.1.10:4318" });
        var loaded = new SettingsStore(directory.Path).Load();

        Assert.Equal("http://192.168.1.10:4318", loaded.AgentBaseUrl);
    }

    [Fact]
    public void CorruptSettings_FallsBackToDefault()
    {
        using var directory = new TempDirectory();
        Directory.CreateDirectory(directory.Path);
        File.WriteAllText(System.IO.Path.Combine(directory.Path, "settings.json"), "{not-json");
        var store = new SettingsStore(directory.Path);

        var settings = store.Load();

        Assert.Equal(AppSettings.DefaultAgentBaseUrl, settings.AgentBaseUrl);
        Assert.NotEmpty(store.LastError);
    }

    private sealed class TempDirectory : IDisposable
    {
        public TempDirectory()
        {
            Path = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "codexflow-tests-" + Guid.NewGuid().ToString("N"));
        }

        public string Path { get; }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
