using CodexFlowWindows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Views;

public sealed partial class ShellPage : Page
{
    public ShellPage()
    {
        InitializeComponent();
        DataContext = ViewModel;
        Current = this;
        Loaded += OnLoaded;
    }

    public static ShellPage? Current { get; private set; }
    public ShellViewModel ViewModel => App.Services.Shell;

    public void NavigateToSettings(bool focusBaseUrl = false)
    {
        if (focusBaseUrl)
        {
            ViewModel.RequestBaseUrlFocus();
        }
        Navigate("Settings");
    }

    public void NavigateToSessionDetail()
    {
        Navigate("SessionDetail");
    }

    public async Task ShowNewSessionDialogAsync()
    {
        App.Services.NewSession.Reset();
        var dialog = new NewSessionDialog
        {
            XamlRoot = XamlRoot
        };
        await dialog.ShowAsync();
    }

    public bool TryCloseTransientUi()
    {
        return false;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (ContentFrame.Content is null)
        {
            Navigate("Dashboard");
        }
    }

    private void NavigationSelectionChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (args.SelectedItem is NavigationViewItem item && item.Tag is string tag)
        {
            Navigate(tag);
        }
    }

    private void Navigate(string tag)
    {
        ViewModel.SelectedPage = tag;
        switch (tag)
        {
            case "Dashboard":
            case "Sessions":
                ContentFrame.Navigate(typeof(DashboardPage));
                break;
            case "SessionDetail":
                ContentFrame.Navigate(typeof(SessionDetailPage));
                break;
            case "Approvals":
                ContentFrame.Navigate(typeof(ApprovalsPage));
                break;
            case "Settings":
                ContentFrame.Navigate(typeof(SettingsPage));
                break;
        }
    }
}
