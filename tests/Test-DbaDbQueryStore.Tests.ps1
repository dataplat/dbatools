#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaDbQueryStore",
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
                "InputObject",
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

        $dbname = "JESSdbatoolsci_querystore_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $db = New-DbaDatabase -SqlInstance $server -Name $dbname

        $null = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.instance2 -Database $dbname -State ReadWrite
        $null = Enable-DbaTraceFlag -SqlInstance $TestConfig.instance2 -TraceFlag 7745

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname
        $null = Disable-DbaTraceFlag -SqlInstance $TestConfig.instance2 -TraceFlag 7745

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Function works as expected" {
        BeforeAll {
            $svr = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $results = Test-DbaDbQueryStore -SqlInstance $svr -Database $dbname
        }

        It "Should return results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should show query store is enabled" {
            ($results | Where-Object Name -eq "ActualState").Value | Should -Be "ReadWrite"
        }

        It "Should show recommended value for query store is to be enabled" {
            ($results | Where-Object Name -eq "ActualState").RecommendedValue | Should -Be "ReadWrite"
        }

        It "Should show query store meets best practice" {
            ($results | Where-Object Name -eq "ActualState").IsBestPractice | Should -Be $true
        }

        It "Should show trace flag 7745 is enabled" {
            ($results | Where-Object Name -eq "Trace Flag 7745 Enabled").Value | Should -Be "Enabled"
        }

        It "Should show trace flag 7745 meets best practice" {
            ($results | Where-Object Name -eq "Trace Flag 7745 Enabled").IsBestPractice | Should -Be $true
        }
    }

    Context "Exclude database works" {
        BeforeAll {
            $svrExclude = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $resultsExclude = Test-DbaDbQueryStore -SqlInstance $TestConfig.instance2 -ExcludeDatabase $dbname
        }

        It "Should return results" {
            $resultsExclude | Should -Not -BeNullOrEmpty
        }

        It "Should not return results for $($dbname)" {
            ($resultsExclude | Where-Object Database -eq $dbname) | Should -BeNullOrEmpty
        }
    }

    Context "Function works with piping smo server object" {
        BeforeAll {
            $svrPipe = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $resultsPipe = $svrPipe | Test-DbaDbQueryStore
        }

        It "Should return results" {
            $resultsPipe | Should -Not -BeNullOrEmpty
        }

        It "Should show query store meets best practice" {
            ($resultsPipe | Where-Object { $PSItem.Database -eq $dbname -and $PSItem.Name -eq "ActualState" }).IsBestPractice | Should -Be $true
        }

        It "Should show trace flag 7745 meets best practice" {
            ($resultsPipe | Where-Object Name -eq "Trace Flag 7745 Enabled").IsBestPractice | Should -Be $true
        }
    }
}