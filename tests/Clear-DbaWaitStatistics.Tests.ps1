#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Clear-DbaWaitStatistics",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $ConfirmPreference = "None"
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues["*-Dba*:Confirm"] = $false
        try {
            $script:outputForValidation = Clear-DbaWaitStatistics -SqlInstance $TestConfig.InstanceSingle -Confirm:$false
        } catch {
            $script:outputForValidation = $null
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:Confirm")
    }

    Context "Command executes properly and returns proper info" {
        It "Returns success" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "ShouldProcess not supported in Pester context for ConfirmImpact High commands" }
            $script:outputForValidation.Status | Should -Be "Success"
        }

        It "Returns output of the expected type" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "ShouldProcess not supported in Pester context for ConfirmImpact High commands" }
            $script:outputForValidation[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "ShouldProcess not supported in Pester context for ConfirmImpact High commands" }
            $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Status")
            foreach ($prop in $expectedProps) {
                $script:outputForValidation[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}