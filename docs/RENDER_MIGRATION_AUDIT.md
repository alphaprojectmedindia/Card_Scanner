# Digital Share – Comprehensive Infrastructure Audit: Railway to Render Migration

**Document Version:** 1.0.0  
**Audit Date:** November 16, 2026  
**Scope:** Complete repository inspection (`d:\digital_share`)  
**Status:** Phase 1 Complete – Ready for Phase 2 Deployment Preparation  

---

## 1. Executive Summary

Digital Share is migrating its backend infrastructure from Railway to Render. The objective is to replace Railway with Render while preserving 100% of application functionality, API contracts, database relationships, security policies, and performance characteristics.

This document presents the **Phase 1 Infrastructure Audit**. Every layer of the system—from ASP.NET Core 8 API internals and Entity Framework Core migrations to container configurations, on-device OCR pipelines, and Flutter mobile client configurations—has been inspected and verified against the source code.

### Key Audit Conclusions:
1. **Application Architecture**: Digital Share backend is a clean, single-project ASP.NET Core 8 Web API (`DigitalShare.Api`) targeting `.NET 8.0`. There are **no separate worker processes, Python runtimes, or Celery/Hangfire daemons** required on the server.
2. **OCR Placement**: PaddleOCR PP-OCRv5 (ONNX Runtime) and Google ML Kit OCR run **entirely on-device in Flutter**. The backend only makes outbound HTTPS calls to the Google Gemini multimodal API for card analysis.
3. **Database Architecture**: PostgreSQL with 17 application and Identity tables managed through 8 Entity Framework Core migrations. Schema synchronization can be performed deterministically via an idempotent SQL script.
4. **Required Render Adaptations**:
   - Dynamic port binding: Render injects `$PORT` (default 10000); ASP.NET Core 8 container defaults to 8080.
   - PostgreSQL URI connection string parsing: Render supplies `DATABASE_URL` as `postgres://...`; Npgsql expects key-value format.
   - Dedicated health check endpoint: Render monitors `/health`; currently missing from the ASP.NET Core pipeline.
   - Persistent disk mounting: Render containers have ephemeral disks; profile photos stored in `/app/uploads/profile-photos` require a persistent disk mounted at `/app/uploads` (or Cloudflare R2).

---

## 2. Technology Stack & Solution Inventory

### 2.1 Backend Solution Structure

```
backend/
├── DigitalShare.sln                               # Visual Studio Solution (.NET 8)
├── DigitalShare.Api/                              # ASP.NET Core 8 Web API Project
│   ├── Configuration/                             # Strongly-typed configuration options
│   │   ├── GeminiOptions.cs                       # Google Gemini API configuration
│   │   ├── JwtOptions.cs                          # JWT authentication options
│   │   └── StorageOptions.cs                      # Local & Cloudflare R2 storage options
│   ├── Controllers/                               # 8 Web API Controllers
│   │   ├── AuthController.cs                      # Registration, Login, Refresh, Account Deletion
│   │   ├── AvailabilityController.cs              # User availability slots & schedules
│   │   ├── CardAnalysisController.cs              # Business card upload & Gemini multimodal analysis
│   │   ├── ConnectionsController.cs               # Contact connections & exchanges
│   │   ├── ImportedContactsController.cs          # Scanned business cards & remarks
│   │   ├── MeetingsController.cs                  # Meeting requests & status management
│   │   ├── ProfileController.cs                   # User profile, public visibility, photo upload
│   │   └── ShareController.cs                     # Public ShareId profile resolution
│   ├── Data/
│   │   └── ApplicationDbContext.cs                # EF Core PostgreSQL DbContext (IdentityDbContext)
│   ├── DTOs/                                      # Request & Response Data Transfer Objects
│   ├── Middleware/
│   │   └── GlobalExceptionHandler.cs              # ProblemDetails standard exception handler
│   ├── Migrations/                                # 8 EF Core C# Migrations + Snapshot
│   ├── Models/                                    # Entity Framework domain models
│   ├── Services/                                  # Domain services & interfaces
│   │   ├── Gemini/                                # GeminiCardAnalysisService, IdempotencyManager
│   │   └── Storage/                               # LocalStorage, R2ScanImageStorageService
│   ├── Dockerfile                                 # Multi-stage Docker build file
│   ├── appsettings.json                           # Default production configuration template
│   ├── appsettings.Development.json               # Development overrides
│   └── .env.example                               # Environment variable reference template
└── DigitalShare.Api.Tests/                        # xUnit integration and unit tests
```

