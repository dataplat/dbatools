#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Add-DbaPfDataCollectorCounter" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaPfDataCollectorCounter
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "Collector",
                "Counter",
                "InputObject",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Add-DbaPfDataCollectorCounter" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues['*:Confirm'] = $false
    }

    BeforeEach {
        $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' |
            Import-DbaPfDataCollectorSetTemplate |
            Get-DbaPfDataCollector |
            Get-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length' |
            Remove-DbaPfDataCollectorCounter

        $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Get-DbaPfDataCollector |
            Add-DbaPfDataCollectorCounter -Counter '\LogicalDisk(*)\Avg. Disk Queue Length'
    }

    AfterAll {
        $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' |
            Remove-DbaPfDataCollectorSet
    }

    Context "When adding a counter to a data collector" {
        It "Returns the correct DataCollectorSet" {
            $results.DataCollectorSet | Should -Be 'Long Running Queries'
        }

        It "Returns the correct counter name" {
            $results.Name | Should -Be '\LogicalDisk(*)\Avg. Disk Queue Length'
        }
    }
}
