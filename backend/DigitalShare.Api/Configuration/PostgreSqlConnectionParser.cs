using System.Net;
using System.Text.RegularExpressions;
using Npgsql;

namespace DigitalShare.Api.Configuration;

/// <summary>
/// Safe diagnostic information about the resolved PostgreSQL connection without exposing sensitive credentials.
/// </summary>
public record PostgreSqlConnectionDiagnostic(
    bool Success,
    string Scheme,
    string Host,
    int Port,
    string Database,
    string SslMode,
    bool HasUsername,
    bool HasPassword,
    string? ErrorMessage = null
)
{
    public override string ToString() =>
        $"[PostgreSQL Connection Diagnostic] Success={Success}, Scheme='{Scheme}', Host='{Host}', Port={Port}, Database='{Database}', SslMode='{SslMode}', HasUsername={HasUsername}, HasPassword={HasPassword}" +
        (string.IsNullOrWhiteSpace(ErrorMessage) ? "" : $", Error='{ErrorMessage}'");
}

/// <summary>
/// Robust PostgreSQL connection string and URI parser.
/// Correctly handles RFC 3986 and PostgreSQL URI format (postgres:// and postgresql://),
/// percent-encoded credentials, special characters in passwords (such as '@', '#', '[', ']'),
/// surrounding quotes, whitespace, and standard key-value Npgsql connection strings.
/// </summary>
public static class PostgreSqlConnectionParser
{
    /// <summary>
    /// Parses either a standard Npgsql key-value connection string or a PostgreSQL URI (postgres:// or postgresql://)
    /// into a sanitized Npgsql connection string, returning safe diagnostics.
    /// NEVER logs or exposes the password.
    /// </summary>
    public static string ParseToConnectionString(string? rawInput, out PostgreSqlConnectionDiagnostic diagnostic)
    {
        if (string.IsNullOrWhiteSpace(rawInput))
        {
            diagnostic = new PostgreSqlConnectionDiagnostic(
                Success: false,
                Scheme: string.Empty,
                Host: string.Empty,
                Port: 0,
                Database: string.Empty,
                SslMode: string.Empty,
                HasUsername: false,
                HasPassword: false,
                ErrorMessage: "Connection string or DATABASE_URL is null or empty.");
            return string.Empty;
        }

        // 1. Sanitize: Trim whitespace, newlines, and enclosing quotes (both single and double)
        var sanitized = rawInput.Trim().Trim('"', '\'', '`');

        // 2. Check if this is already a standard key-value connection string (e.g. Host=...;Port=...)
        if (!sanitized.StartsWith("postgres://", StringComparison.OrdinalIgnoreCase) &&
            !sanitized.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var kvBuilder = new NpgsqlConnectionStringBuilder(sanitized);
                diagnostic = new PostgreSqlConnectionDiagnostic(
                    Success: true,
                    Scheme: "npgsql-key-value",
                    Host: kvBuilder.Host ?? string.Empty,
                    Port: kvBuilder.Port,
                    Database: kvBuilder.Database ?? string.Empty,
                    SslMode: kvBuilder.SslMode.ToString(),
                    HasUsername: !string.IsNullOrWhiteSpace(kvBuilder.Username),
                    HasPassword: !string.IsNullOrWhiteSpace(kvBuilder.Password)
                );
                return kvBuilder.ConnectionString;
            }
            catch (Exception ex)
            {
                // If it wasn't a valid key-value string and doesn't have a URI scheme, report error
                diagnostic = new PostgreSqlConnectionDiagnostic(
                    Success: false,
                    Scheme: "unknown",
                    Host: string.Empty,
                    Port: 0,
                    Database: string.Empty,
                    SslMode: string.Empty,
                    HasUsername: false,
                    HasPassword: false,
                    ErrorMessage: $"Failed to parse key-value connection string: {ex.Message}");
                return sanitized;
            }
        }

