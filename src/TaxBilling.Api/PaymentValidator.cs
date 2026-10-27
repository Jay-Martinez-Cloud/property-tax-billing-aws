public static class PaymentValidator
{
    // Returns an error message, or null if the request is valid.
    public static string? Validate(string? idempotencyKey, decimal amount)
    {
        if (string.IsNullOrWhiteSpace(idempotencyKey))
            return "Idempotency-Key header is required";

        if (amount <= 0)
            return "Amount must be greater than 0";

        return null;
    }
}
