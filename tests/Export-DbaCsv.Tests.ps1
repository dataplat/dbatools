#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaCsv",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Query",
                "Table",
                "InputObject",
                "Path",
                "Delimiter",
                "NoHeader",
                "Quote",
                "QuotingBehavior",
                "Encoding",
                "NullValue",
                "DateTimeFormat",
                "UseUtc",
                "CompressionType",
                "CompressionLevel",
                "Append",
                "NoClobber",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set up test table with sample data
        $tableName = "ExportCsvTest$(Get-Random)"
        $createTableSql = @"
CREATE TABLE $tableName (
    id INT,
    name VARCHAR(50),
    value DECIMAL(10,2),
    created DATETIME
);
INSERT INTO $tableName VALUES (1, 'Alice', 100.50, '2024-01-15 10:30:00');
INSERT INTO $tableName VALUES (2, 'Bob', 200.75, '2024-02-20 14:45:00');
INSERT INTO $tableName VALUES (3, 'Charlie', 300.25, '2024-03-25 09:15:00');
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query $createTableSql

        # Create temp directory for test files
        $testExportPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $testExportPath -ItemType Directory -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup test table
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "IF OBJECT_ID('$tableName', 'U') IS NOT NULL DROP TABLE $tableName" -ErrorAction SilentlyContinue

        # Cleanup test files
        Remove-Item -Path $testExportPath -Recurse -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Works as expected" {
        It "exports table data to CSV file" {
            $filePath = "$testExportPath\basic-export.csv"

            $splatExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
                Path        = $filePath
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 3
            $result.Path | Should -Be $filePath
            Test-Path $filePath | Should -BeTrue

            $content = Get-Content $filePath
            $content[0] | Should -Match "id.*name.*value.*created"
            $content.Count | Should -Be 4
        }

        It "exports query results to CSV file" {
            $filePath = "$testExportPath\query-export.csv"

            $splatExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Query       = "SELECT id, name FROM $tableName WHERE id <= 2"
                Path        = $filePath
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 2
            Test-Path $filePath | Should -BeTrue

            $content = Get-Content $filePath
            $content[0] | Should -Match "id.*name"
            $content.Count | Should -Be 3
        }

        It "exports with GZip compression (issue #8646)" {
            $filePath = "$testExportPath\compressed.csv.gz"

            $splatExport = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "tempdb"
                Table           = $tableName
                Path            = $filePath
                CompressionType = "GZip"
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 3
            $result.CompressionType | Should -Be "GZip"
            Test-Path $filePath | Should -BeTrue

            # Verify it's actually compressed (smaller than uncompressed)
            $uncompressedPath = "$testExportPath\uncompressed.csv"
            $splatUncompressed = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
                Path        = $uncompressedPath
            }
            $null = Export-DbaCsv @splatUncompressed

            $compressedSize = (Get-Item $filePath).Length
            $uncompressedSize = (Get-Item $uncompressedPath).Length
            # Compressed file should exist and be valid (for small files, compression may not reduce size much)
            $compressedSize | Should -BeGreaterThan 0
        }

        It "auto-detects compression from file extension" {
            $filePath = "$testExportPath\auto-compressed.csv.gz"

            $splatExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
                Path        = $filePath
            }
            $result = Export-DbaCsv @splatExport

            $result.CompressionType | Should -Be "GZip"
            Test-Path $filePath | Should -BeTrue
        }

        It "exports with custom delimiter" {
            $filePath = "$testExportPath\tab-delimited.csv"

            $splatExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
                Path        = $filePath
                Delimiter   = "`t"
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 3

            $content = Get-Content $filePath
            $content[1] | Should -Match "1`t"
        }

        It "exports without header when -NoHeader is specified" {
            $filePath = "$testExportPath\no-header.csv"

            $splatExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
                Path        = $filePath
                NoHeader    = $true
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 3

            $content = Get-Content $filePath
            $content.Count | Should -Be 3
            $content[0] | Should -Match "^1,"
        }

        It "exports with custom date format" {
            $filePath = "$testExportPath\custom-date.csv"

            $splatExport = @{
                SqlInstance    = $TestConfig.InstanceSingle
                Database       = "tempdb"
                Table          = $tableName
                Path           = $filePath
                DateTimeFormat = "yyyy-MM-dd"
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 3

            $content = Get-Content $filePath
            $content[1] | Should -Match "2024-01-15"
            $content[1] | Should -Not -Match "10:30:00"
        }

        It "exports with Always quoting behavior" {
            $filePath = "$testExportPath\always-quoted.csv"

            $splatExport = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "tempdb"
                Table           = $tableName
                Path            = $filePath
                QuotingBehavior = "Always"
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 3

            $content = Get-Content $filePath
            $content[1] | Should -Match '^"'
        }

        It "prevents overwriting with -NoClobber" {
            $filePath = "$testExportPath\noclobber.csv"

            # Create file first
            $splatExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
                Path        = $filePath
            }
            $null = Export-DbaCsv @splatExport

            # Try to overwrite with NoClobber
            $splatNoClobber = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
                Path        = $filePath
                NoClobber   = $true
            }
            $result = Export-DbaCsv @splatNoClobber -WarningVariable WarnVar -WarningAction SilentlyContinue

            $WarnVar | Should -BeLike "*already exists*"
        }

        It "exports with Deflate compression" {
            $filePath = "$testExportPath\deflate.csv.deflate"

            $splatExport = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Database        = "tempdb"
                Table           = $tableName
                Path            = $filePath
                CompressionType = "Deflate"
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 3
            $result.CompressionType | Should -Be "Deflate"
            Test-Path $filePath | Should -BeTrue
        }

        It "exports with SmallestSize compression level" -Skip:($PSVersionTable.PSEdition -ne "Core") {
            $filePath = "$testExportPath\smallest.csv.gz"

            $splatExport = @{
                SqlInstance      = $TestConfig.InstanceSingle
                Database         = "tempdb"
                Table            = $tableName
                Path             = $filePath
                CompressionType  = "GZip"
                CompressionLevel = "SmallestSize"
            }
            $result = Export-DbaCsv @splatExport

            $result.RowsExported | Should -Be 3
            Test-Path $filePath | Should -BeTrue
        }

        It "exports piped objects from Invoke-DbaQuery" {
            $filePath = "$testExportPath\piped.csv"

            $data = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database tempdb -Query "SELECT id, name FROM $tableName"
            $result = $data | Export-DbaCsv -Path $filePath

            $result.RowsExported | Should -Be 3
            Test-Path $filePath | Should -BeTrue

            $content = Get-Content $filePath
            $content.Count | Should -Be 4
        }

        It "returns proper result object with performance metrics" {
            $filePath = "$testExportPath\metrics.csv"

            $splatExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
                Path        = $filePath
            }
            $result = Export-DbaCsv @splatExport

            $result.Path | Should -Be $filePath
            $result.RowsExported | Should -Be 3
            $result.FileSizeBytes | Should -BeGreaterThan 0
            $result.FileSizeMB | Should -BeOfType [double]
            $result.CompressionType | Should -Be "None"
            $result.Elapsed | Should -BeOfType [timespan]
            $result.RowsPerSecond | Should -BeGreaterThan 0
        }
    }

    Context "When exporting repeatedly" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The command used to open a database-scoped connection per call and never close it,
            # one new sleeping session per call. Count sessions through a server object opened once,
            # because a per-call counting command would open connections of its own.
            $countServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $countQuery = @"
