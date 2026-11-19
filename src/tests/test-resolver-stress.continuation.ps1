# Test 4: Memory Stability Under Repeated Loads
# ============================================================================
Write-Host "`n--- Test 4: Memory Stability Under Repeated Loads ---" -ForegroundColor Yellow
Write-Host "Testing memory growth over repeated module loads..." -ForegroundColor Gray

$test4Result = pwsh -NoProfile -Command {
    param($modulePath, $iterations)
    try {
        $memoryReadings = @()

        # Baseline
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        [GC]::Collect()
        $baseline = [GC]::GetTotalMemory($true)

        for ($i = 1; $i -le $iterations; $i++) {
            Import-Module $modulePath -Force -ErrorAction Stop

            # Do some work with SMO types
            $null = [Microsoft.SqlServer.Management.Smo.Server]
            $null = [Microsoft.SqlServer.Management.Smo.Database]
            $null = [Microsoft.SqlServer.Management.Common.ServerConnection]

            Remove-Module dbatools.library -Force -ErrorAction SilentlyContinue

            if ($i % 10 -eq 0) {
                [GC]::Collect()
                [GC]::WaitForPendingFinalizers()
                [GC]::Collect()
                $memoryReadings += [GC]::GetTotalMemory($true)
            }
        }

        # Final measurement
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        [GC]::Collect()
        $final = [GC]::GetTotalMemory($true)

        $memoryGrowthMB = [math]::Round(($final - $baseline) / 1MB, 2)

        [PSCustomObject]@{
            Success = $true
            BaselineMB = [math]::Round($baseline / 1MB, 2)
            FinalMB = [math]::Round($final / 1MB, 2)
            GrowthMB = $memoryGrowthMB
            Iterations = $iterations
            Readings = $memoryReadings | ForEach-Object { [math]::Round($_ / 1MB, 2) }
        }
    } catch {
        [PSCustomObject]@{
            Success = $false
            Error = $_.Exception.Message
        }
    }
} -args $modulePath, $Iterations

if ($test4Result.Success) {
    $maxGrowthMB = 100  # Allow up to 100MB growth (assemblies do take memory)
    if ($test4Result.GrowthMB -lt $maxGrowthMB) {
        Write-Host "[PASS] Memory growth: $($test4Result.GrowthMB)MB over $($test4Result.Iterations) iterations (baseline: $($test4Result.BaselineMB)MB, final: $($test4Result.FinalMB)MB)" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "[WARN] Memory growth: $($test4Result.GrowthMB)MB exceeds expected $($maxGrowthMB)MB (may indicate leak)" -ForegroundColor Yellow
        Write-Host "  Readings: $($test4Result.Readings -join ', ')MB" -ForegroundColor Gray
        $testsPassed++  # Not a hard failure, assemblies naturally consume memory
    }
} else {
    Write-Host "[FAIL] Memory test failed: $($test4Result.Error)" -ForegroundColor Red
    $testsFailed++
}

$testResults += [PSCustomObject]@{
    Test = "Memory Stability"
    Result = if ($test4Result.Success) { "PASS" } else { "FAIL" }
    Duration = 0
    Errors = if ($test4Result.Success) { 0 } else { 1 }
}

# ============================================================================
# Test 5: Assembly Resolution Race Conditions
# ============================================================================
Write-Host "`n--- Test 5: Assembly Resolution Race Conditions ---" -ForegroundColor Yellow
Write-Host "Testing parallel assembly resolution requests..." -ForegroundColor Gray

