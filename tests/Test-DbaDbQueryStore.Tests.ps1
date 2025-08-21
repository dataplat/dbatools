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

        $global:dbname = "JESSdbatoolsci_querystore_$(Get-Random)"
        $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $global:db = New-DbaDatabase -SqlInstance $global:server -Name $global:dbname

        $null = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.instance2 -Database $global:dbname -State ReadWrite
        $null = Enable-DbaTraceFlag -SqlInstance $TestConfig.instance2 -TraceFlag 7745

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:dbname -Confirm:$false
        $null = Disable-DbaTraceFlag -SqlInstance $TestConfig.instance2 -TraceFlag 7745

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Function works as expected" {
        BeforeAll {
            $global:svr = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $global:results = Test-DbaDbQueryStore -SqlInstance $global:svr -Database $global:dbname
        }

        It "Should return results" {
            $global:results | Should -Not -BeNullOrEmpty
        }

        It "Should show query store is enabled" {
            ($global:results | Where-Object Name -eq "ActualState").Value | Should -Be "ReadWrite"
        }

        It "Should show recommended value for query store is to be enabled" {
            ($global:results | Where-Object Name -eq "ActualState").RecommendedValue | Should -Be "ReadWrite"
        }

        It "Should show query store meets best practice" {
            ($global:results | Where-Object Name -eq "ActualState").IsBestPractice | Should -Be $true
        }

        It "Should show trace flag 7745 is enabled" {
            ($global:results | Where-Object Name -eq "Trace Flag 7745 Enabled").Value | Should -Be "Enabled"
        }

        It "Should show trace flag 7745 meets best practice" {
            ($global:results | Where-Object Name -eq "Trace Flag 7745 Enabled").IsBestPractice | Should -Be $true
        }
    }

    Context "Exclude database works" {
        BeforeAll {
            $global:svrExclude = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $global:resultsExclude = Test-DbaDbQueryStore -SqlInstance $TestConfig.instance2 -ExcludeDatabase $global:dbname
        }

        It "Should return results" {
            $global:resultsExclude | Should -Not -BeNullOrEmpty
        }

        It "Should not return results for $($global:dbname)" {
            ($global:resultsExclude | Where-Object Database -eq $global:dbname) | Should -BeNullOrEmpty
        }
    }

    Context "Function works with piping smo server object" {
        BeforeAll {
            $global:svrPipe = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $global:resultsPipe = $global:svrPipe | Test-DbaDbQueryStore
        }

        It "Should return results" {
            $global:resultsPipe | Should -Not -BeNullOrEmpty
        }

        It "Should show query store meets best practice" {
            ($global:resultsPipe | Where-Object { $PSItem.Database -eq $global:dbname -and $PSItem.Name -eq "ActualState" }).IsBestPractice | Should -Be $true
        }

        It "Should show trace flag 7745 meets best practice" {
            ($global:resultsPipe | Where-Object Name -eq "Trace Flag 7745 Enabled").IsBestPractice | Should -Be $true
        }
    }
}