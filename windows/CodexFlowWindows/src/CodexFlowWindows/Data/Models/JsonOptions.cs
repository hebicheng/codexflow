using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodexFlowWindows.Data.Models;

public static class JsonOptions
{
    public static JsonSerializerOptions Default { get; } = Create();

    private static JsonSerializerOptions Create()
    {
        var options = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
            WriteIndented = false
        };
        options.Converters.Add(new JsonValueConverter());
        return options;
    }
}
