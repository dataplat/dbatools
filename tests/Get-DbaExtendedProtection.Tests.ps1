#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaExtendedProtection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $originalExtendedProtection = Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceRestart
        $originalValue = [int](($originalExtendedProtection.ExtendedProtection -split " ")[0])
        $originalAcceptedSpns = @($originalExtendedProtection.AcceptedSpns)
        $acceptedSpns = @("MSSQLSvc/dbatoolsci.domain.local:1433", "MSSQLSvc/dbatoolsci:1433")
        $splatSetAcceptedSpns = @{
            SqlInstance     = $TestConfig.InstanceRestart
            Value           = "Required"
            AcceptedSpn     = $acceptedSpns
            Confirm         = $false
            EnableException = $true
        }
        $null = Set-DbaExtendedProtection @splatSetAcceptedSpns

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        if ($null -ne $originalValue) {
            $restoreAcceptedSpns = if ($originalAcceptedSpns.Count -gt 0) { $originalAcceptedSpns } else { "" }
            $splatRestoreExtendedProtection = @{
                SqlInstance     = $TestConfig.InstanceRestart
                Value           = $originalValue
                AcceptedSpn     = $restoreAcceptedSpns
                Confirm         = $false
                EnableException = $true
            }
            $null = Set-DbaExtendedProtection @splatRestoreExtendedProtection
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns a value" {
        $results = Get-DbaExtendedProtection $TestConfig.InstanceRestart -EnableException
        $results.ExtendedProtection | Should -Not -BeNullOrEmpty
    }

    It "returns accepted SPNs as individual values" {
        $results = Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceRestart -EnableException

        $results.AcceptedSpns | Should -Be $acceptedSpns
    }
}
