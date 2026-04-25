using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CodexFlowWindows.Data.Models;
using CodexFlowWindows.Data.Repository;

namespace CodexFlowWindows.ViewModels;

public sealed partial class DashboardViewModel : ObservableObject
{
    public DashboardViewModel(CodexFlowRepository repository)
    {
        Repository = repository;
        SessionGroups = new ObservableCollection<SessionGroup>();
        RefreshCommand = new AsyncRelayCommand(RefreshAsync);
        SelectSessionCommand = new AsyncRelayCommand<SessionSummary>(SelectSessionAsync);
        ResumeSessionCommand = new AsyncRelayCommand<SessionSummary>(ResumeSessionAsync);

        Repository.Sessions.CollectionChanged += OnSessionsChanged;
        Repository.Dashboard.PropertyChanged += OnRepositoryPropertyChanged;
        RebuildGroups();
    }

    public CodexFlowRepository Repository { get; }
    public ObservableCollection<SessionGroup> SessionGroups { get; }
    public IAsyncRelayCommand RefreshCommand { get; }
    public IAsyncRelayCommand<SessionSummary> SelectSessionCommand { get; }
    public IAsyncRelayCommand<SessionSummary> ResumeSessionCommand { get; }

    public DashboardStats Stats => Repository.Dashboard.Dashboard.Stats;
    public AgentSnapshot Agent => Repository.Dashboard.Dashboard.Agent;

    private async Task RefreshAsync()
    {
        try
        {
            await Repository.RefreshAsync();
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private async Task SelectSessionAsync(SessionSummary? session)
    {
        if (session is null)
        {
            return;
        }

        try
        {
            await Repository.LoadSessionAsync(session.Id);
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private async Task ResumeSessionAsync(SessionSummary? session)
    {
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

    private void OnSessionsChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        RebuildGroups();
    }

    private void OnRepositoryPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        OnPropertyChanged(nameof(Stats));
        OnPropertyChanged(nameof(Agent));
    }

    private void RebuildGroups()
    {
        var sessions = Repository.Sessions.ToList();
        var groups = new[]
        {
            new SessionGroup("运行中", sessions.Where(session => !session.Ended && session.PendingApprovals == 0 && session.LastTurnStatus == "inProgress")),
            new SessionGroup("待审批", sessions.Where(session => !session.Ended && session.PendingApprovals > 0)),
            new SessionGroup("已接管", sessions.Where(session => !session.Ended && session.Loaded && session.LastTurnStatus != "inProgress" && session.PendingApprovals == 0)),
            new SessionGroup("历史", sessions.Where(session => !session.Ended && !session.Loaded && session.PendingApprovals == 0)),
            new SessionGroup("已结束", sessions.Where(session => session.Ended))
        }.Where(group => group.Count > 0);

        SessionGroups.Clear();
        foreach (var group in groups)
        {
            SessionGroups.Add(group);
        }
    }
}
