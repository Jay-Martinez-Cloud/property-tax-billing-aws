public class PaymentValidatorTests
{
    [Fact]
    public void Valid_request_passes()
    {
        var error = PaymentValidator.Validate("pay-001", 2450.00m);

        Assert.Null(error);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void Missing_idempotency_key_is_rejected(string? key)
    {
        var error = PaymentValidator.Validate(key, 100m);

        Assert.Equal("Idempotency-Key header is required", error);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(-50)]
    public void Zero_or_negative_amount_is_rejected(int amount)
    {
        var error = PaymentValidator.Validate("pay-001", amount);

        Assert.Equal("Amount must be greater than 0", error);
    }
}