using CodexFlowWindows.Data.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Controls;

public sealed partial class StatsBar : UserControl
{
    public static readonly DependencyProperty StatsProperty =
        DependencyProperty.Register(nameof(Stats), typeof(DashboardStats), typeof(StatsBar), new PropertyMetadata(new DashboardStats(), OnChanged));

    public StatsBar()
    {
        InitializeComponent();
        Update();
    }

    public DashboardStats Stats
    {
        get => (DashboardStats)GetValue(StatsProperty);
        set => SetValue(StatsProperty, value);
    }

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((StatsBar)d).Update();
    }

    private void Update()
    {
        TotalText.Text = Stats.TotalSessions.ToString();
        LoadedText.Text = Stats.LoadedSessions.ToString();
        ActiveText.Text = Stats.ActiveSessions.ToString();
        ApprovalsText.Text = Stats.PendingApprovals.ToString();
    }
}
