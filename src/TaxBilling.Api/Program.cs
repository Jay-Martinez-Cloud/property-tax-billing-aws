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

// 3. Endpoints
app.MapGet("/bills", () => bills);

app.MapGet("/bills/{parcelId}", (string parcelId) =>
{
    var bill = bills.FirstOrDefault(b => b.ParcelId == parcelId);
    return bill is null ? Results.NotFound() : Results.Ok(bill);
});

app.MapHealthChecks("/health");

// 4. Start the web server
app.Run();

// The shape of a tax bill
record TaxBill(string ParcelId, string Address, int TaxYear, decimal AmountDue, string Status);