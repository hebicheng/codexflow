using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.ApplicationModel.DataTransfer;

namespace CodexFlowWindows.Controls;

public sealed partial class DiffViewer : UserControl
{
    public static readonly DependencyProperty DiffProperty =
        DependencyProperty.Register(nameof(Diff), typeof(string), typeof(DiffViewer), new PropertyMetadata(string.Empty, OnChanged));

    public DiffViewer()
    {
        InitializeComponent();
    }

    public string Diff
    {
        get => (string)GetValue(DiffProperty);
        set => SetValue(DiffProperty, value);
    }

    private static void OnChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((DiffViewer)d).DiffText.Text = e.NewValue as string ?? string.Empty;
    }

    private void CopyClicked(object sender, RoutedEventArgs e)
    {
        var package = new DataPackage();
        package.SetText(Diff ?? string.Empty);
        Clipboard.SetContent(package);
    }
}
