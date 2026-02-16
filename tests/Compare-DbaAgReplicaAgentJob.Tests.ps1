#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaAgentJob",
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
                "AvailabilityGroup",
                "ExcludeSystemJob",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When comparing AG replica agent jobs" {
        BeforeAll {
            $splatCompare = @{
                SqlInstance       = $TestConfig.instance1
                AvailabilityGroup = "AG01"
                IncludeModifiedDate = $true
            }
            $result = Compare-DbaAgReplicaAgentJob @splatCompare -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return results for the availability group" {
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should return results with the correct availability group name" {
            $result[0].AvailabilityGroup | Should -Be "AG01"
        }

        It "Should have valid Status values" {
            $result.Status | ForEach-Object { $PSItem | Should -BeIn @("Present", "Missing") }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "AvailabilityGroup",
                "Replica",
                "JobName",
                "Status",
                "DateLastModified"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}
