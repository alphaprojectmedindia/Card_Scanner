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
var connectionString = ResolvePostgreSqlConnectionString(builder.Configuration);
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

// Render and uptime monitoring health check endpoint
app.MapHealthChecks("/health");

app.MapControllers();

app.Run();

// Exposed for WebApplicationFactory integration testing
public partial class Program
{
    /// <summary>
    /// Resolves PostgreSQL connection string from either explicit DefaultConnection or Render/Heroku DATABASE_URL.
    /// </summary>
    public static string ResolvePostgreSqlConnectionString(IConfiguration configuration)
    {
        // 1. Check explicit DefaultConnection
        var explicitConnection = configuration.GetConnectionString("DefaultConnection");
        if (!string.IsNullOrWhiteSpace(explicitConnection) &&
            !explicitConnection.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase) &&
            !explicitConnection.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
        {
            return explicitConnection;
        }

        // 2. Check DATABASE_URL or URI-formatted DefaultConnection
        var rawUrl = !string.IsNullOrWhiteSpace(explicitConnection)
            ? explicitConnection
            : configuration["DATABASE_URL"] ?? Environment.GetEnvironmentVariable("DATABASE_URL");

        if (!string.IsNullOrWhiteSpace(rawUrl) &&
            (rawUrl.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase) ||
             rawUrl.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase)))
        {
            return ConvertPostgreSqlUriToNpgsqlConnectionString(rawUrl);
        }

        return explicitConnection ?? string.Empty;
    }

    /// <summary>
    /// Converts a postgres:// or postgresql:// URI (as supplied by Render/Heroku) into an Npgsql key-value connection string.
    /// </summary>
    public static string ConvertPostgreSqlUriToNpgsqlConnectionString(string databaseUrl)
    {
        var uri = new Uri(databaseUrl);
        var userInfo = uri.UserInfo.Split(':', 2);
        var username = Uri.UnescapeDataString(userInfo[0]);
        var password = userInfo.Length > 1 ? Uri.UnescapeDataString(userInfo[1]) : string.Empty;
        var database = uri.AbsolutePath.TrimStart('/');
        var host = uri.Host;
        var port = uri.Port > 0 ? uri.Port : 5432;

        var builder = new NpgsqlConnectionStringBuilder
        {
            Host = host,
            Port = port,
            Database = database,
            Username = username,
            Password = password,
            SslMode = SslMode.Prefer
        };

        return builder.ConnectionString;
    }
}
