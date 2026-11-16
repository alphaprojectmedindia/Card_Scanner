using DigitalShare.Api.Configuration;
using Npgsql;
using Xunit;

namespace DigitalShare.Api.Tests.Configuration;

public class PostgreSqlConnectionParserTests
{
    [Fact]
    public void SystemUri_Throws_InvalidUri_TheHostnameCouldNotBeParsed_WhenPasswordContainsUnencodedAtSymbol()
    {
        // 1. REPRODUCING THE EXACT PRODUCTION FAILURE:
        // When a PostgreSQL URI has a password containing an unencoded '@', .NET's new Uri() throws
        // "System.UriFormatException: Invalid URI: The hostname could not be parsed."
        const string problematicUri = "postgresql://postgres:p@ssword@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres";

        var ex = Assert.Throws<UriFormatException>(() => new Uri(problematicUri));
        Assert.Contains("The hostname could not be parsed", ex.Message);
    }

    [Fact]
    public void RobustParser_SuccessfullyParses_WhenPasswordContainsUnencodedAtSymbol()
    {
        // The robust parser must handle passwords with unencoded '@' symbols without throwing
        const string problematicUri = "postgresql://postgres:p@ssword@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres";

        var connString = PostgreSqlConnectionParser.ParseToConnectionString(problematicUri, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("aws-1-ap-northeast-1.pooler.supabase.com", diagnostic.Host);
        Assert.Equal(5432, diagnostic.Port);
        Assert.Equal("postgres", diagnostic.Database);
        Assert.True(diagnostic.HasUsername);
        Assert.True(diagnostic.HasPassword);

        var builder = new NpgsqlConnectionStringBuilder(connString);
        Assert.Equal("aws-1-ap-northeast-1.pooler.supabase.com", builder.Host);
        Assert.Equal(5432, builder.Port);
        Assert.Equal("postgres", builder.Username);
        Assert.Equal("p@ssword", builder.Password);
        Assert.Equal("postgres", builder.Database);
    }

    [Theory]
    [InlineData("postgresql://postgres:pass%40123@host:5432/mydb", "pass@123")]
    [InlineData("postgresql://postgres:p%23ss%25w%26rd@host:5432/mydb", "p#ss%w&rd")]
    [InlineData("postgresql://postgres:pass%2Fword@host:5432/mydb", "pass/word")]
    [InlineData("postgresql://postgres:%5BYOUR-PASSWORD%5D@host:5432/mydb", "[YOUR-PASSWORD]")]
    public void RobustParser_CorrectlyDecodes_PercentEncodedCredentials(string uri, string expectedPassword)
    {
        var connString = PostgreSqlConnectionParser.ParseToConnectionString(uri, out var diagnostic);

        Assert.True(diagnostic.Success);
        var builder = new NpgsqlConnectionStringBuilder(connString);
        Assert.Equal(expectedPassword, builder.Password);
    }

    [Fact]
    public void RobustParser_Handles_SupabaseSharedPoolerFormat_WithTenantUsername()
    {
        const string supabaseUrl = "postgresql://postgres.fdnqaqvtxjzvuoeswwav:SecretPass123!@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres?sslmode=require";

        var connString = PostgreSqlConnectionParser.ParseToConnectionString(supabaseUrl, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("aws-1-ap-northeast-1.pooler.supabase.com", diagnostic.Host);
        Assert.Equal(5432, diagnostic.Port);
        Assert.Equal("postgres", diagnostic.Database);
        Assert.Equal("Require", diagnostic.SslMode);
        Assert.True(diagnostic.HasUsername);
        Assert.True(diagnostic.HasPassword);

        var builder = new NpgsqlConnectionStringBuilder(connString);
        Assert.Equal("postgres.fdnqaqvtxjzvuoeswwav", builder.Username);
        Assert.Equal("SecretPass123!", builder.Password);
        Assert.Equal(SslMode.Require, builder.SslMode);
    }

    [Theory]
    [InlineData("\"postgresql://user:pass@host:5432/db\"")]
    [InlineData("'postgresql://user:pass@host:5432/db'")]
    [InlineData("  postgresql://user:pass@host:5432/db \r\n")]
    public void RobustParser_Strips_UnexpectedQuotes_And_Whitespace(string rawInput)
    {
        var connString = PostgreSqlConnectionParser.ParseToConnectionString(rawInput, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("host", diagnostic.Host);
        Assert.Equal(5432, diagnostic.Port);
        Assert.Equal("db", diagnostic.Database);

        var builder = new NpgsqlConnectionStringBuilder(connString);
        Assert.Equal("host", builder.Host);
        Assert.Equal("user", builder.Username);
        Assert.Equal("pass", builder.Password);
    }

    [Fact]
    public void RobustParser_Supports_StandardNpgsqlKeyValueConnectionString()
    {
        const string kv = "Host=aws-1-ap-northeast-1.pooler.supabase.com;Port=5432;Database=postgres;Username=postgres.fdnqaqvtxjzvuoeswwav;Password=mysecret;SSL Mode=Require;";

        var connString = PostgreSqlConnectionParser.ParseToConnectionString(kv, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("npgsql-key-value", diagnostic.Scheme);
        Assert.Equal("aws-1-ap-northeast-1.pooler.supabase.com", diagnostic.Host);
        Assert.Equal(5432, diagnostic.Port);
        Assert.Equal("postgres", diagnostic.Database);
        Assert.Equal("Require", diagnostic.SslMode);
        Assert.True(diagnostic.HasUsername);
        Assert.True(diagnostic.HasPassword);
    }

    [Fact]
    public void RobustParser_Supports_RenderInternalHostWithoutTld()
    {
        const string renderUrl = "postgresql://digital_share_user:secret_render_pass@dpg-cxxxxxxxx-a/digital_share_db";

        var connString = PostgreSqlConnectionParser.ParseToConnectionString(renderUrl, out var diagnostic);

        Assert.True(diagnostic.Success);
        Assert.Equal("dpg-cxxxxxxxx-a", diagnostic.Host);
        Assert.Equal(5432, diagnostic.Port);
        Assert.Equal("digital_share_db", diagnostic.Database);

        var builder = new NpgsqlConnectionStringBuilder(connString);
        Assert.Equal("dpg-cxxxxxxxx-a", builder.Host);
        Assert.Equal("digital_share_user", builder.Username);
        Assert.Equal("secret_render_pass", builder.Password);
    }

    [Fact]
    public void SafeDiagnostic_NeverLogsPasswordOrCompleteConnectionString()
    {
        const string secretPass = "SuperConfidentialPassword123!@#";
        string uri = $"postgresql://postgres:{secretPass}@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres";

        PostgreSqlConnectionParser.ParseToConnectionString(uri, out var diagnostic);
        string diagString = diagnostic.ToString();

        // The diagnostic string must report metadata but NEVER contain the secret
        Assert.True(diagnostic.HasPassword);
        Assert.True(diagnostic.HasUsername);
        Assert.DoesNotContain(secretPass, diagString);
        Assert.DoesNotContain("SuperConfidential", diagString);
        Assert.Contains("Host='aws-1-ap-northeast-1.pooler.supabase.com'", diagString);
        Assert.Contains("Port=5432", diagString);
        Assert.Contains("Success=True", diagString);
    }
}
