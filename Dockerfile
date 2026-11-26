# ---------- Stage 1: build (big SDK image) ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

# Copy only the project file first, then restore (cached unless dependencies change)
COPY src/TaxBilling.Api/TaxBilling.Api.csproj src/TaxBilling.Api/
RUN dotnet restore src/TaxBilling.Api/TaxBilling.Api.csproj

# Now copy the source and publish a release build
COPY src/TaxBilling.Api/ src/TaxBilling.Api/
RUN dotnet publish src/TaxBilling.Api/TaxBilling.Api.csproj -c Release -o /app/publish --no-restore

# Keep only the Datadog tracer files this image uses (linux-arm64 native + net6.0 managed)
RUN cd /app/publish/datadog && \
    rm -rf linux-x64 linux-musl-arm64 linux-musl-x64 osx win-x64 win-x86 \
    net461 netcoreapp3.1 netstandard2.0 dd-dotnet.cmd

# Build an EF Core migration bundle (a standalone executable that applies migrations)
RUN dotnet tool install --global dotnet-ef --version 10.0.14
ENV PATH="$PATH:/root/.dotnet/tools"
RUN ConnectionStrings__TaxBillingDb="Host=localhost" \
    dotnet ef migrations bundle --project src/TaxBilling.Api/TaxBilling.Api.csproj \
    --configuration Release --output /app/publish/efbundle

# ---------- Stage 2: runtime (small image, no SDK) ----------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .



# Datadog .NET tracer (from the Datadog.Trace.Bundle NuGet package, copied with the published app)
ENV CORECLR_ENABLE_PROFILING=1 \
    CORECLR_PROFILER={846F5F1C-F9AE-4B07-969E-05C26BC060D8} \
    CORECLR_PROFILER_PATH=/app/datadog/linux-arm64/Datadog.Trace.ClrProfiler.Native.so \
    DD_DOTNET_TRACER_HOME=/app/datadog \
    DD_TRACE_LOG_DIRECTORY=/tmp/datadog-logs


# Run as a non-root user (built into Microsoft's images)
USER $APP_UID
EXPOSE 8080
CMD ["dotnet", "TaxBilling.Api.dll"]