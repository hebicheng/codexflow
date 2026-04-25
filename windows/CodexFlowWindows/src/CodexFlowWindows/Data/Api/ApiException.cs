using System.Net;

namespace CodexFlowWindows.Data.Api;

public sealed class ApiException : Exception
{
    public ApiException(HttpStatusCode? statusCode, string message, string? responseBody = null, Exception? innerException = null)
        : base(message, innerException)
    {
        StatusCode = statusCode;
        ResponseBody = responseBody;
    }

    public HttpStatusCode? StatusCode { get; }
    public string? ResponseBody { get; }
}
