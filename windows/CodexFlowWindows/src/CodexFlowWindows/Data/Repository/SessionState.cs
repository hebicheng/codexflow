using CommunityToolkit.Mvvm.ComponentModel;
using CodexFlowWindows.Data.Models;

namespace CodexFlowWindows.Data.Repository;

public sealed partial class SessionState : ObservableObject
{
    private string _selectedSessionId = string.Empty;
    private SessionDetail? _detail;
    private bool _isLoading;
    private string _errorMessage = string.Empty;

    public string SelectedSessionId
    {
        get => _selectedSessionId;
        set => SetProperty(ref _selectedSessionId, value);
    }

    public SessionDetail? Detail
    {
        get => _detail;
        set => SetProperty(ref _detail, value);
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
