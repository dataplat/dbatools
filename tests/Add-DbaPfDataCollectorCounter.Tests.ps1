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
            Import-DbaPfDataCollectorSetTemplate -ComputerName $TestConfig.InstanceSingle |
            Get-DbaPfDataCollector |
            Get-DbaPfDataCollectorCounter -Counter "\LogicalDisk(*)\Avg. Disk Queue Length" |
            Remove-DbaPfDataCollectorCounter

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" |
            Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding a counter to a data collector" {
        BeforeAll {
            $results = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" |
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

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" |
                Get-DbaPfDataCollector |
                Add-DbaPfDataCollectorCounter -Counter "\LogicalDisk(*)\Avg. Disk Queue Length" -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                "ComputerName",
                "DataCollectorSet",
                "DataCollector",
                "Name",
                "FileName"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}