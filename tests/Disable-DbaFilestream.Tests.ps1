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

<#
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Store the original FileStream level to restore after testing
        $originalFileStream = Get-DbaFilestream -SqlInstance $TestConfig.instance1

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Restore the original FileStream level
        Set-DbaFilestream -SqlInstance $TestConfig.instance1 -FileStreamLevel $originalFileStream.InstanceAccessLevel -Force

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When changing FileStream Level" {
        BeforeAll {
            # Move it on one, but keep it less than 4 with modulo division
            $newLevel = ($originalFileStream.FileStreamStateId + 1) % 3
            $splatFilestream = @{
                SqlInstance     = $TestConfig.instance1
                FileStreamLevel = $newLevel
                Force           = $true
                WarningAction   = "SilentlyContinue"
                ErrorVariable   = "errvar"
                ErrorAction     = "SilentlyContinue"
            }
            $results = Set-DbaFilestream @splatFilestream
        }

        It "Should change the FileStream Level" {
            $results.InstanceAccessLevel | Should -Be $newLevel
        }
    }
}
#>