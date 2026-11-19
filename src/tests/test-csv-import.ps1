# Force load fresh library from artifacts
$env:PSModulePath = "C:\github\dbatools.library\artifacts;$env:PSModulePath"

Set-Location 'C:\github\dbatools'
Remove-Module dbatools -ErrorAction SilentlyContinue
Remove-Module dbatools.library -ErrorAction SilentlyContinue

# Remove any loaded dbatools assembly
[AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -like "*dbatools*" } | ForEach-Object {
    Write-Host "Found loaded assembly: $($_.FullName)" -ForegroundColor Yellow
}

Import-Module .\dbatools.psm1 -Force
$TestConfig = Get-TestConfig
$PSDefaultParameterValues['*:SqlCredential'] = $TestConfig.SqlCred

# Check if CSV reader type is available
Write-Host "`n=== Checking CSV Reader Type ===" -ForegroundColor Cyan
try {
    $type = [Dataplat.Dbatools.Csv.Reader.CsvReaderOptions]
    Write-Host "[OK] CsvReaderOptions type is available" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] CsvReaderOptions type NOT found: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`nTesting connection..."
Test-DbaConnection -SqlInstance localhost | Format-Table -AutoSize

Write-Host "`n=== Test 1: Import cols.csv (3 columns, 2 data rows) ==="
$params1 = @{
    Path            = 'C:\github\appveyor-lab\csv\cols.csv'
    SqlInstance     = 'localhost'
    Database        = 'tempdb'
    Schema          = 'dbo'
    Table           = 'TestCols'
    Delimiter       = ','
    Truncate        = $true
    AutoCreateTable = $true
}
$result1 = Import-DbaCsv @params1
$result1 | Format-List

Write-Host "`n=== Validating TestCols data ==="
$query1 = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestCols"
$query1 | Format-Table -AutoSize

Write-Host "`nRow count in TestCols:"
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT COUNT(*) as Cnt FROM dbo.TestCols" | Format-Table

Write-Host "`n=== Test 2: Import CommaSeparatedWithHeader.csv ==="
$params2 = @{
    Path            = 'C:\github\appveyor-lab\csv\CommaSeparatedWithHeader.csv'
    SqlInstance     = 'localhost'
    Database        = 'tempdb'
    Schema          = 'dbo'
    Table           = 'TestWithHeader'
    Delimiter       = ','
    Truncate        = $true
    AutoCreateTable = $true
}
$result2 = Import-DbaCsv @params2
$result2 | Format-List

Write-Host "`n=== Validating TestWithHeader data ==="
$query2 = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestWithHeader"
$query2 | Format-Table -AutoSize

Write-Host "`n=== Test 3: Import SuperSmall.csv (1000 rows, single column no header) ==="
$params3 = @{
    Path            = 'C:\github\appveyor-lab\csv\SuperSmall.csv'
    SqlInstance     = 'localhost'
    Database        = 'tempdb'
    Schema          = 'dbo'
    Table           = 'TestSuperSmall'
    Delimiter       = ','
    Truncate        = $true
    AutoCreateTable = $true
    NoHeaderRow     = $true
    SingleColumn    = $true
}
$result3 = Import-DbaCsv @params3
$result3 | Format-List

Write-Host "`n=== Validating SuperSmall data ==="
Write-Host "Row count:"
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT COUNT(*) as Cnt FROM dbo.TestSuperSmall" | Format-Table

Write-Host "`nFirst 10 rows:"
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT TOP 10 * FROM dbo.TestSuperSmall" | Format-Table -AutoSize

Write-Host "`n=== Test 4: Import BIG Logfile.CSV (1.17M rows, 7 columns) ==="
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$params4 = @{
    Path            = 'C:\github\appveyor-lab\csv\Logfile.CSV'
    SqlInstance     = 'localhost'
    Database        = 'tempdb'
    Schema          = 'dbo'
    Table           = 'TestLogfile'
    Delimiter       = ','
    Truncate        = $true
    AutoCreateTable = $true
}
$result4 = Import-DbaCsv @params4
$sw.Stop()
Write-Host "Import took: $($sw.Elapsed.TotalSeconds) seconds" -ForegroundColor Green
$result4 | Format-List

Write-Host "`n=== Validating Logfile data ==="
Write-Host "Row count (expecting ~1,173,222 rows):"
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT COUNT(*) as Cnt FROM dbo.TestLogfile" | Format-Table

Write-Host "`nFirst 10 rows:"
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT TOP 10 * FROM dbo.TestLogfile" | Format-Table -AutoSize

Write-Host "`nSample of distinct ProcessNames:"
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT TOP 20 ProcessName, COUNT(*) as Cnt FROM dbo.TestLogfile GROUP BY ProcessName ORDER BY Cnt DESC" | Format-Table -AutoSize

Write-Host "`nSample of distinct Operations:"
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT TOP 20 Operation, COUNT(*) as Cnt FROM dbo.TestLogfile GROUP BY Operation ORDER BY Cnt DESC" | Format-Table -AutoSize

Write-Host "`n=== Deep validation - checking column types ==="
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH,
    IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME IN ('TestCols', 'TestWithHeader', 'TestSuperSmall', 'TestLogfile')
ORDER BY TABLE_NAME, ORDINAL_POSITION
" | Format-Table -AutoSize

Write-Host "`n=== Verifying exact data match for cols.csv ==="
Write-Host "Expected: firstcol=one, second=two, third=three"
Write-Host "Expected: firstcol=one1, second=two2, third=three3"
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestCols ORDER BY firstcol" | Format-Table -AutoSize

Write-Host "`n=== Verifying exact data match for CommaSeparatedWithHeader.csv ==="
Write-Host 'Expected: date=20210221, col1=test, col2=test2'
Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestWithHeader" | Format-Table -AutoSize

Write-Host "`n=== DONE ==="
