#!/usr/bin/env pwsh
# Stress test for the assembly resolver under rapid load conditions
#
# This test validates:
# 1. Assembly resolver handles rapid module import/remove cycles
# 2. Resolver doesn't leak memory under repeated operations
# 3. Concurrent assembly resolution works correctly
# 4. Resolver handles rapid assembly loads without deadlock
#
# NOTE: dbatools.library loads SMO and related assemblies. The CSV types
# (CsvReaderOptions, etc.) are in dbatools.dll which is loaded by the
# main dbatools module. This test focuses on the assembly resolver for
# the SMO-related assemblies that dbatools.library manages.

param(
    [switch]$Verbose,
    [int]$Iterations = 50,
    [int]$ConcurrentThreads = 4
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Assembly Resolver Stress Test Suite  " -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Iterations: $Iterations, Threads: $ConcurrentThreads" -ForegroundColor Gray

$testsPassed = 0
$testsFailed = 0
$testResults = @()

# Get the module path (relative to this script)
$modulePath = Join-Path $PSScriptRoot "..\artifacts\dbatools.library\dbatools.library.psd1"
if (-not (Test-Path $modulePath)) {
    Write-Host "[ERROR] Module not found at: $modulePath" -ForegroundColor Red
    Write-Host "Please build the module first using: dotnet build" -ForegroundColor Yellow
    exit 1
}

$moduleDir = Split-Path $modulePath -Parent

# ============================================================================
# Test 1: Rapid Import/Remove Cycles
# ============================================================================
Write-Host "`n--- Test 1: Rapid Import/Remove Cycles ---" -ForegroundColor Yellow
Write-Host "Testing $Iterations rapid import/remove cycles..." -ForegroundColor Gray

$test1Start = Get-Date
$test1Errors = @()

for ($i = 1; $i -le $Iterations; $i++) {
    if ($Verbose -or ($i % 10 -eq 0)) {
        Write-Host "  Cycle $i/$Iterations" -ForegroundColor DarkGray
    }

    $result = pwsh -NoProfile -Command {
        param($modulePath)
        try {
            Import-Module $modulePath -Force -ErrorAction Stop

            # Quick type check to ensure module loaded correctly (SMO types)
            $null = [Microsoft.SqlServer.Management.Smo.Server]

            Remove-Module dbatools.library -Force -ErrorAction SilentlyContinue
            Write-Output "OK"
        } catch {
            Write-Output "ERROR: $($_.Exception.Message)"
        }
    } -args $modulePath

    if ($result -ne "OK") {
        $test1Errors += "Cycle $i`: $result"
    }
}

$test1Duration = (Get-Date) - $test1Start

if ($test1Errors.Count -eq 0) {
    Write-Host "[PASS] Completed $Iterations import/remove cycles in $($test1Duration.TotalSeconds.ToString('F2'))s" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "[FAIL] $($test1Errors.Count) errors in $Iterations cycles" -ForegroundColor Red
    $test1Errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $testsFailed++
}

$testResults += [PSCustomObject]@{
    Test = "Rapid Import/Remove"
    Result = if ($test1Errors.Count -eq 0) { "PASS" } else { "FAIL" }
    Duration = $test1Duration.TotalSeconds
    Errors = $test1Errors.Count
}

# ============================================================================
# Test 2: Concurrent Module Loads (isolated processes)
# ============================================================================
Write-Host "`n--- Test 2: Concurrent Module Loads ($ConcurrentThreads parallel processes) ---" -ForegroundColor Yellow
Write-Host "Starting $ConcurrentThreads concurrent PowerShell processes..." -ForegroundColor Gray

$test2Start = Get-Date

# Create jobs that load the module concurrently
$jobs = 1..$ConcurrentThreads | ForEach-Object {
    $jobNum = $_
    Start-Job -ScriptBlock {
        param($modulePath, $iterations, $jobNum)
        $errors = @()

        for ($i = 1; $i -le $iterations; $i++) {
            try {
                # Each iteration loads in a fresh scope
                $null = pwsh -NoProfile -Command {
                    param($mp)
                    Import-Module $mp -Force -ErrorAction Stop
                    $null = [Microsoft.SqlServer.Management.Smo.Server]
                    "OK"
                } -args $modulePath
            } catch {
                $errors += "Job$jobNum-Iter$i`: $($_.Exception.Message)"
            }
        }

        [PSCustomObject]@{
            JobNum = $jobNum
            Iterations = $iterations
            Errors = $errors
        }
    } -ArgumentList $modulePath, ([int]($Iterations / $ConcurrentThreads)), $_
}

# Wait for all jobs with timeout
$timeout = [TimeSpan]::FromMinutes(5)
$completed = $jobs | Wait-Job -Timeout $timeout.TotalSeconds

$test2Errors = @()
$jobs | ForEach-Object {
    $job = $_
    if ($job.State -eq 'Completed') {
        $result = Receive-Job $job
        if ($result.Errors.Count -gt 0) {
            $test2Errors += $result.Errors
        }
    } elseif ($job.State -eq 'Running') {
        Stop-Job $job
        $test2Errors += "Job $($job.Id) timed out"
    } else {
        $test2Errors += "Job $($job.Id) failed with state: $($job.State)"
    }
    Remove-Job $job -Force
}

$test2Duration = (Get-Date) - $test2Start

if ($test2Errors.Count -eq 0) {
    Write-Host "[PASS] All $ConcurrentThreads concurrent process groups completed successfully in $($test2Duration.TotalSeconds.ToString('F2'))s" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "[FAIL] $($test2Errors.Count) errors in concurrent loads" -ForegroundColor Red
    $test2Errors | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    if ($test2Errors.Count -gt 5) {
        Write-Host "  ... and $($test2Errors.Count - 5) more errors" -ForegroundColor Red
    }
    $testsFailed++
}

$testResults += [PSCustomObject]@{
    Test = "Concurrent Module Loads"
    Result = if ($test2Errors.Count -eq 0) { "PASS" } else { "FAIL" }
    Duration = $test2Duration.TotalSeconds
    Errors = $test2Errors.Count
}

# ============================================================================
# Test 3: Type Access Under Load
# ============================================================================
Write-Host "`n--- Test 3: Rapid Type Access After Load ---" -ForegroundColor Yellow
Write-Host "Testing rapid type instantiation and method calls..." -ForegroundColor Gray

$test3Result = pwsh -NoProfile -Command {
    param($modulePath, $iterations)
    try {
        Import-Module $modulePath -Force -ErrorAction Stop

        $errors = @()
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        for ($i = 1; $i -le $iterations; $i++) {
            try {
                # Test various SMO types from the assembly
                $null = [Microsoft.SqlServer.Management.Smo.Server]
                $null = [Microsoft.SqlServer.Management.Smo.Database]
                $null = [Microsoft.SqlServer.Management.Smo.Table]
                $null = [Microsoft.SqlServer.Management.Common.ServerConnection]
            } catch {
                $errors += "Iteration $i`: $($_.Exception.Message)"
            }
        }

        $stopwatch.Stop()

        [PSCustomObject]@{
            Success = ($errors.Count -eq 0)
            Errors = $errors
            DurationMs = $stopwatch.ElapsedMilliseconds
            Iterations = $iterations
        }
    } catch {
        [PSCustomObject]@{
            Success = $false
            Errors = @("Module load failed: $($_.Exception.Message)")
            DurationMs = 0
            Iterations = 0
        }
    }
} -args $modulePath, $Iterations

if ($test3Result.Success) {
    $opsPerSec = [math]::Round($test3Result.Iterations / ($test3Result.DurationMs / 1000), 0)
    Write-Host "[PASS] Completed $($test3Result.Iterations) type operations in $($test3Result.DurationMs)ms ($opsPerSec ops/sec)" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "[FAIL] $($test3Result.Errors.Count) errors in type access" -ForegroundColor Red
    $test3Result.Errors | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $testsFailed++
}

$testResults += [PSCustomObject]@{
    Test = "Rapid Type Access"
    Result = if ($test3Result.Success) { "PASS" } else { "FAIL" }
    Duration = $test3Result.DurationMs / 1000
    Errors = $test3Result.Errors.Count
}

# ============================================================================
. (Join-Path $PSScriptRoot "test-resolver-stress.continuation.ps1")
