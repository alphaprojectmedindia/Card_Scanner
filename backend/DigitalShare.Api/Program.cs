using System.Text;
using Amazon.Runtime;
using Amazon.S3;
using DigitalShare.Api.Configuration;
using DigitalShare.Api.Data;
using DigitalShare.Api.Middleware;
using DigitalShare.Api.Models;
using DigitalShare.Api.Services;
using DigitalShare.Api.Services.Gemini;
using DigitalShare.Api.Services.Storage;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using Npgsql;

var builder = WebApplication.CreateBuilder(args);

// Render sets the PORT environment variable (e.g. 10000). Bind to 0.0.0.0:$PORT when present.
var renderPort = Environment.GetEnvironmentVariable("PORT");
if (!string.IsNullOrWhiteSpace(renderPort))
{
    builder.WebHost.UseUrls($"http://0.0.0.0:{renderPort}");
}

// 1. Configuration
builder.Services.Configure<JwtOptions>(
    builder.Configuration.GetSection(JwtOptions.SectionName));

var jwtOptions = builder.Configuration
    .GetSection(JwtOptions.SectionName)
    .Get<JwtOptions>() ?? new JwtOptions();

// 2. Database Context (Supports standard connection strings and Render/Heroku DATABASE_URL URI format)
var connectionString = ResolvePostgreSqlConnectionString(builder.Configuration, out var dbDiagnostic);
Console.WriteLine(dbDiagnostic.ToString());
builder.Services.AddDbContext<ApplicationDbContext>(options =>
{
    options.UseNpgsql(connectionString);
});

// 3. ASP.NET Core Identity
builder.Services.AddIdentity<ApplicationUser, IdentityRole>(options =>
{
    options.Password.RequireDigit = true;
    options.Password.RequireLowercase = true;
    options.Password.RequireUppercase = true;
    options.Password.RequireNonAlphanumeric = false;
    options.Password.RequiredLength = 6;
    options.User.RequireUniqueEmail = true;
})
.AddEntityFrameworkStores<ApplicationDbContext>()
.AddDefaultTokenProviders();

// 4. JWT Bearer Authentication
var secretKey = jwtOptions.SecretKey;

if (string.IsNullOrWhiteSpace(secretKey))
{
    throw new InvalidOperationException(
        "JWT SecretKey is missing or empty. A secure secret key must be configured in 'Jwt:SecretKey' via appsettings, user secrets, or the 'Jwt__SecretKey' environment variable.");
}

if (Encoding.UTF8.GetByteCount(secretKey) < 32)
{
    throw new InvalidOperationException(
        "JWT SecretKey is too short. It must be at least 256 bits (32 bytes) for HMAC-SHA256 signing.");
}

if (builder.Environment.IsProduction())
{
    var knownInsecureDefaults = new[]
    {
        "DEVELOPMENT_ONLY_SECRET_KEY_NOT_FOR_PRODUCTION_123456789",
        "DEVELOPMENT_SECRET_KEY_FALLBACK_MIN_32_CHARS!"
    };

    if (knownInsecureDefaults.Any(d => string.Equals(d, secretKey, StringComparison.Ordinal)))
    {
        throw new InvalidOperationException(
            "The configured JWT SecretKey is a known development fallback key and cannot be used in Production. Please configure a unique, high-entropy secret key via the 'Jwt__SecretKey' environment variable.");
    }
}

var signingKey = Encoding.UTF8.GetBytes(secretKey);

builder.Services.AddAuthentication(options =>
{
    options.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
    options.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
})
.AddJwtBearer(options =>
{
    options.RequireHttpsMetadata = false; // Note: In production HTTPS is enforced at the gateway/reverse-proxy
    options.SaveToken = true;
    options.TokenValidationParameters = new TokenValidationParameters
    {
        ValidateIssuer = true,
        ValidIssuer = jwtOptions.Issuer,
        ValidateAudience = true,
        ValidAudience = jwtOptions.Audience,
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(signingKey),
        ValidateLifetime = true,
        ClockSkew = TimeSpan.Zero
    };
});

builder.Services.AddAuthorization();

// 5. Application Services (Dependency Injection)
builder.Services.AddSingleton<IShareIdGenerator, ShareIdGenerator>();
builder.Services.AddSingleton<IFileStorageService, LocalFileStorageService>();
builder.Services.AddScoped<IJwtTokenGenerator, JwtTokenGenerator>();
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddScoped<IProfileService, ProfileService>();
builder.Services.AddScoped<IShareService, ShareService>();
builder.Services.AddScoped<IConnectionService, ConnectionService>();
builder.Services.AddScoped<IImportedContactService, ImportedContactService>();
builder.Services.AddSingleton<ITimeZoneService, TimeZoneService>();
builder.Services.AddScoped<IAvailabilityService, AvailabilityService>();
builder.Services.AddScoped<IMeetingService, MeetingService>();

