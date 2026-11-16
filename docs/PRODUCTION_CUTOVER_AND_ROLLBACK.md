# Production Cutover and Rollback Playbook – Digital Share

This document establishes the production cutover procedure and emergency rollback protocols for transitioning Digital Share from Railway to Render.

---

## 1. Cutover Overview & Strategy

The migration aims for zero data loss and minimal client interruption. Because mobile clients hold compiled backend URLs, client-side updates require a coordinated strategy:

### Dual-Run Strategy for Seamless Client Transition
1. **New Render Backend Live**: Deploy Render API and PostgreSQL. Restore full database snapshot.
2. **Reverse-Proxy Railway to Render (Grace Period)**:
   During the cutover, configure Railway or a lightweight reverse proxy on Railway to route incoming requests from existing mobile app instances directly to Render. This ensures existing mobile apps continue functioning without immediate APK updates.
3. **Publish Updated Mobile Build**: Build and release the Flutter APK pointing directly to the Render endpoint (`https://digital-share-api.onrender.com` or custom domain `https://api.digitalshare.app`).
4. **Decommission Railway**: Once analytics confirm traffic to Railway has dropped to zero, terminate Railway services.

---

## 2. Step-by-Step Production Cutover Plan

### T - 2 Hours: Pre-Cutover Checks
1. Verify Render PostgreSQL instance is online and healthy.
2. Confirm Render Web Service responds to `/health` with `HTTP 200`.
3. Confirm Gemini API key is active and has sufficient quota.
4. Prepare the final Flutter release APK configured with the Render endpoint.

### T - 30 Minutes: Data Synchronization Window
1. Temporarily enable read-only or maintenance notice if preferred.
2. Export the final database dump from Railway PostgreSQL using `pg_dump`.
3. Restore the dump into Render PostgreSQL using `pg_restore`.
4. Verify table and row counts across all 18 tables.
5. Sync any newly added profile photos from Railway's storage volume to Render persistent disk `/app/uploads/profile-photos`.

### T - 0: Traffic Cutover
1. Point your custom domain (e.g. `api.digitalshare.app`) from Railway CNAME to Render CNAME:
   - **Render Target CNAME**: `<subdomain>.onrender.com`
2. If using Railway default domain (`*.up.railway.app`):
   - Set up an HTTP proxy or redirect on Railway forwarding requests to Render.
3. Test end-to-end user workflows on Render:
   - Login / Token Refresh
   - Profile retrieval and photo loading
   - Business card scan and Gemini multimodal extraction
   - Contact exchange via QR code
   - Meeting creation and scheduling

### T + 24 Hours: Post-Cutover Monitoring
1. Monitor Render service metrics (CPU, RAM, response latency).
2. Monitor Google AI Studio / Gemini API usage dashboard for token consumption.
3. Monitor application logs for 4xx/5xx spikes.

---

## 3. Emergency Rollback Playbook

If a critical, blocking defect is discovered on Render that cannot be quickly resolved:

### Rollback Decision Criteria:
- Unresolvable database connection failures or data corruption.
- Gemini API communication failure caused by Render network egress restrictions.
- Severe persistent latency degradation impacting mobile card scanning.

### Step-by-Step Rollback Procedure:
1. **Stop Traffic to Render**:
   - Revert DNS CNAME for `api.digitalshare.app` back to Railway.
   - If Railway was forwarding, terminate the forwarder and restart the primary Railway container.
2. **Synchronize Delta Data Back to Railway** (if Render processed new transactions):
   - Run `pg_dump` on Render PostgreSQL for records created after cutover time (`CreatedAtUtc > cutover_timestamp`).
   - Insert new records into Railway PostgreSQL.
3. **Verify Railway Service Health**:
   - Check Railway logs: verify database connection restored.
   - Run mobile test to confirm scanning, auth, and photo endpoints operate normally.
4. **Notify Team & Log Incident**:
   - Document root cause in incident log before scheduling a new migration window.

---

## 4. Decommissioning Railway

Execute only after **all** of the following conditions are satisfied:
1. The Render backend has been running stably in production for at least 7 days with zero critical incidents.
2. The updated mobile app has been distributed and client traffic on Railway has dropped to 0.
3. A final cold backup of the Railway database and volume files has been downloaded and archived securely off-cloud.

### Decommissioning Steps:
1. Download final snapshot of Railway PostgreSQL.
2. Archive all profile photos from Railway storage.
3. Delete the Railway PostgreSQL service.
4. Delete the Railway Web service.
5. Remove billing subscriptions on Railway.

