#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Find-DbaDbQueryStoreRegression",
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
                "BaselineStartDaysAgo",
                "BaselineEndDaysAgo",
                "SlowdownThreshold",
                "MinExecutionCount",
                "MinTotalDurationMs",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # A regression cannot be staged in a test run: the baseline window is measured in whole
        # days before now, so statistics written during the run never land in it. These tests
        # cover what does not need history - the window validation, the Query Store-off skip,
        # piped database input and a clean empty result from a freshly enabled Query Store.
        $qsOnDb = "dbatoolsci_qsreg_on_$(Get-Random)"
        $qsOffDb = "dbatoolsci_qsreg_off_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $qsOnDb, $qsOffDb
        $null = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $qsOnDb -State ReadWrite
        # SQL Server 2022 enables Query Store on new databases by default, so "off" has to be set, not assumed.
        $null = Set-DbaDbQueryStoreOption -SqlInstance $TestConfig.InstanceSingle -Database $qsOffDb -State Off

        # Give Query Store something to record so an empty result means "no regression", not "nothing ran".
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Database $qsOnDb -Query "SELECT TOP 1 name FROM sys.objects"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $qsOnDb, $qsOffDb -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Input validation" {
        It "Rejects a baseline end that is not older than the baseline start" {
            $splatWindow = @{
                SqlInstance          = $TestConfig.InstanceSingle
                Database             = $qsOnDb
                BaselineStartDaysAgo = 1
                BaselineEndDaysAgo   = 7
                EnableException      = $true
            }
            { Find-DbaDbQueryStoreRegression @splatWindow } | Should -Throw "*must be smaller than BaselineStartDaysAgo*"
        }

        It "Requires either SqlInstance or piped databases" {
            { Find-DbaDbQueryStoreRegression -EnableException } | Should -Throw "*You must specify SqlInstance or pipe in databases*"
        }
    }

    Context "Reading Query Store" {
        It "Warns and returns nothing when Query Store is off" {
            $results = Find-DbaDbQueryStoreRegression -SqlInstance $TestConfig.InstanceSingle -Database $qsOffDb -WarningVariable warnOff 3> $null
            $results | Should -BeNullOrEmpty
            $warnOff | Should -Match "Query Store is not enabled on $qsOffDb"
        }

        It "Returns no regression and no warning for a freshly enabled Query Store" {
            $results = Find-DbaDbQueryStoreRegression -SqlInstance $TestConfig.InstanceSingle -Database $qsOnDb -WarningVariable warnOn 3> $null
            $results | Should -BeNullOrEmpty
            $warnOn | Should -BeNullOrEmpty
        }

        It "Processes databases piped in from Get-DbaDatabase" {
            # The Query Store-off warning names the database, which proves the piped object was
            # the one processed rather than the result being vacuously empty.
            $results = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $qsOnDb, $qsOffDb | Find-DbaDbQueryStoreRegression -WarningVariable warnPipe 3> $null
            $results | Should -BeNullOrEmpty
            @($warnPipe).Count | Should -Be 1
            $warnPipe | Should -Match "Query Store is not enabled on $qsOffDb"
        }

        It "Processes an instance piped in from Connect-DbaInstance" {
            $results = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle | Find-DbaDbQueryStoreRegression -Database $qsOffDb -WarningVariable warnServer 3> $null
            $results | Should -BeNullOrEmpty
            @($warnServer).Count | Should -Be 1
            $warnServer | Should -Match "Query Store is not enabled on $qsOffDb"
        }
    }
}
