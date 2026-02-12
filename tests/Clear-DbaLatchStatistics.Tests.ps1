#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Clear-DbaLatchStatistics",
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        try {
            $script:outputForValidation = Clear-DbaLatchStatistics -SqlInstance $TestConfig.InstanceSingle -Confirm:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        } catch {
            $script:outputForValidation = $null
        }
        # Filter out null elements that may come from ShouldProcess issues in Pester
        if ($script:outputForValidation) {
            $script:outputForValidation = @($script:outputForValidation | Where-Object { $null -ne $PSItem })
            if ($script:outputForValidation.Count -eq 0) { $script:outputForValidation = $null }
        }
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command executes properly and returns proper info" {
        It "Returns success" {
            $script:outputForValidation.Status | Should -Be "Success"
        }

        It "Returns output of the documented type" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "ShouldProcess not supported in Pester context for ConfirmImpact High commands" }
            $script:outputForValidation[0] | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            if (-not $script:outputForValidation) { Set-ItResult -Skipped -Because "ShouldProcess not supported in Pester context for ConfirmImpact High commands" }
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Status")
            foreach ($prop in $expectedProperties) {
                $script:outputForValidation[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }
    }
}