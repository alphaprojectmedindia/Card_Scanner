using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DigitalShare.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddConnectionsTable : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "Connections",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<string>(type: "text", nullable: false),
                    SavedProfileId = table.Column<Guid>(type: "uuid", nullable: false),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_Connections", x => x.Id);
                    table.ForeignKey(
                        name: "FK_Connections_AspNetUsers_OwnerUserId",
                        column: x => x.OwnerUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_Connections_UserProfiles_SavedProfileId",
                        column: x => x.SavedProfileId,
                        principalTable: "UserProfiles",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_Connections_OwnerUserId",
                table: "Connections",
                column: "OwnerUserId");

            migrationBuilder.CreateIndex(
                name: "IX_Connections_OwnerUserId_SavedProfileId",
                table: "Connections",
                columns: new[] { "OwnerUserId", "SavedProfileId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_Connections_SavedProfileId",
                table: "Connections",
                column: "SavedProfileId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "Connections");
        }
    }
}
