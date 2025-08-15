#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Enable-DbaFilestream",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "FileStreamLevel",
                "ShareName",
                "Force",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Store the original FileStream level so we can restore it after the test
        # TODO: We should rely on a file stream setting in the test environment and work from there.
        $originalFileStream = Get-DbaFilestream -SqlInstance $TestConfig.instance1

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Restore the original FileStream level
        if ($originalFileStream.InstanceAccessLevel -eq 0) {
            $null = Disable-DbaFilestream -SqlInstance $TestConfig.instance1
        } else {
            $null = Enable-DbaFilestream -SqlInstance $TestConfig.instance1 -FileStreamLevel $originalFileStream.InstanceAccessLevel -WarningAction SilentlyContinue
        }

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When changing FileStream Level" {
        BeforeAll {
            $newLevel = ($originalFileStream.InstanceAccessLevel + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
            $results = Enable-DbaFilestream -SqlInstance $TestConfig.instance1 -FileStreamLevel $newLevel -WarningAction SilentlyContinue
        }

        It "Should change the FileStream Level to the new value" {
            $results.InstanceAccessLevel | Should -Be $newLevel
        }
    }
}