using System.Collections.ObjectModel;
using CodexFlowWindows.Data.Models;

namespace CodexFlowWindows.ViewModels;

public sealed class SessionGroup
{
    public SessionGroup(string title, IEnumerable<SessionSummary> sessions)
    {
        Title = title;
        Sessions = new ObservableCollection<SessionSummary>(sessions);
    }

    public string Title { get; }
    public ObservableCollection<SessionSummary> Sessions { get; }
    public int Count => Sessions.Count;
}
