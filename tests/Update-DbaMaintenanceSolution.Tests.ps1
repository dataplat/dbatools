#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaMaintenanceSolution",
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
                "Database",
                "Solution",
                "LocalFile",
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

        $databaseName = "dbatoolsci_maintenance_update_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $databaseName

        $dbatoolsData = Get-DbatoolsConfigValue -FullName "Path.DbatoolsData"
        $localCachedCopy = Join-DbaPath -Path $dbatoolsData -Child "sql-server-maintenance-solution-main"
        Remove-Item -Path $localCachedCopy -Recurse -Force -ErrorAction SilentlyContinue

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $databaseName
        Remove-Item -Path $localCachedCopy -Recurse -Force -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "downloads the current GitHub source before checking installed procedures" {
        $results = Update-DbaMaintenanceSolution -SqlInstance $TestConfig.InstanceSingle -Database $databaseName -Solution CommandExecute -Force -EnableException

        $results | Should -HaveCount 1
        $results.Procedure | Should -Be "CommandExecute"
        $results.IsUpdated | Should -BeFalse
        $results.Results | Should -Be "Procedure not installed"
        Get-ChildItem -Path $localCachedCopy -Recurse -Filter "CommandExecute.sql" | Should -Not -BeNullOrEmpty
        $WarnVar | Should -Match "Force still suppresses confirmation prompts"
    }
}
