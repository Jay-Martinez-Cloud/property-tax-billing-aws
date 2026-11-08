using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Npgsql;

// 1. Set up the app and register services
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddHealthChecks();
// Connection string comes from config; in AWS the password is injected separately from Secrets Manager
var connectionString = builder.Configuration.GetConnectionString("TaxBillingDb");
var dbPassword = builder.Configuration["DB_PASSWORD"];
if (!string.IsNullOrEmpty(dbPassword))
{
    var csb = new NpgsqlConnectionStringBuilder(connectionString) { Password = dbPassword };
    connectionString = csb.ConnectionString;
}

builder.Services.AddDbContext<TaxBillingDbContext>(options =>
    options.UseNpgsql(connectionString));


var app = builder.Build();

// 2. Endpoints (data now lives in PostgreSQL)
app.MapGet("/bills", async (TaxBillingDbContext db) =>
    await db.Bills.ToListAsync());

app.MapGet("/bills/{parcelId}", async (string parcelId, TaxBillingDbContext db) =>
{
    var bill = await db.Bills.FindAsync(parcelId);
    return bill is null ? Results.NotFound() : Results.Ok(bill);
});

app.MapPost("/payments", async (PaymentRequest req,
    [FromHeader(Name = "Idempotency-Key")] string? idempotencyKey,
    TaxBillingDbContext db) =>
{
    // Validate the request (rules live in PaymentValidator.cs so they can be unit tested)
    var error = PaymentValidator.Validate(idempotencyKey, req.Amount);   // CHANGED (D2)
    if (error is not null)                                               // CHANGED (D2)
        return Results.BadRequest(new { error });                        // CHANGED (D2)

    // Seen this key before? Return the original payment.
    var existing = await db.Payments.FirstOrDefaultAsync(p => p.IdempotencyKey == idempotencyKey);
    if (existing is not null)
        return Results.Ok(existing);

    var bill = await db.Bills.FindAsync(req.ParcelId);
    if (bill is null)
        return Results.NotFound(new { error = $"No bill found for parcel {req.ParcelId}" });

    // (the old "Amount <= 0" check was removed; PaymentValidator handles it now)

    var payment = new Payment(Guid.NewGuid(), req.ParcelId, req.Amount, DateTime.UtcNow, idempotencyKey!);
    db.Payments.Add(payment);

    try
    {
        await db.SaveChangesAsync();
    }
    catch (DbUpdateException ex) when (ex.InnerException is PostgresException { SqlState: PostgresErrorCodes.UniqueViolation })
    {
        // Two identical requests raced; the database let only one win. Return the winner.
        db.ChangeTracker.Clear();
        var winner = await db.Payments.FirstAsync(p => p.IdempotencyKey == idempotencyKey);
        return Results.Ok(winner);
    }

    return Results.Created($"/payments/{payment.Id}", payment);
});

app.MapGet("/payments", async (TaxBillingDbContext db) =>
    await db.Payments.OrderBy(p => p.PaidAt).ToListAsync());

app.MapHealthChecks("/health");

// 3. Start the web server
app.Run();

// Data shapes
record TaxBill(string ParcelId, string Address, int TaxYear, decimal AmountDue, string Status);
record PaymentRequest(string ParcelId, decimal Amount);
record Payment(Guid Id, string ParcelId, decimal Amount, DateTime PaidAt, string IdempotencyKey);