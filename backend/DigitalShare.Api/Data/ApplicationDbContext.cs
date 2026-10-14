using DigitalShare.Api.Models;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace DigitalShare.Api.Data;

public class ApplicationDbContext : IdentityDbContext<ApplicationUser>
{
    public ApplicationDbContext(DbContextOptions<ApplicationDbContext> options)
        : base(options)
    {
    }

    public DbSet<UserProfile> UserProfiles => Set<UserProfile>();
    public DbSet<Connection> Connections => Set<Connection>();
    public DbSet<ImportedBusinessCard> ImportedBusinessCards => Set<ImportedBusinessCard>();
    public DbSet<ImportedBusinessCardPhone> ImportedBusinessCardPhones => Set<ImportedBusinessCardPhone>();
    public DbSet<ImportedBusinessCardEmail> ImportedBusinessCardEmails => Set<ImportedBusinessCardEmail>();
    public DbSet<AvailabilitySettings> AvailabilitySettings => Set<AvailabilitySettings>();
    public DbSet<AvailabilitySlot> AvailabilitySlots => Set<AvailabilitySlot>();
    public DbSet<MeetingRequest> MeetingRequests => Set<MeetingRequest>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);

        builder.Entity<ApplicationUser>(entity =>
        {
            entity.HasOne(u => u.Profile)
                .WithOne(p => p.User)
                .HasForeignKey<UserProfile>(p => p.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        builder.Entity<UserProfile>(entity =>
        {
            entity.HasKey(p => p.Id);
            entity.HasIndex(p => p.UserId).IsUnique();
            entity.HasIndex(p => p.ShareId).IsUnique();
            entity.Property(p => p.ShareId).IsRequired().HasMaxLength(50);
            entity.Property(p => p.Email).IsRequired().HasMaxLength(256);
            entity.Property(p => p.FullName).HasMaxLength(100);
            entity.Property(p => p.PhoneNumber).HasMaxLength(30);
            entity.Property(p => p.JobTitle).HasMaxLength(100);
            entity.Property(p => p.Company).HasMaxLength(100);
            entity.Property(p => p.Website).HasMaxLength(256);
            entity.Property(p => p.Address).HasMaxLength(256);
            entity.Property(p => p.Bio).HasMaxLength(1000);
            entity.Property(p => p.ProfilePhotoUrl).HasMaxLength(500);
            entity.Property(p => p.CreatedAtUtc).IsRequired();
            entity.Property(p => p.UpdatedAtUtc).IsRequired();
        });

        builder.Entity<Connection>(entity =>
        {
            entity.HasKey(c => c.Id);

            // Composite uniqueness: An owner user cannot save the same profile twice
            entity.HasIndex(c => new { c.OwnerUserId, c.SavedProfileId }).IsUnique();

            // Index to optimize listing an owner's connections
            entity.HasIndex(c => c.OwnerUserId);

            entity.Property(c => c.OwnerUserId).IsRequired();
            entity.Property(c => c.SavedProfileId).IsRequired();
            entity.Property(c => c.CreatedAtUtc).IsRequired();

            entity.HasOne(c => c.OwnerUser)
                .WithMany()
                .HasForeignKey(c => c.OwnerUserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasOne(c => c.SavedProfile)
                .WithMany()
                .HasForeignKey(c => c.SavedProfileId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        builder.Entity<ImportedBusinessCard>(entity =>
        {
            entity.HasKey(c => c.Id);
            entity.HasIndex(c => c.OwnerUserId);

            entity.Property(c => c.OwnerUserId).IsRequired();
            entity.Property(c => c.FullName).HasMaxLength(100);
            entity.Property(c => c.Company).HasMaxLength(100);
            entity.Property(c => c.JobTitle).HasMaxLength(100);
            entity.Property(c => c.Website).HasMaxLength(256);
            entity.Property(c => c.Address).HasMaxLength(500);
            entity.Property(c => c.CreatedAtUtc).IsRequired();
            entity.Property(c => c.UpdatedAtUtc).IsRequired();

            entity.HasOne(c => c.OwnerUser)
                .WithMany()
                .HasForeignKey(c => c.OwnerUserId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany(c => c.PhoneNumbers)
                .WithOne(p => p.ImportedBusinessCard)
                .HasForeignKey(p => p.ImportedBusinessCardId)
                .OnDelete(DeleteBehavior.Cascade);

            entity.HasMany(c => c.EmailAddresses)
                .WithOne(e => e.ImportedBusinessCard)
                .HasForeignKey(e => e.ImportedBusinessCardId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        builder.Entity<ImportedBusinessCardPhone>(entity =>
        {
            entity.HasKey(p => p.Id);
            entity.HasIndex(p => p.NormalizedNumber);
            entity.HasIndex(p => p.ImportedBusinessCardId);

            entity.Property(p => p.Number).IsRequired().HasMaxLength(50);
            entity.Property(p => p.NormalizedNumber).IsRequired().HasMaxLength(50);
            entity.Property(p => p.Label).HasMaxLength(50);
        });

        builder.Entity<ImportedBusinessCardEmail>(entity =>
        {
            entity.HasKey(e => e.Id);
            entity.HasIndex(e => e.NormalizedEmail);
            entity.HasIndex(e => e.ImportedBusinessCardId);

            entity.Property(e => e.Email).IsRequired().HasMaxLength(256);
            entity.Property(e => e.NormalizedEmail).IsRequired().HasMaxLength(256);
            entity.Property(e => e.Label).HasMaxLength(50);
        });

        builder.Entity<AvailabilitySettings>(entity =>
        {
            entity.HasKey(s => s.Id);
            entity.HasIndex(s => s.UserId).IsUnique();
            entity.Property(s => s.UserId).IsRequired();
            entity.Property(s => s.TimeZoneId).IsRequired().HasMaxLength(100);
            entity.Property(s => s.MeetingRequestsEnabled).IsRequired();
            entity.Property(s => s.CreatedAtUtc).IsRequired();
            entity.Property(s => s.UpdatedAtUtc).IsRequired();

            entity.HasOne(s => s.User)
                .WithMany()
                .HasForeignKey(s => s.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        builder.Entity<AvailabilitySlot>(entity =>
        {
            entity.HasKey(s => s.Id);
            entity.HasIndex(s => s.UserId);
            entity.HasIndex(s => new { s.UserId, s.DayOfWeek });
            entity.Property(s => s.UserId).IsRequired();
            entity.Property(s => s.DayOfWeek).IsRequired();
            entity.Property(s => s.StartTime).IsRequired();
            entity.Property(s => s.EndTime).IsRequired();
            entity.Property(s => s.CreatedAtUtc).IsRequired();
            entity.Property(s => s.UpdatedAtUtc).IsRequired();

            entity.HasOne(s => s.User)
                .WithMany()
                .HasForeignKey(s => s.UserId)
                .OnDelete(DeleteBehavior.Cascade);
        });

        builder.Entity<MeetingRequest>(entity =>
        {
            entity.HasKey(m => m.Id);
            entity.HasIndex(m => m.RequesterUserId);
            entity.HasIndex(m => m.RecipientUserId);
            entity.HasIndex(m => m.Status);
            entity.HasIndex(m => new { m.RecipientUserId, m.Status, m.StartAtUtc, m.EndAtUtc });
            entity.Property(m => m.RequesterUserId).IsRequired();
            entity.Property(m => m.RecipientUserId).IsRequired();
            entity.Property(m => m.StartAtUtc).IsRequired();
            entity.Property(m => m.EndAtUtc).IsRequired();
            entity.Property(m => m.Title).HasMaxLength(200);
            entity.Property(m => m.Note).HasMaxLength(2000);
            entity.Property(m => m.Status)
                .IsRequired()
                .HasConversion<string>()
                .HasMaxLength(20);
            entity.Property(m => m.CreatedAtUtc).IsRequired();
            entity.Property(m => m.UpdatedAtUtc).IsRequired();

            entity.HasOne(m => m.RequesterUser)
                .WithMany()
                .HasForeignKey(m => m.RequesterUserId)
                .OnDelete(DeleteBehavior.Restrict);

            entity.HasOne(m => m.RecipientUser)
                .WithMany()
                .HasForeignKey(m => m.RecipientUserId)
                .OnDelete(DeleteBehavior.Restrict);
        });
    }
}
