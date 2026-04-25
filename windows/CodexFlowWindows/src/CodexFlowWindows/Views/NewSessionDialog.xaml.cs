using CodexFlowWindows.ViewModels;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Views;

public sealed partial class NewSessionDialog : ContentDialog
{
    public NewSessionDialog()
    {
        InitializeComponent();
        DataContext = ViewModel;
    }

    public NewSessionViewModel ViewModel => App.Services.NewSession;

    private async void PrimaryClicked(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            await ViewModel.CreateCommand.ExecuteAsync(null);
            args.Cancel = !string.IsNullOrWhiteSpace(ViewModel.ErrorMessage);
        }
        finally
        {
            deferral.Complete();
        }
    }
}
