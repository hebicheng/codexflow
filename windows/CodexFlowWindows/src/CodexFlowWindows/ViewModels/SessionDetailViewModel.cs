using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CodexFlowWindows.Data.Models;
using CodexFlowWindows.Data.Repository;

namespace CodexFlowWindows.ViewModels;

public sealed partial class SessionDetailViewModel : ObservableObject
{
    private string _prompt = string.Empty;

    public SessionDetailViewModel(CodexFlowRepository repository)
    {
        Repository = repository;
        SubmitPromptCommand = new AsyncRelayCommand(SubmitPromptAsync, CanSubmitPrompt);
        InterruptCommand = new AsyncRelayCommand(InterruptAsync, () => CurrentSession?.IsRunningTurn == true);
        ResumeCommand = new AsyncRelayCommand(ResumeAsync, () => CurrentSession is not null);
        EndCommand = new AsyncRelayCommand(EndAsync, () => CurrentSession is not null);
        ArchiveCommand = new AsyncRelayCommand(ArchiveAsync, () => CurrentSession is not null);
        RefreshCommand = new AsyncRelayCommand(RefreshAsync, () => !string.IsNullOrWhiteSpace(Repository.CurrentSession.SelectedSessionId));

        Repository.CurrentSession.PropertyChanged += OnSessionStateChanged;
        Repository.PropertyChanged += OnRepositoryChanged;
    }

    public CodexFlowRepository Repository { get; }
    public IAsyncRelayCommand SubmitPromptCommand { get; }
    public IAsyncRelayCommand InterruptCommand { get; }
    public IAsyncRelayCommand ResumeCommand { get; }
    public IAsyncRelayCommand EndCommand { get; }
    public IAsyncRelayCommand ArchiveCommand { get; }
    public IAsyncRelayCommand RefreshCommand { get; }

    public string Prompt
    {
        get => _prompt;
        set
        {
            if (SetProperty(ref _prompt, value))
            {
                SubmitPromptCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public SessionDetail? Detail => Repository.CurrentSession.Detail;

    public SessionSummary? CurrentSession =>
        Detail?.Summary ??
        Repository.Sessions.FirstOrDefault(session => session.Id == Repository.CurrentSession.SelectedSessionId);

    public string ComposerButtonText => CurrentSession?.IsRunningTurn == true ? "Steer 当前 turn" : "继续下一步";
    public bool HasSelectedSession => CurrentSession is not null;

    private bool CanSubmitPrompt() => CurrentSession is not null && !string.IsNullOrWhiteSpace(Prompt);

    private async Task SubmitPromptAsync()
    {
        var session = CurrentSession;
        if (session is null)
        {
            return;
        }

        try
        {
            await Repository.SubmitPromptAsync(session, Prompt);
            Prompt = string.Empty;
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private async Task InterruptAsync()
    {
        var session = CurrentSession;
        if (session is null)
        {
            return;
        }

        try
        {
            await Repository.InterruptAsync(session);
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private async Task ResumeAsync()
    {
        var session = CurrentSession;
        if (session is null)
        {
            return;
        }

        try
        {
            await Repository.ResumeSessionAsync(session.Id);
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private async Task EndAsync()
    {
        var session = CurrentSession;
        if (session is null)
        {
            return;
        }

        try
        {
            await Repository.EndSessionAsync(session.Id);
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private async Task ArchiveAsync()
    {
        var session = CurrentSession;
        if (session is null)
        {
            return;
        }

        try
        {
            await Repository.ArchiveSessionAsync(session.Id);
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private async Task RefreshAsync()
    {
        try
        {
            await Repository.RefreshAsync();
            if (!string.IsNullOrWhiteSpace(Repository.CurrentSession.SelectedSessionId))
            {
                await Repository.LoadSessionAsync(Repository.CurrentSession.SelectedSessionId);
            }
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private void OnSessionStateChanged(object? sender, PropertyChangedEventArgs e)
    {
        NotifyAll();
    }

    private void OnRepositoryChanged(object? sender, PropertyChangedEventArgs e)
    {
        NotifyAll();
    }

    private void NotifyAll()
    {
        OnPropertyChanged(nameof(Detail));
        OnPropertyChanged(nameof(CurrentSession));
        OnPropertyChanged(nameof(ComposerButtonText));
        OnPropertyChanged(nameof(HasSelectedSession));
        SubmitPromptCommand.NotifyCanExecuteChanged();
        InterruptCommand.NotifyCanExecuteChanged();
        ResumeCommand.NotifyCanExecuteChanged();
        EndCommand.NotifyCanExecuteChanged();
        ArchiveCommand.NotifyCanExecuteChanged();
        RefreshCommand.NotifyCanExecuteChanged();
    }
}
