#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Import-DbaParquet",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

if ($null -eq $PSDefaultParameterValues) {
    $PSDefaultParameterValues = @{ }
}

$hasIntegrationConfig = $false
if ($TestConfig -and $TestConfig.appveyorlabrepo -and $TestConfig.InstanceMulti1) {
    $parquetFixturePath = Join-Path -Path $TestConfig.appveyorlabrepo -ChildPath "parquet"
    $pathEcdc = Join-Path -Path $parquetFixturePath -ChildPath "ecdc_cases.parquet"
    $pathBoundaries = Join-Path -Path $parquetFixturePath -ChildPath "world-administrative-boundaries.parquet"
    $pathMixedTypes = Join-Path -Path $parquetFixturePath -ChildPath "mixed_types.parquet"
    $hasIntegrationConfig = (Test-Path $pathEcdc) -and (Test-Path $pathBoundaries) -and (Test-Path $pathMixedTypes)
}

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = @(
                "Path",
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "Schema",
                "Truncate",
                "BatchSize",
                "NotifyAfter",
                "TableLock",
                "CheckConstraints",
                "FireTriggers",
                "KeepIdentity",
                "Column",
                "ColumnMap",
                "KeepOrdinalOrder",
                "AutoCreateTable",
                "NoUtf8",
                "NoColumnOptimize",
                "NoProgress",
                "UseFileNameForSchema",
                "NoTransaction",
                "StaticColumns",
                "EnableException"
            )
            ($expectedParameters | Where-Object { $PSItem -notin $hasParameters }) | Should -BeNullOrEmpty
        }

        It "Should not have any CSV-only parameters" {
            $csvOnlyParams = @(
                "NoHeaderRow",
                "Delimiter",
                "SingleColumn",
                "KeepNulls",
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
                "MaxDecompressedSize",
                "SkipRows",
                "QuoteMode",
                "DuplicateHeaderBehavior",
                "MismatchedFieldAction",
                "DistinguishEmptyFromNull",
                "NormalizeQuotes",
                "CollectParseErrors",
                "MaxParseErrors",
                "DateTimeFormats",
                "Culture",
                "SampleRows",
                "DetectColumnTypes"
            )
            $commandParams = (Get-Command $CommandName).Parameters.Keys
            foreach ($csvParam in $csvOnlyParams) {
                $commandParams | Should -Not -Contain $csvParam
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:(-not $hasIntegrationConfig) {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Install-DbaParquet

        # Set up Parquet file paths for testing
        $parquetFixturePath = Join-Path -Path $TestConfig.appveyorlabrepo -ChildPath "parquet"
        $pathEcdc = Join-Path -Path $parquetFixturePath -ChildPath "ecdc_cases.parquet"
        $pathBoundaries = Join-Path -Path $parquetFixturePath -ChildPath "world-administrative-boundaries.parquet"
        $pathMixedTypes = Join-Path -Path $parquetFixturePath -ChildPath "mixed_types.parquet"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup test tables
        Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases, "world-administrative-boundaries", ecdc_cases_static, ecdc_cases_ordinal, ecdc_cases_notxn, ecdc_cases_utf8, ecdc_cases_utf16, mixed_types, mixed_types_columns, mixed_types_column_map, world_boundaries_exact -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Auto-create table path" {
        It "imports a Parquet file with AutoCreateTable" {
            $result = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0
            $result.Database | Should -Be "tempdb"
            $result.Table | Should -Be "ecdc_cases"
        }

        It "imports binary parquet columns with AutoCreateTable" {
            $result = Import-DbaParquet -Path $pathBoundaries -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0
            $result.Database | Should -Be "tempdb"
            $result.Table | Should -Be "world-administrative-boundaries"
        }

        It "creates SQL column types from Parquet schema in AutoCreateTable mode" {
            $null = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable -NoColumnOptimize -Truncate

            $sql = @"
SELECT
    c.name AS ColumnName,
    t.name AS TypeName
FROM sys.columns c
INNER JOIN sys.types t
    ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.ecdc_cases')
  AND c.name IN ('date_rep', 'day', 'pop_data_2018')
"@
            $types = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $sql
            ($types | Where-Object ColumnName -eq "date_rep").TypeName | Should -Be "datetime2"
            ($types | Where-Object ColumnName -eq "day").TypeName | Should -Be "smallint"
            ($types | Where-Object ColumnName -eq "pop_data_2018").TypeName | Should -Be "int"
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Deterministic lab fixtures" {
        It "imports mixed-type fixture rows and preserves exact values" {
            $result = Import-DbaParquet -Path $pathMixedTypes -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable -Table mixed_types -NoColumnOptimize -NoUtf8

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -Be 3

            $data = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELECT [key], label, CAST(amount AS decimal(10,2)) AS amount, CONVERT(date, imported_on) AS imported_on FROM dbo.mixed_types ORDER BY [key]"
            $data.Count | Should -Be 3
            $data[0]."key" | Should -Be 10
            $data[0].label | Should -Be "alpha"
            $data[0].amount | Should -Be ([decimal]"12.34")
            $data[0].imported_on | Should -Be ([datetime]"2024-05-01")
            $data[2]."key" | Should -Be 30
            $data[2].label | Should -Be "gamma"
            $data[2].amount | Should -Be ([decimal]"90.12")
            $data[2].imported_on | Should -Be ([datetime]"2024-05-03")
        }

        It "imports a selected-column projection into a pre-created table" {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "IF OBJECT_ID('dbo.mixed_types_columns') IS NOT NULL DROP TABLE dbo.mixed_types_columns; CREATE TABLE dbo.mixed_types_columns ([key] int NULL, [label] nvarchar(20) NULL);"

            $result = Import-DbaParquet -Path $pathMixedTypes -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table mixed_types_columns -Column key, label

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -Be 3

            $metadata = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELECT COUNT(*) AS cnt FROM sys.columns WHERE object_id = OBJECT_ID('dbo.mixed_types_columns') AND name IN ('amount', 'imported_on')"
            $metadata.cnt | Should -Be 0

            $summary = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELECT COUNT(*) AS cnt, MIN([key]) AS min_key, MAX([key]) AS max_key, MAX(label) AS max_label FROM dbo.mixed_types_columns"
            $summary.cnt | Should -Be 3
            $summary.min_key | Should -Be 10
            $summary.max_key | Should -Be 30
            $summary.max_label | Should -Be "gamma"
        }

        It "maps parquet columns into differently named SQL columns" {
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "IF OBJECT_ID('dbo.mixed_types_column_map') IS NOT NULL DROP TABLE dbo.mixed_types_column_map; CREATE TABLE dbo.mixed_types_column_map ([identifier] int NULL, [display_name] nvarchar(20) NULL);"

            $columnMap = @{
                key   = "identifier"
                label = "display_name"
            }
            $result = Import-DbaParquet -Path $pathMixedTypes -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table mixed_types_column_map -ColumnMap $columnMap

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -Be 3

            $row = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELECT identifier, display_name FROM dbo.mixed_types_column_map WHERE identifier = 20"
            $row.display_name | Should -Be "beta"
        }

        It "imports binary fixture bytes and preserves their lengths" {
            $result = Import-DbaParquet -Path $pathBoundaries -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable -Table world_boundaries_exact -NoColumnOptimize -NoUtf8

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -Be 2

            $lengths = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELECT objectid, DATALENGTH(shape) AS shape_length FROM dbo.world_boundaries_exact ORDER BY objectid"
            $lengths[0].shape_length | Should -Be 3
            $lengths[1].shape_length | Should -Be 4
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table mixed_types, mixed_types_columns, mixed_types_column_map, world_boundaries_exact -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Import into existing table" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # First create table via auto-create, then truncate
            $null = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "TRUNCATE TABLE ecdc_cases"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "imports into a pre-existing table" {
            $result = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0
            $result.Database | Should -Be "tempdb"
            $result.Table | Should -Be "ecdc_cases"
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Truncate path" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "truncates and re-imports correctly" {
            $result = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases -Truncate

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0

            # Verify row count equals single import, not doubled
            $count = (Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELECT COUNT(*) AS cnt FROM ecdc_cases").cnt
            $count | Should -Be $result.RowsCopied
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Static columns" {
        It "adds static columns to imported data" {
            $result = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable -Table ecdc_cases_static -StaticColumns @{ ImportSource = "test" }

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0

            $data = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "SELECT TOP 1 ImportSource FROM ecdc_cases_static"
            $data.ImportSource | Should -Be "test"
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases_static -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Ordinal mapping" {
        It "imports with KeepOrdinalOrder" {
            $result = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable -Table ecdc_cases_ordinal -KeepOrdinalOrder

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases_ordinal -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "Non-transaction path" {
        It "imports with NoTransaction" {
            $result = Import-DbaParquet -Path $pathEcdc -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable -Table ecdc_cases_notxn -NoTransaction

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases_notxn -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "UseFileNameForSchema" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $schemaTestFile = Join-Path $TestDrive "staging.ecdc_parquet_test.parquet"
            Copy-Item $pathEcdc $schemaTestFile
            # Create the staging schema if it doesn't exist
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging') EXEC('CREATE SCHEMA staging')"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "derives schema from filename" {
            $result = Import-DbaParquet -Path $schemaTestFile -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -AutoCreateTable -UseFileNameForSchema

            $result | Should -Not -BeNullOrEmpty
            $result.Schema | Should -Be "staging"
            $result.Table | Should -Be "ecdc_parquet_test"
            $result.RowsCopied | Should -BeGreaterThan 0
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query "IF OBJECT_ID('staging.ecdc_parquet_test') IS NOT NULL DROP TABLE staging.ecdc_parquet_test" -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

    Context "NoUtf8 behavior" {
        It "creates UTF-8 varchar columns by default" {
            $splatImport = @{
                Path             = $pathEcdc
                SqlInstance      = $TestConfig.InstanceMulti1
                Database         = "tempdb"
                AutoCreateTable  = $true
                Table            = "ecdc_cases_utf8"
                NoColumnOptimize = $true
            }
            $result = Import-DbaParquet @splatImport

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0

            $utf8ColumnSql = @"
SELECT TOP 1
    t.name AS TypeName,
    c.collation_name AS CollationName
FROM sys.columns c
INNER JOIN sys.types t
    ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.ecdc_cases_utf8')
  AND t.name IN ('varchar', 'nvarchar')
ORDER BY c.column_id
"@
            $utf8Column = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $utf8ColumnSql
            $utf8Column.TypeName | Should -Be "varchar"
            $utf8Column.CollationName | Should -Match "UTF8"
        }

        It "creates nvarchar columns when NoUtf8 is specified" {
            $splatImport = @{
                Path             = $pathEcdc
                SqlInstance      = $TestConfig.InstanceMulti1
                Database         = "tempdb"
                AutoCreateTable  = $true
                Table            = "ecdc_cases_utf16"
                NoColumnOptimize = $true
                NoUtf8           = $true
            }
            $result = Import-DbaParquet @splatImport

            $result | Should -Not -BeNullOrEmpty
            $result.RowsCopied | Should -BeGreaterThan 0

            $utf16ColumnSql = @"
SELECT TOP 1
    t.name AS TypeName,
    c.collation_name AS CollationName
FROM sys.columns c
INNER JOIN sys.types t
    ON c.user_type_id = t.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.ecdc_cases_utf16')
  AND t.name IN ('varchar', 'nvarchar')
ORDER BY c.column_id
"@
            $utf16Column = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Query $utf16ColumnSql
            $utf16Column.TypeName | Should -Be "nvarchar"
            $utf16Column.CollationName | Should -Not -Match "UTF8"
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaDbTable -SqlInstance $TestConfig.InstanceMulti1 -Database tempdb -Table ecdc_cases_utf8, ecdc_cases_utf16 -ErrorAction SilentlyContinue | Remove-DbaDbTable -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
    }

}
