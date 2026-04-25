using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Controls;

public sealed partial class ErrorBanner : UserControl
{
    public static readonly DependencyProperty MessageProperty =
        DependencyProperty.Register(nameof(Message), typeof(string), typeof(ErrorBanner), new PropertyMetadata(string.Empty, OnMessageChanged));

    public ErrorBanner()
    {
        InitializeComponent();
    }

    public string Message
    {
        get => (string)GetValue(MessageProperty);
        set => SetValue(MessageProperty, value);
    }

    private static void OnMessageChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        var control = (ErrorBanner)d;
        var message = e.NewValue as string ?? string.Empty;
        control.Info.Message = message;
        control.Info.IsOpen = !string.IsNullOrWhiteSpace(message);
    }
}
