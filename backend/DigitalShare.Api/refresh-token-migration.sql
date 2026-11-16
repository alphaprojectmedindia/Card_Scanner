START TRANSACTION;


DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261021120627_AddRefreshTokens') THEN
    CREATE TABLE "RefreshTokens" (
        "Id" uuid NOT NULL,
        "UserId" text NOT NULL,
        "TokenHash" character varying(128) NOT NULL,
        "CreatedAtUtc" timestamp with time zone NOT NULL,
        "ExpiresAtUtc" timestamp with time zone NOT NULL,
        "RevokedAtUtc" timestamp with time zone,
        "ReplacedByTokenId" uuid,
        "CreatedByIp" character varying(50),
        "RevokedByIp" character varying(50),
        CONSTRAINT "PK_RefreshTokens" PRIMARY KEY ("Id"),
        CONSTRAINT "FK_RefreshTokens_AspNetUsers_UserId" FOREIGN KEY ("UserId") REFERENCES "AspNetUsers" ("Id") ON DELETE CASCADE
    );
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261021120627_AddRefreshTokens') THEN
    CREATE UNIQUE INDEX "IX_RefreshTokens_TokenHash" ON "RefreshTokens" ("TokenHash");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261021120627_AddRefreshTokens') THEN
    CREATE INDEX "IX_RefreshTokens_UserId" ON "RefreshTokens" ("UserId");
    END IF;
END $EF$;

DO $EF$
BEGIN
    IF NOT EXISTS(SELECT 1 FROM "__EFMigrationsHistory" WHERE "MigrationId" = '20261021120627_AddRefreshTokens') THEN
    INSERT INTO "__EFMigrationsHistory" ("MigrationId", "ProductVersion")
    VALUES ('20261021120627_AddRefreshTokens', '8.0.11');
    END IF;
END $EF$;
COMMIT;

