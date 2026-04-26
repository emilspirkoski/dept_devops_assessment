using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Microsoft.Data.SqlClient;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/health", async () =>
{
    var results = new Dictionary<string, object>();

    // --- Key Vault sample call ---
    // The Key Vault URL is set via KEYVAULT_URL app setting at deploy time.
    var kvUrl = app.Configuration["KeyVaultUrl"];
    if (!string.IsNullOrWhiteSpace(kvUrl))
    {
        try
        {
            var client = new SecretClient(new Uri(kvUrl), new DefaultAzureCredential());
            // Fetch one secret to prove Managed Identity → Key Vault access works.
            KeyVaultSecret secret = await client.GetSecretAsync("app-insights-connection-string");
            results["keyvault"] = "ok";
        }
        catch (Exception ex)
        {
            results["keyvault"] = $"error: {ex.Message}";
        }
    }
    else
    {
        results["keyvault"] = "skipped (KeyVaultUrl not configured)";
    }

    // --- SQL Database sample call ---
    // Connection string is injected via #{TOKEN}# substitution at deploy time.
    var connStr = app.Configuration.GetConnectionString("DefaultConnection");
    if (!string.IsNullOrWhiteSpace(connStr))
    {
        try
        {
            await using var conn = new SqlConnection(connStr);
            await conn.OpenAsync();
            await using var cmd = new SqlCommand("SELECT @@VERSION", conn);
            var version = (string?)await cmd.ExecuteScalarAsync();
            results["sqldb"] = version?.Split('\n')[0].Trim() ?? "ok";
        }
        catch (Exception ex)
        {
            results["sqldb"] = $"error: {ex.Message}";
        }
    }
    else
    {
        results["sqldb"] = "skipped (connection string not configured)";
    }

    return Results.Ok(new
    {
        status = "healthy",
        environment = app.Environment.EnvironmentName,
        checks = results
    });
});

app.MapGet("/", () => Results.Redirect("/health"));

app.Run();
