# Performance comparison test
$env:PSModulePath = "C:\github\dbatools.library\artifacts;$env:PSModulePath"
Set-Location 'C:\github\dbatools'
Remove-Module dbatools -ErrorAction SilentlyContinue
Remove-Module dbatools.library -ErrorAction SilentlyContinue
Import-Module .\dbatools.psm1 -Force
$TestConfig = Get-TestConfig
$PSDefaultParameterValues['*:SqlCredential'] = $TestConfig.SqlCred

Write-Host "=== PERFORMANCE TEST: 1.17M row CSV file ===" -ForegroundColor Cyan
Write-Host ""

$csvPath = 'C:\github\appveyor-lab\csv\Logfile.CSV'
$fileInfo = Get-Item $csvPath
Write-Host "File: $csvPath"
Write-Host "Size: $([math]::Round($fileInfo.Length / 1MB, 2)) MB"
Write-Host ""

# Run test 3 times and average
$results = @()
$runs = 3

for ($i = 1; $i -le $runs; $i++) {
    Write-Host "Run $i of $runs..." -ForegroundColor Yellow

    # Drop table if exists
    Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "IF OBJECT_ID('dbo.PerfTest', 'U') IS NOT NULL DROP TABLE dbo.PerfTest" -ErrorAction SilentlyContinue

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $result = Import-DbaCsv -Path $csvPath -SqlInstance localhost -Database tempdb -Schema dbo -Table PerfTest -Delimiter ',' -AutoCreateTable -Truncate

    $sw.Stop()

    $results += [PSCustomObject]@{
        Run = $i
        RowsCopied = $result.RowsCopied
        Seconds = $sw.Elapsed.TotalSeconds
        RowsPerSecond = [math]::Round($result.RowsCopied / $sw.Elapsed.TotalSeconds)
        MBPerSecond = [math]::Round($fileInfo.Length / 1MB / $sw.Elapsed.TotalSeconds, 2)
    }

    Write-Host "  Rows: $($result.RowsCopied) | Time: $([math]::Round($sw.Elapsed.TotalSeconds, 1))s | Rate: $([math]::Round($result.RowsCopied / $sw.Elapsed.TotalSeconds)) rows/s" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== RESULTS ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize

$avgRowsPerSec = [math]::Round(($results.RowsPerSecond | Measure-Object -Average).Average)
$avgMBPerSec = [math]::Round(($results.MBPerSecond | Measure-Object -Average).Average, 2)
$avgSeconds = [math]::Round(($results.Seconds | Measure-Object -Average).Average, 1)

Write-Host "AVERAGES:" -ForegroundColor Green
Write-Host "  Average Time: $avgSeconds seconds"
Write-Host "  Average Rate: $avgRowsPerSec rows/second"
Write-Host "  Average Throughput: $avgMBPerSec MB/second"
Write-Host ""

# Memory check
Write-Host "=== MEMORY USAGE ===" -ForegroundColor Cyan
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
$memMB = [math]::Round([GC]::GetTotalMemory($true) / 1MB, 2)
Write-Host "Managed heap: $memMB MB"

Write-Host ""
Write-Host "=== PARALLEL PROCESSING TEST ===" -ForegroundColor Cyan

# Drop and recreate
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "IF OBJECT_ID('dbo.PerfTestParallel', 'U') IS NOT NULL DROP TABLE dbo.PerfTestParallel" -ErrorAction SilentlyContinue

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$result = Import-DbaCsv -Path $csvPath -SqlInstance localhost -Database tempdb -Schema dbo -Table PerfTestParallel -Delimiter ',' -AutoCreateTable -Truncate -Parallel
$sw.Stop()

Write-Host "Parallel import:" -ForegroundColor Green
Write-Host "  Rows: $($result.RowsCopied)"
Write-Host "  Time: $([math]::Round($sw.Elapsed.TotalSeconds, 1)) seconds"
Write-Host "  Rate: $([math]::Round($result.RowsCopied / $sw.Elapsed.TotalSeconds)) rows/second"

Write-Host ""
Write-Host "=== DONE ===" -ForegroundColor Cyan
