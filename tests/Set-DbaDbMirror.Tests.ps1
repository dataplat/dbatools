#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbMirror",
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
                "Partner",
                "Witness",
                "SafetyLevel",
                "State",
                "InputObject",
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
        $db1 = "dbatoolsci_setmirror"

        # Clean up any existing processes and databases
        $null = Get-DbaProcess -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 | Where-Object Program -Match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue

        Remove-DbaDbMirror -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $db1
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $db1 | Remove-DbaDatabase

        # Create test database and set up mirroring
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $null = $server.Query("CREATE DATABASE $db1")
        $null = Invoke-DbaDbMirroring -Primary $TestConfig.InstanceMulti1 -Mirror $TestConfig.InstanceMulti2 -Database $db1 -Force -SharedPath $TestConfig.Temp -WarningAction Continue

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $db1 | Remove-DbaDbMirror
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $db1 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When changing mirror state" {
        It "Should suspend and resume the mirrored database" {
            $splatSuspend = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = $db1
                State       = "Suspend"
                Confirm     = $false
            }
            $result = Set-DbaDbMirror @splatSuspend -OutVariable "global:dbatoolsciOutput"
            $result | Should -Not -BeNullOrEmpty
            $result.Name | Should -Be $db1

            $splatResume = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = $db1
                State       = "Resume"
                Confirm     = $false
            }
            $null = Set-DbaDbMirror @splatResume
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Database"
        }
    }
}