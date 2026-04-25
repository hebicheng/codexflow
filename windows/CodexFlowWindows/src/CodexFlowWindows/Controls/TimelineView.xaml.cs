using CodexFlowWindows.Data.Models;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Controls;

public sealed partial class TimelineView : UserControl
{
    public static readonly DependencyProperty ItemsProperty =
        DependencyProperty.Register(nameof(Items), typeof(IEnumerable<TurnItem>), typeof(TimelineView), new PropertyMetadata(Array.Empty<TurnItem>(), OnChanged));

    public TimelineView()
    {
        InitializeComponent();
    }

    public IEnumerable<TurnItem> Items
    {
        get => (IEnumerable<TurnItem>)GetValue(ItemsProperty);
        set => SetValue(ItemsProperty, value);
    }

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((TimelineView)d).TimelineItems.ItemsSource = e.NewValue;
    }
}
