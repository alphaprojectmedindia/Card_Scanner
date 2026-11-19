using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DigitalShare.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddScanJobsAndContactIdempotency : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ClientRequestId",
                table: "ImportedBusinessCards",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "RequestPayloadHash",
                table: "ImportedBusinessCards",
                type: "character varying(64)",
                maxLength: 64,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "ScanJobs",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    UserId = table.Column<string>(type: "text", nullable: false),
                    ClientJobId = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: false),
                    Status = table.Column<string>(type: "character varying(20)", maxLength: 20, nullable: false),
                    FrontImageStorageKey = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    BackImageStorageKey = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    ImageSha256Checksum = table.Column<string>(type: "character varying(64)", maxLength: 64, nullable: true),
                    LocalOcrDraftJson = table.Column<string>(type: "text", nullable: true),
                    ReconciledResultJson = table.Column<string>(type: "text", nullable: true),
                    ErrorMessage = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    RetryCount = table.Column<int>(type: "integer", nullable: false),
                    WorkerInstanceId = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    LockedUntilUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    ExpiresAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ScanJobs", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ScanJobs_AspNetUsers_UserId",
                        column: x => x.UserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ImportedBusinessCards_OwnerUserId_ClientRequestId",
                table: "ImportedBusinessCards",
                columns: new[] { "OwnerUserId", "ClientRequestId" },
                unique: true,
                filter: "\"ClientRequestId\" IS NOT NULL");

            migrationBuilder.CreateIndex(
                name: "IX_ScanJobs_ExpiresAtUtc",
                table: "ScanJobs",
                column: "ExpiresAtUtc");

            migrationBuilder.CreateIndex(
                name: "IX_ScanJobs_Status_LockedUntilUtc",
                table: "ScanJobs",
                columns: new[] { "Status", "LockedUntilUtc" });

            migrationBuilder.CreateIndex(
                name: "IX_ScanJobs_UserId_ClientJobId",
                table: "ScanJobs",
                columns: new[] { "UserId", "ClientJobId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_ScanJobs_UserId_Status",
                table: "ScanJobs",
                columns: new[] { "UserId", "Status" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ScanJobs");

            migrationBuilder.DropIndex(
                name: "IX_ImportedBusinessCards_OwnerUserId_ClientRequestId",
                table: "ImportedBusinessCards");

            migrationBuilder.DropColumn(
                name: "ClientRequestId",
                table: "ImportedBusinessCards");

            migrationBuilder.DropColumn(
                name: "RequestPayloadHash",
                table: "ImportedBusinessCards");
        }
    }
}
