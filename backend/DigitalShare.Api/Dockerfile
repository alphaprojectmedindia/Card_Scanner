FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY backend/DigitalShare.Api/DigitalShare.Api.csproj backend/DigitalShare.Api/
RUN dotnet restore backend/DigitalShare.Api/DigitalShare.Api.csproj

COPY backend/DigitalShare.Api/ backend/DigitalShare.Api/
WORKDIR /src/backend/DigitalShare.Api

RUN dotnet publish DigitalShare.Api.csproj -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS final
WORKDIR /app

COPY --from=build /app/publish .

ENV ASPNETCORE_ENVIRONMENT=Production

ENTRYPOINT ["dotnet", "DigitalShare.Api.dll"]