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
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $db1 = "dbatoolsci_dbstate_online"
            $db2 = "dbatoolsci_dbstate_offline"
            $db3 = "dbatoolsci_dbstate_emergency"
            $db4 = "dbatoolsci_dbstate_single"
            $db5 = "dbatoolsci_dbstate_restricted"
            $db6 = "dbatoolsci_dbstate_multi"
            $db7 = "dbatoolsci_dbstate_rw"
            $db8 = "dbatoolsci_dbstate_ro"

            $splatRemoveDb = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
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

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatSetState = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db2, $db3, $db4, $db5, $db7
                Online      = $true
                ReadWrite   = $true
                MultiUser   = $true
                Force       = $true
            }
            $null = Set-DbaDbState @splatSetState

            $splatRemoveDbCleanup = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database    = $db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8
            }
            Remove-DbaDatabase @splatRemoveDbCleanup

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Waits for BeforeAll to finish" {
            $true | Should -BeTrue
        }

        It "Honors the Database parameter" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db2
            $result.DatabaseName | Should -Be $db2
            $results = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2
            $results.Count | Should -Be 2
        }

        It "Honors the ExcludeDatabase parameter" {
            $alldbs_ = $server.Query("select name from sys.databases")
            $alldbs = ($alldbs_ | Where-Object Name -notin @($db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8)).name
            $results = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $alldbs
            $comparison = Compare-Object -ReferenceObject ($results.DatabaseName) -DifferenceObject (@($db1, $db2, $db3, $db4, $db5, $db6, $db7, $db8))
            $comparison.Count | Should -Be 0
        }

        It "Identifies online database" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db1 -OutVariable "global:dbatoolsciOutput"
            $result.DatabaseName | Should -Be $db1
            $result.Status | Should -Be "ONLINE"
        }

        It "Identifies offline database" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db2
            $result.DatabaseName | Should -Be $db2
            $result.Status | Should -Be "OFFLINE"
        }

        It "Identifies emergency database" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db3
            $result.DatabaseName | Should -Be $db3
            $result.Status | Should -Be "EMERGENCY"
        }

        It "Identifies single_user database" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db4
            $result.DatabaseName | Should -Be $db4
            $result.Access | Should -Be "SINGLE_USER"
        }

        It "Identifies restricted_user database" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db5
            $result.DatabaseName | Should -Be $db5
            $result.Access | Should -Be "RESTRICTED_USER"
        }

        It "Identifies multi_user database" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db6
            $result.DatabaseName | Should -Be $db6
            $result.Access | Should -Be "MULTI_USER"
        }

        It "Identifies read_write database" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db7
            $result.DatabaseName | Should -Be $db7
            $result.RW | Should -Be "READ_WRITE"
        }

        It "Identifies read_only database" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db8
            $result.DatabaseName | Should -Be $db8
            $result.RW | Should -Be "READ_ONLY"
        }

        It "Has the correct properties" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db1
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

        It "Has the correct default properties" {
            $result = Get-DbaDbState -SqlInstance $TestConfig.InstanceSingle -Database $db1
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
                "DatabaseName",
                "RW",
                "Status",
                "Access",
                "Database"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "DatabaseName",
                "RW",
                "Status",
                "Access"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}