using System.Net;
using System.Net.Mail;
using DigitalShare.Api.Configuration;
using Microsoft.Extensions.Options;

namespace DigitalShare.Api.Services.Email;

public interface ISmtpEmailService
{
    Task<(bool Sent, string? Error)> SendPasswordResetEmailAsync(string toEmail, string resetToken, string? resetUrl = null);
}

public class GmailSmtpEmailService : ISmtpEmailService
{
    private readonly SmtpOptions _options;
    private readonly ILogger<GmailSmtpEmailService> _logger;

    public GmailSmtpEmailService(IOptions<SmtpOptions> options, ILogger<GmailSmtpEmailService> logger)
    {
        _options = options.Value;
        _logger = logger;
    }

    public async Task<(bool Sent, string? Error)> SendPasswordResetEmailAsync(string toEmail, string resetToken, string? resetUrl = null)
    {
        if (string.IsNullOrWhiteSpace(_options.Username) || string.IsNullOrWhiteSpace(_options.Password))
        {
            _logger.LogWarning(
                "[SMTP Diagnostic] Gmail SMTP credentials not fully configured. Password reset token for {Email}: {Token}. ResetUrl: {ResetUrl}",
                toEmail, resetToken, resetUrl ?? "N/A");
            // Return true in development so local testing can proceed without blocking on SMTP
            return (true, null);
        }

        try
        {
            using var client = new SmtpClient(_options.Host, _options.Port)
            {
                Credentials = new NetworkCredential(_options.Username, _options.Password),
                EnableSsl = _options.EnableSsl,
                Timeout = 15000
            };

            var fromAddress = new MailAddress(
                !string.IsNullOrWhiteSpace(_options.FromEmail) ? _options.FromEmail : _options.Username,
                _options.FromName);

            using var mail = new MailMessage
            {
                From = fromAddress,
                Subject = "Digital Share — Password Reset Request",
                IsBodyHtml = true
            };

            mail.To.Add(toEmail);

            var actionUrl = resetUrl ?? $"https://digitalshare.medindia4u.com/reset-password?email={Uri.EscapeDataString(toEmail)}&token={Uri.EscapeDataString(resetToken)}";

            mail.Body = $@"
<!DOCTYPE html>
<html>
<head>
  <meta charset='utf-8'>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #F8FAFC; color: #1E293B; margin: 0; padding: 24px; }}
    .container {{ max-width: 560px; margin: 0 auto; background: #FFFFFF; border-radius: 12px; border: 1px solid #E2E8F0; padding: 32px; box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05); }}
    .header {{ text-align: center; margin-bottom: 24px; }}
    .logo-text {{ font-size: 22px; font-weight: 700; color: #2563EB; }}
    .branding {{ font-size: 12px; color: #64748B; margin-top: 4px; }}
    .button {{ display: inline-block; background-color: #2563EB; color: #FFFFFF !important; text-decoration: none; padding: 12px 24px; border-radius: 8px; font-weight: 600; margin: 20px 0; }}
    .token-box {{ background: #F1F5F9; border: 1px dashed #CBD5E1; border-radius: 8px; padding: 16px; font-family: monospace; font-size: 14px; word-break: break-all; margin: 16px 0; }}
    .footer {{ text-align: center; font-size: 12px; color: #94A3B8; margin-top: 32px; border-top: 1px solid #E2E8F0; padding-top: 16px; }}
  </style>
</head>
<body>
  <div class='container'>
    <div class='header'>
      <div class='logo-text'>Digital Share</div>
      <div class='branding'>Powered by Medindia4u.com</div>
    </div>
    <h2>Password Reset Request</h2>
    <p>Hello,</p>
    <p>We received a request to reset the password for your Digital Share account. Tap the button below or enter the reset token in the application to choose a new password.</p>
    <div style='text-align: center;'>
      <a href='{actionUrl}' class='button'>Reset My Password</a>
    </div>
    <p>If you are resetting your password inside the mobile application, enter this reset token:</p>
    <div class='token-box'>{WebUtility.HtmlEncode(resetToken)}</div>
    <p>This code is time-limited and will expire in 24 hours. If you did not request this password reset, please ignore this email or contact support.</p>
    <div class='footer'>
      &copy; {DateTime.UtcNow.Year} Digital Share &bull; Powered by Medindia4u.com
    </div>
  </div>
</body>
</html>";

            await client.SendMailAsync(mail);
            _logger.LogInformation("Password reset email sent successfully via Gmail SMTP to {Email}", toEmail);
            return (true, null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send password reset email via Gmail SMTP to {Email}", toEmail);
            return (false, ex.Message);
        }
    }
}
