#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Reset-DbaAdmin",
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
                "Login",
                "SecurePassword",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:($PSVersionTable.PSVersion.Major -gt 5) {
    # Skip IntegrationTests on pwsh because command is not supported.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.instance2 -Login dbatoolsci_resetadmin | Stop-DbaProcess -WarningAction SilentlyContinue
        Get-DbaLogin -SqlInstance $TestConfig.instance2 -Login dbatoolsci_resetadmin | Remove-DbaLogin

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding a sql login" {
        It "Should add the login as sysadmin" {
            $password = ConvertTo-SecureString -Force -AsPlainText resetadmin1
            $cred = New-Object System.Management.Automation.PSCredential ("dbatoolsci_resetadmin", $password)
            $results = Reset-DbaAdmin -SqlInstance $TestConfig.instance2 -Login dbatoolsci_resetadmin -SecurePassword $password
            $results.Name | Should -Be dbatoolsci_resetadmin
            $results.IsMember("sysadmin") | Should -Be $true
        }
    }
}