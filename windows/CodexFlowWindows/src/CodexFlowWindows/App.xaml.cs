using Microsoft.UI.Xaml;

namespace CodexFlowWindows;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
        UnhandledException += OnUnhandledException;
    }

    public static AppServices Services { get; private set; } = null!;

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Services = AppServices.Create();
        _window = new MainWindow();
        _window.Activate();
        _ = Services.Repository.InitializeAsync();
    }

    private void OnUnhandledException(object sender, Microsoft.UI.Xaml.UnhandledExceptionEventArgs e)
    {
        if (Services is not null)
        {
            Services.Repository.ReportError(e.Exception.Message);
        }
        e.Handled = true;
    }
}
