#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaMemoryCondition",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $results = Get-DbaMemoryCondition -SqlInstance $TestConfig.instance1
        }

        It "returns results" {
            $results.Status.Count | Should -BeGreaterThan 0
        }

        It "has the correct properties" {
            $result = $results[0]
            $expectedProps = "ComputerName", "InstanceName", "SqlInstance", "Runtime", "NotificationTime", "NotificationType", "MemoryUtilizationPercent", "TotalPhysicalMemory", "AvailablePhysicalMemory", "TotalPageFile", "AvailablePageFile", "TotalVirtualAddressSpace", "AvailableVirtualAddressSpace", "NodeId", "SQLReservedMemory", "SQLCommittedMemory", "RecordId", "Type", "Indicators", "RecordTime", "CurrentTime"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }
    }
}