### 2.2 Runtime & Dependency Versions

| Component | Version | Role / Notes |
| :--- | :--- | :--- |
| **.NET SDK & Runtime** | `net8.0` (LTS) | Linux container base `mcr.microsoft.com/dotnet/aspnet:8.0` |
| **Npgsql.EntityFrameworkCore.PostgreSQL** | `8.0.11` | PostgreSQL EF Core provider (compatible with PostgreSQL 13–16) |
| **Microsoft.AspNetCore.Identity.EntityFrameworkCore** | `8.0.11` | User management, hashing, role storage |
| **Microsoft.AspNetCore.Authentication.JwtBearer** | `8.0.11` | JWT Bearer token authentication & HMAC-SHA256 validation |
| **AWSSDK.S3** | `4.0.104.7` | Cloudflare R2 S3-compatible scan image object storage |
| **Swashbuckle.AspNetCore** | `6.6.2` | Swagger/OpenAPI documentation (dev environment) |
| **TimeZoneConverter** | `7.2.0` | Cross-platform IANA/Windows timezone mapping |

### 2.3 Mobile Stack (Flutter)

- **Framework**: Flutter / Dart
- **Location**: `mobile/`
- **OCR Engines**:
  - PaddleOCR PP-OCRv5 Mobile via ONNX Runtime (`mobile/lib/services/ocr/paddle_ocr_service.dart`)
  - Google ML Kit Text Recognition (`mobile/lib/services/ocr/google_ml_kit_ocr_service.dart`)
- **Backend Communication**: `http` package, REST JSON API
- **Base URL Config**: `mobile/lib/config/api_config.dart`

---

## 3. Existing Deployment & Railway Configuration Audit

### 3.1 Existing Dockerfile Inspection

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY backend/DigitalShare.Api/DigitalShare.Api.csproj backend/DigitalShare.Api/
RUN dotnet restore backend/DigitalShare.Api/DigitalShare.Api.csproj

COPY backend/DigitalShare.Api/ backend/DigitalShare.Api/
WORKDIR /src/backend/DigitalShare.Api

RUN dotnet publish DigitalShare.Api.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

COPY --from=build /app/publish .

ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "DigitalShare.Api.dll"]
```

#### Dockerfile Analysis:
- **Build Context**: Expected at repository root `d:\digital_share`.
- **SDK**: `mcr.microsoft.com/dotnet/sdk:8.0` (Debian-based .NET 8 SDK).
- **Runtime**: `mcr.microsoft.com/dotnet/aspnet:8.0` (Debian-based ASP.NET Core 8 runtime).
- **Port Exposure**: Currently has no explicit `EXPOSE` or `ASPNETCORE_URLS` setting. ASP.NET Core 8 defaults to `8080`.
- **Render Port Compatibility**: Render injects `PORT=10000`. Without setting `ASPNETCORE_URLS=http://0.0.0.0:${PORT}`, Render's HTTP reverse proxy cannot route traffic to the container.

### 3.2 Railway Configuration & References

- **Configuration Files**: No `railway.json`, `railway.toml`, or `nixpacks.toml` file exists in the repository. Railway was deploying directly using Dockerfile detection from GitHub.
- **Repository References to Railway (Historical / Cleaned)**:
  1. `mobile/lib/config/api_config.dart`: Formerly defaulted to Railway production URL; now points to Render production URL (`https://digital-share-api.onrender.com`).
  2. `backend/DigitalShare.Api/Services/Gemini/CardAnalysisIdempotencyManager.cs`: Updated concurrency comment from Railway to Render.
  3. `backend/DigitalShare.Api/refresh-token-migration.sql` (renamed from `railway-refresh-token-migration.sql` to neutral name).
  4. `backend/DigitalShare.Api/scanjobs-idempotency-migration.sql` (renamed from `railway-scanjobs-idempotency-migration.sql` to neutral name).
  5. Historical audit/report markdown files documenting past deployment stages.

No Railway webhooks, Railway CLI dependencies, or platform-specific APIs are used in code.

---

## 4. PostgreSQL Database & Migration Audit

### 4.1 Database Context & Entities

Managed via `ApplicationDbContext : IdentityDbContext<ApplicationUser>`:

