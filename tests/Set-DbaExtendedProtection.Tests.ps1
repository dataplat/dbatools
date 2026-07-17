#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaExtendedProtection",
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
                "Value",
                "AcceptedSpn",
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

    It "writes accepted SPNs and the requested protection level" {
        $splatSetExtendedProtection = @{
            SqlInstance     = $TestConfig.InstanceRestart
            Value           = "Required"
            AcceptedSpn     = $acceptedSpns
            Confirm         = $false
            EnableException = $true
        }
        $results = Set-DbaExtendedProtection @splatSetExtendedProtection
        $readBack = Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceRestart -EnableException

        $results.ExtendedProtection | Should -Be "2 - Required"
        $readBack.ExtendedProtection | Should -Be "2 - Required"
        $readBack.AcceptedSpns | Should -Be $acceptedSpns
    }

    It "leaves accepted SPNs unchanged when AcceptedSpn is omitted" {
        $splatSetProtectionOnly = @{
            SqlInstance     = $TestConfig.InstanceRestart
            Value           = "Off"
            Confirm         = $false
            EnableException = $true
        }
        $null = Set-DbaExtendedProtection @splatSetProtectionOnly
        $readBack = Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceRestart -EnableException

        $readBack.ExtendedProtection | Should -Be "0 - Off"
        $readBack.AcceptedSpns | Should -Be $acceptedSpns
    }

    It "leaves Extended Protection unchanged when only AcceptedSpn is supplied" {
        $replacementSpn = "MSSQLSvc/dbatoolsci-replacement:1433"
        $splatSetAcceptedSpnOnly = @{
            SqlInstance     = $TestConfig.InstanceRestart
            AcceptedSpn     = $replacementSpn
            Confirm         = $false
            EnableException = $true
        }
        $null = Set-DbaExtendedProtection @splatSetAcceptedSpnOnly
        $readBack = Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceRestart -EnableException

        $readBack.ExtendedProtection | Should -Be "0 - Off"
        $readBack.AcceptedSpns | Should -Be $replacementSpn
    }

    It "clears accepted SPNs when an empty string is supplied" {
        $splatClearAcceptedSpns = @{
            SqlInstance     = $TestConfig.InstanceRestart
            AcceptedSpn     = ""
            Confirm         = $false
            EnableException = $true
        }
        $null = Set-DbaExtendedProtection @splatClearAcceptedSpns
        $readBack = Get-DbaExtendedProtection -SqlInstance $TestConfig.InstanceRestart -EnableException

        $readBack.AcceptedSpns | Should -BeNullOrEmpty
    }
}
