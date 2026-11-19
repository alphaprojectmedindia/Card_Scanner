using DigitalShare.Api.Configuration;
using MySqlConnector;
using Xunit;

namespace DigitalShare.Api.Tests.Configuration;

public class MySqlConnectionParserTests
{
    [Fact]
    public void StandardKeyValue_ParsesCorrectly_WithHostingerDefaults()
    {
        const string connStr = "Server=127.0.0.1;Port=3306;Database=digitalshare;User=digitalshare_user;Password=SecurePassword123!;CharSet=utf8mb4;";

        var parsed = MySqlConnectionParser.ParseToConnectionString(connStr, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("127.0.0.1", diagnostic.Host);
        Assert.Equal(3306, diagnostic.Port);
        Assert.Equal("digitalshare", diagnostic.Database);
        Assert.Equal("utf8mb4", diagnostic.CharSet);
        Assert.True(diagnostic.HasUsername);
        Assert.True(diagnostic.HasPassword);
        Assert.DoesNotContain("SecurePassword123!", diagnostic.ToString()); // Verify password is NOT leaked in diagnostic

        var builder = new MySqlConnectionStringBuilder(parsed);
        Assert.Equal("127.0.0.1", builder.Server);
        Assert.Equal((uint)3306, builder.Port);
        Assert.Equal("digitalshare", builder.Database);
        Assert.Equal("digitalshare_user", builder.UserID);
        Assert.Equal("SecurePassword123!", builder.Password);
        Assert.Equal("utf8mb4", builder.CharacterSet);
    }

    [Fact]
    public void StandardKeyValue_Quoted_IsSanitizedAndParsed()
    {
        const string quoted = "\"Server=localhost;Port=3306;Database=digitalshare;User Id=root;Password=root_pass;\"";

        var parsed = MySqlConnectionParser.ParseToConnectionString(quoted, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("localhost", diagnostic.Host);
        Assert.Equal("digitalshare", diagnostic.Database);

        var builder = new MySqlConnectionStringBuilder(parsed);
        Assert.Equal("localhost", builder.Server);
        Assert.Equal("root", builder.UserID);
        Assert.Equal("root_pass", builder.Password);
    }

    [Fact]
    public void MySqlUri_StandardFormat_ParsesCorrectly()
    {
        const string uri = "mysql://digitalshare_user:SecurePassword123!@127.0.0.1:3306/digitalshare?charset=utf8mb4";

        var parsed = MySqlConnectionParser.ParseToConnectionString(uri, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("127.0.0.1", diagnostic.Host);
        Assert.Equal(3306, diagnostic.Port);
        Assert.Equal("digitalshare", diagnostic.Database);
        Assert.Equal("utf8mb4", diagnostic.CharSet);
        Assert.True(diagnostic.HasUsername);
        Assert.True(diagnostic.HasPassword);

        var builder = new MySqlConnectionStringBuilder(parsed);
        Assert.Equal("127.0.0.1", builder.Server);
        Assert.Equal((uint)3306, builder.Port);
        Assert.Equal("digitalshare", builder.Database);
        Assert.Equal("digitalshare_user", builder.UserID);
        Assert.Equal("SecurePassword123!", builder.Password);
    }

    [Fact]
    public void MariaDbUri_Scheme_IsRecognizedAndParsed()
    {
        const string uri = "mariadb://appuser:mypassword@db.hostinger.internal:3306/digitalshare";

        var parsed = MySqlConnectionParser.ParseToConnectionString(uri, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("mariadb", diagnostic.Scheme);
        Assert.Equal("db.hostinger.internal", diagnostic.Host);
        Assert.Equal(3306, diagnostic.Port);
        Assert.Equal("digitalshare", diagnostic.Database);

        var builder = new MySqlConnectionStringBuilder(parsed);
        Assert.Equal("db.hostinger.internal", builder.Server);
        Assert.Equal("appuser", builder.UserID);
        Assert.Equal("mypassword", builder.Password);
    }

    [Fact]
    public void MySqlUri_WithUnencodedAtSymbolInPassword_ParsesCorrectly()
    {
        const string uri = "mysql://digitalshare_user:p@ssword!@127.0.0.1:3306/digitalshare";

        var parsed = MySqlConnectionParser.ParseToConnectionString(uri, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("127.0.0.1", diagnostic.Host);
        Assert.Equal(3306, diagnostic.Port);
        Assert.Equal("digitalshare", diagnostic.Database);

        var builder = new MySqlConnectionStringBuilder(parsed);
        Assert.Equal("127.0.0.1", builder.Server);
        Assert.Equal("digitalshare_user", builder.UserID);
        Assert.Equal("p@ssword!", builder.Password);
    }

    [Theory]
    [InlineData("mysql://user:pass%40123@host:3306/mydb", "pass@123")]
    [InlineData("mysql://user:p%23ss%25w%26rd@host:3306/mydb", "p#ss%w&rd")]
    [InlineData("mysql://user:pass%2Fword@host:3306/mydb", "pass/word")]
    [InlineData("mysql://user:%5BYOUR-PASSWORD%5D@host:3306/mydb", "[YOUR-PASSWORD]")]
    public void MySqlUri_CorrectlyDecodes_PercentEncodedCredentials(string uri, string expectedPassword)
    {
        var parsed = MySqlConnectionParser.ParseToConnectionString(uri, out var diagnostic);

        Assert.True(diagnostic.Success);
        var builder = new MySqlConnectionStringBuilder(parsed);
        Assert.Equal(expectedPassword, builder.Password);
    }

    [Fact]
    public void MySqlUri_WithoutPort_DefaultsTo3306()
    {
        const string uri = "mysql://digitalshare_user:secret@127.0.0.1/digitalshare";

        var parsed = MySqlConnectionParser.ParseToConnectionString(uri, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal(3306, diagnostic.Port);
        var builder = new MySqlConnectionStringBuilder(parsed);
        Assert.Equal((uint)3306, builder.Port);
    }

    [Fact]
    public void NullOrEmptyInput_ReturnsFailedDiagnostic()
    {
        var result1 = MySqlConnectionParser.ParseToConnectionString(null, out var diag1);
        Assert.False(diag1.Success);
        Assert.Empty(result1);

        var result2 = MySqlConnectionParser.ParseToConnectionString("   ", out var diag2);
        Assert.False(diag2.Success);
        Assert.Empty(result2);
    }

    [Fact]
    public void DiagnosticToString_MasksSensitiveCredentials()
    {
        const string connStr = "Server=127.0.0.1;Port=3306;Database=digitalshare;User=admin;Password=SuperSecretPassword99!";

        MySqlConnectionParser.ParseToConnectionString(connStr, out var diagnostic);

        var str = diagnostic.ToString();
        Assert.Contains("Success=True", str);
        Assert.Contains("Host='127.0.0.1'", str);
        Assert.Contains("Database='digitalshare'", str);
        Assert.Contains("HasPassword=True", str);
        Assert.DoesNotContain("SuperSecretPassword99!", str);
    }
}
