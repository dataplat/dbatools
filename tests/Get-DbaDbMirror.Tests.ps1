#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMirror",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}


Describe $CommandName -Tag IntegrationTests -Skip {
    # Skip IntegrationTests because Mirroring need additional setup.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $db1 = "dbatoolsci_mirroring"
        $db2 = "dbatoolsci_mirroring_db2"

        # Clean up any existing processes and databases
        $null = Get-DbaProcess -SqlInstance $TestConfig.instance2, $TestConfig.instance3 | Where-Object Program -Match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue

        Remove-DbaDbMirror -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2 | Remove-DbaDatabase

        # Create test databases
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $null = $server.Query("CREATE DATABASE $db1")
        $null = $server.Query("CREATE DATABASE $db2")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2 | Remove-DbaDbMirror
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db1, $db2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "returns more than one database" {
        $null = Invoke-DbaDbMirroring -Primary $TestConfig.instance2 -Mirror $TestConfig.instance3 -Database $db1, $db2 -Force -SharedPath $TestConfig.Temp -WarningAction Continue
        @(Get-DbaDbMirror -SqlInstance $TestConfig.instance3).Count | Should -Be 2
    }


    It "returns just one database" {
        @(Get-DbaDbMirror -SqlInstance $TestConfig.instance3 -Database $db2).Count | Should -Be 1
    }

    It "returns 2x1 database" {
        @(Get-DbaDbMirror -SqlInstance $TestConfig.instance2, $TestConfig.instance3 -Database $db2).Count | Should -Be 2
    }
}