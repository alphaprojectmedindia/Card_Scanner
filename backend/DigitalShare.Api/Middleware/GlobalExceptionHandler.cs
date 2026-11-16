using System.Text.Json;
using DigitalShare.Api.DTOs.Common;
using Microsoft.AspNetCore.Diagnostics;

namespace DigitalShare.Api.Middleware;

public class GlobalExceptionHandler : IExceptionHandler
{
    private readonly ILogger<GlobalExceptionHandler> _logger;

    public GlobalExceptionHandler(ILogger<GlobalExceptionHandler> logger)
    {
        _logger = logger;
    }

    public async ValueTask<bool> TryHandleAsync(
        HttpContext httpContext,
        Exception exception,
        CancellationToken cancellationToken)
    {
        if (httpContext.Response.HasStarted)
        {
            _logger.LogWarning("Response has already started, skipping global exception handling.");
            return false;
        }

        var traceId = httpContext.TraceIdentifier;
        _logger.LogError(exception, "An unhandled exception occurred while processing the request. TraceIdentifier: {TraceId}", traceId);

        httpContext.Response.StatusCode = StatusCodes.Status500InternalServerError;
        httpContext.Response.ContentType = "application/json";

        var response = new ErrorResponse("An unexpected server error occurred. Please try again later.");
        await JsonSerializer.SerializeAsync(
            httpContext.Response.Body,
            response,
            cancellationToken: cancellationToken);

        return true;
    }
}
