using System.Net.Http;
using CodexFlowWindows.Configuration;
using CodexFlowWindows.Data.Api;
using CodexFlowWindows.Data.Repository;
using CodexFlowWindows.ViewModels;

namespace CodexFlowWindows;

public sealed class AppServices
{
    private AppServices(
        SettingsStore settingsStore,
        IAgentApiClient apiClient,
        SseClient sseClient,
        CodexFlowRepository repository,
        ShellViewModel shell,
        DashboardViewModel dashboard,
        SessionDetailViewModel sessionDetail,
        ApprovalsViewModel approvals,
        SettingsViewModel settings,
        NewSessionViewModel newSession)
    {
        SettingsStore = settingsStore;
        ApiClient = apiClient;
        SseClient = sseClient;
        Repository = repository;
        Shell = shell;
        Dashboard = dashboard;
        SessionDetail = sessionDetail;
        Approvals = approvals;
        Settings = settings;
        NewSession = newSession;
    }

    public SettingsStore SettingsStore { get; }
    public IAgentApiClient ApiClient { get; }
    public SseClient SseClient { get; }
    public CodexFlowRepository Repository { get; }
    public ShellViewModel Shell { get; }
    public DashboardViewModel Dashboard { get; }
    public SessionDetailViewModel SessionDetail { get; }
    public ApprovalsViewModel Approvals { get; }
    public SettingsViewModel Settings { get; }
    public NewSessionViewModel NewSession { get; }

    public static AppServices Create()
    {
        var settingsStore = new SettingsStore();
        settingsStore.Load();

        var apiHttpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(35)
        };
        var sseHttpClient = new HttpClient
        {
            Timeout = Timeout.InfiniteTimeSpan
        };

        var apiClient = new AgentApiClient(apiHttpClient, settingsStore);
        var sseClient = new SseClient(sseHttpClient, settingsStore);
        var repository = new CodexFlowRepository(apiClient, sseClient, settingsStore);

        var shell = new ShellViewModel(repository, settingsStore);
        var dashboard = new DashboardViewModel(repository);
        var sessionDetail = new SessionDetailViewModel(repository);
        var approvals = new ApprovalsViewModel(repository);
        var settings = new SettingsViewModel(repository, settingsStore);
        var newSession = new NewSessionViewModel(repository);

        return new AppServices(
            settingsStore,
            apiClient,
            sseClient,
            repository,
            shell,
            dashboard,
            sessionDetail,
            approvals,
            settings,
            newSession);
    }
}
