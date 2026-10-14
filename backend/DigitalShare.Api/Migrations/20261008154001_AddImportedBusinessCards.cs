using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DigitalShare.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddImportedBusinessCards : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "ImportedBusinessCards",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    OwnerUserId = table.Column<string>(type: "text", nullable: false),
                    FullName = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    Company = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    JobTitle = table.Column<string>(type: "character varying(100)", maxLength: 100, nullable: true),
                    Website = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: true),
                    Address = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    CreatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false),
                    UpdatedAtUtc = table.Column<DateTime>(type: "timestamp with time zone", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ImportedBusinessCards", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ImportedBusinessCards_AspNetUsers_OwnerUserId",
                        column: x => x.OwnerUserId,
                        principalTable: "AspNetUsers",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ImportedBusinessCardEmails",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ImportedBusinessCardId = table.Column<Guid>(type: "uuid", nullable: false),
                    Email = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    NormalizedEmail = table.Column<string>(type: "character varying(256)", maxLength: 256, nullable: false),
                    Label = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ImportedBusinessCardEmails", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ImportedBusinessCardEmails_ImportedBusinessCards_ImportedBu~",
                        column: x => x.ImportedBusinessCardId,
                        principalTable: "ImportedBusinessCards",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateTable(
                name: "ImportedBusinessCardPhones",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uuid", nullable: false),
                    ImportedBusinessCardId = table.Column<Guid>(type: "uuid", nullable: false),
                    Number = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    NormalizedNumber = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: false),
                    Label = table.Column<string>(type: "character varying(50)", maxLength: 50, nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_ImportedBusinessCardPhones", x => x.Id);
                    table.ForeignKey(
                        name: "FK_ImportedBusinessCardPhones_ImportedBusinessCards_ImportedBu~",
                        column: x => x.ImportedBusinessCardId,
                        principalTable: "ImportedBusinessCards",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_ImportedBusinessCardEmails_ImportedBusinessCardId",
                table: "ImportedBusinessCardEmails",
                column: "ImportedBusinessCardId");

            migrationBuilder.CreateIndex(
                name: "IX_ImportedBusinessCardEmails_NormalizedEmail",
                table: "ImportedBusinessCardEmails",
                column: "NormalizedEmail");

            migrationBuilder.CreateIndex(
                name: "IX_ImportedBusinessCardPhones_ImportedBusinessCardId",
                table: "ImportedBusinessCardPhones",
                column: "ImportedBusinessCardId");

            migrationBuilder.CreateIndex(
                name: "IX_ImportedBusinessCardPhones_NormalizedNumber",
                table: "ImportedBusinessCardPhones",
                column: "NormalizedNumber");

            migrationBuilder.CreateIndex(
                name: "IX_ImportedBusinessCards_OwnerUserId",
                table: "ImportedBusinessCards",
                column: "OwnerUserId");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "ImportedBusinessCardEmails");

            migrationBuilder.DropTable(
                name: "ImportedBusinessCardPhones");

            migrationBuilder.DropTable(
                name: "ImportedBusinessCards");
        }
    }
}
