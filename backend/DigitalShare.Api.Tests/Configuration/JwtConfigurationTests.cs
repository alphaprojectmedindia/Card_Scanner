using DigitalShare.Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Xunit;

namespace DigitalShare.Api.Tests.Configuration;

public class JwtConfigurationTests
{
    private WebApplicationFactory<Program> CreateFactory(string environment, string? secretKey)
    {
        return new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment(environment);
                builder.UseSetting("Jwt:SecretKey", secretKey ?? "");
                builder.ConfigureServices(services =>
                {
                    var descriptors = services.Where(d =>
                        d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>) ||
                        d.ServiceType == typeof(DbContextOptions)).ToList();

                    foreach (var descriptor in descriptors)
                    {
                        services.Remove(descriptor);
                    }

                    services.AddDbContext<ApplicationDbContext>(options =>
                    {
                        options.UseInMemoryDatabase("JwtConfigTestDb_" + Guid.NewGuid());
                    });
                });
            });
    }

    [Fact]
    public void Startup_InProduction_WithMissingSecret_ThrowsInvalidOperationException()
    {
        using var factory = CreateFactory("Production", "");
        var ex = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());
        Assert.Contains("missing or empty", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Startup_InProduction_WithShortSecret_ThrowsInvalidOperationException()
    {
        using var factory = CreateFactory("Production", "short-secret-less-than-32-chars");
        var ex = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());
        Assert.Contains("too short", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Startup_InProduction_WithKnownDevelopmentFallback_ThrowsInvalidOperationException()
    {
        using var factory = CreateFactory("Production", "DEVELOPMENT_ONLY_SECRET_KEY_NOT_FOR_PRODUCTION_123456789");
        var ex = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());
        Assert.Contains("known development fallback", ex.Message, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Startup_InProduction_WithValidSecret_StartsSuccessfully()
    {
        using var factory = CreateFactory("Production", "AValidProductionSecretKeyThatIsAtLeast32BytesLong!");
        var client = factory.CreateClient();
        Assert.NotNull(client);
    }

    [Fact]
    public void Startup_InDevelopment_WithConfiguredDevSecret_StartsSuccessfully()
    {
        using var factory = CreateFactory("Development", "DEVELOPMENT_ONLY_SECRET_KEY_NOT_FOR_PRODUCTION_123456789");
        var client = factory.CreateClient();
        Assert.NotNull(client);
    }
}
