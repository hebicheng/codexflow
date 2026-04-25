using Microsoft.UI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace CodexFlowWindows.Controls;

public sealed partial class StatusBadge : UserControl
{
    public static readonly DependencyProperty StatusProperty =
        DependencyProperty.Register(nameof(Status), typeof(string), typeof(StatusBadge), new PropertyMetadata(string.Empty, OnStatusChanged));

    public static readonly DependencyProperty WaitingProperty =
        DependencyProperty.Register(nameof(Waiting), typeof(bool), typeof(StatusBadge), new PropertyMetadata(false, OnStatusChanged));

    public static readonly DependencyProperty EndedProperty =
        DependencyProperty.Register(nameof(Ended), typeof(bool), typeof(StatusBadge), new PropertyMetadata(false, OnStatusChanged));

    public StatusBadge()
    {
        InitializeComponent();
        Update();
    }

    public string Status
    {
        get => (string)GetValue(StatusProperty);
        set => SetValue(StatusProperty, value);
    }

    public bool Waiting
    {
        get => (bool)GetValue(WaitingProperty);
        set => SetValue(WaitingProperty, value);
    }

    public bool Ended
    {
        get => (bool)GetValue(EndedProperty);
        set => SetValue(EndedProperty, value);
    }

    private static void OnStatusChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((StatusBadge)d).Update();
    }

    private void Update()
    {
        var (label, color) = Resolve(Status, Waiting, Ended);
        LabelText.Text = label;
        LabelText.Foreground = new SolidColorBrush(color);
        RootBorder.Background = new SolidColorBrush(Color.FromArgb(28, color.R, color.G, color.B));
    }

    private static (string Label, Color Color) Resolve(string status, bool waiting, bool ended)
    {
        if (ended)
        {
            return ("已结束", Colors.Gray);
        }
        if (waiting)
        {
            return ("待审批", Color.FromArgb(255, 184, 100, 34));
        }

        return status switch
        {
            "active" or "inProgress" => ("运行中", Color.FromArgb(255, 33, 150, 83)),
            "completed" or "idle" => ("已完成", Color.FromArgb(255, 28, 126, 72)),
            "failed" or "systemError" => ("失败", Color.FromArgb(255, 190, 58, 58)),
            "notLoaded" => ("未接管", Color.FromArgb(255, 53, 106, 170)),
            "" => ("未知", Colors.Gray),
            _ => (status, Colors.Gray)
        };
    }
}
