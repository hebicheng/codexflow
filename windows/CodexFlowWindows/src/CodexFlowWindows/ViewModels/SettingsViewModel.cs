using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CodexFlowWindows.Configuration;
using CodexFlowWindows.Data.Repository;

namespace CodexFlowWindows.ViewModels;

public sealed partial class SettingsViewModel : ObservableObject
{
    private readonly ISettingsStore _settingsStore;
    private string _baseUrl;
    private string _testResult = string.Empty;

    public SettingsViewModel(CodexFlowRepository repository, ISettingsStore settingsStore)
    {
        Repository = repository;
        _settingsStore = settingsStore;
        _baseUrl = _settingsStore.Current.AgentBaseUrl;
        SaveCommand = new AsyncRelayCommand(SaveAsync);
        TestConnectionCommand = new AsyncRelayCommand(TestConnectionAsync);
        ResetCommand = new RelayCommand(Reset);
    }

    public CodexFlowRepository Repository { get; }
    public IAsyncRelayCommand SaveCommand { get; }
    public IAsyncRelayCommand TestConnectionCommand { get; }
    public IRelayCommand ResetCommand { get; }

    public string BaseUrl
    {
        get => _baseUrl;
        set => SetProperty(ref _baseUrl, value);
    }

    public string TestResult
    {
        get => _testResult;
        set => SetProperty(ref _testResult, value);
    }

    private async Task SaveAsync()
    {
        try
        {
            await _settingsStore.SaveAsync(_settingsStore.Current.WithBaseUrl(BaseUrl));
            TestResult = "已保存";
        }
        catch (Exception ex)
        {
            TestResult = ex.Message;
            Repository.ReportError(ex.Message);
        }
    }

    private async Task TestConnectionAsync()
    {
        try
        {
            var health = await Repository.TestConnectionAsync(BaseUrl);
            TestResult = health.Ok ? $"连接成功：{health.Timestamp}" : "Agent 返回非健康状态";
        }
        catch (Exception ex)
        {
            TestResult = ex.Message;
            Repository.ReportError(ex.Message);
        }
    }

    private void Reset()
    {
        BaseUrl = AppSettings.DefaultAgentBaseUrl;
        TestResult = "已恢复默认值，点击保存后生效";
    }
}
