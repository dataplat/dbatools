#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbCompression",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Table",
                "CompressionType",
                "MaxRunTime",
                "PercentCompression",
                "ForceOfflineRebuilds",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Create unique test database name
        $dbname = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("Create Database [$dbname]")
        $null = $server.Query("select * into syscols from sys.all_columns
                                select * into sysallparams from sys.all_parameters
                                create clustered index CL_sysallparams on sysallparams (object_id)
                                create nonclustered index NC_syscols on syscols (precision) include (collation_name)", $dbname)
        
        # Create InputObject for testing
        $InputObject = Test-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname
        
        # Run initial compression test
        $results = Set-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -MaxRunTime 5 -PercentCompression 0

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }
    
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true
        
        Get-DbaProcess -SqlInstance $TestConfig.instance2 -Database $dbname | Stop-DbaProcess -WarningAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
    }

    Context "Command gets results" {
        It "Should contain objects" {
            $results | Should -Not -BeNullOrEmpty
        }
    }

    Context "Command handles heaps and clustered indexes" {
        BeforeAll {
            $heapAndClusteredResults = $results | Where-Object IndexId -le 1
        }
        
        It "Should process all heap and clustered index objects" {
            $heapAndClusteredResults | Should -Not -BeNullOrEmpty
            $heapAndClusteredResults.AlreadyProcessed | Should -Be $true
        }
    }

    Context "Command handles nonclustered indexes" {
        BeforeAll {
            $nonclusteredResults = $results | Where-Object IndexId -gt 1
        }
        
        It "Should process all nonclustered index objects" {
            $nonclusteredResults | Should -Not -BeNullOrEmpty
            $nonclusteredResults.AlreadyProcessed | Should -Be $true
        }
    }

    Context "Command excludes results for specified database" {
        BeforeAll {
            $server.Databases[$dbname].Tables["syscols"].PhysicalPartitions[0].DataCompression = "NONE"
            $server.Databases[$dbname].Tables["syscols"].Rebuild()
            $excludeResults = @(Set-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -ExcludeDatabase $dbname -MaxRunTime 5 -PercentCompression 0)
        }
        
        It "Shouldn't get any results for excluded database" {
            $excludeResults.Database | Should -Not -Match $dbname
        }
    }

    Context "Command can accept InputObject from Test-DbaDbCompression" {
        BeforeAll {
            $inputObjectResults = @(Set-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -MaxRunTime 5 -PercentCompression 0 -InputObject $InputObject)
        }
        
        It "Should get results when using InputObject" {
            $inputObjectResults | Should -Not -BeNullOrEmpty
        }
        
        It "Should process all objects from InputObject" {
            $inputObjectResults.AlreadyProcessed | Should -Be $true
        }
    }

    Context "Command sets compression to Row for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -CompressionType Row
            $rowResults = Get-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname
        }
        
        It "Should set all objects to Row compression" {
            $rowResults | Should -Not -BeNullOrEmpty
            $rowResults.DataCompression | Should -Be "Row"
        }
    }

    Context "Command sets compression to Page for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -CompressionType Page
            $pageResults = Get-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname
        }
        
        It "Should set all objects to Page compression" {
            $pageResults | Should -Not -BeNullOrEmpty
            $pageResults.DataCompression | Should -Be "Page"
        }
    }

    Context "Command sets compression to None for all objects" {
        BeforeAll {
            $null = Set-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname -CompressionType None
            $noneResults = Get-DbaDbCompression -SqlInstance $TestConfig.instance2 -Database $dbname
        }
        
        It "Should set all objects to no compression" {
            $noneResults | Should -Not -BeNullOrEmpty
            $noneResults.DataCompression | Should -Be "None"
        }
    }
}