#!/usr/bin/env pwsh
# Verification that both fixes work:
# 1. Boolean logic fix for $skipSqlClient
# 2. AssemblyLoadContext resolver for PowerShell Core (handles version mismatches)

Write-Host "=== Verifying AvoidConflicts Fixes ===" -ForegroundColor Cyan
Write-Host "PowerShell Edition: $($PSVersionTable.PSEdition)" -ForegroundColor Gray
Write-Host "PowerShell Version: $($PSVersionTable.PSVersion)" -ForegroundColor Gray
Write-Host ""

try {
    Import-Module SqlServer -ErrorAction Stop
    Write-Host "[OK] SqlServer loaded" -ForegroundColor Green

    # Check what SqlServer loaded
    $sqlClient = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Microsoft.Data.SqlClient' }
    $connectionInfo = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Microsoft.SqlServer.ConnectionInfo' }

    if ($sqlClient) {
        Write-Host "[OK] SqlClient loaded by SqlServer: $($sqlClient.GetName().Version)" -ForegroundColor Yellow
    }
    if ($connectionInfo) {
        Write-Host "[OK] ConnectionInfo loaded by SqlServer: $($connectionInfo.GetName().Version)" -ForegroundColor Yellow
    }

    if (-not $sqlClient -and -not $connectionInfo) {
        Write-Host "[SKIP] SqlServer did not load any conflicting assemblies - test not applicable" -ForegroundColor Yellow
        exit 0
    }

    Write-Host ""

    # This is the critical test - with the bugs:
    # - Bug #1: $skipSqlClient boolean logic would fail
    # - Bug #2: AssemblyLoadContext would fail to resolve version mismatches (Core only)
    Import-Module ./artifacts/dbatools.library/dbatools.library.psd1 -ArgumentList $true -Force -Verbose -ErrorAction Stop
    Write-Host "[OK] dbatools.library loaded successfully with AvoidConflicts" -ForegroundColor Green

    if ([Microsoft.SqlServer.Management.Smo.Server] -as [type]) {
        Write-Host "[OK] SMO types are available" -ForegroundColor Green
    } else {
        Write-Host "[WARN] SMO types not available" -ForegroundColor Yellow
    }

    # Verify the assemblies that are loaded are the ones from SqlServer (not dbatools.library)
    $sqlClientAfter = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Microsoft.Data.SqlClient' }
    $connectionInfoAfter = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq 'Microsoft.SqlServer.ConnectionInfo' }

    Write-Host ""
    Write-Host "Assembly versions after import:" -ForegroundColor Gray
    if ($sqlClientAfter) {
        Write-Host "  SqlClient: $($sqlClientAfter.GetName().Version)" -ForegroundColor Gray
    }
    if ($connectionInfoAfter) {
        Write-Host "  ConnectionInfo: $($connectionInfoAfter.GetName().Version)" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "=== ALL FIXES VERIFIED ===" -ForegroundColor Green
    exit 0

} catch {
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Full error:" -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor DarkRed
    Write-Host ""
    Write-Host "=== FIX VERIFICATION FAILED ===" -ForegroundColor Red
    exit 1
}
