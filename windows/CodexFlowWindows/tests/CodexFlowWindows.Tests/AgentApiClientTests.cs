using System.Net;
using System.Text;
using CodexFlowWindows.Configuration;
using CodexFlowWindows.Data.Api;
using Xunit;

namespace CodexFlowWindows.Tests;

public sealed class AgentApiClientTests
{
    [Fact]
    public async Task BaseUrlJoin_DoesNotProduceDoubleSlash()
    {
        var handler = new CaptureHandler(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = Json("{\"ok\":true,\"timestamp\":\"now\"}")
        });
        var client = new AgentApiClient(new HttpClient(handler), new TestSettingsStore("http://example.test:4318/"));

        await client.HealthAsync();

        Assert.Equal("http://example.test:4318/healthz", handler.RequestUri!.ToString());
    }

    [Fact]
    public async Task Health_UsesGetWithoutBody()
    {
        var handler = new CaptureHandler(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = Json("{\"ok\":true,\"timestamp\":\"now\"}")
        });
        var client = new AgentApiClient(new HttpClient(handler), new TestSettingsStore());

        await client.HealthAsync();

        Assert.Equal(HttpMethod.Get, handler.Method);
        Assert.Null(handler.Content);
        Assert.Equal("/healthz", handler.RequestUri!.AbsolutePath);
    }

    [Fact]
    public async Task NonSuccess_ParsesErrorEnvelope()
    {
        var handler = new CaptureHandler(new HttpResponseMessage(HttpStatusCode.BadRequest)
        {
            Content = Json("{\"error\":\"bad request\"}")
        });
        var client = new AgentApiClient(new HttpClient(handler), new TestSettingsStore());

        var error = await Assert.ThrowsAsync<ApiException>(() => client.HealthAsync());

        Assert.Equal(HttpStatusCode.BadRequest, error.StatusCode);
        Assert.Equal("bad request", error.Message);
    }

    [Fact]
    public async Task EmptyPostBody_SendsEmptyJsonObject()
    {
        var handler = new CaptureHandler(new HttpResponseMessage(HttpStatusCode.OK)
        {
            Content = Json("{}")
        });
        var client = new AgentApiClient(new HttpClient(handler), new TestSettingsStore());

        await client.ResumeSessionAsync("session-1");

        Assert.Equal(HttpMethod.Post, handler.Method);
        Assert.Equal("application/json", handler.ContentType);
        Assert.Equal("{}", handler.Body);
    }

    private static StringContent Json(string json) => new(json, Encoding.UTF8, "application/json");

    private sealed class CaptureHandler : HttpMessageHandler
    {
        private readonly HttpResponseMessage _response;

        public CaptureHandler(HttpResponseMessage response)
        {
            _response = response;
        }

        public HttpMethod? Method { get; private set; }
        public Uri? RequestUri { get; private set; }
        public HttpContent? Content { get; private set; }
        public string Body { get; private set; } = string.Empty;
        public string ContentType { get; private set; } = string.Empty;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Method = request.Method;
            RequestUri = request.RequestUri;
            Content = request.Content;
            if (request.Content is not null)
            {
                Body = await request.Content.ReadAsStringAsync(cancellationToken);
                ContentType = request.Content.Headers.ContentType?.MediaType ?? string.Empty;
            }
            return _response;
        }
    }
}
