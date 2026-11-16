# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Restore dependencies
COPY backend/DigitalShare.Api/DigitalShare.Api.csproj backend/DigitalShare.Api/
RUN dotnet restore backend/DigitalShare.Api/DigitalShare.Api.csproj

# Build and publish application
COPY backend/DigitalShare.Api/ backend/DigitalShare.Api/
WORKDIR /src/backend/DigitalShare.Api

RUN dotnet publish DigitalShare.Api.csproj -c Release -o /app/publish --no-restore

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

COPY --from=build /app/publish .

# Install curl for container health checks
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*

# Default environment and port configuration
ENV ASPNETCORE_ENVIRONMENT=Production
ENV PORT=10000

# Expose Render standard port
EXPOSE 10000

# Docker container healthcheck targeting Render health check route
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:${PORT:-10000}/health || exit 1

ENTRYPOINT ["dotnet", "DigitalShare.Api.dll"]
