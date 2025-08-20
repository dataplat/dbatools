$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Schema', 'Table', 'ResultSize', 'Rank', 'FilterBy', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        Get-DbaProcess -SqlInstance $TestConfig.instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
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
        Get-DbaProcess -SqlInstance $TestConfig.instance2 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
    }
    Context "Command gets suggestions" {
        $results = Test-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname
        It "Should get results for $dbname" {
            $results | Should -Not -Be $null
        }
        $results.foreach{
            It "Should suggest ROW, PAGE or NO_GAIN for $($PSItem.TableName) - $($PSItem.IndexType) " {
                $PSItem.CompressionTypeRecommendation | Should -BeIn ("ROW", "PAGE", "NO_GAIN", "?")
            }
            It "Should have values for PercentScan and PercentUpdate  $($PSItem.TableName) - $($PSItem.IndexType) " {
                $PSItem.PercentUpdate | Should -Not -BeNullOrEmpty
                $PSItem.PercentScan | Should -Not -BeNullOrEmpty
            }
        }
    }
    Context "Command makes right suggestions" {
        $results = Test-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname
        It "Should suggest PAGE compression for a table with no updates or scans" {
            $($results | Where-Object { $_.TableName -eq "syscols" -and $_.IndexType -eq "HEAP" }).CompressionTypeRecommendation | Should -Be "PAGE"
        }
        It "Should suggest ROW compression for table with more updates" {
            $($results | Where-Object { $_.TableName -eq "sysallparams" }).CompressionTypeRecommendation | Should -Be "ROW"
        }
    }
    Context "Command excludes results for specified database" {
        It "Shouldn't get any results for $dbname" {
            $(Test-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -ExcludeDatabase $dbname).Database | Should -Not -Match $dbname
        }
    }
    Context "Command gets Schema suggestions" {
        $schema = 'dbo'
        $results = Test-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -Schema $schema
        It "Should get results for Schema:$schema" {
            $results | Should -Not -Be $null
        }
    }
    Context "Command gets Table suggestions" {
        $table = 'syscols'
        $results = Test-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -Table $table
        It "Should get results for table:$table" {
            $results | Should -Not -Be $null
        }
    }
    Context "Command gets limited output" {
        $resultCount = 2
        $results = Test-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -ResultSize $resultCount -Rank TotalPages -FilterBy Partition
        It "Should get only $resultCount results" {
            $results.Count | Should -Be $resultCount
        }
    }
    Context "Returns result for empty table (see #9469)" {
        $table = 'testtable'
        $results = Test-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -Table $table
        It "Should get results for table:$table" {
            $results | Should -Not -Be $null
            $results[0].CompressionTypeRecommendation | Should -Be '?'
        }
    }
}