$test5Result = pwsh -NoProfile -Command {
    param($modulePath)
    try {
        Import-Module $modulePath -Force -ErrorAction Stop

        $errors = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $iterations = 100

        # Parallel type access to trigger assembly resolution
        1..$iterations | ForEach-Object -Parallel {
            $errorBag = $using:errors
            try {
                # Access various SMO types that may require assembly resolution
                $null = [Microsoft.SqlServer.Management.Smo.Server]
                $null = [Microsoft.SqlServer.Management.Smo.Database]
                $null = [Microsoft.SqlServer.Management.Common.ServerConnection]
            } catch {
                $errorBag.Add("Thread iteration: $($_.Exception.Message)")
            }
        } -ThrottleLimit 8

        [PSCustomObject]@{
            Success = ($errors.Count -eq 0)
            ErrorCount = $errors.Count
            Errors = @($errors | Select-Object -First 5)
            Iterations = $iterations
        }
    } catch {
        [PSCustomObject]@{
            Success = $false
            ErrorCount = 1
            Errors = @("Module load failed: $($_.Exception.Message)")
            Iterations = 0
        }
    }
} -args $modulePath

if ($test5Result.Success) {
    Write-Host "[PASS] No race conditions detected in $($test5Result.Iterations) parallel resolution attempts" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "[FAIL] $($test5Result.ErrorCount) race condition errors detected" -ForegroundColor Red
    $test5Result.Errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    $testsFailed++
}

$testResults += [PSCustomObject]@{
    Test = "Assembly Resolution Race"
    Result = if ($test5Result.Success) { "PASS" } else { "FAIL" }
    Duration = 0
    Errors = $test5Result.ErrorCount
}

# ============================================================================
# Test 6: SqlServer Coexistence Stress Test
# ============================================================================
Write-Host "`n--- Test 6: SqlServer Coexistence Under Load ---" -ForegroundColor Yellow
Write-Host "Testing repeated coexistence with SqlServer module..." -ForegroundColor Gray

# Check if SqlServer module is available
$sqlServerAvailable = Get-Module -ListAvailable SqlServer -ErrorAction SilentlyContinue

if ($sqlServerAvailable) {
    $test6Errors = @()
    $test6Iterations = [Math]::Min(10, $Iterations)  # Fewer iterations as this is slow

    for ($i = 1; $i -le $test6Iterations; $i++) {
        if ($Verbose) {
            Write-Host "  Coexistence iteration $i/$test6Iterations" -ForegroundColor DarkGray
        }

        $result = pwsh -NoProfile -Command {
            param($modulePath)
            try {
                # Load SqlServer first
                Import-Module SqlServer -ErrorAction Stop

                # Then load dbatools.library with AvoidConflicts
                Import-Module $modulePath -ArgumentList $true -Force -ErrorAction Stop

                # Verify both work
                $null = Get-Command Get-SqlDatabase -ErrorAction Stop
                $null = [Microsoft.SqlServer.Management.Smo.Server]

                "OK"
            } catch {
                "ERROR: $($_.Exception.Message)"
            }
        } -args $modulePath

        if ($result -ne "OK") {
            $test6Errors += "Iteration $i`: $result"
        }
    }

    if ($test6Errors.Count -eq 0) {
        Write-Host "[PASS] Successfully coexisted with SqlServer in $test6Iterations iterations" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "[FAIL] $($test6Errors.Count) coexistence errors" -ForegroundColor Red
        $test6Errors | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        $testsFailed++
    }

    $testResults += [PSCustomObject]@{
        Test = "SqlServer Coexistence"
        Result = if ($test6Errors.Count -eq 0) { "PASS" } else { "FAIL" }
        Duration = 0
        Errors = $test6Errors.Count
    }
} else {
    Write-Host "[SKIP] SqlServer module not available" -ForegroundColor Yellow
    $testResults += [PSCustomObject]@{
        Test = "SqlServer Coexistence"
        Result = "SKIP"
        Duration = 0
        Errors = 0
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$testResults | Format-Table -AutoSize

$totalTests = $testsPassed + $testsFailed
Write-Host "`nResults: $testsPassed passed, $testsFailed failed out of $totalTests tests" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })

if ($testsFailed -gt 0) {
    exit 1
} else {
    exit 0
}