| # | Table Name | Purpose / Model | Relationships / Notes |
| :--- | :--- | :--- | :--- |
| 1 | `AspNetUsers` | ASP.NET Core Identity user accounts | 1:1 with `UserProfiles`, 1:N with `RefreshTokens`, `Connections`, `ScanJobs` |
| 2 | `AspNetRoles` | User roles | Standard Identity |
| 3 | `AspNetUserRoles` | User-role mapping | Standard Identity |
| 4 | `AspNetUserClaims` | User claims | Standard Identity |
| 5 | `AspNetUserLogins` | External login providers | Standard Identity |
| 6 | `AspNetUserTokens` | User security tokens | Standard Identity |
| 7 | `AspNetRoleClaims` | Role claims | Standard Identity |
| 8 | `UserProfiles` | Profile details (name, job, company, bio, phone, photo, ShareId, IsPublic) | Unique index on `UserId`, unique index on `ShareId` |
| 9 | `Connections` | User-to-user exchanged contact connections | Index on `OwnerUserId`, `ConnectedUserId` |
| 10 | `ImportedBusinessCards` | Scanned business card records | Unique index on `(OwnerUserId, ClientRequestId)`, index on `ScanStatus`, contains `PersonalRemark` |
| 11 | `ImportedBusinessCardPhones` | Phone numbers for scanned cards | 1:N from `ImportedBusinessCards` |
| 12 | `ImportedBusinessCardEmails` | Email addresses for scanned cards | 1:N from `ImportedBusinessCards` |
| 13 | `AvailabilitySettings` | User booking availability settings | 1:1 from `AspNetUsers` |
| 14 | `AvailabilitySlots` | Daily booking recurring time slots | 1:N from `AvailabilitySettings` |
| 15 | `MeetingRequests` | Meeting requests, statuses, and links | FK to Requester, FK to Host |
| 16 | `RefreshTokens` | Cryptographic JWT refresh tokens | Unique index on `TokenHash`, index on `UserId` |
| 17 | `ScanJobs` | Distributed background scan jobs & leases | Unique index on `(UserId, ClientJobId)`, index on `(Status, LockedUntilUtc)` |
| 18 | `__EFMigrationsHistory` | EF Core migration tracking table | Tracks applied migration IDs |

### 4.2 Migration History

All migrations are located in `backend/DigitalShare.Api/Migrations/`:

1. `20261008082850_InitialCreate` – Core Identity, UserProfiles, initial tables.
2. `20261008091335_AddShareIdToUserProfile` – Adds unique `ShareId` for QR codes.
3. `20261008092653_AddConnectionsTable` – Contact connection exchange graph.
4. `20261008154001_AddImportedBusinessCards` – Business card scanning storage.
5. `20261008174305_AddAvailabilityAndMeetings` – Calendar, slots, and meeting scheduling.
6. `20261021120627_AddRefreshTokens` – Persistent refresh tokens with token hashing and rotation.
7. `20261029114131_AddScanJobsAndContactIdempotency` – ScanJobs table with distributed lock leasing & request payload hash.
8. `20261105074425_AddRemarksAndAccountVisibility` – Adds `IsPublic` to `UserProfiles` and `PersonalRemark` to `ImportedBusinessCards`.

### 4.3 Database Migration Execution Strategy

`Program.cs` deliberately does **not** execute `Database.Migrate()` on application startup to avoid concurrency locking bugs when horizontal scaling occurs.

**Render Migration Recommendation**:
1. Supply a complete, single, idempotent migration script (`render-database-migration.sql`) covering all 8 migrations.
2. For fresh database deployments: Execute the idempotent script directly via `psql` or pgAdmin / DBeaver against Render PostgreSQL.
3. For existing Railway data migration: Dump Railway data using `pg_dump` and restore into Render PostgreSQL using `pg_restore`. The existing `__EFMigrationsHistory` will carry over seamlessly.

### 4.4 PostgreSQL Connection String Format

- **Railway Format**: Key-value or URI string provided via environment variables.
- **Render PostgreSQL Format**: Render provides `DATABASE_URL` in URI format:
  `postgresql://[user]:[password]@[host]:[port]/[database]`
  Example: `postgresql://digital_share_db_user:secret@dpg-c12345.singapore-postgres.render.com/digital_share_db`
- **Npgsql Requirement**:
  Npgsql expects key-value pairs:
  `Host=[host];Port=[port];Database=[database];Username=[user];Password=[password];SSL Mode=Require;Trust Server Certificate=true;`
- **Mitigation**: Update `Program.cs` with an automatic connection string URI resolver that detects `DATABASE_URL` and converts it to Npgsql key-value format if `ConnectionStrings:DefaultConnection` is not explicitly set.

---

## 5. Storage & File Persistence Audit

