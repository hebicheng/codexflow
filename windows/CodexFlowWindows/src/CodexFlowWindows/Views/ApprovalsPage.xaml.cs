using CodexFlowWindows.Data.Models;
using CodexFlowWindows.ViewModels;
using Microsoft.UI.Xaml.Controls;

namespace CodexFlowWindows.Views;

public sealed partial class ApprovalsPage : Page
{
    public ApprovalsPage()
    {
        InitializeComponent();
        DataContext = ViewModel;
    }

    public ApprovalsViewModel ViewModel => App.Services.Approvals;

    private async void ApprovalClicked(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is not PendingRequestView approval)
        {
            return;
        }

        ViewModel.SelectedApproval = approval;
        var dialog = new ApprovalDetailDialog
        {
            XamlRoot = XamlRoot
        };
        await dialog.ShowAsync();
    }
}
