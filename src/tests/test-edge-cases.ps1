# Edge case testing for CSV import
$env:PSModulePath = "C:\github\dbatools.library\artifacts;$env:PSModulePath"
Set-Location 'C:\github\dbatools'
Remove-Module dbatools -ErrorAction SilentlyContinue
Remove-Module dbatools.library -ErrorAction SilentlyContinue
Import-Module .\dbatools.psm1 -Force
$TestConfig = Get-TestConfig
$PSDefaultParameterValues['*:SqlCredential'] = $TestConfig.SqlCred

$testsPassed = 0
$testsFailed = 0
$results = @()

function Test-CsvImport {
    param(
        [string]$TestName,
        [string]$Path,
        [hashtable]$Params,
        [int]$ExpectedRows,
        [scriptblock]$Validation
    )

    Write-Host "`n=== $TestName ===" -ForegroundColor Cyan

    try {
        $defaultParams = @{
            SqlInstance     = 'localhost'
            Database        = 'tempdb'
            Truncate        = $true
            AutoCreateTable = $true
        }

        $mergedParams = $defaultParams.Clone()
        foreach ($key in $Params.Keys) {
            $mergedParams[$key] = $Params[$key]
        }
        $mergedParams['Path'] = $Path

        $result = Import-DbaCsv @mergedParams

        if ($result.RowsCopied -eq $ExpectedRows) {
            Write-Host "[PASS] Imported $($result.RowsCopied) rows as expected" -ForegroundColor Green

            if ($Validation) {
                $validationResult = & $Validation
                if ($validationResult) {
                    Write-Host "[PASS] Data validation passed" -ForegroundColor Green
                    $script:testsPassed++
                } else {
                    Write-Host "[FAIL] Data validation failed" -ForegroundColor Red
                    $script:testsFailed++
                }
            } else {
                $script:testsPassed++
            }
        } else {
            Write-Host "[FAIL] Expected $ExpectedRows rows, got $($result.RowsCopied)" -ForegroundColor Red
            $script:testsFailed++
        }

        return $result
    }
    catch {
        Write-Host "[FAIL] Exception: $_" -ForegroundColor Red
        $script:testsFailed++
        return $null
    }
}

# ============== TEST 1: Duplicate Headers ==============
Test-CsvImport -TestName "Duplicate Headers (Rename)" `
    -Path "C:\github\appveyor-lab\csv\duplicate-headers.csv" `
    -Params @{
        Schema = 'dbo'
        Table = 'TestDuplicateHeaders'
        Delimiter = ','
        DuplicateHeaderBehavior = 'Rename'
    } `
    -ExpectedRows 2 `
    -Validation {
        $cols = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'TestDuplicateHeaders' ORDER BY ORDINAL_POSITION"
        Write-Host "  Columns: $($cols.COLUMN_NAME -join ', ')"
        # Should have 3 columns: name, value, name_2 (renamed duplicate)
        return ($cols.Count -eq 3 -and ($cols.COLUMN_NAME -contains 'name_2'))
    }

# ============== TEST 2: Mismatched Fields (Pad with nulls) ==============
Test-CsvImport -TestName "Mismatched Fields (PadWithNulls)" `
    -Path "C:\github\appveyor-lab\csv\mismatched-fields.csv" `
    -Params @{
        Schema = 'dbo'
        Table = 'TestMismatchedPad'
        Delimiter = ','
        MismatchedFieldAction = 'PadWithNulls'
    } `
    -ExpectedRows 3 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestMismatchedPad"
        # First row has 2 values, so col3 should be null
        $hasNull = $null -eq $data[0].col3 -or [string]::IsNullOrEmpty($data[0].col3)
        Write-Host "  Row 1 col3 is null/empty: $hasNull"
        return ($data.Count -eq 3 -and $hasNull)
    }

# ============== TEST 3: Multi-character delimiter ==============
Test-CsvImport -TestName "Multi-character Delimiter (::)" `
    -Path "C:\github\appveyor-lab\csv\multichar-delim.csv" `
    -Params @{
        Schema = 'dbo'
        Table = 'TestMultiChar'
        Delimiter = '::'
    } `
    -ExpectedRows 3 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestMultiChar"
        Write-Host "  First row: col1=$($data[0].col1), col2=$($data[0].col2), col3=$($data[0].col3)"
        return ($data[0].col1 -eq 'val1' -and $data[0].col2 -eq 'val2' -and $data[0].col3 -eq 'val3')
    }