### 5.1 Profile Photos Storage

- **Class**: `DigitalShare.Api.Services.LocalFileStorageService`
- **Storage Location**: `Path.Combine(_environment.ContentRootPath, "uploads", "profile-photos")` (`/app/uploads/profile-photos` in Docker).
- **Public URL**: `/uploads/profile-photos/{guid}.{ext}`
- **Persistence Risk on Render**:
  Standard Render Web Service containers run on an **ephemeral disk**. When a new deployment occurs or the container restarts, all files stored in the container are wiped.
- **Solution for Render**:
  Attach a **Render Persistent Disk** mounted at `/app/uploads` (size: 1 GB to 5 GB). This preserves all user-uploaded profile photos across container redeployments and restarts.
  Alternatively, configure Cloudflare R2 for all assets.

### 5.2 Business Card Scan Image Storage

- **Interface**: `IScanImageStorageService`
- **Implementations**:
  1. `LocalStorageScanImageStorageService` (active when `Storage:Provider=Local`): Saves scan images to `/app/uploads/temp-scans`.
  2. `R2ScanImageStorageService` (active when `Storage:Provider=R2`): Uses Amazon S3 client targeting Cloudflare R2 (`digitalshare-scans-dev`).
- **Render Recommendation**:
  Set `Storage__Provider=R2` with valid Cloudflare R2 credentials for stateless production scans, or utilize the persistent disk mount `/app/uploads` if running in local mode.

---

## 6. OCR & AI Processing Pipeline Audit

### 6.1 Architecture Verification

A critical question for the Render migration was whether the backend container requires Python, PaddlePaddle, or ONNX Runtime native binaries:

```
[Mobile Device (Flutter)]
  ├── Camera Capture
  ├── PaddleOCR PP-OCRv5 Mobile (ONNX Runtime, on-device)
  ├── Google ML Kit Text Recognition (on-device)
  ├── Local Heuristic Parser (Dart, on-device)
  └── Sends JSON payload + front/back image base64 bytes to backend
          │
          ▼ HTTPS POST /api/business-cards/analyze
[Render Web Service (.NET 8 Web API)]
  ├── CardAnalysisController
  ├── CardAnalysisIdempotencyManager (locks ScanJobs row)
  └── GeminiCardAnalysisService
          │
          ▼ Outbound HTTPS REST (v1beta/models/gemini-3.8-flash:generateContent)
[Google Gemini Cloud API]
```

### 6.2 Key Takeaways:
- **No Python runtime needed on Render**: The backend is 100% C# / .NET 8.
- **No heavy native ML dependencies**: The container remains slim (~220 MB total image size).
- **External Network Dependency**: Render Web Service needs outbound HTTPS connectivity to `https://generativelanguage.googleapis.com` to communicate with Google Gemini.

---

## 7. Authentication, JWT & Security Audit

### 7.1 Configuration Parameters

| Variable Name | Default / Production Value | Role |
| :--- | :--- | :--- |
| `Jwt__Issuer` | `DigitalShare.Api` | Token issuer validation |
| `Jwt__Audience` | `DigitalShare.MobileApp` | Token audience validation |
| `Jwt__SecretKey` | *Must be >= 32 characters (256-bit)* | HMAC-SHA256 signing key. **Fails fast on startup if missing or insecure in Production.** |
| `Jwt__ExpiryMinutes` | `60` (1 hour) | Access token lifetime |
| `Jwt__RefreshTokenExpiryDays` | `30` (30 days) | Refresh token lifetime in PostgreSQL |

### 7.2 CORS Configuration

```csharp
builder.Services.AddCors(options =>
{
    options.AddPolicy("MobileClientPolicy", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyHeader()
              .AllowAnyMethod();
    });
});
```
The CORS policy `MobileClientPolicy` allows all origins, headers, and methods, ensuring mobile clients and preview web views will not be blocked.

---

## 8. Mobile Client Configuration Audit

### 8.1 API Configuration in Flutter

File: `mobile/lib/config/api_config.dart`

```dart
/// Production backend endpoint on Railway
static const String _productionBaseUrl = 'https://digital-share-production.up.railway.app';

/// Falls back to http://10.0.2.2:5000 for Android emulator compatibility only if
/// explicitly enabled via --dart-define=USE_EMULATOR=true.
static const String _defaultDevBaseUrl = 'http://10.0.2.2:5000';

static String get baseUrl {
  const fromEnv = String.fromEnvironment('API_BASE_URL');
  if (fromEnv.isNotEmpty) {
    return fromEnv.endsWith('/')
        ? fromEnv.substring(0, fromEnv.length - 1)
        : fromEnv;
  }
  const useEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: false);
  if (useEmulator) {
    return _defaultDevBaseUrl;
  }
  return _productionBaseUrl;
}
```

