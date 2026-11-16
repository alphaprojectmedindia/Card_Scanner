# Render Environment Variables Reference – Digital Share API

This document details all environment variables required to deploy and run the Digital Share ASP.NET Core 8 backend on Render.

---

## 1. Environment Variable Summary

| Variable Name | Required | Default / Recommended | Sensitive? | Description |
| :--- | :---: | :--- | :---: | :--- |
| `ASPNETCORE_ENVIRONMENT` | **Yes** | `Production` | No | Enables production optimizations and disables Swagger / stack trace leaks. |
| `PORT` | Auto | `10000` | No | Injected automatically by Render. Application binds dynamically to `0.0.0.0:$PORT`. |
| `DATABASE_URL` | **Yes** | *Linked from Database* | **Yes** | PostgreSQL connection URI provided by Render (e.g. `postgresql://user:pass@host:5432/dbname`). Automatically parsed by `Program.cs`. |
| `ConnectionStrings__DefaultConnection` | Optional | *(Leave empty if using `DATABASE_URL`)* | **Yes** | Standard Npgsql key-value connection string. Used as fallback if `DATABASE_URL` is absent. |
| `Jwt__Issuer` | **Yes** | `DigitalShare.Api` | No | Token issuer claim validated against JWT bearer tokens. |
| `Jwt__Audience` | **Yes** | `DigitalShare.MobileApp` | No | Token audience claim validated against incoming mobile tokens. |
| `Jwt__SecretKey` | **Yes** | *(Auto-generated 256-bit key)* | **Yes** | HMAC-SHA256 signature key. Must be at least 32 characters (256 bits). Fails fast on startup if missing. |
| `Jwt__ExpiryMinutes` | No | `60` | No | Access token expiration duration in minutes (default: 1 hour). |
| `Jwt__RefreshTokenExpiryDays` | No | `30` | No | Refresh token lifespan stored in PostgreSQL (default: 30 days). |
| `Gemini__ApiKey` | **Yes** | *(Your Google AI Studio Key)* | **Yes** | Google Gemini API Key for card multimodal analysis. Never exposed to mobile client. |
| `Gemini__ModelId` | No | `gemini-3.8-flash` | No | Primary Gemini multimodal model used for business card interpretation. |
| `Gemini__FallbackModelId` | No | `gemini-3.5-flash-lite` | No | Fallback model if primary model experiences rate limits or timeouts. |
| `Gemini__Enabled` | No | `true` | No | Master toggle for Gemini AI card interpretation. |
| `Gemini__TimeoutSeconds` | No | `8` | No | Request timeout before falling back to local OCR parsing. |
| `Gemini__MaxRetries` | No | `2` | No | Bounded retries for transient 429/503 errors. |
| `Storage__Provider` | **Yes** | `Local` (or `R2`) | No | Set to `Local` when using Render Persistent Disk, or `R2` when using Cloudflare R2. |
| `Storage__Local__Directory` | If Local | `uploads/temp-scans` | No | Relative path within disk mount for temporary card scans. |
| `Storage__Local__MaxFileSizeMb`| If Local | `20` | No | Maximum upload file size in megabytes. |
| `Storage__R2__AccountId` | If R2 | *(Cloudflare Account ID)* | **Yes** | Required if `Storage__Provider=R2`. |
| `Storage__R2__AccessKeyId` | If R2 | *(Cloudflare R2 Access Key)*| **Yes** | S3-compatible Access Key. |
| `Storage__R2__SecretAccessKey`| If R2 | *(Cloudflare R2 Secret)* | **Yes** | S3-compatible Secret Key. |
| `Storage__R2__BucketName` | If R2 | `digitalshare-scans-dev` | No | Cloudflare R2 bucket name. |
| `Storage__R2__ServiceUrl` | If R2 | `https://<AccountId>.r2.cloudflarestorage.com` | No | Cloudflare R2 S3 endpoint URL. |

---

## 2. Setting Up in the Render Dashboard

### 2.1 Automatically via `render.yaml` Blueprint

When creating a new Blueprint instance in Render from your repository:
1. Render provisions the PostgreSQL database `digital-share-db`.
2. Render automatically injects `DATABASE_URL` linking the database to `digital-share-api`.
3. Render automatically generates a cryptographically secure random `Jwt__SecretKey`.
4. The dashboard prompts you for only two secrets:
   - `Gemini__ApiKey`: Enter your Google AI Studio API key.
   - `Storage__Provider`: Default is `Local` with persistent disk.

### 2.2 Manual Web Service Configuration

If creating the Web Service manually via **New + -> Web Service**:

1. Under **Environment Variables**, click **Add Environment Variable** and enter:

```env
ASPNETCORE_ENVIRONMENT=Production
DATABASE_URL=postgresql://digital_share_user:password@dpg-xxxx.singapore-postgres.render.com/digital_share_db
Jwt__Issuer=DigitalShare.Api
Jwt__Audience=DigitalShare.MobileApp
Jwt__SecretKey=REPLACE_WITH_SECURE_256_BIT_SECRET_AT_LEAST_32_CHARS_LONG
Jwt__ExpiryMinutes=60
Jwt__RefreshTokenExpiryDays=30
Gemini__ApiKey=AIzaSy...
Gemini__ModelId=gemini-3.8-flash
Gemini__FallbackModelId=gemini-3.5-flash-lite
Gemini__Enabled=true
Gemini__TimeoutSeconds=8
Gemini__MaxRetries=2
Storage__Provider=Local
Storage__Local__Directory=uploads/temp-scans
Storage__Local__MaxFileSizeMb=20
```

2. Generate a secure `Jwt__SecretKey` on your terminal if needed:
```bash
openssl rand -base64 32
# Example output: eF3Zq/R2o8X+9z6b4sW...
```

---

## 3. Persistent Disk Configuration

Because profile photos are saved to `/app/uploads/profile-photos`, attach a Persistent Disk to ensure photos survive redeployments:

- **Disk Name**: `digital-share-uploads`
- **Mount Path**: `/app/uploads`
- **Size**: `1 GB` (or `5 GB` depending on expected volume)

In `render.yaml`, this is preconfigured as:
```yaml
disk:
  name: digital-share-uploads
  mountPath: /app/uploads
  sizeGB: 1
```

---

## 4. Verification Check

Once environment variables are saved and the service deploys:
1. Probe the health check:
   ```bash
   curl -i https://<your-render-subdomain>.onrender.com/health
   # Expected response: HTTP/1.1 200 OK  (Healthy)
   ```
2. Check deployment logs:
   - Verify `Now listening on: http://0.0.0.0:10000`
   - Verify no JWT startup exceptions or database connection errors.

