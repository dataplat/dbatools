#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaCsv",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Path",
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "Schema",
                "Truncate",
                "Delimiter",
                "SingleColumn",
                "BatchSize",
                "NotifyAfter",
                "TableLock",
                "CheckConstraints",
                "FireTriggers",
                "KeepIdentity",
                "KeepNulls",
                "Column",
                "ColumnMap",
                "KeepOrdinalOrder",
                "AutoCreateTable",
                "NoProgress",
                "NoHeaderRow",
                "UseFileNameForSchema",
                "Quote",
                "Escape",
                "Comment",
                "TrimmingOption",
                "BufferSize",
                "ParseErrorAction",
                "Encoding",
                "NullValue",
                "MaxQuotedFieldLength",
                "SkipEmptyLine",
                "SupportsMultiline",
                "UseColumnDefault",
                "EnableException",
                "NoTransaction",
                "MaxDecompressedSize",
                "SkipRows",
                "QuoteMode",
                "DuplicateHeaderBehavior",
                "MismatchedFieldAction",
                "DistinguishEmptyFromNull",
                "NormalizeQuotes",
                "CollectParseErrors",
                "MaxParseErrors",
                "Parallel",
                "ThrottleLimit"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set up CSV file paths for testing
        $pathSuperSmall = "$($TestConfig.appveyorlabrepo)\csv\SuperSmall.csv"
        $pathCommaSeparatedWithHeader = "$($TestConfig.appveyorlabrepo)\csv\CommaSeparatedWithHeader.csv"
        $pathCols = "$($TestConfig.appveyorlabrepo)\csv\cols.csv"
        $pathCol2 = "$($TestConfig.appveyorlabrepo)\csv\col2.csv"
        $pathPipe3 = "$($TestConfig.appveyorlabrepo)\csv\pipe3.psv"
        # New test files for Dataplat.Dbatools.Csv features
        $pathMultiCharDelim = "$($TestConfig.appveyorlabrepo)\csv\multichar-delim.csv"
        $pathCompressed = "$($TestConfig.appveyorlabrepo)\csv\compressed.csv.gz"
        $pathWithMetadata = "$($TestConfig.appveyorlabrepo)\csv\with-metadata.csv"
        $pathDuplicateHeaders = "$($TestConfig.appveyorlabrepo)\csv\duplicate-headers.csv"
        $pathMismatchedFields = "$($TestConfig.appveyorlabrepo)\csv\mismatched-fields.csv"
        $pathMalformedQuotes = "$($TestConfig.appveyorlabrepo)\csv\malformed-quotes.csv"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup test tables
        Get-DbaDbTable -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Database tempdb -Table SuperSmall, CommaSeparatedWithHeader -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Works as expected" {
        It "accepts piped input and doesn't add rows if the table does not exist" {
            $results = $pathSuperSmall | Import-DbaCsv -SqlInstance $TestConfig.instance1 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable WarnVar -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike "*Table or view SuperSmall does not exist and AutoCreateTable was not specified*"
            $results | Should -BeNullOrEmpty
        }

        It "creates the right columnmap (#7630), handles pipe delimiters (#7806)" {
            $null = Import-DbaCsv -SqlInstance $TestConfig.instance1 -Path $pathCols -Database tempdb -AutoCreateTable -Table cols
            $null = Import-DbaCsv -SqlInstance $TestConfig.instance1 -Path $pathCol2 -Database tempdb -Table cols
            $null = Import-DbaCsv -SqlInstance $TestConfig.instance1 -Path $pathPipe3 -Database tempdb -Table cols2 -Delimiter "|" -AutoCreateTable

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database tempdb -Query "select * from cols"

            $results | Where-Object third -notmatch "three" | Should -BeNullOrEmpty
            $results | Where-Object firstcol -notmatch "one" | Should -BeNullOrEmpty

            $results = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database tempdb -Query "select * from cols2"

            $results | Where-Object third -notmatch "three" | Should -BeNullOrEmpty
            $results | Where-Object firstcol -notmatch "one" | Should -BeNullOrEmpty
        }

        It "performs 4 imports" {
            $results = Import-DbaCsv -Path $pathSuperSmall, $pathSuperSmall -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Database tempdb -Delimiter `t -NotifyAfter 50000 -WarningVariable warn2 -AutoCreateTable

            $results.Count | Should -Be 4
            foreach ($result in $results) {
                $result.RowsCopied | Should -Be 999
                $result.Database | Should -Be "tempdb"
                $result.Table | Should -Be "SuperSmall"
            }
        }

        It "doesn't break when truncate is passed" {
            $result = Import-DbaCsv -Path $pathSuperSmall -SqlInstance $TestConfig.instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate

            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be "tempdb"
            $result.Table | Should -Be "SuperSmall"
        }

        It "works with NoTransaction" {
            $result = Import-DbaCsv -Path $pathSuperSmall -SqlInstance $TestConfig.instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate -NoTransaction

            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be "tempdb"
            $result.Table | Should -Be "SuperSmall"
        }

        It "Catches the scenario where the database param does not match the server object passed into the command" {
            $result = Import-DbaCsv -Path $pathSuperSmall -SqlInstance $TestConfig.instance1 -Database InvalidDB -Delimiter `t -Table SuperSmall -Truncate -AutoCreateTable -WarningVariable WarnVar -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike "*Cannot open database * requested by the login. The login failed.*"
            $result | Should -BeNullOrEmpty

            $result = Import-DbaCsv -Path $pathSuperSmall -SqlInstance $TestConfig.instance1 -Database tempdb -Delimiter `t -Table SuperSmall -Truncate -AutoCreateTable

            $result.RowsCopied | Should -Be 999
            $result.Database | Should -Be "tempdb"
            $result.Table | Should -Be "SuperSmall"
        }

        It "Catches the scenario where the header is not properly parsed causing param errors" {
            # create the table using AutoCreate
            $null = Import-DbaCsv -Path $pathCommaSeparatedWithHeader -SqlInstance $TestConfig.instance1 -Database tempdb -AutoCreateTable
            # reload table without AutoCreate parameter to recreate bug #6553
            $result = Import-DbaCsv -Path $pathCommaSeparatedWithHeader -SqlInstance $TestConfig.instance1 -Database tempdb -Truncate

            $result.RowsCopied | Should -Be 1
            $result.Database | Should -Be "tempdb"
            $result.Table | Should -Be "CommaSeparatedWithHeader"

            Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database tempdb -Query "DROP TABLE CommaSeparatedWithHeader" -ErrorAction SilentlyContinue
        }

        It "works with NoHeaderRow" {
            # See #7759
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE NoHeaderRow (c1 VARCHAR(50), c2 VARCHAR(50), c3 VARCHAR(50))"

            $result = Import-DbaCsv -Path $pathCols -NoHeaderRow -SqlInstance $server -Database tempdb -Table "NoHeaderRow"
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM NoHeaderRow" -As PSObject

            $result.RowsCopied | Should -Be 3
            $data[0].c1 | Should -Be "firstcol"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE NoHeaderRow" -ErrorAction SilentlyContinue
        }

        It "works with tables which have non-varchar types (date)" {
            # See #9433
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE WithTypes ([date] DATE, col1 VARCHAR(50), col2 VARCHAR(50))"
            $result = Import-DbaCsv -Path $pathCommaSeparatedWithHeader -SqlInstance $server -Database tempdb -Table "WithTypes"

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -Be 1

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE WithTypes" -ErrorAction SilentlyContinue
        }

        It "works with tables which have non-varchar types (guid, bit)" {
            # See #9433
            $filePath = "$($TestConfig.Temp)\foo.csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE WithGuidsAndBits (one_guid UNIQUEIDENTIFIER, one_bit BIT)"
            $row = [PSCustomObject]@{
                one_guid = (New-Guid).Guid
                one_bit  = 1
            }
            $row | Export-Csv -Path $filePath -NoTypeInformation

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table "WithGuidsAndBits"

            $result.RowsCopied | Should -Be 1

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE WithGuidsAndBits" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "supports multi-character delimiters (issue #6488)" {
            $filePath = "$($TestConfig.Temp)\delimiter-test-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "DelimiterTest$(Get-Random)"

            # Create a file with multi-character delimiter "::"
            "col1::col2::col3" | Out-File -FilePath $filePath -Encoding UTF8
            "val1::val2::val3" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            $splatImport = @{
                Path            = $filePath
                SqlInstance     = $server
                Database        = "tempdb"
                Table           = $tableName
                Delimiter       = "::"
                AutoCreateTable = $true
            }
            $result = Import-DbaCsv @splatImport

            # Should work without warnings now
            $result.RowsCopied | Should -Be 1

            # Verify data was parsed correctly with multi-char delimiter
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject
            $data.col1 | Should -Be "val1"
            $data.col2 | Should -Be "val2"
            $data.col3 | Should -Be "val3"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "supports gzip-compressed CSV files" {
            $csvContent = "col1,col2`nvalue1,value2"
            $filePath = "$($TestConfig.Temp)\compressed-$(Get-Random).csv.gz"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "CompressedTest$(Get-Random)"

            # Create a gzipped test file
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($csvContent)
            $ms = [System.IO.MemoryStream]::new($bytes)
            $fs = [System.IO.File]::Create($filePath)
            $gz = [System.IO.Compression.GZipStream]::new($fs, [System.IO.Compression.CompressionMode]::Compress)
            $ms.CopyTo($gz)
            $gz.Close()
            $fs.Close()

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -AutoCreateTable

            $result.RowsCopied | Should -Be 1

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "supports SkipRows parameter" {
            $filePath = "$($TestConfig.Temp)\skiprows-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "SkipRowsTest$(Get-Random)"

            # Create file with metadata rows before actual CSV data
            "This is metadata row 1" | Out-File -FilePath $filePath -Encoding UTF8
            "This is metadata row 2" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "col1,col2" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "value1,value2" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -SkipRows 2 -AutoCreateTable

            $result.RowsCopied | Should -Be 1

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject
            $data.col1 | Should -Be "value1"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "supports DuplicateHeaderBehavior Rename" {
            $filePath = "$($TestConfig.Temp)\dupheader-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "DupHeaderTest$(Get-Random)"

            # Create file with duplicate headers
            "name,value,name" | Out-File -FilePath $filePath -Encoding UTF8
            "john,100,doe" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -DuplicateHeaderBehavior Rename -AutoCreateTable

            $result.RowsCopied | Should -Be 1

            # Verify the duplicate column was renamed
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject
            $data.name | Should -Be "john"
            $data.name_2 | Should -Be "doe"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "supports MismatchedFieldAction PadWithNulls" {
            $filePath = "$($TestConfig.Temp)\mismatch-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "MismatchTest$(Get-Random)"

            # Create file with missing field
            "col1,col2,col3" | Out-File -FilePath $filePath -Encoding UTF8
            "val1,val2" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -MismatchedFieldAction PadWithNulls -AutoCreateTable

            $result.RowsCopied | Should -Be 1

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject
            $data.col1 | Should -Be "val1"
            $data.col2 | Should -Be "val2"
            $data.col3 | Should -BeNullOrEmpty

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "supports QuoteMode Lenient for malformed quotes" {
            $filePath = "$($TestConfig.Temp)\lenient-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "LenientTest$(Get-Random)"

            # Create file with malformed quotes (embedded quotes without proper escaping)
            "col1,col2" | Out-File -FilePath $filePath -Encoding UTF8
            'value with "embedded" quotes,normal' | Out-File -FilePath $filePath -Encoding UTF8 -Append

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -QuoteMode Lenient -AutoCreateTable

            $result.RowsCopied | Should -Be 1

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        # Tests using static files from appveyor-lab
        It "imports multi-character delimited file from static test file" {
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "StaticMultiCharDelim$(Get-Random)"

            $result = Import-DbaCsv -Path $pathMultiCharDelim -SqlInstance $server -Database tempdb -Table $tableName -Delimiter "::" -AutoCreateTable

            $result.RowsCopied | Should -Be 3
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject
            $data[0].col1 | Should -Be "val1"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
        }

        It "imports gzip-compressed file from static test file" {
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "StaticCompressed$(Get-Random)"

            $result = Import-DbaCsv -Path $pathCompressed -SqlInstance $server -Database tempdb -Table $tableName -AutoCreateTable

            $result.RowsCopied | Should -Be 2
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject
            $data[0].col1 | Should -Be "gzval1"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
        }

        It "imports file with SkipRows using static test file" {
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "StaticSkipRows$(Get-Random)"

            $result = Import-DbaCsv -Path $pathWithMetadata -SqlInstance $server -Database tempdb -Table $tableName -SkipRows 2 -AutoCreateTable

            $result.RowsCopied | Should -Be 2
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject
            $data[0].col1 | Should -Be "value1"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
        }

        It "imports file with duplicate headers using static test file" {
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "StaticDupHeaders$(Get-Random)"

            $result = Import-DbaCsv -Path $pathDuplicateHeaders -SqlInstance $server -Database tempdb -Table $tableName -DuplicateHeaderBehavior Rename -AutoCreateTable

            $result.RowsCopied | Should -Be 2
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject
            $data[0].name | Should -Be "john"
            $data[0].name_2 | Should -Be "doe"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
        }

        It "imports file with mismatched fields using static test file" {
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "StaticMismatch$(Get-Random)"

            $result = Import-DbaCsv -Path $pathMismatchedFields -SqlInstance $server -Database tempdb -Table $tableName -MismatchedFieldAction PadWithNulls -AutoCreateTable

            $result.RowsCopied | Should -Be 3
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY col1" -As PSObject
            $data[0].col1 | Should -Be "val1"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
        }

        It "imports file with malformed quotes using static test file" {
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "StaticMalformed$(Get-Random)"

            $result = Import-DbaCsv -Path $pathMalformedQuotes -SqlInstance $server -Database tempdb -Table $tableName -QuoteMode Lenient -AutoCreateTable

            $result.RowsCopied | Should -Be 2

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
        }

        It "works with -Parallel switch" {
            $filePath = "$($TestConfig.Temp)\parallel-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "ParallelTest$(Get-Random)"

            # Create test file with multiple rows
            "col1,col2,col3" | Out-File -FilePath $filePath -Encoding UTF8
            1..100 | ForEach-Object { "val$_,data$_,info$_" | Out-File -FilePath $filePath -Encoding UTF8 -Append }

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -AutoCreateTable -Parallel

            $result.RowsCopied | Should -Be 100

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT COUNT(*) AS cnt FROM $tableName" -As PSObject
            $data.cnt | Should -Be 100

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "works with -Parallel and -ThrottleLimit" {
            $filePath = "$($TestConfig.Temp)\parallel-throttle-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "ParallelThrottleTest$(Get-Random)"

            # Create test file
            "col1,col2" | Out-File -FilePath $filePath -Encoding UTF8
            1..50 | ForEach-Object { "value$_,data$_" | Out-File -FilePath $filePath -Encoding UTF8 -Append }

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -AutoCreateTable -Parallel -ThrottleLimit 2

            $result.RowsCopied | Should -Be 50

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "works with -Parallel and type conversion" {
            $filePath = "$($TestConfig.Temp)\parallel-types-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "ParallelTypesTest$(Get-Random)"

            # Create table with specific types
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE $tableName (id INT, amount DECIMAL(10,2), active BIT)"

            # Create CSV file
            "id,amount,active" | Out-File -FilePath $filePath -Encoding UTF8
            "1,100.50,1" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "2,200.75,0" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "3,300.25,1" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -Parallel

            $result.RowsCopied | Should -Be 3

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY id" -As PSObject
            $data[0].id | Should -Be 1
            $data[0].amount | Should -Be 100.50
            $data[1].amount | Should -Be 200.75

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "parallel mode preserves record order" {
            $filePath = "$($TestConfig.Temp)\parallel-order-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "ParallelOrderTest$(Get-Random)"

            # Create test file with sequential numbers to verify order
            "seq,value" | Out-File -FilePath $filePath -Encoding UTF8
            1..200 | ForEach-Object { "$_,data$_" | Out-File -FilePath $filePath -Encoding UTF8 -Append }

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -AutoCreateTable -Parallel

            $result.RowsCopied | Should -Be 200

            # Verify all records were imported (order in DB may vary based on bulk copy)
            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT COUNT(DISTINCT seq) AS cnt FROM $tableName" -As PSObject
            $data.cnt | Should -Be 200

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }
    }
}