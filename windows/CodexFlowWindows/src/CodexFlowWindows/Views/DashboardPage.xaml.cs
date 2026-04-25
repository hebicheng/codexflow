using CodexFlowWindows.Data.Models;
using CodexFlowWindows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Views;

public sealed partial class DashboardPage : Page
{
    public DashboardPage()
    {
        InitializeComponent();
        DataContext = ViewModel;
    }

    public DashboardViewModel ViewModel => App.Services.Dashboard;

    private async void NewSessionClicked(object sender, RoutedEventArgs e)
    {
        if (ShellPage.Current is not null)
        {
            await ShellPage.Current.ShowNewSessionDialogAsync();
        }
    }

    private async void SessionSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (e.AddedItems.FirstOrDefault() is SessionSummary session)
        {
            await ViewModel.SelectSessionCommand.ExecuteAsync(session);
        }
    }

    private async void SessionItemClicked(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is SessionSummary session)
        {
            await ViewModel.SelectSessionCommand.ExecuteAsync(session);
            if (ActualWidth < 820)
            {
                ShellPage.Current?.NavigateToSessionDetail();
            }
        }
    }
}