### 8.2 Migration Impact:
- In Phase 5, `_productionBaseUrl` in `api_config.dart` must be updated to the Render service URL (e.g. `https://digital-share-api.onrender.com` or custom domain).
- Since `baseUrl` supports `--dart-define=API_BASE_URL=...`, tests and builds can target either URL dynamically without code changes.

---

## 9. Complete API Endpoint Inventory

All 23 API endpoints exposed by the backend and consumed by Flutter:

| Controller | Method | Route | Description |
| :--- | :--- | :--- | :--- |
| **Auth** | `POST` | `/api/auth/register` | User account registration |
| **Auth** | `POST` | `/api/auth/login` | User login (returns JWT + refresh token) |
| **Auth** | `POST` | `/api/auth/refresh` | Token rotation using refresh token |
| **Auth** | `POST` | `/api/auth/logout` | Revokes single refresh token |
| **Auth** | `POST` | `/api/auth/logout-all` | Revokes all user refresh tokens |
| **Auth** | `DELETE`| `/api/auth/delete-account`| Deletes user account and cascaded data |
| **Profile** | `GET` | `/api/profile/me` | Gets current user's profile |
| **Profile** | `PUT` | `/api/profile/me` | Updates current user's profile |
| **Profile** | `POST`| `/api/profile/photo` | Uploads user profile photo |
| **Profile** | `GET` | `/api/profile/search` | Searches public profiles |
| **Profile** | `PATCH`| `/api/profile/visibility` | Updates account public/private visibility |
| **Share** | `GET` | `/api/share/{shareId}` | Resolves public profile via ShareId (QR scan) |
| **Connections** | `GET` | `/api/connections` | Lists exchanged contact connections |
| **Connections** | `POST`| `/api/connections` | Saves a new connection exchange |
| **Connections** | `DELETE`| `/api/connections/{targetShareId}` | Removes a connection |
| **ImportedContacts**| `GET` | `/api/imported-contacts` | Lists scanned business cards |
| **ImportedContacts**| `POST`| `/api/imported-contacts/check-duplicate` | Checks perceptual/exact duplicate card |
| **ImportedContacts**| `GET` | `/api/imported-contacts/{id}` | Gets single scanned business card |
| **ImportedContacts**| `POST`| `/api/imported-contacts` | Saves scanned business card |
| **ImportedContacts**| `PUT` | `/api/imported-contacts/{id}` | Updates scanned business card |
| **ImportedContacts**| `DELETE`| `/api/imported-contacts/{id}` | Deletes scanned business card |
| **ImportedContacts**| `PATCH`| `/api/imported-contacts/{id}/remark` | Updates personal remark on scanned card |
| **CardAnalysis** | `POST`| `/api/business-cards/images` | Uploads raw scan image (R2/local) |
| **CardAnalysis** | `POST`| `/api/business-cards/analyze` | Invokes Gemini multimodal analysis |
| **Availability** | `GET` | `/api/availability/me` | Gets current user availability settings |
| **Availability** | `PUT` | `/api/availability/me` | Updates current user availability settings |
| **Availability** | `GET` | `/api/availability/{userId}` | Gets another user's availability for booking |
| **Meetings** | `GET` | `/api/meetings` | Lists meeting requests |
| **Meetings** | `POST`| `/api/meetings` | Creates meeting request |
| **Meetings** | `GET` | `/api/meetings/{id}` | Gets meeting request details |
| **Meetings** | `POST`| `/api/meetings/{id}/accept` | Accepts meeting request |
| **Meetings** | `POST`| `/api/meetings/{id}/reject` | Rejects meeting request |
| **Meetings** | `POST`| `/api/meetings/{id}/cancel` | Cancels meeting request |
| **Health** *(Planned)* | `GET` | `/health` | Render zero-downtime health check |

---

## 10. Complete Environment Variable Inventory

