using CommunityToolkit.Mvvm.ComponentModel;
using CodexFlowWindows.Data.Models;

namespace CodexFlowWindows.Data.Repository;

public sealed partial class DashboardState : ObservableObject
{
    private DashboardResponse _dashboard = DashboardResponse.Empty;
    private bool _isLoading;
    private string _errorMessage = string.Empty;

    public DashboardResponse Dashboard
    {
        get => _dashboard;
        set => SetProperty(ref _dashboard, value);
    }

    public bool IsLoading
    {
        get => _isLoading;
        set => SetProperty(ref _isLoading, value);
    }

    public string ErrorMessage
    {
        get => _errorMessage;
        set => SetProperty(ref _errorMessage, value);
    }
}
