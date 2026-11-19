using System.Net;
using System.Text.RegularExpressions;
using MySqlConnector;

namespace DigitalShare.Api.Configuration;

/// <summary>
/// Safe diagnostic information about the resolved MySQL connection without exposing sensitive credentials.
/// </summary>
public record MySqlConnectionDiagnostic(
    bool Success,
    string Scheme,
    string Host,
    int Port,
    string Database,
    string CharSet,
    bool HasUsername,
    bool HasPassword,
    string? ErrorMessage = null
)
{
    public override string ToString() =>
        $"[MySQL Connection Diagnostic] Success={Success}, Scheme='{Scheme}', Host='{Host}', Port={Port}, Database='{Database}', CharSet='{CharSet}', HasUsername={HasUsername}, HasPassword={HasPassword}" +
        (string.IsNullOrWhiteSpace(ErrorMessage) ? "" : $", Error='{ErrorMessage}'");
}

/// <summary>
/// Robust MySQL connection string and URI parser.
/// Correctly handles RFC 3986 and MySQL/MariaDB URI formats (mysql:// and mariadb://),
/// percent-encoded credentials, special characters in passwords (such as '@', '#', '[', ']'),
/// surrounding quotes, whitespace, and standard key-value MySQL connection strings.
/// </summary>
public static class MySqlConnectionParser
{
    /// <summary>
    /// Parses either a standard MySQL key-value connection string or a MySQL URI (mysql:// or mariadb://)
    /// into a sanitized MySqlConnector connection string, returning safe diagnostics.
    /// NEVER logs or exposes the password.
    /// </summary>
    public static string ParseToConnectionString(string? rawInput, out MySqlConnectionDiagnostic diagnostic)
    {
        if (string.IsNullOrWhiteSpace(rawInput))
        {
            diagnostic = new MySqlConnectionDiagnostic(
                Success: false,
                Scheme: string.Empty,
                Host: string.Empty,
                Port: 0,
                Database: string.Empty,
                CharSet: string.Empty,
                HasUsername: false,
                HasPassword: false,
                ErrorMessage: "Connection string or DATABASE_URL is null or empty.");
            return string.Empty;
        }

        // 1. Sanitize: Trim whitespace, newlines, and enclosing quotes (both single and double)
        var sanitized = rawInput.Trim().Trim('"', '\'', '`');

        // 2. Check if this is already a standard key-value connection string (e.g. Server=...;Port=...)
        if (!sanitized.StartsWith("mysql://", StringComparison.OrdinalIgnoreCase) &&
            !sanitized.StartsWith("mariadb://", StringComparison.OrdinalIgnoreCase))
        {
            try
            {
                var kvBuilder = new MySqlConnectionStringBuilder(sanitized);
                if (string.IsNullOrWhiteSpace(kvBuilder.CharacterSet))
                {
                    kvBuilder.CharacterSet = "utf8mb4";
                }

                diagnostic = new MySqlConnectionDiagnostic(
                    Success: true,
                    Scheme: "mysql-key-value",
                    Host: kvBuilder.Server ?? string.Empty,
                    Port: (int)kvBuilder.Port,
                    Database: kvBuilder.Database ?? string.Empty,
                    CharSet: kvBuilder.CharacterSet,
                    HasUsername: !string.IsNullOrWhiteSpace(kvBuilder.UserID),
                    HasPassword: !string.IsNullOrWhiteSpace(kvBuilder.Password)
                );
                return kvBuilder.ConnectionString;
            }
            catch (Exception ex)
            {
                // If it wasn't a valid key-value string and doesn't have a URI scheme, report error
                diagnostic = new MySqlConnectionDiagnostic(
                    Success: false,
                    Scheme: "unknown",
                    Host: string.Empty,
                    Port: 0,
                    Database: string.Empty,
                    CharSet: string.Empty,
                    HasUsername: false,
                    HasPassword: false,
                    ErrorMessage: $"Failed to parse key-value connection string: {ex.Message}");
                return sanitized;
            }
        }

        // 3. Dedicated MySQL/MariaDB URI Parser
        try
        {
            string scheme;
            string remainder;

            if (sanitized.StartsWith("mariadb://", StringComparison.OrdinalIgnoreCase))
            {
                scheme = "mariadb";
                remainder = sanitized.Substring("mariadb://".Length);
            }
            else
            {
                scheme = "mysql";
                remainder = sanitized.Substring("mysql://".Length);
            }

            // A URI structure: [user[:password]@]host[:port][/database][?options]
            string? userInfo = null;
            string hostAndBeyond;

            var atIndex = remainder.LastIndexOf('@');
            if (atIndex >= 0)
            {
                userInfo = remainder.Substring(0, atIndex);
                hostAndBeyond = remainder.Substring(atIndex + 1);
            }
            else
            {
                hostAndBeyond = remainder;
            }

            // Extract username and password from userInfo
            string? username = null;
            string? password = null;

            if (!string.IsNullOrEmpty(userInfo))
            {
                var colonIndex = userInfo.IndexOf(':');
                if (colonIndex >= 0)
                {
                    username = WebUtility.UrlDecode(userInfo.Substring(0, colonIndex));
                    password = WebUtility.UrlDecode(userInfo.Substring(colonIndex + 1));
                }
                else
                {
                    username = WebUtility.UrlDecode(userInfo);
                }
            }

            // Extract query parameters (?key=val&...)
            string? queryParams = null;
            string hostAndPath;

            var questionIndex = hostAndBeyond.IndexOf('?');
            if (questionIndex >= 0)
            {
                queryParams = hostAndBeyond.Substring(questionIndex + 1);
                hostAndPath = hostAndBeyond.Substring(0, questionIndex);
            }
            else
            {
                hostAndPath = hostAndBeyond;
            }

            // Extract database from path
            string? database = null;
            string hostAndPort;

            var slashIndex = hostAndPath.IndexOf('/');
            if (slashIndex >= 0)
            {
                hostAndPort = hostAndPath.Substring(0, slashIndex);
                var rawDb = hostAndPath.Substring(slashIndex + 1).Trim('/');
                if (!string.IsNullOrEmpty(rawDb))
                {
                    database = WebUtility.UrlDecode(rawDb);
                }
            }
            else
            {
                hostAndPort = hostAndPath;
            }

            // Extract host and port
            string host;
            int port = 3306; // Default MySQL port

            if (hostAndPort.StartsWith('['))
            {
                // IPv6 literal: [2001:db8::1]:3306
                var closingBracket = hostAndPort.IndexOf(']');
                if (closingBracket > 0)
                {
                    host = hostAndPort.Substring(1, closingBracket - 1);
                    var postBracket = hostAndPort.Substring(closingBracket + 1);
                    if (postBracket.StartsWith(':') && int.TryParse(postBracket.Substring(1), out var parsedPort))
                    {
                        port = parsedPort;
                    }
                }
                else
                {
                    host = hostAndPort;
                }
            }
            else
            {
                var colonIndex = hostAndPort.LastIndexOf(':');
                if (colonIndex >= 0 && int.TryParse(hostAndPort.Substring(colonIndex + 1), out var parsedPort))
                {
                    host = hostAndPort.Substring(0, colonIndex);
                    port = parsedPort;
                }
                else
                {
                    host = hostAndPort;
                }
            }

            // Build sanitized MySqlConnectionStringBuilder
            var builder = new MySqlConnectionStringBuilder
            {
                Server = host,
                Port = (uint)port,
                CharacterSet = "utf8mb4"
            };

            if (!string.IsNullOrEmpty(username)) builder.UserID = username;
            if (!string.IsNullOrEmpty(password)) builder.Password = password;
            if (!string.IsNullOrEmpty(database)) builder.Database = database;

            // Parse optional query parameters
            if (!string.IsNullOrWhiteSpace(queryParams))
            {
                var pairs = queryParams.Split('&', StringSplitOptions.RemoveEmptyEntries);
                foreach (var pair in pairs)
                {
                    var kv = pair.Split('=', 2);
                    var key = WebUtility.UrlDecode(kv[0]).Trim();
                    var val = kv.Length > 1 ? WebUtility.UrlDecode(kv[1]).Trim() : string.Empty;

                    if (string.Equals(key, "charset", StringComparison.OrdinalIgnoreCase))
                    {
                        builder.CharacterSet = val;
                    }
                    else if (string.Equals(key, "sslmode", StringComparison.OrdinalIgnoreCase))
                    {
                        if (Enum.TryParse<MySqlSslMode>(val, true, out var sslMode))
                        {
                            builder.SslMode = sslMode;
                        }
                    }
                }
            }

            diagnostic = new MySqlConnectionDiagnostic(
                Success: true,
                Scheme: scheme,
                Host: builder.Server,
                Port: (int)builder.Port,
                Database: builder.Database ?? string.Empty,
                CharSet: builder.CharacterSet,
                HasUsername: !string.IsNullOrWhiteSpace(builder.UserID),
                HasPassword: !string.IsNullOrWhiteSpace(builder.Password)
            );

            return builder.ConnectionString;
        }
        catch (Exception ex)
        {
            diagnostic = new MySqlConnectionDiagnostic(
                Success: false,
                Scheme: "uri-parse-error",
                Host: string.Empty,
                Port: 0,
                Database: string.Empty,
                CharSet: string.Empty,
                HasUsername: false,
                HasPassword: false,
                ErrorMessage: $"Exception parsing MySQL URI: {ex.Message}");
            throw new FormatException($"Invalid MySQL URI: {ex.Message}", ex);
        }
    }
}
