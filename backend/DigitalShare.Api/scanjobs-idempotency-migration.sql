START TRANSACTION;


DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    ALTER TABLE "ImportedBusinessCards" ADD "ClientRequestId" character varying(64);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    ALTER TABLE "ImportedBusinessCards" ADD "RequestPayloadHash" character varying(64);
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    CREATE TABLE "ScanJobs" (
        "Id" uuid NOT NULL,
        "UserId" text NOT NULL,
        "ClientJobId" character varying(64) NOT NULL,
        "Status" character varying(20) NOT NULL,
        "FrontImageStorageKey" character varying(500) NOT NULL,
        "BackImageStorageKey" character varying(500),
        "ImageSha256Checksum" character varying(64),
        "LocalOcrDraftJson" text,
        "ReconciledResultJson" text,
        "ErrorMessage" character varying(500),
        "RetryCount" integer NOT NULL,
        "WorkerInstanceId" character varying(100),
        "LockedUntilUtc" timestamp with time zone,
        "CreatedAtUtc" timestamp with time zone NOT NULL,
        "UpdatedAtUtc" timestamp with time zone NOT NULL,
        "ExpiresAtUtc" timestamp with time zone NOT NULL,
        CONSTRAINT "PK_ScanJobs" PRIMARY KEY ("Id"),
        CONSTRAINT "FK_ScanJobs_AspNetUsers_UserId" FOREIGN KEY ("UserId") REFERENCES "AspNetUsers" ("Id") ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    CREATE UNIQUE INDEX "IX_ImportedBusinessCards_OwnerUserId_ClientRequestId" ON "ImportedBusinessCards" ("OwnerUserId", "ClientRequestId") WHERE "ClientRequestId" IS NOT NULL;
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    CREATE INDEX "IX_ScanJobs_ExpiresAtUtc" ON "ScanJobs" ("ExpiresAtUtc");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    CREATE INDEX "IX_ScanJobs_Status_LockedUntilUtc" ON "ScanJobs" ("Status", "LockedUntilUtc");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    CREATE UNIQUE INDEX "IX_ScanJobs_UserId_ClientJobId" ON "ScanJobs" ("UserId", "ClientJobId");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    CREATE INDEX "IX_ScanJobs_UserId_Status" ON "ScanJobs" ("UserId", "Status");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261029114131_AddScanJobsAndContactIdempotency') THEN
    INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
    VALUES ('20261029114131_AddScanJobsAndContactIdempotency', '8.0.11');
    END IF;
END $EF$;
COMMIT;

