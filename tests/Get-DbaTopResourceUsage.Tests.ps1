#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaTopResourceUsage",
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
                "Type",
                "Limit",
                "EnableException",
                "ExcludeSystem"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $splatDuration = @{
            SqlInstance = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            Type        = "Duration"
            Database    = "master"
        }
        $results = Get-DbaTopResourceUsage @splatDuration

        $splatExcluded = @{
            SqlInstance     = $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2
            Type            = "Duration"
            ExcludeDatabase = "master"
        }
        $resultsExcluded = Get-DbaTopResourceUsage @splatExcluded
    }

    Context "Command returns proper info" {
        It "returns results" {
            $results.Count -gt 0 | Should -Be $true
        }

        It "only returns results from master" {
            foreach ($result in $results) {
                $result.Database | Should -Be "master"
            }
        }

        # Each of the 4 -Types return slightly different information so this way, we can check to ensure only duration was returned
        It "Should have correct properties for Duration" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ObjectName",
                "QueryHash",
                "TotalElapsedTimeMs",
                "ExecutionCount",
                "AverageDurationMs",
                "QueryTotalElapsedTimeMs",
                "QueryText"
            )
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "No results for excluded database" {
            $resultsExcluded.Database -notcontains "master" | Should -Be $true
        }
    }

    Context "Output Validation - Duration" {
        BeforeAll {
            $resultDuration = Get-DbaTopResourceUsage -SqlInstance $TestConfig.InstanceMulti1 -Type Duration -Database master -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $resultDuration.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties for Duration metric" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ObjectName",
                "QueryHash",
                "TotalElapsedTimeMs",
                "ExecutionCount",
                "AverageDurationMs",
                "QueryTotalElapsedTimeMs",
                "QueryText"
            )
            $actualProps = $resultDuration.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has QueryPlan property available with Select-Object *" {
            $resultWithAll = Get-DbaTopResourceUsage -SqlInstance $TestConfig.InstanceMulti1 -Type Duration -Database master -Limit 1 -EnableException | Select-Object -First 1 *
            $resultWithAll.PSObject.Properties.Name | Should -Contain "QueryPlan"
        }
    }

    Context "Output Validation - Frequency" {
        BeforeAll {
            $resultFrequency = Get-DbaTopResourceUsage -SqlInstance $TestConfig.InstanceMulti1 -Type Frequency -Database master -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $resultFrequency.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties for Frequency metric" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ObjectName",
                "QueryHash",
                "ExecutionCount",
                "QueryTotalExecutions",
                "QueryText"
            )
            $actualProps = $resultFrequency.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output Validation - IO" {
        BeforeAll {
            $resultIO = Get-DbaTopResourceUsage -SqlInstance $TestConfig.InstanceMulti1 -Type IO -Database master -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $resultIO.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties for IO metric" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ObjectName",
                "QueryHash",
                "TotalIO",
                "ExecutionCount",
                "AverageIO",
                "QueryTotalIO",
                "QueryText"
            )
            $actualProps = $resultIO.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output Validation - CPU" {
        BeforeAll {
            $resultCPU = Get-DbaTopResourceUsage -SqlInstance $TestConfig.InstanceMulti1 -Type CPU -Database master -EnableException | Select-Object -First 1
        }

        It "Returns PSCustomObject" {
            $resultCPU.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties for CPU metric" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "ObjectName",
                "QueryHash",
                "CpuTime",
                "ExecutionCount",
                "AverageCpuMs",
                "QueryTotalCpu",
                "QueryText"
            )
            $actualProps = $resultCPU.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}