# ============== TEST 4: File with metadata rows (skip rows) ==============
Test-CsvImport -TestName "Skip Metadata Rows" `
    -Path "C:\github\appveyor-lab\csv\with-metadata.csv" `
    -Params @{
        Schema = 'dbo'
        Table = 'TestSkipRows'
        Delimiter = ','
        SkipRows = 2
    } `
    -ExpectedRows 2 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestSkipRows"
        Write-Host "  First row: col1=$($data[0].col1), col2=$($data[0].col2), col3=$($data[0].col3)"
        return ($data[0].col1 -eq 'value1')
    }

# ============== TEST 5: Empty CSV (header only) ==============
$emptyCSV = "C:\github\dbatools.library\test-empty.csv"
"col1,col2,col3" | Set-Content $emptyCSV
Write-Host "`n=== Empty CSV (Header Only) ===" -ForegroundColor Cyan
try {
    $result = Import-DbaCsv -Path $emptyCSV -SqlInstance localhost -Database tempdb -Schema dbo -Table TestEmpty -Delimiter ',' -AutoCreateTable -Truncate
    if ($result.RowsCopied -eq 0) {
        Write-Host "[PASS] Empty file handled correctly (0 rows)" -ForegroundColor Green
        $testsPassed++
    } else {
        Write-Host "[FAIL] Expected 0 rows" -ForegroundColor Red
        $testsFailed++
    }
} catch {
    Write-Host "[FAIL] Exception: $_" -ForegroundColor Red
    $testsFailed++
}
Remove-Item $emptyCSV -ErrorAction SilentlyContinue

# ============== TEST 6: Quoted fields with embedded commas ==============
$quotedCSV = "C:\github\dbatools.library\test-quoted.csv"
@"
name,address,city
"John Doe","123 Main St, Apt 4","New York, NY"
"Jane Smith","456 Oak Ave, Suite 100","Los Angeles, CA"
"@ | Set-Content $quotedCSV

Test-CsvImport -TestName "Quoted Fields with Embedded Commas" `
    -Path $quotedCSV `
    -Params @{
        Schema = 'dbo'
        Table = 'TestQuoted'
        Delimiter = ','
    } `
    -ExpectedRows 2 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestQuoted"
        Write-Host "  Address 1: $($data[0].address)"
        # The embedded comma should be preserved
        return ($data[0].address -eq '123 Main St, Apt 4')
    }
Remove-Item $quotedCSV -ErrorAction SilentlyContinue

# ============== TEST 7: Quoted fields with embedded quotes ==============
$embeddedQuotesCSV = "C:\github\dbatools.library\test-embedded-quotes.csv"
@"
name,quote,source
"John","He said ""Hello World""","Test"
"Jane","The ""quick"" brown fox","Example"
"@ | Set-Content $embeddedQuotesCSV

Test-CsvImport -TestName "Quoted Fields with Embedded Quotes" `
    -Path $embeddedQuotesCSV `
    -Params @{
        Schema = 'dbo'
        Table = 'TestEmbeddedQuotes'
        Delimiter = ','
    } `
    -ExpectedRows 2 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestEmbeddedQuotes"
        Write-Host "  Quote 1: $($data[0].quote)"
        # The escaped quotes should become single quotes
        return ($data[0].quote -eq 'He said "Hello World"')
    }
Remove-Item $embeddedQuotesCSV -ErrorAction SilentlyContinue

# ============== TEST 8: Multiline fields ==============
$multilineCSV = "C:\github\dbatools.library\test-multiline.csv"
@"
name,description,value
"Item1","This is a
multi-line
description","100"
"Item2","Single line","200"
"@ | Set-Content $multilineCSV

Test-CsvImport -TestName "Multiline Fields" `
    -Path $multilineCSV `
    -Params @{
        Schema = 'dbo'
        Table = 'TestMultiline'
        Delimiter = ','
    } `
    -ExpectedRows 2 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestMultiline"
        Write-Host "  Description length: $($data[0].description.Length)"
        # Should contain newlines
        return ($data[0].description -match "`n" -or $data[0].description -match "`r")
    }
Remove-Item $multilineCSV -ErrorAction SilentlyContinue

# ============== TEST 9: Unicode data ==============
$unicodeCSV = "C:\github\dbatools.library\test-unicode.csv"
@"
name,city,emoji
北京市,中国,🎉
東京,日本,🗼
München,Deutschland,🍺
"@ | Set-Content $unicodeCSV -Encoding UTF8

Test-CsvImport -TestName "Unicode Data" `
    -Path $unicodeCSV `
    -Params @{
        Schema = 'dbo'
        Table = 'TestUnicode'
        Delimiter = ','
    } `
    -ExpectedRows 3 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestUnicode"
        Write-Host "  Row 1 name: $($data[0].name), city: $($data[0].city)"
        return ($data[0].name -eq '北京市' -and $data[1].name -eq '東京')
    }
