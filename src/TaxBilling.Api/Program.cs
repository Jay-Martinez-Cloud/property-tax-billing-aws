using Microsoft.AspNetCore.Mvc;

// 1. Set up the app and register services
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHealthChecks();

var app = builder.Build();

// 2. Sample data (in memory for now; a real database comes later)
var bills = new List<TaxBill>
{
    new("R-1001", "123 Main St", 2026, 2450.00m, "Unpaid"),
    new("R-1002", "88 Oak Ave",  2026, 1875.50m, "Paid"),
};

var payments = new List<Payment>();
var processedKeys = new Dictionary<string, Payment>();

// 3. Endpoints
app.MapGet("/bills", () => bills);

app.MapGet("/bills/{parcelId}", (string parcelId) =>
{
    var bill = bills.FirstOrDefault(b => b.ParcelId == parcelId);
    return bill is null ? Results.NotFound() : Results.Ok(bill);
});

app.MapPost("/payments", (PaymentRequest req,
    [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey) =>
{
    if (string.IsNullOrWhiteSpace(idempotencyKey))
        return Results.BadRequest(new { error = "Idempotency-Key header is required" });

    if (processedKeys.TryGetValue(idempotencyKey, out var existing))   // NEW (B2.3)
        return Results.Ok(existing);                                    // NEW (B2.3)

    var bill = bills.FirstOrDefault(b => b.ParcelId == req.ParcelId);
    if (bill is null)
        return Results.NotFound(new { error = $"No bill found for parcel {req.ParcelId}" });

    if (req.Amount <= 0)
        return Results.BadRequest(new { error = "Amount must be greater than 0" });

    var payment = new Payment(Guid.NewGuid(), req.ParcelId, req.Amount, DateTime.UtcNow);
    payments.Add(payment);
    processedKeys[idempotencyKey] = payment;                            // NEW (B2.3)

    return Results.Created($"/payments/{payment.Id}", payment);
});

app.MapGet("/payments", () => payments);

app.MapHealthChecks("/health");

// 4. Start the web server
app.Run();

// The shape of a tax bill
record TaxBill(string ParcelId, string Address, int TaxYear, decimal AmountDue, string Status);
record PaymentRequest(string ParcelId, decimal Amount);
record Payment(Guid Id, string ParcelId, decimal Amount, DateTime PaidAt);