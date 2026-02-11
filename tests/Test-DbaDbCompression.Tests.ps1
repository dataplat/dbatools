#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbCompression",
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
                "ExcludeDatabase",
                "Schema",
                "Table",
                "ResultSize",
                "Rank",
                "FilterBy",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("Create Schema test", $dbname)
        $null = $server.Query(" select * into syscols from sys.all_columns;
                                select 1 as col into testtable where 1=0;
                                select * into test.sysallparams from sys.all_parameters;
                                create clustered index CL_sysallparams on test.sysallparams (object_id);
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name);
                                update test.sysallparams set is_xml_document = 1 where name = '@dbname';
                                ", $dbname)
    }
    AfterAll {
        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $dbname
    }
    Context "Command gets suggestions" {
        It "Should get results for $dbname" {
            $results = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname
            $results | Should -Not -Be $null
            $results.foreach{
                $PSItem.CompressionTypeRecommendation | Should -BeIn ("ROW", "PAGE", "NO_GAIN", "?")
                $PSItem.PercentUpdate | Should -Not -BeNullOrEmpty
                $PSItem.PercentScan | Should -Not -BeNullOrEmpty
            }
        }
    }
    Context "Command makes right suggestions" {
        BeforeAll {
            $results = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname
        }
        It "Should suggest PAGE compression for a table with no updates or scans" {
            $($results | Where-Object { $_.TableName -eq "syscols" -and $_.IndexType -eq "HEAP" }).CompressionTypeRecommendation | Should -Be "PAGE"
        }
        It "Should suggest ROW compression for table with more updates" {
            $($results | Where-Object { $_.TableName -eq "sysallparams" }).CompressionTypeRecommendation | Should -Be "ROW"
        }
    }
    Context "Command excludes results for specified database" {
        It "Shouldn't get any results for $dbname" {
            $(Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ExcludeDatabase $dbname).Database | Should -Not -Match $dbname
        }
    }
    Context "Command gets Schema suggestions" {
        It "Should get results for Schema:$schema" {
            $schema = 'dbo'
            $results = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Schema $schema
            $results | Should -Not -Be $null
        }
    }
    Context "Command gets Table suggestions" {
        It "Should get results for table:$table" {
            $table = 'syscols'
            $results = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $table
            $results | Should -Not -Be $null
        }
    }
    Context "Command gets limited output" {
        It "Should get only $resultCount results" {
            $resultCount = 2
            $results = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname -ResultSize $resultCount -Rank TotalPages -FilterBy Partition
            $results.Count | Should -Be $resultCount
        }
    }
    Context "Returns result for empty table (see #9469)" {
        It "Should get results for table:$table" {
            $table = 'testtable'
            $results = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table $table
            $results | Should -Not -Be $null
            $results[0].CompressionTypeRecommendation | Should -Be '?'
        }
    }

    Context "Output validation" {
        BeforeAll {
            $result = Test-DbaDbCompression -SqlInstance $TestConfig.InstanceSingle -Database $dbname -Table syscols
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Schema", "TableName", "IndexName", "Partition", "IndexID", "IndexType", "PercentScan", "PercentUpdate", "RowEstimatePercentOriginal", "PageEstimatePercentOriginal", "CompressionTypeRecommendation", "SizeCurrent", "SizeRequested", "PercentCompression")
            foreach ($prop in $expectedProps) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Has SizeCurrent as DbaSize type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].SizeCurrent | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
        }

        It "Has SizeRequested as DbaSize type" {
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].SizeRequested | Should -BeOfType [Dataplat.Dbatools.Utility.Size]
        }
    }
}