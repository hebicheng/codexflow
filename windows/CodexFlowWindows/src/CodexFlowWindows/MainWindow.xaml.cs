using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Windows.Foundation;
using Windows.System;

namespace CodexFlowWindows;

public sealed partial class MainWindow : Window
{
    public MainWindow()
    {
        InitializeComponent();
        Title = "CodexFlow";
        Closed += OnClosed;
        RegisterKeyboardShortcuts();
    }

    private void RegisterKeyboardShortcuts()
    {
        AddAccelerator(VirtualKey.R, VirtualKeyModifiers.Control, async (_, args) =>
        {
            args.Handled = true;
            try
            {
                await App.Services.Repository.RefreshAsync();
            }
            catch
            {
                // Repository publishes the visible error state.
            }
        });

        AddAccelerator(VirtualKey.L, VirtualKeyModifiers.Control, (_, args) =>
        {
            args.Handled = true;
            Shell.NavigateToSettings(focusBaseUrl: true);
        });

        AddAccelerator(VirtualKey.N, VirtualKeyModifiers.Control, async (_, args) =>
        {
            args.Handled = true;
            await Shell.ShowNewSessionDialogAsync();
        });

        AddAccelerator(VirtualKey.Escape, VirtualKeyModifiers.None, (_, args) =>
        {
            args.Handled = Shell.TryCloseTransientUi();
        });
    }

    private void AddAccelerator(
        VirtualKey key,
        VirtualKeyModifiers modifiers,
        TypedEventHandler<KeyboardAccelerator, KeyboardAcceleratorInvokedEventArgs> handler)
    {
        var accelerator = new KeyboardAccelerator { Key = key, Modifiers = modifiers };
        accelerator.Invoked += handler;
        KeyboardAccelerators.Add(accelerator);
    }

    private void OnClosed(object sender, WindowEventArgs args)
    {
        App.Services.Repository.Dispose();
    }
}
