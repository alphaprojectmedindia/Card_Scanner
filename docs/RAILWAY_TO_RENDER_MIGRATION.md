# Railway to Render Migration Guide – Digital Share

This document details the operational procedure for migrating production data, media files, and services from Railway to Render with zero data loss.

---

## 1. Migration Architecture & Workflow

```
[Railway Production]                                        [Render Production]
  ├── Railway PostgreSQL   --- (pg_dump / pg_restore) --->    ├── Render PostgreSQL (digital-share-db)
  └── Uploads Volume       --- (File Archive Download) -->    └── Render Persistent Disk (/app/uploads)
```

### Pre-requisites
1. PostgreSQL client tools (`pg_dump` and `pg_restore`) installed locally (PostgreSQL 14, 15, or 16).
2. Railway project credentials (host, port, user, password, database).
3. Render PostgreSQL credentials (**External Database URL**).
4. Terminal access to execute migration commands.

---

## 2. Step 1: Database Migration (Zero Data Loss)

### 2.1 Put Application in Maintenance Mode (Recommended)
To ensure no new data is written to Railway while taking the dump:
1. In the Railway dashboard, set the Web service replicas to 0, or briefly stop the service.

### 2.2 Export Database from Railway (`pg_dump`)
Run `pg_dump` against Railway PostgreSQL in custom archive format (`-F c`):

```bash
pg_dump \
  -h <RAILWAY_PG_HOST> \
  -p <RAILWAY_PG_PORT> \
  -U <RAILWAY_PG_USER> \
  -d <RAILWAY_PG_DB> \
  -F c \
  -b \
  -v \
  -f digital_share_production.dump
```
*Note: When prompted, enter your Railway database password.*

### 2.3 Restore Database to Render (`pg_restore`)
Restore the archive into your fresh Render PostgreSQL database:

```bash
pg_restore \
  -h <RENDER_PG_HOST> \
  -p 5432 \
  -U <RENDER_PG_USER> \
  -d <RENDER_PG_DB> \
  -v \
  --no-owner \
  --no-privileges \
  --clean \
  --if-exists \
  digital_share_production.dump
```
*Note: `--no-owner` and `--no-privileges` ensure objects are restored cleanly under the Render database user without permission conflicts.*

### 2.4 Verify Database Integrity
Run verification queries on Render PostgreSQL:

```sql
-- Check total number of tables (should be 18)
SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';

-- Check record counts
SELECT 'AspNetUsers' AS tbl, count(*) FROM "AspNetUsers"
UNION ALL
SELECT 'UserProfiles', count(*) FROM "UserProfiles"
UNION ALL
SELECT 'ImportedBusinessCards', count(*) FROM "ImportedBusinessCards"
UNION ALL
SELECT 'Connections', count(*) FROM "Connections"
UNION ALL
SELECT 'ScanJobs', count(*) FROM "ScanJobs"
UNION ALL
SELECT 'RefreshTokens', count(*) FROM "RefreshTokens"
UNION ALL
SELECT '__EFMigrationsHistory', count(*) FROM "__EFMigrationsHistory";
```
Compare these counts with Railway to confirm 100% data parity.

---

## 3. Step 2: Uploaded Media Migration (Profile Photos)

If user profile photos were stored locally on a Railway volume in `uploads/profile-photos`:

### 3.1 Extract Files from Railway
Using the Railway CLI or dashboard:
```bash
# Via Railway CLI into the container volume
railway run tar -czvf profile_photos.tar.gz uploads/profile-photos
railway volume download uploads profile_photos_backup/
```

### 3.2 Upload Files to Render Persistent Disk
Render allows accessing container volumes via SSH (available on Starter and higher plans) or via Render's web shell:
1. Open the **Shell** tab on the `digital-share-api` service in the Render dashboard.
2. Verify mount:
   ```bash
   df -h /app/uploads
   ```
3. Transfer the archive and extract:
   ```bash
   tar -xzvf profile_photos.tar.gz -C /app/uploads/
   ```
4. Verify files are accessible:
   ```bash
   ls -la /app/uploads/profile-photos
   ```

*Note: If Cloudflare R2 was used (`Storage__Provider=R2`), scan images and files already reside in R2 and require no data movement.*

---

## 4. Step 3: Service Startup & Health Verification

1. Start the Render Web Service `digital-share-api`.
2. Inspect the live logs in the Render Dashboard to ensure the service started cleanly and connected to the database.
3. Test the health endpoint:
   ```bash
   curl -i https://<RENDER_SUBDOMAIN>.onrender.com/health
   # Expected: HTTP 200 OK
   ```
4. Test photo serving:
   ```bash
   curl -i https://<RENDER_SUBDOMAIN>.onrender.com/uploads/profile-photos/<known-photo-id>.jpg
   # Expected: HTTP 200 OK with Content-Type: image/jpeg
   ```

---

## 5. Verification Checklist

- [ ] PostgreSQL dump created without errors.
- [ ] Render database restored with matching row counts across all 18 tables.
- [ ] `__EFMigrationsHistory` verified with all 8 migrations present.
- [ ] Uploaded profile photos transferred to `/app/uploads/profile-photos`.
- [ ] Render Web Service deployed and reporting `Live`.
- [ ] `/health` endpoint returning 200 OK.
- [ ] Google Gemini API integration verified via test business card scan.

