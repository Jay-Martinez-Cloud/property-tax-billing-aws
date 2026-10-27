using Microsoft.EntityFrameworkCore;

class TaxBillingDbContext(DbContextOptions<TaxBillingDbContext> options) : DbContext(options)
{
    public DbSet<TaxBill> Bills => Set<TaxBill>();
    public DbSet<Payment> Payments => Set<Payment>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // Bills: ParcelId is the primary key
        modelBuilder.Entity<TaxBill>().HasKey(b => b.ParcelId);
        modelBuilder.Entity<TaxBill>().Property(b => b.AmountDue).HasPrecision(12, 2);

        // Seed the two sample bills into the table
        modelBuilder.Entity<TaxBill>().HasData(
            new TaxBill("R-1001", "123 Main St", 2026, 2450.00m, "Unpaid"),
            new TaxBill("R-1002", "88 Oak Ave", 2026, 1875.50m, "Paid"));

        // Payments: money precision + one payment per idempotency key
        modelBuilder.Entity<Payment>().Property(p => p.Amount).HasPrecision(12, 2);
        modelBuilder.Entity<Payment>().HasIndex(p => p.IdempotencyKey).IsUnique();
    }
}