        // 3. Dedicated PostgreSQL URI Parser
        try
        {
            string scheme;
            string remainder;

            if (sanitized.StartsWith("postgresql://", StringComparison.OrdinalIgnoreCase))
            {
                scheme = "postgresql";
                remainder = sanitized.Substring("postgresql://".Length);
            }
            else
            {
                scheme = "postgres";
                remainder = sanitized.Substring("postgres://".Length);
            }

            // Separate query string (?param=val&...)
            string query = string.Empty;
            int queryIndex = remainder.IndexOf('?');
            if (queryIndex >= 0)
            {
                query = remainder.Substring(queryIndex + 1);
                remainder = remainder.Substring(0, queryIndex);
            }

            // Separate credentials [user[:password]] from hostAndPath [host[:port][/database]]
            // In database URIs, passwords frequently contain '@' (e.g. P@ssword).
            // Since hostnames CANNOT contain '@', the LAST '@' before the database path delimiter '/' is the credentials delimiter.
            string credentialsPart = string.Empty;
            string hostAndPathPart;

            int lastAtIndex = remainder.LastIndexOf('@');
            if (lastAtIndex >= 0)
            {
                credentialsPart = remainder.Substring(0, lastAtIndex);
                hostAndPathPart = remainder.Substring(lastAtIndex + 1);
            }
            else
            {
                hostAndPathPart = remainder;
            }

            // Separate host[:port] from database path
            string hostPortPart;
            string databasePart = string.Empty;

            int firstSlashIndex = hostAndPathPart.IndexOf('/');
            if (firstSlashIndex >= 0)
            {
                hostPortPart = hostAndPathPart.Substring(0, firstSlashIndex);
                databasePart = hostAndPathPart.Substring(firstSlashIndex + 1);
            }
            else
            {
                hostPortPart = hostAndPathPart;
            }

            // Parse Host and Port
            string host;
            int port = 5432;

            hostPortPart = hostPortPart.Trim();

            if (hostPortPart.StartsWith("["))
            {
                // IPv6 host literal: [fe80::1]:5432 or [fe80::1]
                int closingBracket = hostPortPart.IndexOf(']');
                if (closingBracket > 0)
                {
                    host = hostPortPart.Substring(0, closingBracket + 1);
                    var portPart = hostPortPart.Substring(closingBracket + 1).TrimStart(':');
                    if (int.TryParse(portPart, out int parsedIpv6Port) && parsedIpv6Port > 0)
                    {
                        port = parsedIpv6Port;
                    }
                }
                else
                {
                    host = hostPortPart;
                }
            }
            else
            {
                // Standard host or host:port
                int colonIndex = hostPortPart.LastIndexOf(':');
                if (colonIndex >= 0)
                {
                    host = hostPortPart.Substring(0, colonIndex);
                    var portPart = hostPortPart.Substring(colonIndex + 1);
                    if (int.TryParse(portPart, out int parsedPort) && parsedPort > 0)
                    {
                        port = parsedPort;
                    }
                }
                else
                {
                    host = hostPortPart;
                }
            }

            host = host.Trim().Trim('"', '\'');
            if (string.IsNullOrWhiteSpace(host))
            {
                host = "localhost";
            }

            // Parse Username and Password from credentialsPart
            string username = string.Empty;
            string password = string.Empty;

            if (!string.IsNullOrWhiteSpace(credentialsPart))
            {
                int colonIndex = credentialsPart.IndexOf(':');
                if (colonIndex >= 0)
                {
                    username = credentialsPart.Substring(0, colonIndex);
                    password = credentialsPart.Substring(colonIndex + 1);
                }
                else
                {
                    username = credentialsPart;
                }

                // Decode percent-encoded credentials safely (e.g. %40 -> @, %23 -> #)
                username = Uri.UnescapeDataString(username.Trim());
                password = Uri.UnescapeDataString(password);
            }

            // Parse Database Name
            string database = Uri.UnescapeDataString(databasePart.Trim().TrimStart('/'));
            if (string.IsNullOrWhiteSpace(database))
            {
                database = "postgres";
            }

            // Parse Query Parameters
            var sslMode = SslMode.Prefer;

            // Enforce Require for cloud providers if not explicitly set
            if (host.Contains("supabase.co", StringComparison.OrdinalIgnoreCase) ||
                host.Contains("supabase.com", StringComparison.OrdinalIgnoreCase) ||
                host.Contains("render.com", StringComparison.OrdinalIgnoreCase) ||
                host.Contains("railway.app", StringComparison.OrdinalIgnoreCase))
            {
                sslMode = SslMode.Require;
            }

            bool? pooling = null;
            int? timeout = null;

            if (!string.IsNullOrWhiteSpace(query))
            {
                var queryParams = query.Split('&', StringSplitOptions.RemoveEmptyEntries);
                foreach (var param in queryParams)
                {
                    var kv = param.Split('=', 2);
                    var key = kv[0].Trim().ToLowerInvariant();
                    var val = kv.Length > 1 ? kv[1].Trim() : string.Empty;

                    if (key == "sslmode")
                    {
                        if (val.Equals("require", StringComparison.OrdinalIgnoreCase))
                            sslMode = SslMode.Require;
                        else if (val.Equals("disable", StringComparison.OrdinalIgnoreCase))
                            sslMode = SslMode.Disable;
                        else if (val.Equals("prefer", StringComparison.OrdinalIgnoreCase))
                            sslMode = SslMode.Prefer;
                        else if (val.Equals("verify-full", StringComparison.OrdinalIgnoreCase))
                            sslMode = SslMode.VerifyFull;
                        else if (val.Equals("verify-ca", StringComparison.OrdinalIgnoreCase))
                            sslMode = SslMode.VerifyCA;
                    }
                    else if (key == "pooling" && bool.TryParse(val, out bool parsedPooling))
                    {
                        pooling = parsedPooling;
                    }
                    else if ((key == "timeout" || key == "connect_timeout") && int.TryParse(val, out int parsedTimeout))
                    {
                        timeout = parsedTimeout;
                    }
                }
            }

            var builder = new NpgsqlConnectionStringBuilder
            {
                Host = host,
                Port = port,
                Database = database,
                Username = username,
                Password = password,
                SslMode = sslMode
            };

            if (pooling.HasValue)
            {
                builder.Pooling = pooling.Value;
            }

            if (timeout.HasValue)
            {
                builder.Timeout = timeout.Value;
            }

            diagnostic = new PostgreSqlConnectionDiagnostic(
                Success: true,
                Scheme: scheme,
                Host: host,
                Port: port,
                Database: database,
                SslMode: sslMode.ToString(),
                HasUsername: !string.IsNullOrWhiteSpace(username),
                HasPassword: !string.IsNullOrWhiteSpace(password)
            );

            return builder.ConnectionString;
        }
        catch (Exception ex)
        {
            diagnostic = new PostgreSqlConnectionDiagnostic(
                Success: false,
                Scheme: "invalid",
                Host: string.Empty,
                Port: 0,
                Database: string.Empty,
                SslMode: string.Empty,
                HasUsername: false,
                HasPassword: false,
                ErrorMessage: $"Exception parsing PostgreSQL URI: {ex.Message}");
            throw new FormatException($"Invalid PostgreSQL URI: {ex.Message}", ex);
        }
    }
}
