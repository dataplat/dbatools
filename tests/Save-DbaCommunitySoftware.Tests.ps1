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

        It "Should accept an array of Software values" {
            (Get-Command $CommandName).Parameters["Software"].ParameterType | Should -Be ([string[]])
        }

        It "Should allow All as a Software value" {
            (Get-Command $CommandName).Parameters["Software"].Attributes.ValidValues | Should -Contain "All"
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

    It "warns instead of downloading when LocalDirectory is combined with multiple Software values" {
        Save-DbaCommunitySoftware -Software MaintenanceSolution, DarlingData -LocalDirectory $targetDirectory -WarningAction SilentlyContinue

        $WarnVar | Should -Match "single -Software value"
    }

    It "warns instead of downloading when LocalDirectory is combined with All" {
        Save-DbaCommunitySoftware -Software All -LocalDirectory $targetDirectory -WarningAction SilentlyContinue

        $WarnVar | Should -Match "single -Software value"
    }

    Context "Downloading multiple tools to an isolated cache" {
        BeforeEach {
            # Software's per-tool cache paths default from Path.DbatoolsData, so these tests
            # point that config at a throwaway TestDrive folder instead of touching the real
            # shared cache, and restore it afterwards.
            $originalDbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
            $isolatedDbatoolsData = Join-Path -Path $TestDrive -ChildPath "dbatoolsdata-$(Get-Random)"
            $null = New-Item -Path $isolatedDbatoolsData -ItemType Directory
            Set-DbatoolsConfig -FullName "Path.DbatoolsData" -Value $isolatedDbatoolsData
        }

        AfterEach {
            Set-DbatoolsConfig -FullName "Path.DbatoolsData" -Value $originalDbatoolsData
        }

        It "downloads each tool when Software is passed as an array" {
            Save-DbaCommunitySoftware -Software MaintenanceSolution, DarlingData -EnableException

            $splatMaintenanceCheck = @{
                Path    = Join-Path -Path $isolatedDbatoolsData -ChildPath "sql-server-maintenance-solution-main"
                Recurse = $true
                Filter  = "CommandExecute.sql"
            }
            Get-ChildItem @splatMaintenanceCheck | Should -Not -BeNullOrEmpty

            $splatDarlingCheck = @{
                Path    = Join-Path -Path $isolatedDbatoolsData -ChildPath "DarlingData-main"
                Recurse = $true
                Filter  = "*.sql"
            }
            Get-ChildItem @splatDarlingCheck | Should -Not -BeNullOrEmpty
        }

        It "downloads every tool when Software is All" {
            Save-DbaCommunitySoftware -Software All -EnableException

            $expectedFolders = @(
                "sql-server-maintenance-solution-main",
                "SQL-Server-First-Responder-Kit-main",
                "DarlingData-main",
                "SQLWATCH",
                "WhoIsActive",
                "dba-multitool-main",
                "AzSqlTips"
            )
            foreach ($expectedFolder in $expectedFolders) {
                $splatFolderCheck = @{
                    Path    = Join-Path -Path $isolatedDbatoolsData -ChildPath $expectedFolder
                    Recurse = $true
                    File    = $true
                }
                Get-ChildItem @splatFolderCheck | Should -Not -BeNullOrEmpty
            }
        }
    }
}
