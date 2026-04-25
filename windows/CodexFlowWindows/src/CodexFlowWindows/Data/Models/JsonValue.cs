using System.Globalization;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CodexFlowWindows.Data.Models;

[JsonConverter(typeof(JsonValueConverter))]
public sealed class JsonValue : IEquatable<JsonValue>
{
    private JsonValue(JsonValueKind kind, object? value)
    {
        Kind = kind;
        Value = value;
    }

    public JsonValueKind Kind { get; }
    public object? Value { get; }

    public string? StringValue => Value as string;
    public double? NumberValue => Kind == JsonValueKind.Number ? (double)Value! : null;
    public bool? BoolValue => Kind == JsonValueKind.Bool ? (bool)Value! : null;
    public IReadOnlyDictionary<string, JsonValue>? ObjectValue => Value as IReadOnlyDictionary<string, JsonValue>;
    public IReadOnlyList<JsonValue>? ArrayValue => Value as IReadOnlyList<JsonValue>;

    public static JsonValue String(string value) => new(JsonValueKind.String, value);
    public static JsonValue Number(double value) => new(JsonValueKind.Number, value);
    public static JsonValue Bool(bool value) => new(JsonValueKind.Bool, value);
    public static JsonValue Object(IReadOnlyDictionary<string, JsonValue> value) => new(JsonValueKind.Object, value);
    public static JsonValue Array(IReadOnlyList<JsonValue> value) => new(JsonValueKind.Array, value);
    public static JsonValue Null { get; } = new(JsonValueKind.Null, null);

    public static JsonValue FromJsonElement(JsonElement element)
    {
        return element.ValueKind switch
        {
            System.Text.Json.JsonValueKind.String => String(element.GetString() ?? string.Empty),
            System.Text.Json.JsonValueKind.Number => Number(element.GetDouble()),
            System.Text.Json.JsonValueKind.True => Bool(true),
            System.Text.Json.JsonValueKind.False => Bool(false),
            System.Text.Json.JsonValueKind.Null => Null,
            System.Text.Json.JsonValueKind.Undefined => Null,
            System.Text.Json.JsonValueKind.Object => Object(
                element.EnumerateObject()
                    .ToDictionary(property => property.Name, property => FromJsonElement(property.Value))),
            System.Text.Json.JsonValueKind.Array => Array(
                element.EnumerateArray()
                    .Select(FromJsonElement)
                    .ToList()),
            _ => Null
        };
    }

    public object? ToPlainObject()
    {
        return Kind switch
        {
            JsonValueKind.String => StringValue ?? string.Empty,
            JsonValueKind.Number => NumberValue ?? 0,
            JsonValueKind.Bool => BoolValue ?? false,
            JsonValueKind.Object => ObjectValue?.ToDictionary(pair => pair.Key, pair => pair.Value.ToPlainObject()),
            JsonValueKind.Array => ArrayValue?.Select(value => value.ToPlainObject()).ToList(),
            JsonValueKind.Null => null,
            _ => null
        };
    }

    public bool Equals(JsonValue? other)
    {
        if (other is null || Kind != other.Kind)
        {
            return false;
        }

        return Kind switch
        {
            JsonValueKind.String => StringValue == other.StringValue,
            JsonValueKind.Number => NumberValue == other.NumberValue,
            JsonValueKind.Bool => BoolValue == other.BoolValue,
            JsonValueKind.Null => true,
            JsonValueKind.Object => DictionariesEqual(ObjectValue, other.ObjectValue),
            JsonValueKind.Array => SequencesEqual(ArrayValue, other.ArrayValue),
            _ => false
        };
    }

    public override bool Equals(object? obj) => Equals(obj as JsonValue);

    public override int GetHashCode()
    {
        return Kind switch
        {
            JsonValueKind.String => HashCode.Combine(Kind, StringValue),
            JsonValueKind.Number => HashCode.Combine(Kind, NumberValue),
            JsonValueKind.Bool => HashCode.Combine(Kind, BoolValue),
            JsonValueKind.Object => ObjectValue?.Aggregate((int)Kind, (hash, pair) => HashCode.Combine(hash, pair.Key, pair.Value)) ?? (int)Kind,
            JsonValueKind.Array => ArrayValue?.Aggregate((int)Kind, (hash, value) => HashCode.Combine(hash, value)) ?? (int)Kind,
            _ => (int)Kind
        };
    }

    public override string ToString()
    {
        return Kind switch
        {
            JsonValueKind.String => StringValue ?? string.Empty,
            JsonValueKind.Number => (NumberValue ?? 0).ToString(CultureInfo.InvariantCulture),
            JsonValueKind.Bool => BoolValue == true ? "true" : "false",
            JsonValueKind.Null => "null",
            _ => JsonSerializer.Serialize(this, JsonOptions.Default)
        };
    }

    private static bool DictionariesEqual(
        IReadOnlyDictionary<string, JsonValue>? left,
        IReadOnlyDictionary<string, JsonValue>? right)
    {
        if (ReferenceEquals(left, right))
        {
            return true;
        }
        if (left is null || right is null || left.Count != right.Count)
        {
            return false;
        }

        foreach (var pair in left)
        {
            if (!right.TryGetValue(pair.Key, out var value) || !pair.Value.Equals(value))
            {
                return false;
            }
        }
        return true;
    }

    private static bool SequencesEqual(IReadOnlyList<JsonValue>? left, IReadOnlyList<JsonValue>? right)
    {
        if (ReferenceEquals(left, right))
        {
            return true;
        }
        if (left is null || right is null || left.Count != right.Count)
        {
            return false;
        }

        for (var i = 0; i < left.Count; i++)
        {
            if (!left[i].Equals(right[i]))
            {
                return false;
            }
        }
        return true;
    }
}

public enum JsonValueKind
{
    String,
    Number,
    Bool,
    Object,
    Array,
    Null
}

public sealed class JsonValueConverter : JsonConverter<JsonValue>
{
    public override JsonValue Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options)
    {
        using var document = JsonDocument.ParseValue(ref reader);
        return JsonValue.FromJsonElement(document.RootElement);
    }

    public override void Write(Utf8JsonWriter writer, JsonValue value, JsonSerializerOptions options)
    {
        switch (value.Kind)
        {
            case JsonValueKind.String:
                writer.WriteStringValue(value.StringValue);
                break;
            case JsonValueKind.Number:
                writer.WriteNumberValue(value.NumberValue ?? 0);
                break;
            case JsonValueKind.Bool:
                writer.WriteBooleanValue(value.BoolValue ?? false);
                break;
            case JsonValueKind.Object:
                writer.WriteStartObject();
                foreach (var pair in value.ObjectValue ?? new Dictionary<string, JsonValue>())
                {
                    writer.WritePropertyName(pair.Key);
                    Write(writer, pair.Value, options);
                }
                writer.WriteEndObject();
                break;
            case JsonValueKind.Array:
                writer.WriteStartArray();
                foreach (var item in value.ArrayValue ?? Array.Empty<JsonValue>())
                {
                    Write(writer, item, options);
                }
                writer.WriteEndArray();
                break;
            case JsonValueKind.Null:
            default:
                writer.WriteNullValue();
                break;
        }
    }
}
