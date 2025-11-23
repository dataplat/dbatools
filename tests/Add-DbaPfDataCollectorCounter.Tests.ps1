#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaPfDataCollectorCounter",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "Collector",
                "Counter",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" |
            Import-DbaPfDataCollectorSetTemplate -ComputerName $TestConfig.instance1 |
            Get-DbaPfDataCollector |
            Get-DbaPfDataCollectorCounter -Counter "\LogicalDisk(*)\Avg. Disk Queue Length" |
            Remove-DbaPfDataCollectorCounter

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.instance1 -CollectorSet "Long Running Queries" |
            Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding a counter to a data collector" {
        BeforeAll {
            $results = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.instance1 -CollectorSet "Long Running Queries" |
                Get-DbaPfDataCollector |
                Add-DbaPfDataCollectorCounter -Counter "\LogicalDisk(*)\Avg. Disk Queue Length"
        }

        It "Returns the correct DataCollectorSet" {
            $results.DataCollectorSet | Should -Be "Long Running Queries"
        }

        It "Returns the correct counter name" {
            $results.Name | Should -Be "\LogicalDisk(*)\Avg. Disk Queue Length"
        }
    }
}