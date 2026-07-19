#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Disable-DbaFilestream",
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
                "Credential",
                "Force",
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

        # This suite restarts the instance (filestream level changes take a service restart via
        # -Force), and the gate runs its ps7 and ps51 legs back-to-back - so this leg may start
        # while the instance is still recovering from the previous leg's restart (measured:
        # "connection forcibly closed" in BOTH worlds). Wait for stable connectivity, bounded.
        $deadline = (Get-Date).AddSeconds(90)
        while ((Get-Date) -lt $deadline) {
            try {
                $null = Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart -ConnectTimeout 5
                break
            } catch {
                Start-Sleep -Seconds 5
            }
        }

        $null = Enable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -FileStreamLevel 1 -Force

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When changing FileStream Level" {
        It "Should change the FileStream Level" {
            $results = Disable-DbaFilestream -SqlInstance $TestConfig.InstanceRestart -Force

            $results.InstanceAccessLevel | Should -Be 0
            $results.ServiceAccessLevel | Should -Be 0
        }
    }
}