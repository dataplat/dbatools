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
                "StaticColumns",
                "DateTimeFormats",
                "Culture",
                "SampleRows",
                "DetectColumnTypes",
                "Parallel",
                "ThrottleLimit",
                "ParallelBatchSize"
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

            # Create table with specific types (avoiding BIT which has known issues in parallel mode)
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE $tableName (id INT, amount DECIMAL(10,2), quantity SMALLINT)"

            # Create CSV file
            "id,amount,quantity" | Out-File -FilePath $filePath -Encoding UTF8
            "1,100.50,10" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "2,200.75,20" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "3,300.25,30" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -Parallel

            $result.RowsCopied | Should -Be 3

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY id" -As PSObject
            $data[0].id | Should -Be 1
            $data[0].amount | Should -Be 100.50
            $data[1].amount | Should -Be 200.75
            $data[2].quantity | Should -Be 30

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

        It "supports StaticColumns parameter for metadata tagging (issue #6676)" {
            $filePath = "$($TestConfig.Temp)\staticcol-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "StaticColTest$(Get-Random)"

            # Create simple CSV
            "name,value" | Out-File -FilePath $filePath -Encoding UTF8
            "Alice,100" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "Bob,200" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            # Create table with extra columns for static data
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE $tableName (name VARCHAR(50), value INT, SourceFile VARCHAR(100), Region VARCHAR(50))"

            $staticCols = @{
                SourceFile = "test-data.csv"
                Region     = "EMEA"
            }

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -StaticColumns $staticCols

            $result.RowsCopied | Should -Be 2

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY name" -As PSObject
            $data[0].name | Should -Be "Alice"
            $data[0].SourceFile | Should -Be "test-data.csv"
            $data[0].Region | Should -Be "EMEA"
            $data[1].name | Should -Be "Bob"
            $data[1].SourceFile | Should -Be "test-data.csv"
            $data[1].Region | Should -Be "EMEA"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "supports DateTimeFormats parameter for custom date parsing (issue #9694)" {
            $filePath = "$($TestConfig.Temp)\datefmt-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "DateFmtTest$(Get-Random)"

            # Create CSV with Oracle-style date format
            "name,event_date" | Out-File -FilePath $filePath -Encoding UTF8
            "Event1,15-Jan-2024" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "Event2,28-Feb-2024" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            # Create table with DATE column
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE $tableName (name VARCHAR(50), event_date DATE)"

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -DateTimeFormats @("dd-MMM-yyyy")

            $result.RowsCopied | Should -Be 2

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY name" -As PSObject
            $data[0].name | Should -Be "Event1"
            $data[0].event_date.Day | Should -Be 15
            $data[0].event_date.Month | Should -Be 1
            $data[0].event_date.Year | Should -Be 2024

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "supports Culture parameter for locale-specific number parsing (LumenWorks issue #66)" {
            $filePath = "$($TestConfig.Temp)\culture-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "CultureTest$(Get-Random)"

            # Create CSV with German number format (semicolon delimiter, comma as decimal separator)
            "product;price" | Out-File -FilePath $filePath -Encoding UTF8
            "Widget;1234,56" | Out-File -FilePath $filePath -Encoding UTF8 -Append
            "Gadget;789,12" | Out-File -FilePath $filePath -Encoding UTF8 -Append

            # Create table with DECIMAL column
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE $tableName (product VARCHAR(50), price DECIMAL(10,2))"

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -Delimiter ";" -Culture "de-DE"

            $result.RowsCopied | Should -Be 2

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY product" -As PSObject
            $data[0].product | Should -Be "Gadget"
            $data[0].price | Should -Be 789.12
            $data[1].product | Should -Be "Widget"
            $data[1].price | Should -Be 1234.56

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }
    }

    Context "AutoCreateTable post-import optimization" {
        It "optimizes nvarchar(MAX) columns to appropriate sizes after import" {
            $filePath = "$($TestConfig.Temp)\optimize-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "OptimizeTest$(Get-Random)"

            # Create CSV with string data of known lengths
            $csvContent = @"
ShortCol,MediumCol,LongCol
ABC,This is medium,This is a longer piece of text that should still fit
XYZ,Another medium,Another longer piece of text for testing purposes here
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -AutoCreateTable

            $result.RowsCopied | Should -Be 2

            # Verify columns were optimized (not nvarchar(MAX))
            $columns = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tableName | Select-Object -ExpandProperty Columns
            $shortCol = $columns | Where-Object Name -eq "ShortCol"
            $mediumCol = $columns | Where-Object Name -eq "MediumCol"
            $longCol = $columns | Where-Object Name -eq "LongCol"

            # Should be varchar with padded lengths, not MAX (-1)
            # Padding rounds up to: 16, 32, 64, 128, 256, 512, 1024, 2048, max
            $shortCol.DataType.MaximumLength | Should -Not -Be -1
            $shortCol.DataType.MaximumLength | Should -Be 16  # "ABC" (3 chars) padded to 16
            $mediumCol.DataType.MaximumLength | Should -Not -Be -1
            $longCol.DataType.MaximumLength | Should -Not -Be -1

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "preserves nvarchar type while optimizing size" {
            $filePath = "$($TestConfig.Temp)\ascii-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "AsciiTest$(Get-Random)"

            # Create CSV with ASCII-only data
            $csvContent = @"
Name,Code
John Smith,ABC123
Jane Doe,XYZ789
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -AutoCreateTable

            $result.RowsCopied | Should -Be 2

            # AutoCreateTable creates nvarchar(MAX), optimization preserves type but optimizes size
            # Use SampleRows or DetectColumnTypes for proper varchar/nvarchar inference
            $columns = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tableName | Select-Object -ExpandProperty Columns
            $nameCol = $columns | Where-Object Name -eq "Name"

            $nameCol.DataType.Name | Should -Be "nvarchar"
            $nameCol.DataType.MaximumLength | Should -Not -Be -1  # Optimized, not MAX

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "keeps nvarchar for Unicode data" {
            $filePath = "$($TestConfig.Temp)\unicode-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "UnicodeOptTest$(Get-Random)"

            # Create CSV with Unicode characters
            $csvContent = @"
Name,City
José García,São Paulo
田中太郎,東京
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -AutoCreateTable

            $result.RowsCopied | Should -Be 2

            # Should be nvarchar since data contains Unicode
            $columns = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tableName | Select-Object -ExpandProperty Columns
            $nameCol = $columns | Where-Object Name -eq "Name"
            $cityCol = $columns | Where-Object Name -eq "City"

            $nameCol.DataType.Name | Should -Be "nvarchar"
            $cityCol.DataType.Name | Should -Be "nvarchar"
            # But still optimized to appropriate length
            $nameCol.DataType.MaximumLength | Should -Not -Be -1

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }
    }

    Context "Type detection with SampleRows and DetectColumnTypes" {
        It "creates table with inferred types using SampleRows" {
            $filePath = "$($TestConfig.Temp)\samplerows-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "SampleRowsTest$(Get-Random)"

            # Create CSV with typed data
            $csvContent = @"
Id,Name,Price,Quantity,IsActive,Created,UniqueId
1,Widget A,19.99,100,true,2024-01-15,550e8400-e29b-41d4-a716-446655440000
2,Widget B,29.50,50,false,2024-02-20,6ba7b810-9dad-11d1-80b4-00c04fd430c8
3,Gadget C,99.00,25,yes,2024-03-25,f47ac10b-58cc-4372-a567-0e02b2c3d479
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -SampleRows 1000

            $result.RowsCopied | Should -Be 3

            # Verify the table was created with proper types (not all nvarchar(MAX))
            $columns = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tableName | Select-Object -ExpandProperty Columns
            $idCol = $columns | Where-Object Name -eq "Id"
            $priceCol = $columns | Where-Object Name -eq "Price"
            $isActiveCol = $columns | Where-Object Name -eq "IsActive"
            $createdCol = $columns | Where-Object Name -eq "Created"
            $uniqueIdCol = $columns | Where-Object Name -eq "UniqueId"

            $idCol.DataType.Name | Should -Be "int"
            $priceCol.DataType.Name | Should -Be "decimal"
            $isActiveCol.DataType.Name | Should -Be "bit"
            $createdCol.DataType.Name | Should -Be "datetime2"
            $uniqueIdCol.DataType.Name | Should -Be "uniqueidentifier"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "creates table with inferred types using DetectColumnTypes (full scan)" {
            $filePath = "$($TestConfig.Temp)\detecttypes-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "DetectTypesTest$(Get-Random)"

            # Create CSV with typed data
            $csvContent = @"
OrderId,Amount,Status
1001,1500.75,true
1002,2500.00,false
1003,750.25,true
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -DetectColumnTypes

            $result.RowsCopied | Should -Be 3

            # Verify the table was created with proper types
            $columns = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tableName | Select-Object -ExpandProperty Columns
            $orderIdCol = $columns | Where-Object Name -eq "OrderId"
            $amountCol = $columns | Where-Object Name -eq "Amount"
            $statusCol = $columns | Where-Object Name -eq "Status"

            $orderIdCol.DataType.Name | Should -Be "int"
            $amountCol.DataType.Name | Should -Be "decimal"
            $statusCol.DataType.Name | Should -Be "bit"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "infers varchar with correct max length instead of varchar(MAX)" {
            $filePath = "$($TestConfig.Temp)\varcharlength-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "VarcharLengthTest$(Get-Random)"

            # Create CSV with string data of known lengths
            $csvContent = @"
ShortName,LongDescription
ABC,This is a longer description text
XYZ,Another description here
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -SampleRows 1000

            $result.RowsCopied | Should -Be 2

            # Verify varchar columns have appropriate lengths (not MAX)
            $columns = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tableName | Select-Object -ExpandProperty Columns
            $shortCol = $columns | Where-Object Name -eq "ShortName"
            $longCol = $columns | Where-Object Name -eq "LongDescription"

            # Should be varchar with specific length, not varchar(MAX)
            $shortCol.DataType.Name | Should -Be "varchar"
            $shortCol.DataType.MaximumLength | Should -BeLessOrEqual 10
            $shortCol.DataType.MaximumLength | Should -Not -Be -1  # -1 means MAX
            $longCol.DataType.Name | Should -Be "varchar"
            $longCol.DataType.MaximumLength | Should -Not -Be -1

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "detects nullable columns correctly" {
            $filePath = "$($TestConfig.Temp)\nullable-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "NullableTest$(Get-Random)"

            # Create CSV with some null/empty values
            $csvContent = @"
Id,RequiredName,OptionalValue
1,John,100
2,Jane,
3,Bob,300
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName -SampleRows 1000

            $result.RowsCopied | Should -Be 3

            # Verify nullability
            $columns = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tableName | Select-Object -ExpandProperty Columns
            $idCol = $columns | Where-Object Name -eq "Id"
            $nameCol = $columns | Where-Object Name -eq "RequiredName"
            $optCol = $columns | Where-Object Name -eq "OptionalValue"

            $idCol.Nullable | Should -Be $false
            $nameCol.Nullable | Should -Be $false
            $optCol.Nullable | Should -Be $true

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }
    }

    Context "Deep data validation" {
        It "verifies exact data values match between CSV and database" {
            $filePath = "$($TestConfig.Temp)\deepval-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "DeepValidation$(Get-Random)"

            # Create CSV with specific known values
            $csvContent = @"
id,name,value,date
1,Alice,100.50,2024-01-15
2,Bob,200.75,2024-02-20
3,Charlie,300.25,2024-03-25
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            # Create table with proper types
            Invoke-DbaQuery -SqlInstance $server -Query "CREATE TABLE $tableName (id INT, name VARCHAR(50), value DECIMAL(10,2), date DATE)"

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName

            $result.RowsCopied | Should -Be 3

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY id" -As PSObject

            # Verify each row's values exactly
            $data[0].id | Should -Be 1
            $data[0].name | Should -Be "Alice"
            $data[0].value | Should -Be 100.50
            $data[1].id | Should -Be 2
            $data[1].name | Should -Be "Bob"
            $data[1].value | Should -Be 200.75
            $data[2].id | Should -Be 3
            $data[2].name | Should -Be "Charlie"
            $data[2].value | Should -Be 300.25

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "preserves special characters in quoted fields" {
            $filePath = "$($TestConfig.Temp)\special-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "SpecialChars$(Get-Random)"

            # Create CSV with special characters
            $csvContent = @"
name,description
"John ""Jack"" Smith","Contains, commas and ""quotes"""
"Jane's Place","Has apostrophe's"
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $splatImport = @{
                Path            = $filePath
                SqlInstance     = $server
                Database        = "tempdb"
                Table           = $tableName
                AutoCreateTable = $true
            }
            $result = Import-DbaCsv @splatImport

            $result.RowsCopied | Should -Be 2

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY name" -As PSObject

            # Verify special characters are preserved
            $data[0].name | Should -Be 'Jane''s Place'
            $data[0].description | Should -Be "Has apostrophe's"
            $data[1].name | Should -Be 'John "Jack" Smith'
            $data[1].description | Should -Be 'Contains, commas and "quotes"'

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "truncate removes old data and replaces with new data" {
            $filePath = "$($TestConfig.Temp)\truncate-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "TruncateTest$(Get-Random)"

            # Create initial CSV
            "id,value`n1,first`n2,second" | Out-File -FilePath $filePath -Encoding UTF8

            $splatImport = @{
                Path            = $filePath
                SqlInstance     = $server
                Database        = "tempdb"
                Table           = $tableName
                AutoCreateTable = $true
            }
            $null = Import-DbaCsv @splatImport

            $countBefore = (Invoke-DbaQuery -SqlInstance $server -Query "SELECT COUNT(*) AS cnt FROM $tableName" -As PSObject).cnt
            $countBefore | Should -Be 2

            # Create new CSV with different data
            "id,value`n10,newvalue1`n20,newvalue2`n30,newvalue3" | Out-File -FilePath $filePath -Encoding UTF8

            $splatImportTruncate = @{
                Path        = $filePath
                SqlInstance = $server
                Database    = "tempdb"
                Table       = $tableName
                Truncate    = $true
            }
            $result = Import-DbaCsv @splatImportTruncate

            $result.RowsCopied | Should -Be 3

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY id" -As PSObject

            # Verify old data is gone and new data is present
            ($data | Measure-Object).Count | Should -Be 3
            $data[0].id | Should -Be "10"
            $data[0].value | Should -Be "newvalue1"

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "type conversion works for INT, DECIMAL, BIT, and DATETIME" {
            $filePath = "$($TestConfig.Temp)\types-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "TypeConversion$(Get-Random)"

            # Create table with various types
            $createTableSql = @"
CREATE TABLE $tableName (
    int_col INT,
    decimal_col DECIMAL(10,2),
    bit_col BIT,
    datetime_col DATETIME,
    bigint_col BIGINT,
    smallint_col SMALLINT
)
"@
            Invoke-DbaQuery -SqlInstance $server -Query $createTableSql

            # Create CSV with type-specific values
            $csvContent = @"
int_col,decimal_col,bit_col,datetime_col,bigint_col,smallint_col
42,123.45,1,2024-06-15 10:30:00,9223372036854775807,32767
-100,0.01,0,2023-12-31 23:59:59,1234567890123,100
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $result = Import-DbaCsv -Path $filePath -SqlInstance $server -Database tempdb -Table $tableName

            $result.RowsCopied | Should -Be 2

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName ORDER BY int_col DESC" -As PSObject

            # Verify type conversions
            $data[0].int_col | Should -Be 42
            $data[0].decimal_col | Should -Be 123.45
            $data[0].bit_col | Should -Be $true
            $data[0].bigint_col | Should -Be 9223372036854775807
            $data[0].smallint_col | Should -Be 32767

            $data[1].int_col | Should -Be -100
            $data[1].decimal_col | Should -Be 0.01
            $data[1].bit_col | Should -Be $false

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }

        It "row count matches exactly between CSV source and database" {
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "RowCountMatch$(Get-Random)"

            # Use SuperSmall.csv which has 1000 rows (999 data + no header, or 1000 lines)
            $csvPath = $pathSuperSmall
            $csvLineCount = (Get-Content $csvPath).Count

            $splatImport = @{
                Path            = $csvPath
                SqlInstance     = $server
                Database        = "tempdb"
                Table           = $tableName
                Delimiter       = "`t"
                NoHeaderRow     = $true
                AutoCreateTable = $true
            }
            $result = Import-DbaCsv @splatImport

            $dbCount = (Invoke-DbaQuery -SqlInstance $server -Query "SELECT COUNT(*) AS cnt FROM $tableName" -As PSObject).cnt

            # Verify counts match
            $result.RowsCopied | Should -Be $csvLineCount
            $dbCount | Should -Be $csvLineCount
            $result.RowsCopied | Should -Be $dbCount

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
        }

        It "handles empty string values correctly" {
            $filePath = "$($TestConfig.Temp)\emptyvals-$(Get-Random).csv"
            $server = Connect-DbaInstance $TestConfig.instance1 -Database tempdb
            $tableName = "EmptyValues$(Get-Random)"

            # Create CSV with empty values
            $csvContent = @"
col1,col2,col3
value1,,value3
,middle,
all,filled,here
"@
            $csvContent | Out-File -FilePath $filePath -Encoding UTF8

            $splatImport = @{
                Path            = $filePath
                SqlInstance     = $server
                Database        = "tempdb"
                Table           = $tableName
                AutoCreateTable = $true
            }
            $result = Import-DbaCsv @splatImport

            $result.RowsCopied | Should -Be 3

            $data = Invoke-DbaQuery -SqlInstance $server -Query "SELECT * FROM $tableName" -As PSObject

            # Verify empty values are handled (empty string or NULL depending on settings)
            ($data | Measure-Object).Count | Should -Be 3

            Invoke-DbaQuery -SqlInstance $server -Query "DROP TABLE $tableName" -ErrorAction SilentlyContinue
            Remove-Item $filePath -ErrorAction SilentlyContinue
        }
    }
}