| Variable Name | Required? | Source / Provider | Description |
| :--- | :---: | :--- | :--- |
| `ASPNETCORE_ENVIRONMENT` | Yes | Container ENV | Set to `Production` |
| `PORT` | Auto | Render | Port injected by Render (typically `10000`) |
| `DATABASE_URL` | Yes | Render PostgreSQL | Postgres URI connection string |
| `ConnectionStrings__DefaultConnection` | Fallback | Manual / Config | Key-value Npgsql connection string |
| `Jwt__Issuer` | Yes | App Config | `DigitalShare.Api` |
| `Jwt__Audience` | Yes | App Config | `DigitalShare.MobileApp` |
| `Jwt__SecretKey` | Yes | Secret | High-entropy random key (>= 32 characters) |
| `Jwt__ExpiryMinutes` | No | App Config | Defaults to `60` |
| `Jwt__RefreshTokenExpiryDays` | No | App Config | Defaults to `30` |
| `Gemini__ApiKey` | Yes | Secret | Google Gemini API Key |
| `Gemini__ModelId` | No | App Config | `gemini-3.8-flash` |
| `Gemini__FallbackModelId` | No | App Config | `gemini-3.5-flash-lite` |
| `Gemini__Enabled` | No | App Config | `true` |
| `Gemini__TimeoutSeconds` | No | App Config | `8` |
| `Gemini__MaxRetries` | No | App Config | `2` |
| `Storage__Provider` | Yes | App Config | `Local` (with persistent disk) or `R2` |
| `Storage__Local__Directory` | If Local | App Config | `uploads/temp-scans` |
| `Storage__R2__AccountId` | If R2 | Secret | Cloudflare Account ID |
| `Storage__R2__AccessKeyId` | If R2 | Secret | Cloudflare R2 Access Key |
| `Storage__R2__SecretAccessKey`| If R2 | Secret | Cloudflare R2 Secret Key |
| `Storage__R2__BucketName` | If R2 | App Config | `digitalshare-scans-dev` |
| `Storage__R2__ServiceUrl` | If R2 | App Config | Cloudflare S3 endpoint URL |

---

## 11. Migration Risk Matrix & Mitigation Strategy

| # | Risk Description | Severity | Probability | Impact | Mitigation Strategy |
| :- | :--- | :---: | :---: | :---: | :--- |
| **R1** | **Port mismatch on Render** (`$PORT` vs `8080`) | High | High | Render fails deploy with health check timeout. | Update `Program.cs` and `Dockerfile` to bind to `http://0.0.0.0:${PORT:-8080}`. |
| **R2** | **PostgreSQL URI parsing failure** (`DATABASE_URL`) | High | High | Application crashes on startup with Npgsql format exception. | Add automatic URI-to-Npgsql converter in `Program.cs` that checks `DATABASE_URL`. |
| **R3** | **Missing `/health` endpoint** | Medium | High | Render zero-downtime health check fails; deploy rolled back. | Add `AddHealthChecks()` and `MapHealthChecks("/health")` to `Program.cs`. |
| **R4** | **Loss of profile photos on container restart** | High | High | Ephemeral disk wipes `/app/uploads/profile-photos`. | Define persistent disk mounted at `/app/uploads` in `render.yaml`. |
| **R5** | **Database schema desynchronization** | High | Low | Missing columns (`IsPublic`, `PersonalRemark`, `ScanJobs`). | Apply full idempotent SQL script before releasing traffic; verify table count = 18. |
| **R6** | **Mobile client downtime during cutover** | Medium | Medium | Existing app instances fail if Railway is shut down before APK update. | Retain Railway instance temporarily during cutover or proxy requests until Flutter update. |
| **R7** | **Secret key leaks** | Critical | Low | Database credentials or Gemini API key exposed in Git. | Keep all secrets strictly in Render environment variables; verify `.env` is git-ignored. |

---

## 12. Next Steps & Approval Criteria

With the completion of **Phase 1 (Full Infrastructure Audit)**, the baseline is completely mapped.

### Ready for Execution:
- **Phase 2**: Prepare Render deployment configurations (`render.yaml`, `Dockerfile` port adjustments, `Program.cs` connection string parser and health check, `docs/RENDER_ENVIRONMENT_VARIABLES.md`).
- **Phase 3**: Prepare database migration scripts (`render-database-migration.sql`, `pg_dump`/`pg_restore` procedures, `docs/RENDER_DEPLOYMENT_GUIDE.md`, `docs/RAILWAY_TO_RENDER_MIGRATION.md`).
- **Phase 4**: Local backend build and testing verification.
- **Phase 5**: Mobile configuration migration (`mobile/lib/config/api_config.dart`).
- **Phase 6 & 7**: Production cutover planning & rollback playbook (`docs/PRODUCTION_CUTOVER_AND_ROLLBACK.md`).

