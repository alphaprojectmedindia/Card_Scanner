using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DigitalShare.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddRememberThisContact : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "RememberThisContact",
                table: "ImportedBusinessCards",
                type: "character varying(2000)",
                maxLength: 2000,
                nullable: true);

            migrationBuilder.Sql("UPDATE \"ImportedBusinessCards\" SET \"RememberThisContact\" = \"PersonalRemark\" WHERE \"RememberThisContact\" IS NULL AND \"PersonalRemark\" IS NOT NULL;");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "RememberThisContact",
                table: "ImportedBusinessCards");
        }
    }
}
