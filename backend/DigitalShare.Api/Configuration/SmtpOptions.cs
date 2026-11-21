namespace DigitalShare.Api.Configuration;

public class SmtpOptions
{
    public const string SectionName = "Smtp";

    public string Host { get; set; } = "smtp.gmail.com";
    public int Port { get; set; } = 587;
    public string Username { get; set; } = string.Empty;
    public string Password { get; set; } = string.Empty;
    public string FromEmail { get; set; } = "no-reply@medindia4u.com";
    public string FromName { get; set; } = "Digital Share (Powered by Medindia4u.com)";
    public bool EnableSsl { get; set; } = true;
}
