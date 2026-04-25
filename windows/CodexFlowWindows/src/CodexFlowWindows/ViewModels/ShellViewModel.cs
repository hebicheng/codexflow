using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CodexFlowWindows.Configuration;
using CodexFlowWindows.Data.Repository;

namespace CodexFlowWindows.ViewModels;

public sealed partial class ShellViewModel : ObservableObject
{
    private readonly ISettingsStore _settingsStore;
    private string _selectedPage = "Dashboard";
    private bool _focusBaseUrlRequested;

    public ShellViewModel(CodexFlowRepository repository, ISettingsStore settingsStore)
    {
        Repository = repository;
        _settingsStore = settingsStore;
        RefreshCommand = new AsyncRelayCommand(RefreshAsync);

        Repository.PropertyChanged += OnRepositoryPropertyChanged;
        Repository.Dashboard.PropertyChanged += OnRepositoryPropertyChanged;
    }

    public CodexFlowRepository Repository { get; }
    public IAsyncRelayCommand RefreshCommand { get; }

    public string SelectedPage
    {
        get => _selectedPage;
        set => SetProperty(ref _selectedPage, value);
    }

    public string AgentBaseUrl => _settingsStore.Current.AgentBaseUrl;
    public int PendingApprovals => Repository.Dashboard.Dashboard.Stats.PendingApprovals;
    public string HealthText => Repository.IsAgentHealthy ? "在线" : "离线";
    public string SseText => Repository.SseState.ToString();

    public bool ConsumeBaseUrlFocusRequest()
    {
        if (!_focusBaseUrlRequested)
        {
            return false;
        }
        _focusBaseUrlRequested = false;
        return true;
    }

    public void RequestBaseUrlFocus()
    {
        _focusBaseUrlRequested = true;
    }

    private async Task RefreshAsync()
    {
        try
        {
            await Repository.RefreshAsync();
        }
        catch
        {
            // Repository publishes the visible error message.
        }
    }

    private void OnRepositoryPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        OnPropertyChanged(nameof(AgentBaseUrl));
        OnPropertyChanged(nameof(PendingApprovals));
        OnPropertyChanged(nameof(HealthText));
        OnPropertyChanged(nameof(SseText));
    }
}
