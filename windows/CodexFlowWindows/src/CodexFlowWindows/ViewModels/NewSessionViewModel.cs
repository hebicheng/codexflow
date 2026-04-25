using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CodexFlowWindows.Data.Repository;

namespace CodexFlowWindows.ViewModels;

public sealed partial class NewSessionViewModel : ObservableObject
{
    private string _cwd = string.Empty;
    private string _prompt = string.Empty;
    private string _errorMessage = string.Empty;

    public NewSessionViewModel(CodexFlowRepository repository)
    {
        Repository = repository;
        CreateCommand = new AsyncRelayCommand(CreateAsync, CanCreate);
    }

    public CodexFlowRepository Repository { get; }
    public IAsyncRelayCommand CreateCommand { get; }

    public string Cwd
    {
        get => _cwd;
        set
        {
            if (SetProperty(ref _cwd, value))
            {
                CreateCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string Prompt
    {
        get => _prompt;
        set
        {
            if (SetProperty(ref _prompt, value))
            {
                CreateCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string ErrorMessage
    {
        get => _errorMessage;
        private set => SetProperty(ref _errorMessage, value);
    }

    public void Reset()
    {
        Cwd = string.Empty;
        Prompt = string.Empty;
        ErrorMessage = string.Empty;
    }

    private bool CanCreate() =>
        IsAbsolutePath(Cwd.Trim()) && !string.IsNullOrWhiteSpace(Prompt);

    private async Task CreateAsync()
    {
        if (!CanCreate())
        {
            ErrorMessage = "工作目录必须是绝对路径，首轮 prompt 不能为空。";
            return;
        }

        try
        {
            ErrorMessage = string.Empty;
            await Repository.StartSessionAsync(Cwd, Prompt);
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
    }

    private static bool IsAbsolutePath(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }

        return Path.IsPathRooted(value) ||
               value.StartsWith('/') ||
               value.StartsWith(@"\\", StringComparison.Ordinal);
    }
}
