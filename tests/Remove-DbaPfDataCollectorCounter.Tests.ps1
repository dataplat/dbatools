#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaPfDataCollectorCounter",
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
        $null = Get-DbaPfDataCollectorSetTemplate -Template "Long Running Queries" | Import-DbaPfDataCollectorSetTemplate -ComputerName $TestConfig.InstanceSingle
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" | Remove-DbaPfDataCollectorSet

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Verifying command returns all the required results" {
        It "returns the correct values" {
            $results = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" |
                Get-DbaPfDataCollector |
                Get-DbaPfDataCollectorCounter -Counter "\LogicalDisk(*)\Avg. Disk Queue Length" |
                Remove-DbaPfDataCollectorCounter -Counter "\LogicalDisk(*)\Avg. Disk Queue Length"
            $results.DataCollectorSet | Should -Be "Long Running Queries"
            $results.Name | Should -Be "\LogicalDisk(*)\Avg. Disk Queue Length"
            $results.Status | Should -Be "Removed"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $result = Get-DbaPfDataCollectorSet -ComputerName $TestConfig.InstanceSingle -CollectorSet "Long Running Queries" |
                Get-DbaPfDataCollector |
                Get-DbaPfDataCollectorCounter |
                Select-Object -First 1 |
                Remove-DbaPfDataCollectorCounter -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties" {
            $expectedProps = @(
                'ComputerName',
                'DataCollectorSet',
                'DataCollector',
                'Name',
                'Status'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
            }
        }

        It "Status property is 'Removed' on success" {
            $result.Status | Should -Be "Removed"
        }
    }
}