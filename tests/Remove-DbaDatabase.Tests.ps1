#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDatabase",
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

Describe $CommandName -Tag IntegrationTests {
    Context "Should not munge system databases." {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $dbs = @( "master", "model", "tempdb", "msdb" )

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should not attempt to remove system databases." {
            foreach ($db in $dbs) {
                $db1 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db
                Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db
                $db2.Name | Should -Be $db1.Name
            }
        }

        It "Should not take system databases offline or change their status." {
            foreach ($db in $dbs) {
                $db1 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db
                Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db
                $db2.Status | Should -Be $db1.Status
                $db2.IsAccessible | Should -Be $db1.IsAccessible
            }
        }
    }
    Context "Should remove user databases and return useful errors if it cannot." {
        It "Should remove a non system database." {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database singlerestore
            Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database singlerestore | Stop-DbaProcess
            Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -WithReplace
            (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database singlerestore).IsAccessible | Should -BeTrue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database singlerestore
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database singlerestore | Should -BeNullOrEmpty
        }
    }
    Context "Should remove restoring database and return useful errors if it cannot." {
        It "Should remove a non system database." {
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database singlerestore
            Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Database singlerestore | Stop-DbaProcess
            Restore-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Path "$($TestConfig.appveyorlabrepo)\singlerestore\singlerestore.bak" -WithReplace -NoRecovery
            (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).Databases['singlerestore'].IsAccessible | Should -BeFalse
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database singlerestore
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database singlerestore | Should -BeNullOrEmpty
        }
    }
}