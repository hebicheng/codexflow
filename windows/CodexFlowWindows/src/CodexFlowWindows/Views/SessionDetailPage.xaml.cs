using CodexFlowWindows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Views;

public sealed partial class SessionDetailPage : Page
{
    public SessionDetailPage()
    {
        InitializeComponent();
        DataContext = ViewModel;
    }

    public SessionDetailViewModel ViewModel => App.Services.SessionDetail;

    private async void EndClicked(object sender, RoutedEventArgs e)
    {
        if (await ConfirmAsync("结束会话", "结束前会中断正在运行的 turn，确认继续？"))
        {
            await ViewModel.EndCommand.ExecuteAsync(null);
        }
    }

    private async void ArchiveClicked(object sender, RoutedEventArgs e)
    {
        if (await ConfirmAsync("归档会话", "归档会从 CodexFlow 列表移除本地状态，确认继续？"))
        {
            await ViewModel.ArchiveCommand.ExecuteAsync(null);
        }
    }

    private async Task<bool> ConfirmAsync(string title, string message)
    {
        var dialog = new ContentDialog
        {
            XamlRoot = XamlRoot,
            Title = title,
            Content = message,
            PrimaryButtonText = "确认",
            CloseButtonText = "取消",
            DefaultButton = ContentDialogButton.Close
        };

        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }
}
