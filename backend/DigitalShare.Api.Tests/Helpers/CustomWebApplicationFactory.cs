using System.Text.Json;
using DigitalShare.Api.Data;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Formatters;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace DigitalShare.Api.Tests.Helpers;

public class CustomWebApplicationFactory : WebApplicationFactory<Program>
{
    private readonly string _dbName = "TestDb_" + Guid.NewGuid().ToString();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Remove real DbContext registration (PostgreSQL)
            var descriptors = services.Where(d =>
                d.ServiceType == typeof(DbContextOptions<ApplicationDbContext>) ||
                d.ServiceType == typeof(DbContextOptions)).ToList();

            foreach (var descriptor in descriptors)
            {
                services.Remove(descriptor);
            }

            // Register in-memory DbContext for fast and isolated testing
            services.AddDbContext<ApplicationDbContext>(options =>
            {
                options.UseInMemoryDatabase(_dbName);
            });

            // Replace SystemTextJsonOutputFormatter with a stream-writing formatter to resolve the
            // .NET 10/9 runtime PipeWriter.UnflushedBytes incompatibility with TestHost's ResponseBodyPipeWriter
            services.PostConfigure<MvcOptions>(options =>
            {
                var formatters = options.OutputFormatters;
                for (int i = 0; i < formatters.Count; i++)
                {
                    if (formatters[i] is SystemTextJsonOutputFormatter)
                    {
                        formatters[i] = new TestStreamJsonOutputFormatter();
                    }
                }
            });
        });
    }

    private class TestStreamJsonOutputFormatter : TextOutputFormatter
    {
        public TestStreamJsonOutputFormatter()
        {
            SupportedEncodings.Add(System.Text.Encoding.UTF8);
            SupportedEncodings.Add(System.Text.Encoding.Unicode);
            SupportedMediaTypes.Add(Microsoft.Net.Http.Headers.MediaTypeHeaderValue.Parse("application/json"));
            SupportedMediaTypes.Add(Microsoft.Net.Http.Headers.MediaTypeHeaderValue.Parse("text/json"));
            SupportedMediaTypes.Add(Microsoft.Net.Http.Headers.MediaTypeHeaderValue.Parse("application/*+json"));
        }

        public override async Task WriteResponseBodyAsync(OutputFormatterWriteContext context, System.Text.Encoding selectedEncoding)
        {
            var response = context.HttpContext.Response;
            var objectType = context.ObjectType ?? context.Object?.GetType() ?? typeof(object);
            var jsonOptions = context.HttpContext.RequestServices.GetService<IOptions<JsonOptions>>()?.Value.JsonSerializerOptions
                              ?? new JsonSerializerOptions(JsonSerializerDefaults.Web);

            await JsonSerializer.SerializeAsync(
                response.Body,
                context.Object,
                objectType,
                jsonOptions,
                context.HttpContext.RequestAborted);
        }
    }
}
