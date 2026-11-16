using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using DigitalShare.Api.DTOs.Auth;
using DigitalShare.Api.DTOs.Common;
using DigitalShare.Api.DTOs.ImportedContacts;
using DigitalShare.Api.Middleware;
using DigitalShare.Api.Services;
using DigitalShare.Api.Tests.Helpers;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace DigitalShare.Api.Tests.Middleware;

public class GlobalExceptionHandlerTests : IClassFixture<CustomWebApplicationFactory>
{
    private readonly CustomWebApplicationFactory _factory;
    private readonly HttpClient _client;

    public GlobalExceptionHandlerTests(CustomWebApplicationFactory factory)
    {
        _factory = factory;
        _client = factory.CreateClient();
    }

    private async Task<string> RegisterAndGetTokenAsync()
    {
        var registerRequest = new RegisterRequest
        {
            Email = $"errortest_{Guid.NewGuid()}@example.com",
            Password = "Password123!",
            ConfirmPassword = "Password123!"
        };

        var regResponse = await _client.PostAsJsonAsync("/api/auth/register", registerRequest);
        regResponse.EnsureSuccessStatusCode();
        var auth = await regResponse.Content.ReadFromJsonAsync<AuthResponse>();
        Assert.NotNull(auth);
        return auth.Token;
    }

    [Fact]
    public async Task Unit_TryHandleAsync_WhenResponseHasStarted_ReturnsFalseWithoutOverwriting()
    {
        // Arrange
        var logger = LoggerFactory.Create(_ => { }).CreateLogger<GlobalExceptionHandler>();
        var handler = new GlobalExceptionHandler(logger);

        var context = new DefaultHttpContext();
        context.Features.Set<Microsoft.AspNetCore.Http.Features.IHttpResponseFeature>(new StartedResponseFeature());

        var exception = new InvalidOperationException("Sensitive failure message");

        // Act
        var handled = await handler.TryHandleAsync(context, exception, CancellationToken.None);

        // Assert
        Assert.False(handled);
    }

    [Fact]
    public async Task Unit_TryHandleAsync_WritesGeneric500ErrorResponseWithoutExposingSensitiveDetails()
    {
        // Arrange
        var logger = LoggerFactory.Create(_ => { }).CreateLogger<GlobalExceptionHandler>();
        var handler = new GlobalExceptionHandler(logger);

        var context = new DefaultHttpContext();
        var bodyStream = new MemoryStream();
        context.Response.Body = bodyStream;

        var exception = new InvalidOperationException(
            "FATAL_LEAK: ConnectionString='Host=prod-db;Username=admin;Password=SuperSecret123!' stack trace line 42");

        // Act
        var handled = await handler.TryHandleAsync(context, exception, CancellationToken.None);

        // Assert
        Assert.True(handled);
        Assert.Equal(StatusCodes.Status500InternalServerError, context.Response.StatusCode);
        Assert.NotNull(context.Response.ContentType);
        Assert.StartsWith("application/json", context.Response.ContentType);

        bodyStream.Seek(0, SeekOrigin.Begin);
        var rawResponse = new StreamReader(bodyStream).ReadToEnd();

        // Must contain generic client message
        Assert.Contains("An unexpected server error occurred. Please try again later.", rawResponse);

        // Must NOT leak internal exception details, credentials, or stack traces
        Assert.DoesNotContain("FATAL_LEAK", rawResponse);
        Assert.DoesNotContain("SuperSecret123!", rawResponse);
        Assert.DoesNotContain("prod-db", rawResponse);
        Assert.DoesNotContain("stack trace", rawResponse);
    }

