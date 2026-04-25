using CodexFlowWindows.Data.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Controls;

public sealed partial class SessionCard : UserControl
{
    public static readonly DependencyProperty SessionProperty =
        DependencyProperty.Register(nameof(Session), typeof(SessionSummary), typeof(SessionCard), new PropertyMetadata(null, OnChanged));

    public SessionCard()
    {
        InitializeComponent();
    }

    public SessionSummary? Session
    {
        get => (SessionSummary?)GetValue(SessionProperty);
        set => SetValue(SessionProperty, value);
    }

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((SessionCard)d).Update();
    }

    private void Update()
    {
        var session = Session;
        if (session is null)
        {
            return;
        }

        NameText.Text = session.DisplayName;
        CwdText.Text = session.Cwd;
        PreviewText.Text = session.PreviewExcerpt;
        BranchText.Text = string.IsNullOrWhiteSpace(session.Branch) ? "分支 未识别" : $"分支 {session.Branch}";
        UpdatedText.Text = $"更新 {session.UpdatedAtDisplay}";
        ApprovalText.Text = session.PendingApprovals > 0 ? $"待审批 {session.PendingApprovals}" : string.Empty;
        SourceText.Text = $"来源 {session.Source} · 模型 {session.ModelProvider}";
        Badge.Status = session.IsRunningTurn ? "inProgress" : session.Status;
        Badge.Waiting = session.HasWaitingState;
        Badge.Ended = session.Ended;
    }
}
