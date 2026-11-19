using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DigitalShare.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddRemarksAndAccountVisibility : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "IsPublic",
                table: "UserProfiles",
                type: "boolean",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "PersonalRemark",
                table: "ImportedBusinessCards",
                type: "character varying(2000)",
                maxLength: 2000,
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "IsPublic",
                table: "UserProfiles");

            migrationBuilder.DropColumn(
                name: "PersonalRemark",
                table: "ImportedBusinessCards");
        }
    }
}