Remove-Item $unicodeCSV -ErrorAction SilentlyContinue

# ============== TEST 10: Very long lines ==============
$longLineCSV = "C:\github\dbatools.library\test-longline.csv"
$longValue = "x" * 10000
@"
id,longfield
1,$longValue
2,short
"@ | Set-Content $longLineCSV

Test-CsvImport -TestName "Very Long Lines (10KB field)" `
    -Path $longLineCSV `
    -Params @{
        Schema = 'dbo'
        Table = 'TestLongLine'
        Delimiter = ','
    } `
    -ExpectedRows 2 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT LEN(longfield) as len FROM dbo.TestLongLine WHERE id = '1'"
        Write-Host "  Long field length: $($data.len)"
        return ($data.len -eq 10000)
    }
Remove-Item $longLineCSV -ErrorAction SilentlyContinue

# ============== TEST 11: Tab-delimited ==============
$tsvFile = "C:\github\dbatools.library\test-tab.tsv"
"col1`tcol2`tcol3`nval1`tval2`tval3`nval4`tval5`tval6" | Set-Content $tsvFile

Test-CsvImport -TestName "Tab-Delimited File" `
    -Path $tsvFile `
    -Params @{
        Schema = 'dbo'
        Table = 'TestTSV'
        Delimiter = "`t"
    } `
    -ExpectedRows 2 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestTSV"
        return ($data[0].col1 -eq 'val1' -and $data[0].col2 -eq 'val2')
    }
Remove-Item $tsvFile -ErrorAction SilentlyContinue

# ============== TEST 12: Null value handling ==============
$nullCSV = "C:\github\dbatools.library\test-null.csv"
@"
id,name,value
1,NULL,100
2,,200
3,Actual,NULL
"@ | Set-Content $nullCSV

Test-CsvImport -TestName "NULL Value Handling" `
    -Path $nullCSV `
    -Params @{
        Schema = 'dbo'
        Table = 'TestNull'
        Delimiter = ','
        NullValue = 'NULL'
    } `
    -ExpectedRows 3 `
    -Validation {
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT * FROM dbo.TestNull WHERE name IS NULL"
        Write-Host "  Rows with NULL name: $($data.Count)"
        return ($data.Count -ge 1)
    }
Remove-Item $nullCSV -ErrorAction SilentlyContinue

# ============== TEST 13: Column mapping (map specific columns) ==============
# Note: -Column parameter is for SqlBulkCopy column mapping, not filtering
# When AutoCreateTable is used, all columns are created; -Column just maps which to insert
$colSelectCSV = "C:\github\dbatools.library\test-colselect.csv"
@"
id,name,email,phone,address
1,John,john@example.com,555-1234,123 Main St
2,Jane,jane@example.com,555-5678,456 Oak Ave
"@ | Set-Content $colSelectCSV

Test-CsvImport -TestName "Column Mapping (map id,name,email only)" `
    -Path $colSelectCSV `
    -Params @{
        Schema = 'dbo'
        Table = 'TestColSelect'
        Delimiter = ','
        Column = @('id','name','email')
    } `
    -ExpectedRows 2 `
    -Validation {
        # When using Column mapping with AutoCreateTable, all columns are still created
        # but only the mapped columns have data - phone and address will be NULL
        $data = Invoke-DbaQuery -SqlInstance localhost -Database tempdb -Query "SELECT phone, address FROM dbo.TestColSelect WHERE id = '1'"
        Write-Host "  Phone: [$($data.phone)], Address: [$($data.address)]"
        # phone and address should be empty/null since we only mapped id,name,email
        $phoneEmpty = [string]::IsNullOrEmpty($data.phone)
        $addrEmpty = [string]::IsNullOrEmpty($data.address)
        return ($phoneEmpty -and $addrEmpty)
    }
Remove-Item $colSelectCSV -ErrorAction SilentlyContinue

# ============== SUMMARY ==============
Write-Host "`n`n========================================" -ForegroundColor White
Write-Host "       TEST SUMMARY" -ForegroundColor White
Write-Host "========================================" -ForegroundColor White
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -gt 0) { 'Red' } else { 'Green' })
Write-Host "Total:  $($testsPassed + $testsFailed)" -ForegroundColor White

if ($testsFailed -eq 0) {
    Write-Host "`nALL EDGE CASE TESTS PASSED!" -ForegroundColor Green
} else {
    Write-Host "`nSOME TESTS FAILED - REVIEW BEFORE RELEASE" -ForegroundColor Red
}
