CREATE TABLE IF NOT EXISTS `__EFMigrationsHistory` (
    `MigrationId` varchar(150) CHARACTER SET utf8mb4 NOT NULL,
    `ProductVersion` varchar(32) CHARACTER SET utf8mb4 NOT NULL,
    CONSTRAINT `PK___EFMigrationsHistory` PRIMARY KEY (`MigrationId`)
) CHARACTER SET=utf8mb4;

START TRANSACTION;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    ALTER DATABASE CHARACTER SET utf8mb4;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AspNetRoles` (
        `Id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `Name` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `NormalizedName` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `ConcurrencyStamp` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        CONSTRAINT `PK_AspNetRoles` PRIMARY KEY (`Id`)
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AspNetUsers` (
        `Id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `UserName` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `NormalizedUserName` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Email` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `NormalizedEmail` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `EmailConfirmed` tinyint(1) NOT NULL,
        `PasswordHash` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `SecurityStamp` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `ConcurrencyStamp` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `PhoneNumber` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `PhoneNumberConfirmed` tinyint(1) NOT NULL,
        `TwoFactorEnabled` tinyint(1) NOT NULL,
        `LockoutEnd` datetime(6) NULL,
        `LockoutEnabled` tinyint(1) NOT NULL,
        `AccessFailedCount` int NOT NULL,
        CONSTRAINT `PK_AspNetUsers` PRIMARY KEY (`Id`)
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AspNetRoleClaims` (
        `Id` int NOT NULL AUTO_INCREMENT,
        `RoleId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `ClaimType` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `ClaimValue` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        CONSTRAINT `PK_AspNetRoleClaims` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_AspNetRoleClaims_AspNetRoles_RoleId` FOREIGN KEY (`RoleId`) REFERENCES `AspNetRoles` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AspNetUserClaims` (
        `Id` int NOT NULL AUTO_INCREMENT,
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `ClaimType` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `ClaimValue` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        CONSTRAINT `PK_AspNetUserClaims` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_AspNetUserClaims_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AspNetUserLogins` (
        `LoginProvider` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `ProviderKey` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `ProviderDisplayName` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        CONSTRAINT `PK_AspNetUserLogins` PRIMARY KEY (`LoginProvider`, `ProviderKey`),
        CONSTRAINT `FK_AspNetUserLogins_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AspNetUserRoles` (
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `RoleId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        CONSTRAINT `PK_AspNetUserRoles` PRIMARY KEY (`UserId`, `RoleId`),
        CONSTRAINT `FK_AspNetUserRoles_AspNetRoles_RoleId` FOREIGN KEY (`RoleId`) REFERENCES `AspNetRoles` (`Id`) ON DELETE CASCADE,
        CONSTRAINT `FK_AspNetUserRoles_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AspNetUserTokens` (
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `LoginProvider` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `Name` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `Value` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        CONSTRAINT `PK_AspNetUserTokens` PRIMARY KEY (`UserId`, `LoginProvider`, `Name`),
        CONSTRAINT `FK_AspNetUserTokens_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AvailabilitySettings` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `MeetingRequestsEnabled` tinyint(1) NOT NULL,
        `TimeZoneId` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `CreatedAtUtc` datetime(6) NOT NULL,
        `UpdatedAtUtc` datetime(6) NOT NULL,
        CONSTRAINT `PK_AvailabilitySettings` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_AvailabilitySettings_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `AvailabilitySlots` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `DayOfWeek` int NOT NULL,
        `StartTime` time(6) NOT NULL,
        `EndTime` time(6) NOT NULL,
        `CreatedAtUtc` datetime(6) NOT NULL,
        `UpdatedAtUtc` datetime(6) NOT NULL,
        CONSTRAINT `PK_AvailabilitySlots` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_AvailabilitySlots_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `ImportedBusinessCards` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `OwnerUserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `ClientRequestId` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `RequestPayloadHash` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `FullName` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Company` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `JobTitle` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Website` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Address` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `RememberThisContact` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `PersonalRemark` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `CreatedAtUtc` datetime(6) NOT NULL,
        `UpdatedAtUtc` datetime(6) NOT NULL,
        CONSTRAINT `PK_ImportedBusinessCards` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_ImportedBusinessCards_AspNetUsers_OwnerUserId` FOREIGN KEY (`OwnerUserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `MeetingRequests` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `RequesterUserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `RecipientUserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `StartAtUtc` datetime(6) NOT NULL,
        `EndAtUtc` datetime(6) NOT NULL,
        `Title` varchar(200) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Note` varchar(2000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Status` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `CreatedAtUtc` datetime(6) NOT NULL,
        `UpdatedAtUtc` datetime(6) NOT NULL,
        CONSTRAINT `PK_MeetingRequests` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_MeetingRequests_AspNetUsers_RecipientUserId` FOREIGN KEY (`RecipientUserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE RESTRICT,
        CONSTRAINT `FK_MeetingRequests_AspNetUsers_RequesterUserId` FOREIGN KEY (`RequesterUserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE RESTRICT
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `RefreshTokens` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `TokenHash` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `CreatedAtUtc` datetime(6) NOT NULL,
        `ExpiresAtUtc` datetime(6) NOT NULL,
        `RevokedAtUtc` datetime(6) NULL,
        `ReplacedByTokenId` char(36) COLLATE ascii_general_ci NULL,
        `CreatedByIp` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `RevokedByIp` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        CONSTRAINT `PK_RefreshTokens` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_RefreshTokens_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `ScanJobs` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `ClientJobId` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `Status` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `FrontImageStorageKey` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `BackImageStorageKey` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `ImageSha256Checksum` varchar(64) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `LocalOcrDraftJson` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `ReconciledResultJson` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `ErrorMessage` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `RetryCount` int NOT NULL,
        `WorkerInstanceId` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `LockedUntilUtc` datetime(6) NULL,
        `CreatedAtUtc` datetime(6) NOT NULL,
        `UpdatedAtUtc` datetime(6) NOT NULL,
        `ExpiresAtUtc` datetime(6) NOT NULL,
        CONSTRAINT `PK_ScanJobs` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_ScanJobs_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `UserConsents` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `TermsVersion` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `PrivacyPolicyVersion` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `CookiePolicyVersion` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `Jurisdiction` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `EssentialAccepted` tinyint(1) NOT NULL,
        `AnalyticsAccepted` tinyint(1) NOT NULL,
        `ConsentTimestampUtc` datetime(6) NOT NULL,
        `Status` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `IpAddress` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `UserAgent` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        CONSTRAINT `PK_UserConsents` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_UserConsents_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `UserProfiles` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `UserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `ShareId` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `FullName` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `PhoneNumber` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Email` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `JobTitle` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Company` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Website` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Address` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `Bio` varchar(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `ProfilePhotoUrl` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        `IsPublic` tinyint(1) NOT NULL DEFAULT FALSE,
        `CreatedAtUtc` datetime(6) NOT NULL,
        `UpdatedAtUtc` datetime(6) NOT NULL,
        CONSTRAINT `PK_UserProfiles` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_UserProfiles_AspNetUsers_UserId` FOREIGN KEY (`UserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `ImportedBusinessCardEmails` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `ImportedBusinessCardId` char(36) COLLATE ascii_general_ci NOT NULL,
        `Email` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `NormalizedEmail` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `Label` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        CONSTRAINT `PK_ImportedBusinessCardEmails` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_ImportedBusinessCardEmails_ImportedBusinessCards_ImportedBus~` FOREIGN KEY (`ImportedBusinessCardId`) REFERENCES `ImportedBusinessCards` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `ImportedBusinessCardPhones` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `ImportedBusinessCardId` char(36) COLLATE ascii_general_ci NOT NULL,
        `Number` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `NormalizedNumber` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `Label` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NULL,
        CONSTRAINT `PK_ImportedBusinessCardPhones` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_ImportedBusinessCardPhones_ImportedBusinessCards_ImportedBus~` FOREIGN KEY (`ImportedBusinessCardId`) REFERENCES `ImportedBusinessCards` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE TABLE `Connections` (
        `Id` char(36) COLLATE ascii_general_ci NOT NULL,
        `OwnerUserId` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
        `SavedProfileId` char(36) COLLATE ascii_general_ci NOT NULL,
        `CreatedAtUtc` datetime(6) NOT NULL,
        CONSTRAINT `PK_Connections` PRIMARY KEY (`Id`),
        CONSTRAINT `FK_Connections_AspNetUsers_OwnerUserId` FOREIGN KEY (`OwnerUserId`) REFERENCES `AspNetUsers` (`Id`) ON DELETE CASCADE,
        CONSTRAINT `FK_Connections_UserProfiles_SavedProfileId` FOREIGN KEY (`SavedProfileId`) REFERENCES `UserProfiles` (`Id`) ON DELETE CASCADE
    ) CHARACTER SET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_AspNetRoleClaims_RoleId` ON `AspNetRoleClaims` (`RoleId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `RoleNameIndex` ON `AspNetRoles` (`NormalizedName`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_AspNetUserClaims_UserId` ON `AspNetUserClaims` (`UserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_AspNetUserLogins_UserId` ON `AspNetUserLogins` (`UserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_AspNetUserRoles_RoleId` ON `AspNetUserRoles` (`RoleId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `EmailIndex` ON `AspNetUsers` (`NormalizedEmail`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `UserNameIndex` ON `AspNetUsers` (`NormalizedUserName`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `IX_AvailabilitySettings_UserId` ON `AvailabilitySettings` (`UserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_AvailabilitySlots_UserId` ON `AvailabilitySlots` (`UserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_AvailabilitySlots_UserId_DayOfWeek` ON `AvailabilitySlots` (`UserId`, `DayOfWeek`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_Connections_OwnerUserId` ON `Connections` (`OwnerUserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `IX_Connections_OwnerUserId_SavedProfileId` ON `Connections` (`OwnerUserId`, `SavedProfileId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_Connections_SavedProfileId` ON `Connections` (`SavedProfileId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_ImportedBusinessCardEmails_ImportedBusinessCardId` ON `ImportedBusinessCardEmails` (`ImportedBusinessCardId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_ImportedBusinessCardEmails_NormalizedEmail` ON `ImportedBusinessCardEmails` (`NormalizedEmail`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_ImportedBusinessCardPhones_ImportedBusinessCardId` ON `ImportedBusinessCardPhones` (`ImportedBusinessCardId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_ImportedBusinessCardPhones_NormalizedNumber` ON `ImportedBusinessCardPhones` (`NormalizedNumber`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_ImportedBusinessCards_OwnerUserId` ON `ImportedBusinessCards` (`OwnerUserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `IX_ImportedBusinessCards_OwnerUserId_ClientRequestId` ON `ImportedBusinessCards` (`OwnerUserId`, `ClientRequestId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_MeetingRequests_RecipientUserId` ON `MeetingRequests` (`RecipientUserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_MeetingRequests_RecipientUserId_Status_StartAtUtc_EndAtUtc` ON `MeetingRequests` (`RecipientUserId`, `Status`, `StartAtUtc`, `EndAtUtc`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_MeetingRequests_RequesterUserId` ON `MeetingRequests` (`RequesterUserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_MeetingRequests_Status` ON `MeetingRequests` (`Status`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `IX_RefreshTokens_TokenHash` ON `RefreshTokens` (`TokenHash`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_RefreshTokens_UserId` ON `RefreshTokens` (`UserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_ScanJobs_ExpiresAtUtc` ON `ScanJobs` (`ExpiresAtUtc`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_ScanJobs_Status_LockedUntilUtc` ON `ScanJobs` (`Status`, `LockedUntilUtc`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `IX_ScanJobs_UserId_ClientJobId` ON `ScanJobs` (`UserId`, `ClientJobId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_ScanJobs_UserId_Status` ON `ScanJobs` (`UserId`, `Status`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE INDEX `IX_UserConsents_UserId_ConsentTimestampUtc` ON `UserConsents` (`UserId`, `ConsentTimestampUtc`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `IX_UserProfiles_ShareId` ON `UserProfiles` (`ShareId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    CREATE UNIQUE INDEX `IX_UserProfiles_UserId` ON `UserProfiles` (`UserId`);

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

DROP PROCEDURE IF EXISTS MigrationsScript;
DELIMITER //
CREATE PROCEDURE MigrationsScript()
BEGIN
    IF NOT EXISTS(SELECT 1 FROM `__EFMigrationsHistory` WHERE `MigrationId` = '20261119110923_InitialMySqlBaseline') THEN

    INSERT INTO `__EFMigrationsHistory` (`MigrationId`, `ProductVersion`)
    VALUES ('20261119110923_InitialMySqlBaseline', '8.0.11');

    END IF;
END //
DELIMITER ;
CALL MigrationsScript();
DROP PROCEDURE MigrationsScript;

COMMIT;

