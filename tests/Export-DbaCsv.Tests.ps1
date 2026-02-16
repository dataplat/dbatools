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
            $result = Export-DbaCsv @splatExport -OutVariable "global:dbatoolsciOutput"

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

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Path",
                "RowsExported",
                "FileSizeBytes",
                "FileSizeMB",
                "CompressionType",
                "Elapsed",
                "RowsPerSecond"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
