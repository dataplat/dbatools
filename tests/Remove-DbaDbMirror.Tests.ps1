#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMirror",
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
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip {
    # Skip IntegrationTests because Mirroring needs additional setup.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $db1 = "dbatoolsci_removemirror"
        $db2 = "dbatoolsci_removemirror_db2"

        # Clean up any existing processes and databases
        $null = Get-DbaProcess -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Where-Object Program -Match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue

        Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $db1, $db2 -ErrorAction SilentlyContinue
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $db1, $db2 | Remove-DbaDatabase

        # Create test databases
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $null = $server.Query("CREATE DATABASE $db1")
        $null = $server.Query("CREATE DATABASE $db2")

        # Set up mirroring
        $splatMirroring = @{
            Primary    = $TestConfig.InstanceMulti1
            Mirror     = $TestConfig.InstanceMulti2
            Database   = $db1, $db2
            Force      = $true
            SharedPath = $TestConfig.Temp
        }
        $null = Invoke-DbaDbMirroring @splatMirroring -WarningAction Continue

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $db1, $db2 | Remove-DbaDbMirror -ErrorAction SilentlyContinue
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $db1, $db2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing database mirroring" {
        It "removes mirroring from a database" {
            $splatRemove = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = $db1
                Confirm     = $false
            }
            $result = Remove-DbaDbMirror @splatRemove -OutVariable "global:dbatoolsciOutput"
            $result.Status | Should -Be "Removed"
            $result.Database | Should -Be $db1
        }

        It "removes mirroring via pipeline" {
            $result = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Database $db2 | Remove-DbaDbMirror -Confirm:$false
            $result.Status | Should -Be "Removed"
            $result.Database | Should -Be $db2
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Status"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}