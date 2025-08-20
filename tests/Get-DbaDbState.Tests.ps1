#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbState",
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
                "ExcludeDatabase",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Reading db statuses" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $db1 = "dbatoolsci_dbstate_online"
            $db2 = "dbatoolsci_dbstate_offline"
            $db3 = "dbatoolsci_dbstate_emergency"
            $db4 = "dbatoolsci_dbstate_single"
            $db5 = "dbatoolsci_dbstate_restricted"
            $db6 = "dbatoolsci_dbstate_multi"
            $db7 = "dbatoolsci_dbstate_rw"
            $db8 = "dbatoolsci_dbstate_ro"

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.instance2
                Database    = $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
                Confirm     = $false
            }
            Get-DbaDatabase @splatRemoveDb | Remove-DbaDatabase

            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2; ALTER DATABASE $db2 SET OFFLINE WITH ROLLBACK IMMEDIATE")
            $server.Query("CREATE DATABASE $db3; ALTER DATABASE $db3 SET EMERGENCY WITH ROLLBACK IMMEDIATE")
            $server.Query("CREATE DATABASE $db4; ALTER DATABASE $db4 SET SINGLE_USER WITH ROLLBACK IMMEDIATE")
            $server.Query("CREATE DATABASE $db5; ALTER DATABASE $db5 SET RESTRICTED_USER WITH ROLLBACK IMMEDIATE")
            $server.Query("CREATE DATABASE $db6; ALTER DATABASE $db6 SET MULTI_USER WITH ROLLBACK IMMEDIATE")
            $server.Query("CREATE DATABASE $db7; ALTER DATABASE $db7 SET READ_WRITE WITH ROLLBACK IMMEDIATE")
            $server.Query("CREATE DATABASE $db8; ALTER DATABASE $db8 SET READ_ONLY WITH ROLLBACK IMMEDIATE")

            $setupright = $true
            $needed_ = $server.Query("select name from sys.databases")
            $needed = $needed_ | Where-Object name -in $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
            if ($needed.Count -ne 8) {
                $setupright = $false
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

            $splatSetState = @{
                SqlInstance = $TestConfig.instance2
                Database    = $db2, $db3, $db4, $db5, $db7
                Online      = $true
                ReadWrite   = $true
                MultiUser   = $true
                Force       = $true
            }
            $null = Set-DbaDbState @splatSetState

            $splatRemoveDbCleanup = @{
                SqlInstance = $TestConfig.instance2
                Database    = $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
                Confirm     = $false
            }
            Remove-DbaDatabase @splatRemoveDbCleanup -ErrorAction SilentlyContinue

            # As this is the last block we do not need to reset the $PSDefaultParameterValues.
        }

        It "Waits for BeforeAll to finish" -Skip:(-not $setupright) {
            $true | Should -BeTrue
        }

        It "Honors the Database parameter" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db2
            $result.DatabaseName | Should -Be $db2
            $results = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1, $db2
            $results.Count | Should -Be 2
        }

        It "Honors the ExcludeDatabase parameter" -Skip:(-not $setupright) {
            $alldbs_ = $server.Query("select name from sys.databases")
            $alldbs = ($alldbs_ | Where-Object Name -notin @($db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8)).name
            $results = Get-DbaDbState -SqlInstance $TestConfig.instance2 -ExcludeDatabase $alldbs
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8))
            $comparison.Count | Should -Be 0
        }

        It "Identifies online database" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1
            $result.DatabaseName | Should -Be $db1
            $result.Status | Should -Be "ONLINE"
        }

        It "Identifies offline database" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db2
            $result.DatabaseName | Should -Be $db2
            $result.Status | Should -Be "OFFLINE"
        }

        It "Identifies emergency database" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db3
            $result.DatabaseName | Should -Be $db3
            $result.Status | Should -Be "EMERGENCY"
        }

        It "Identifies single_user database" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db4
            $result.DatabaseName | Should -Be $db4
            $result.Access | Should -Be "SINGLE_USER"
        }

        It "Identifies restricted_user database" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db5
            $result.DatabaseName | Should -Be $db5
            $result.Access | Should -Be "RESTRICTED_USER"
        }

        It "Identifies multi_user database" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db6
            $result.DatabaseName | Should -Be $db6
            $result.Access | Should -Be "MULTI_USER"
        }

        It "Identifies read_write database" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db7
            $result.DatabaseName | Should -Be $db7
            $result.RW | Should -Be "READ_WRITE"
        }

        It "Identifies read_only database" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db8
            $result.DatabaseName | Should -Be $db8
            $result.RW | Should -Be "READ_ONLY"
        }

        It "Has the correct properties" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1
            $ExpectedProps = @(
                "SqlInstance",
                "InstanceName",
                "ComputerName",
                "DatabaseName",
                "RW",
                "Status",
                "Access",
                "Database"
            )
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Has the correct default properties" -Skip:(-not $setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $db1
            $ExpectedPropsDefault = @(
                "SqlInstance",
                "InstanceName",
                "ComputerName",
                "DatabaseName",
                "RW",
                "Status",
                "Access"
            )
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}