    [Fact]
    public async Task Integration_UnhandledException_Returns500WithGenericJsonContract()
    {
        // Arrange: Build a client where IImportedContactService throws an unhandled exception with sensitive data
        var faultClient = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                var descriptor = services.SingleOrDefault(d => d.ServiceType == typeof(IImportedContactService));
                if (descriptor != null)
                {
                    services.Remove(descriptor);
                }
                services.AddScoped<IImportedContactService, ThrowingImportedContactService>();
            });
        }).CreateClient();

        var token = await RegisterAndGetTokenAsync();
        var request = new HttpRequestMessage(HttpMethod.Get, "/api/imported-contacts");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // Act
        var response = await faultClient.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.InternalServerError, response.StatusCode);
        Assert.Equal("application/json", response.Content.Headers.ContentType?.MediaType);

        var rawContent = await response.Content.ReadAsStringAsync();
        var errorResponse = await response.Content.ReadFromJsonAsync<ErrorResponse>();

        Assert.NotNull(errorResponse);
        Assert.Equal("An unexpected server error occurred. Please try again later.", errorResponse.Message);

        // Confirm zero disclosure of internal database/service internals or stack traces
        Assert.DoesNotContain("SECRET_DB_PASSWORD_XYZ", rawContent);
        Assert.DoesNotContain("ThrowingImportedContactService", rawContent);
        Assert.DoesNotContain("NpgsqlException", rawContent);
        Assert.DoesNotContain("Exception", rawContent);
    }

    [Fact]
    public async Task Integration_ExistingValidationErrors_Retain400BadRequestContract()
    {
        // Arrange
        var token = await RegisterAndGetTokenAsync();
        var request = new HttpRequestMessage(HttpMethod.Post, "/api/imported-contacts");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new SaveImportedContactRequest
        {
            FullName = new string('X', 101) // Exceeds max length of 100
        });

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Integration_ExistingAuthenticationFailures_Retain401UnauthorizedContract()
    {
        // Act: Make request without authorization header
        var response = await _client.GetAsync("/api/imported-contacts");

        // Assert
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Integration_ExistingNotFoundErrors_Retain404NotFoundContract()
    {
        // Arrange
        var token = await RegisterAndGetTokenAsync();
        var nonExistentId = Guid.NewGuid();
        var request = new HttpRequestMessage(HttpMethod.Get, $"/api/imported-contacts/{nonExistentId}");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);

        // Act
        var response = await _client.SendAsync(request);

        // Assert
        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var errorResponse = await response.Content.ReadFromJsonAsync<ErrorResponse>();
        Assert.NotNull(errorResponse);
        Assert.Equal("Imported business card not found.", errorResponse.Message);
    }

    private class ThrowingImportedContactService : IImportedContactService
    {
        public Task<CheckDuplicateResponse> CheckDuplicateAsync(string ownerUserId, CheckDuplicateRequest request)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");

        public Task<ImportedContactResponse> SaveContactAsync(string ownerUserId, SaveImportedContactRequest request)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");

        public Task<ImportedContactResponse> SaveContactAsync(string ownerUserId, SaveImportedContactRequest request, string? clientRequestId)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");

        public Task<IEnumerable<ImportedContactResponse>> GetContactsAsync(string ownerUserId)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");

        public Task<ImportedContactResponse?> GetContactByIdAsync(string ownerUserId, Guid id)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");

        public Task<ImportedContactResponse?> UpdateContactAsync(string ownerUserId, Guid id, UpdateImportedContactRequest request)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");

        public Task<bool> DeleteContactAsync(string ownerUserId, Guid id)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");

        public Task<ImportedContactResponse?> UpdateRemarkAsync(string ownerUserId, Guid id, string? remark)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");

        public Task<ImportedContactResponse?> ClearRemarkAsync(string ownerUserId, Guid id)
            => throw new InvalidOperationException("DB Failure: Server=prod-db;Password=SECRET_DB_PASSWORD_XYZ;");
    }

    private class StartedResponseFeature : Microsoft.AspNetCore.Http.Features.IHttpResponseFeature
    {
        public int StatusCode { get; set; } = 200;
        public string? ReasonPhrase { get; set; }
        public IHeaderDictionary Headers { get; set; } = new HeaderDictionary();
        public Stream Body { get; set; } = Stream.Null;
        public bool HasStarted => true;
        public void OnStarting(Func<object, Task> callback, object state) { }
        public void OnCompleted(Func<object, Task> callback, object state) { }
    }
}
