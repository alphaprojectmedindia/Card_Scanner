using System.Security.Cryptography;

namespace DigitalShare.Api.Services;

public interface IShareIdGenerator
{
    string GenerateShareId();
}

public class ShareIdGenerator : IShareIdGenerator
{
    private const int ByteLength = 18; // 18 bytes * 8 = 144 bits of cryptographic entropy

    public string GenerateShareId()
    {
        var randomBytes = RandomNumberGenerator.GetBytes(ByteLength);
        return Convert.ToBase64String(randomBytes)
            .Replace('+', '-')
            .Replace('/', '_')
            .TrimEnd('=');
    }
}