// 5b. Gemini AI Business Card Analysis Services
builder.Services.Configure<GeminiOptions>(
    builder.Configuration.GetSection(GeminiOptions.SectionName));
builder.Services.AddHttpClient<IGeminiCardAnalysisService, GeminiCardAnalysisService>();
builder.Services.AddSingleton<CardAnalysisSemanticValidator>();
builder.Services.AddScoped<CardAnalysisIdempotencyManager>();

// Storage configuration & temporary scan storage registration
builder.Services.Configure<StorageOptions>(
    builder.Configuration.GetSection(StorageOptions.SectionName));

var storageOptions = builder.Configuration
    .GetSection(StorageOptions.SectionName)
    .Get<StorageOptions>() ?? new StorageOptions();

if (storageOptions.Provider == StorageProvider.R2)
{
    storageOptions.R2.Validate();

    builder.Services.AddSingleton<IAmazonS3>(sp =>
    {
        var creds = new BasicAWSCredentials(
            storageOptions.R2.AccessKeyId,
            storageOptions.R2.SecretAccessKey);

        var config = new AmazonS3Config
        {
            ServiceURL = storageOptions.R2.ResolveServiceUrl(),
            ForcePathStyle = true
        };

        return new AmazonS3Client(creds, config);
    });

    builder.Services.AddSingleton<IScanImageStorageService, R2ScanImageStorageService>();
}
else
{
    if (builder.Environment.IsProduction() &&
        string.Equals(builder.Configuration[$"{StorageOptions.SectionName}:Provider"], "R2", StringComparison.OrdinalIgnoreCase))
    {
        throw new InvalidOperationException(
            "Production configuration error: Storage:Provider was set to R2 but R2 credentials or configuration failed validation.");
    }

    builder.Services.AddSingleton<IScanImageStorageService, LocalStorageScanImageStorageService>();
}

// 6. Controllers, Exception Handling, Health Checks, and Web API Setup
builder.Services.AddExceptionHandler<GlobalExceptionHandler>();
builder.Services.AddProblemDetails();
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddHealthChecks();

// 7. CORS Configuration (Configured for Flutter development / Mobile clients)
builder.Services.AddCors(options =>
{
    options.AddPolicy("MobileClientPolicy", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});

// 8. Swagger / OpenAPI Configuration with Bearer Authentication
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo
    {
        Title = "Digital Share API",
        Version = "v1",
        Description = "Digital Share Backend API - Phase 4 Contact Exchange"
    });

    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Description = "JWT Authorization header using the Bearer scheme.\n\nEnter 'Bearer' [space] and then your token in the text input below.\nExample: \"Bearer eyJhbGciOi...\"",
        Name = "Authorization",
        In = ParameterLocation.Header,
        Type = SecuritySchemeType.ApiKey,
        Scheme = "Bearer",
        BearerFormat = "JWT"
    });

    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference
                {
                    Type = ReferenceType.SecurityScheme,
                    Id = "Bearer"
                }
            },
            Array.Empty<string>()
        }
    });
});

var app = builder.Build();

// 1. Global Exception Handling (Must be first in pipeline to catch all downstream unhandled exceptions)
app.UseExceptionHandler();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI(c =>
    {
        c.SwaggerEndpoint("/swagger/v1/swagger.json", "Digital Share API v1");
    });
}

app.UseHttpsRedirection();
app.UseCors("MobileClientPolicy");

// Serve uploaded profile photos safely from the uploads directory
var uploadsDirectory = Path.Combine(app.Environment.ContentRootPath, "uploads", "profile-photos");
if (!Directory.Exists(uploadsDirectory))
{
    Directory.CreateDirectory(uploadsDirectory);
}

app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = new Microsoft.Extensions.FileProviders.PhysicalFileProvider(uploadsDirectory),
    RequestPath = "/uploads/profile-photos"
});

app.UseAuthentication();
app.UseAuthorization();

// Render and uptime monitoring health check endpoint (liveness probe)
app.MapHealthChecks("/health");