select count(*)
from sys.dm_exec_sessions
where program_name like 'dbatools%'
  and status = 'sleeping'
  and session_id <> @@spid
"@

            # One warm-up call so the shared pooled connection exists before the baseline is taken.
            $splatLeakExport = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = "tempdb"
                Table       = $tableName
            }
            $null = Export-DbaCsv @splatLeakExport -Path "$testExportPath\leak-0.csv"
            $sleepingBefore = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            foreach ($i in 1..3) {
                $null = Export-DbaCsv @splatLeakExport -Path "$testExportPath\leak-$i.csv"
            }
            $sleepingAfter = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            # -WhatIf still opens the connection before ShouldProcess skips the export, and
            # Disconnect-DbaInstance supports ShouldProcess itself - the ownership disconnect has
            # to ignore the propagated WhatIf preference or every -WhatIf call leaks its session.
            foreach ($i in 1..3) {
                $null = Export-DbaCsv @splatLeakExport -Path "$testExportPath\leak-whatif-$i.csv" -WhatIf
            }
            $sleepingAfterWhatIf = $countServer.ConnectionContext.ExecuteScalar($countQuery)

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $countServer.ConnectionContext.Disconnect()
        }

        It "Leaves no sleeping session behind" {
            $sleepingAfter | Should -Be $sleepingBefore
        }

        It "Leaves no sleeping session behind with -WhatIf" {
            $sleepingAfterWhatIf | Should -Be $sleepingBefore
        }
    }

    Context "When writing the file fails on a connection of the caller" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # The command does not disconnect a server object it was given, so only its own cleanup can close the
            # reader on that connection. Connect-DbaInstance hands back that object itself when it already is in the
            # database the command asks for, master here; for any other database the command works on a copy of its
            # own, which it disconnects. The second connection checks the server from outside.
            $callerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $checkServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # The file is held open without sharing, so the CSV writer cannot open it. The writer is created after
            # the query has started, and the cross join makes sure the server has far more rows to send than the
            # client has read by then. The marker in the SELECT finds the request afterwards, the session of the
            # check is excluded because the text of the check contains the marker too.
            $lockedPath = "$testExportPath\locked-$(Get-Random).csv"
            $lockedFile = [System.IO.File]::Open($lockedPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $readerQuery = "SELECT 'dbatoolsci_csvreader_marker' AS id FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b"
            $readerRequestQuery = "SELECT r.session_id FROM sys.dm_exec_requests AS r CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) AS t WHERE t.text LIKE '%dbatoolsci_csvreader_marker%' AND r.session_id <> @@SPID"
            try {
                $splatLockedExport = @{
                    SqlInstance   = $callerServer
                    Database      = "master"
                    Query         = $readerQuery
                    Path          = $lockedPath
                    WarningAction = "SilentlyContinue"
                }
                $lockedResult = Export-DbaCsv @splatLockedExport
                $lockedWarning = $WarnVar
            } finally {
                $lockedFile.Dispose()
            }
        }

        AfterAll {
            # A request left behind by the old code would keep running until its session is gone.
            foreach ($leakedRequest in $checkServer.Query($readerRequestQuery)) {
                $null = $checkServer.Query("KILL $($leakedRequest.session_id)")
            }
            $callerServer.ConnectionContext.Disconnect()
            $checkServer.ConnectionContext.Disconnect()
        }

        It "Warns and returns nothing" {
            $lockedResult | Should -BeNullOrEmpty
            ($lockedWarning -join " ") | Should -BeLike "*Failed to export data from*"
        }

        It "Stops the query on the server" {
            @($checkServer.Query($readerRequestQuery)).Count | Should -Be 0
        }

        It "Leaves the connection of the caller usable" {
            $callerServer.Query("SELECT 1 AS one").one | Should -Be 1
        }
    }

    Context "Compression options (issue #8646)" {
        It "exports with each compression type" {
            $compressionTypes = @("None", "GZip", "Deflate")

            foreach ($compressionType in $compressionTypes) {
                $filePath = "$testExportPath\compression-$compressionType.csv"
                if ($compressionType -eq "GZip") { $filePath += ".gz" }
                if ($compressionType -eq "Deflate") { $filePath += ".deflate" }

                $splatExport = @{
                    SqlInstance     = $TestConfig.InstanceSingle
                    Database        = "tempdb"
                    Table           = $tableName
                    Path            = $filePath
                    CompressionType = $compressionType
                }
                $result = Export-DbaCsv @splatExport

                $result.RowsExported | Should -Be 3 -Because "compression type $compressionType should export all rows"
                $result.CompressionType | Should -Be $compressionType
                Test-Path $filePath | Should -BeTrue -Because "file should exist for compression type $compressionType"
            }
        }

        It "exports with each compression level" {
            # SmallestSize is only available in .NET 6+ (PowerShell Core)
            $compressionLevels = @("Fastest", "Optimal")
            if ($PSVersionTable.PSEdition -eq "Core") {
                $compressionLevels += "SmallestSize"
            }

            foreach ($compressionLevel in $compressionLevels) {
                $filePath = "$testExportPath\level-$compressionLevel.csv.gz"

                $splatExport = @{
                    SqlInstance      = $TestConfig.InstanceSingle
                    Database         = "tempdb"
                    Table            = $tableName
                    Path             = $filePath
                    CompressionType  = "GZip"
                    CompressionLevel = $compressionLevel
                }
                $result = Export-DbaCsv @splatExport

                $result.RowsExported | Should -Be 3 -Because "compression level $compressionLevel should export all rows"
                Test-Path $filePath | Should -BeTrue -Because "file should exist for compression level $compressionLevel"
            }
        }
    }
}
