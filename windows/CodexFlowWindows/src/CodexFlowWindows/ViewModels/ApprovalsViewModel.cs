using System.Collections.ObjectModel;
using System.Collections.Specialized;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CodexFlowWindows.Data.Models;
using CodexFlowWindows.Data.Repository;

namespace CodexFlowWindows.ViewModels;

public sealed partial class ApprovalsViewModel : ObservableObject
{
    private PendingRequestView? _selectedApproval;
    private string _replyText = string.Empty;
    private string _selectedChoice = string.Empty;

    public ApprovalsViewModel(CodexFlowRepository repository)
    {
        Repository = repository;
        ApprovalGroups = new ObservableCollection<ApprovalGroup>();
        ResolveCommand = new AsyncRelayCommand(ResolveAsync, () => SelectedApproval is not null);
        Repository.Approvals.CollectionChanged += OnApprovalsChanged;
        RebuildGroups();
    }

    public CodexFlowRepository Repository { get; }
    public ObservableCollection<ApprovalGroup> ApprovalGroups { get; }
    public IAsyncRelayCommand ResolveCommand { get; }

    public PendingRequestView? SelectedApproval
    {
        get => _selectedApproval;
        set
        {
            if (SetProperty(ref _selectedApproval, value))
            {
                SelectedChoice = value?.Choices.FirstOrDefault() ?? string.Empty;
                ReplyText = string.Empty;
                ResolveCommand.NotifyCanExecuteChanged();
            }
        }
    }

    public string ReplyText
    {
        get => _replyText;
        set => SetProperty(ref _replyText, value);
    }

    public string SelectedChoice
    {
        get => _selectedChoice;
        set => SetProperty(ref _selectedChoice, value);
    }

    public async Task ResolveAsync(PendingRequestView approval, string choice, string text = "")
    {
        SelectedApproval = approval;
        SelectedChoice = choice;
        ReplyText = text;
        await ResolveAsync();
    }

    private async Task ResolveAsync()
    {
        if (SelectedApproval is null)
        {
            return;
        }

        try
        {
            var choice = string.IsNullOrWhiteSpace(SelectedChoice)
                ? FallbackChoice(SelectedApproval.Kind)
                : SelectedChoice;
            var result = ApprovalResultBuilder.Build(SelectedApproval, choice, ReplyText);
            await Repository.ResolveApprovalAsync(SelectedApproval, result);
            SelectedApproval = null;
        }
        catch
        {
            // Repository owns the visible error state.
        }
    }

    private static string FallbackChoice(string kind) => kind switch
    {
        "permissions" => "decline",
        "userInput" => "answer",
        _ => "accept"
    };

    private void OnApprovalsChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        RebuildGroups();
    }

    private void RebuildGroups()
    {
        var groups = Repository.Approvals
            .GroupBy(approval => string.IsNullOrWhiteSpace(approval.ThreadId) ? "unknown" : approval.ThreadId)
            .OrderBy(group => group.Key)
            .Select(group => new ApprovalGroup(group.Key, group));

        ApprovalGroups.Clear();
        foreach (var group in groups)
        {
            ApprovalGroups.Add(group);
        }
    }
}

public sealed class ApprovalGroup
{
    public ApprovalGroup(string threadId, IEnumerable<PendingRequestView> approvals)
    {
        ThreadId = threadId;
        Approvals = new ObservableCollection<PendingRequestView>(approvals);
    }

    public string ThreadId { get; }
    public ObservableCollection<PendingRequestView> Approvals { get; }
    public int Count => Approvals.Count;
}