// Database readiness check endpoint: verifies PostgreSQL database connectivity and migration synchronization
app.MapGet("/health/ready", async (ApplicationDbContext db, ILogger<Program> logger) =>
{
    try
    {
        if (!db.Database.IsRelational())
        {
            return Results.Text("{\"status\":\"Healthy\",\"database\":\"InMemory\",\"schema\":\"Synchronized\"}", "application/json");
        }

        var canConnect = await db.Database.CanConnectAsync();
        if (!canConnect)
        {
            return Results.Text("{\"status\":\"Unhealthy\",\"error\":\"Cannot connect to database\"}", "application/json", statusCode: StatusCodes.Status503ServiceUnavailable);
        }

        var pendingMigrations = await db.Database.GetPendingMigrationsAsync();
        var pendingList = pendingMigrations.ToList();
        if (pendingList.Count > 0)
        {
            logger.LogWarning("Readiness check found {Count} pending migrations: {Migrations}", pendingList.Count, string.Join(", ", pendingList));
            var json = System.Text.Json.JsonSerializer.Serialize(new { status = "Unhealthy", error = "Pending database migrations not applied", pending = pendingList });
            return Results.Text(json, "application/json", statusCode: StatusCodes.Status503ServiceUnavailable);
        }

        return Results.Text("{\"status\":\"Healthy\",\"database\":\"Connected\",\"schema\":\"Synchronized\"}", "application/json");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "Readiness probe failed connecting to database.");
        return Results.Text("{\"status\":\"Unhealthy\",\"error\":\"Database connection error\"}", "application/json", statusCode: StatusCodes.Status503ServiceUnavailable);
    }
});

app.MapControllers();

// Apply pending EF Core migrations automatically on startup in production/container.
// If migrations fail, log fatal error and fail startup to prevent running with an incomplete/missing schema.
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();
    var dbContext = services.GetRequiredService<ApplicationDbContext>();

    try
    {
        logger.LogInformation("Database connection configuration diagnostic: {Diagnostic}", dbDiagnostic.ToString());

        if (dbContext.Database.IsRelational())
        {
            logger.LogInformation("Checking and applying pending database migrations...");
            dbContext.Database.Migrate();
            logger.LogInformation("Database migrations applied successfully.");
        }
        else
        {
            logger.LogInformation("Non-relational database provider detected (e.g. In-Memory test provider). Skipping relational migrations.");
        }
    }
    catch (Exception ex)
    {
        logger.LogCritical(ex, "FATAL: Database migration failed on application startup. Stopping application to prevent running with an incomplete or missing schema.");
        throw;
    }
}

app.Run();

// Exposed for WebApplicationFactory integration testing
public partial class Program
{
    /// <summary>
    /// Resolves PostgreSQL connection string from either explicit Render/Heroku/Supabase DATABASE_URL or ConnectionStrings:DefaultConnection.
    /// Priority is given to DATABASE_URL so production cloud environment variables override local development appsettings.json.
    /// Returns safe diagnostics without logging sensitive credentials.
    /// </summary>
    public static string ResolvePostgreSqlConnectionString(IConfiguration configuration)
    {
        return ResolvePostgreSqlConnectionString(configuration, out _);
    }

    /// <summary>
    /// Resolves PostgreSQL connection string with diagnostic information.
    /// </summary>
    public static string ResolvePostgreSqlConnectionString(IConfiguration configuration, out PostgreSqlConnectionDiagnostic diagnostic)
    {
        // 1. Priority 1: DATABASE_URL environment variable (Render, Supabase, Railway, Heroku)
        var databaseUrl = configuration["DATABASE_URL"] ?? Environment.GetEnvironmentVariable("DATABASE_URL");
        if (!string.IsNullOrWhiteSpace(databaseUrl))
        {
            return PostgreSqlConnectionParser.ParseToConnectionString(databaseUrl, out diagnostic);
        }

        // 2. Priority 2: Explicit ConnectionStrings:DefaultConnection
        var connectionString = configuration.GetConnectionString("DefaultConnection");
        if (!string.IsNullOrWhiteSpace(connectionString))
        {
            return PostgreSqlConnectionParser.ParseToConnectionString(connectionString, out diagnostic);
        }

        diagnostic = new PostgreSqlConnectionDiagnostic(
            Success: false,
            Scheme: string.Empty,
            Host: string.Empty,
            Port: 0,
            Database: string.Empty,
            SslMode: string.Empty,
            HasUsername: false,
            HasPassword: false,
            ErrorMessage: "No database connection string configured.");
        return string.Empty;
    }

    /// <summary>
    /// Converts a postgres:// or postgresql:// URI (as supplied by Render/Heroku/Supabase) into an Npgsql key-value connection string.
    /// Backward-compatible overload.
    /// </summary>
    public static string ConvertPostgreSqlUriToNpgsqlConnectionString(string databaseUrl)
    {
        return PostgreSqlConnectionParser.ParseToConnectionString(databaseUrl, out _);
    }
}
