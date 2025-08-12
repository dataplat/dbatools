#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbState",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Reading db statuses" {
        BeforeAll {
            $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $global:db1 = "dbatoolsci_dbstate_online"
            $global:db2 = "dbatoolsci_dbstate_offline"
            $global:db3 = "dbatoolsci_dbstate_emergency"
            $global:db4 = "dbatoolsci_dbstate_single"
            $global:db5 = "dbatoolsci_dbstate_restricted"
            $global:db6 = "dbatoolsci_dbstate_multi"
            $global:db7 = "dbatoolsci_dbstate_rw"
            $global:db8 = "dbatoolsci_dbstate_ro"
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $global:db1, $global:db2, $global:db3, $global:db4, $global:db5, $global:db6, $global:db7, $global:db8 | Remove-DbaDatabase -Confirm:$false
            $global:server.Query("CREATE DATABASE $global:db1")
            $global:server.Query("CREATE DATABASE $global:db2; ALTER DATABASE $global:db2 SET OFFLINE WITH ROLLBACK IMMEDIATE")
            $global:server.Query("CREATE DATABASE $global:db3; ALTER DATABASE $global:db3 SET EMERGENCY WITH ROLLBACK IMMEDIATE")
            $global:server.Query("CREATE DATABASE $global:db4; ALTER DATABASE $global:db4 SET SINGLE_USER WITH ROLLBACK IMMEDIATE")
            $global:server.Query("CREATE DATABASE $global:db5; ALTER DATABASE $global:db5 SET RESTRICTED_USER WITH ROLLBACK IMMEDIATE")
            $global:server.Query("CREATE DATABASE $global:db6; ALTER DATABASE $global:db6 SET MULTI_USER WITH ROLLBACK IMMEDIATE")
            $global:server.Query("CREATE DATABASE $global:db7; ALTER DATABASE $global:db7 SET READ_WRITE WITH ROLLBACK IMMEDIATE")
            $global:server.Query("CREATE DATABASE $global:db8; ALTER DATABASE $global:db8 SET READ_ONLY WITH ROLLBACK IMMEDIATE")
            $global:setupright = $true
            $needed_ = $global:server.Query("select name from sys.databases")
            $needed = $needed_ | Where-Object name -in $global:db1, $global:db2, $global:db3, $global:db4, $global:db5, $global:db6, $global:db7, $global:db8
            if ($needed.Count -ne 8) {
                $global:setupright = $false
            }
        }
        AfterAll {
            $null = Set-DbaDbState -Sqlinstance $TestConfig.instance2 -Database $global:db2, $global:db3, $global:db4, $global:db5, $global:db7 -Online -ReadWrite -MultiUser -Force -ErrorAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $global:db1, $global:db2, $global:db3, $global:db4, $global:db5, $global:db6, $global:db7, $global:db8 -ErrorAction SilentlyContinue
        }
        It "Should fail if setup was not successful" -Skip:$global:setupright {
            $global:setupright | Should -Be $false -Because "Setup failed"
        }

        # just to have a correct report on how much time BeforeAll takes
        It "Waits for BeforeAll to finish" -Skip:(-not $global:setupright) {
            $true | Should -Be $true
        }

        It "Honors the Database parameter" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db2
            $result.DatabaseName | Should -Be $global:db2
            $results = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1, $global:db2
            $results.Count | Should -Be 2
        }

        It "Honors the ExcludeDatabase parameter" -Skip:(-not $global:setupright) {
            $alldbs_ = $global:server.Query("select name from sys.databases")
            $alldbs = ($alldbs_ | Where-Object Name -notin @($global:db1, $global:db2, $global:db3, $global:db4, $global:db5, $global:db6, $global:db7, $global:db8)).name
            $results = Get-DbaDbState -SqlInstance $TestConfig.instance2 -ExcludeDatabase $alldbs
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($global:db1, $global:db2, $global:db3, $global:db4, $global:db5, $global:db6, $global:db7, $global:db8))
            $comparison.Count | Should -Be 0
        }

        It "Identifies online database" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1
            $result.DatabaseName | Should -Be $global:db1
            $result.Status | Should -Be "ONLINE"
        }

        It "Identifies offline database" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db2
            $result.DatabaseName | Should -Be $global:db2
            $result.Status | Should -Be "OFFLINE"
        }

        It "Identifies emergency database" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db3
            $result.DatabaseName | Should -Be $global:db3
            $result.Status | Should -Be "EMERGENCY"
        }

        It "Identifies single_user database" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db4
            $result.DatabaseName | Should -Be $global:db4
            $result.Access | Should -Be "SINGLE_USER"
        }

        It "Identifies restricted_user database" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db5
            $result.DatabaseName | Should -Be $global:db5
            $result.Access | Should -Be "RESTRICTED_USER"
        }

        It "Identifies multi_user database" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db6
            $result.DatabaseName | Should -Be $global:db6
            $result.Access | Should -Be "MULTI_USER"
        }

        It "Identifies read_write database" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db7
            $result.DatabaseName | Should -Be $global:db7
            $result.RW | Should -Be "READ_WRITE"
        }

        It "Identifies read_only database" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db8
            $result.DatabaseName | Should -Be $global:db8
            $result.RW | Should -Be "READ_ONLY"
        }

        It "Has the correct properties" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1
            $ExpectedProps = "SqlInstance", "InstanceName", "ComputerName", "DatabaseName", "RW", "Status", "Access", "Database"
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }

        It "Has the correct default properties" -Skip:(-not $global:setupright) {
            $result = Get-DbaDbState -SqlInstance $TestConfig.instance2 -Database $global:db1
            $ExpectedPropsDefault = "SqlInstance", "InstanceName", "ComputerName", "DatabaseName", "RW", "Status", "Access"
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }
}