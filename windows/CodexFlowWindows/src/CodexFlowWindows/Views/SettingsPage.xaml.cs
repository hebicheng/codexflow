using CodexFlowWindows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Views;

public sealed partial class SettingsPage : Page
{
    public SettingsPage()
    {
        InitializeComponent();
        DataContext = ViewModel;
        Loaded += OnLoaded;
    }

    public SettingsViewModel ViewModel => App.Services.Settings;

    public void FocusBaseUrl()
    {
        BaseUrlBox.Focus(FocusState.Programmatic);
        BaseUrlBox.SelectAll();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        if (App.Services.Shell.ConsumeBaseUrlFocusRequest())
        {
            FocusBaseUrl();
        }
    }
}
