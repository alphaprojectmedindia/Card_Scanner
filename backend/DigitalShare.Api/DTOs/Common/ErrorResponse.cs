namespace DigitalShare.Api.DTOs.Common;

public class ErrorResponse
{
    public string Message { get; set; } = string.Empty;
    public IDictionary<string, string[]>? Errors { get; set; }

    public ErrorResponse()
    {
    }

    public ErrorResponse(string message)
    {
        Message = message;
    }

    public ErrorResponse(string message, IDictionary<string, string[]> errors)
    {
        Message = message;
        Errors = errors;
    }
}
