#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAvailabilityGroup",
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
                "Type",
                "ExcludeSystemJob",
                "ExcludeSystemLogin",
                "IncludeModifiedDate",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "When comparing all types across AG replicas" {
        BeforeAll {
            $splatCompare = @{
                SqlInstance       = $TestConfig.instance1
                AvailabilityGroup = "AG01"
            }
            $result = Compare-DbaAvailabilityGroup @splatCompare
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

    Context "When comparing a specific type" {
        BeforeAll {
            $splatAgentJob = @{
                SqlInstance          = $TestConfig.instance1
                AvailabilityGroup    = "AG01"
                Type                 = "AgentJob"
                IncludeModifiedDate  = $true
            }
            $resultAgentJob = Compare-DbaAvailabilityGroup @splatAgentJob -OutVariable "global:dbatoolsciOutput"
        }

        It "Should return agent job results" {
            $resultAgentJob | Should -Not -BeNullOrEmpty
        }

        It "Should only return agent job properties" {
            $resultAgentJob[0].PSObject.Properties.Name | Should -Contain "JobName"
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
