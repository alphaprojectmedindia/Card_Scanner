using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace DigitalShare.Api.Migrations
{
    /// <inheritdoc />
    public partial class AddShareIdToUserProfile : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "ShareId",
                table: "UserProfiles",
                type: "character varying(50)",
                maxLength: 50,
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateIndex(
                name: "IX_UserProfiles_ShareId",
                table: "UserProfiles",
                column: "ShareId",
                unique: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_UserProfiles_ShareId",
                table: "UserProfiles");

            migrationBuilder.DropColumn(
                name: "ShareId",
                table: "UserProfiles");
        }
    }
}
