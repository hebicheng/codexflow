using CodexFlowWindows.ViewModels;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Views;

public sealed partial class ApprovalDetailDialog : ContentDialog
{
    public ApprovalDetailDialog()
    {
        InitializeComponent();
        DataContext = ViewModel;
    }

    public ApprovalsViewModel ViewModel => App.Services.Approvals;

    private async void PrimaryClicked(ContentDialog sender, ContentDialogButtonClickEventArgs args)
    {
        var deferral = args.GetDeferral();
        try
        {
            await ViewModel.ResolveCommand.ExecuteAsync(null);
        }
        finally
        {
            deferral.Complete();
        }
    }
}
