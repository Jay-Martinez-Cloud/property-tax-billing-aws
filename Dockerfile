# ---------- Stage 1: build (big SDK image) ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy only the project file first, then restore (cached unless dependencies change)
COPY src/TaxBilling.Api/TaxBilling.Api.csproj src/TaxBilling.Api/
RUN dotnet restore src/TaxBilling.Api/TaxBilling.Api.csproj

# Now copy the source and publish a release build
COPY src/TaxBilling.Api/ src/TaxBilling.Api/
RUN dotnet publish src/TaxBilling.Api/TaxBilling.Api.csproj -c Release -o /app/publish --no-restore

# ---------- Stage 2: runtime (small image, no SDK) ----------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .

# Run as a non-root user (built into Microsoft's images)
USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "TaxBilling.Api.dll"]