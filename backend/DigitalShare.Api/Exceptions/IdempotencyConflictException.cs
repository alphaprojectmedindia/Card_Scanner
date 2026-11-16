namespace DigitalShare.Api.Exceptions;

public class IdempotencyConflictException : Exception
{
    public IdempotencyConflictException(string message) : base(message)
    {
    }

    public IdempotencyConflictException(string message, Exception innerException) : base(message, innerException)
    {
    }
}
