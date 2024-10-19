param($ModuleName = 'dbatools')

Describe "Test-DbaDbCompression Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaDbCompression
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have Schema as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Schema
        }
        It "Should have Table as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Table
        }
        It "Should have ResultSize as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter ResultSize
        }
        It "Should have Rank as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Rank
        }
        It "Should have FilterBy as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter FilterBy
        }
        It "Should have EnableException as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Test-DbaDbCompression Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("Create Schema test", $dbname)
        $null = $server.Query(@"
            select * into syscols from sys.all_columns;
            select 1 as col into testtable where 1=0;
            select * into test.sysallparams from sys.all_parameters;
            create clustered index CL_sysallparams on test.sysallparams (object_id);
            create nonclustered index NC_syscols on syscols (precision) include (collation_name);
            update test.sysallparams set is_xml_document = 1 where name = '@dbname';
"@, $dbname)
    }

    AfterAll {
        Get-DbaProcess -SqlInstance $global:instance2 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
    }

    Context "Command gets suggestions" {
        BeforeAll {
            $results = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname
        }

        It "Should get results for $dbname" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should suggest ROW, PAGE or NO_GAIN for <_.TableName> - <_.IndexType>" -ForEach $results {
            $_.CompressionTypeRecommendation | Should -BeIn @("ROW", "PAGE", "NO_GAIN", "?")
        }

        It "Should have values for PercentScan and PercentUpdate for <_.TableName> - <_.IndexType>" -ForEach $results {
            $_.PercentUpdate | Should -Not -BeNullOrEmpty
            $_.PercentScan | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command makes right suggestions" {
        BeforeAll {
            $results = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname
        }

        It "Should suggest PAGE compression for a table with no updates or scans" {
            ($results | Where-Object { $_.TableName -eq "syscols" -and $_.IndexType -eq "HEAP"}).CompressionTypeRecommendation | Should -Be "PAGE"
        }

        It "Should suggest ROW compression for table with more updates" {
            ($results | Where-Object { $_.TableName -eq "sysallparams"}).CompressionTypeRecommendation | Should -Be "ROW"
        }
    }

    Context "Command excludes results for specified database" {
        It "Shouldn't get any results for $dbname" {
            $result = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -ExcludeDatabase $dbname
            $result.Database | Should -Not -Contain $dbname
        }
    }

    Context "Command gets Schema suggestions" {
        BeforeAll {
            $schema = 'dbo'
            $results = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -Schema $schema
        }

        It "Should get results for Schema:$schema" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command gets Table suggestions" {
        BeforeAll {
            $table = 'syscols'
            $results = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -Table $table
        }

        It "Should get results for table:$table" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command gets limited output" {
        BeforeAll {
            $resultCount = 2
            $results = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -ResultSize $resultCount -Rank TotalPages -FilterBy Partition
        }

        It "Should get only $resultCount results" {
            $results.Count | Should -Be $resultCount
        }
    }

    Context "Returns result for empty table (see #9469)" {
        BeforeAll {
            $table = 'testtable'
            $results = Test-DbaDbCompression -SqlInstance $global:instance2 -Database $dbname -Table $table
        }

        It "Should get results for table:$table" {
            $results | Should -Not -BeNullOrEmpty
            $results[0].CompressionTypeRecommendation | Should -Be '?'
        }
    }
}
