using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Controls;

public sealed partial class LoadingOverlay : UserControl
{
    public static readonly DependencyProperty IsLoadingProperty =
        DependencyProperty.Register(nameof(IsLoading), typeof(bool), typeof(LoadingOverlay), new PropertyMetadata(false, OnChanged));

    public LoadingOverlay()
    {
        InitializeComponent();
    }

    public bool IsLoading
    {
        get => (bool)GetValue(IsLoadingProperty);
        set => SetValue(IsLoadingProperty, value);
    }

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((LoadingOverlay)d).Visibility = (bool)e.NewValue ? Visibility.Visible : Visibility.Collapsed;
    }
}
