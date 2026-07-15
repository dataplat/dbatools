#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Save-DbaCommunitySoftware",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Software",
                "Branch",
                "LocalFile",
                "Url",
                "LocalDirectory",
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

        # The content check inside Save-DbaCommunitySoftware expects the target directory leaf
        # to match the archive's top-level folder name, so keep the leaf as sql-server-maintenance-solution-main.
        $targetParent = Join-Path -Path $TestDrive -ChildPath "target-$(Get-Random)"
        $null = New-Item -Path $targetParent -ItemType Directory
        $targetDirectory = Join-Path -Path $targetParent -ChildPath "sql-server-maintenance-solution-main"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-Item -Path $targetParent -Recurse -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "downloads and extracts the real GitHub archive" {
        Save-DbaCommunitySoftware -Software MaintenanceSolution -LocalDirectory $targetDirectory -EnableException

        Get-ChildItem -Path $targetDirectory -Recurse -Filter "CommandExecute.sql" | Should -Not -BeNullOrEmpty
    }

    It "replaces an existing cached copy that contains dotfiles" {
        # GitHub archives ship dotfiles (.github, .gitignore) which PowerShell treats as
        # hidden on macOS/Linux. Regression test for replacing a cache that contains them.
        Set-Content -Path (Join-Path -Path $targetDirectory -ChildPath ".gitignore") -Value "dbatoolsci hidden file"
        Set-Content -Path (Join-Path -Path $targetDirectory -ChildPath "stale.txt") -Value "dbatoolsci stale content"

        Save-DbaCommunitySoftware -Software MaintenanceSolution -LocalDirectory $targetDirectory -EnableException

        Get-ChildItem -Path $targetDirectory -Recurse -Filter "CommandExecute.sql" | Should -Not -BeNullOrEmpty
        Test-Path -Path (Join-Path -Path $targetDirectory -ChildPath "stale.txt") | Should -BeFalse
    }
}
