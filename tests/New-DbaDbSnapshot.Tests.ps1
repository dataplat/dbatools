#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaDbSnapshot",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

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
                "AllDatabases",
                "Name",
                "NameSuffix",
                "Path",
                "Force",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# Targets only instance2 because it's the only one where Snapshots can happen
Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Parameter validation" {
        It "Stops if no Database or AllDatabases" {
            { New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -WarningAction SilentlyContinue } | Should Throw "You must specify"
        }
        It "Is nice by default" {
            { New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 *> $null -WarningAction SilentlyContinue } | Should Not Throw "You must specify"
        }
    }

    Context "Operations on not supported databases" {
        It "Doesn't support model, master or tempdb" {
            $result = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database model, master, tempdb -WarningAction SilentlyContinue
            $result | Should -Be $null
        }
    }

    Context "Operations on databases" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $global:server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            Get-DbaProcess -SqlInstance $TestConfig.instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
            $global:db1 = "dbatoolsci_SnapMe"
            $global:db2 = "dbatoolsci_SnapMe2"
            $global:db3 = "dbatoolsci_SnapMe3_Offline"
            $global:db4 = "dbatoolsci_SnapMe4.WithDot"
            $global:server.Query("CREATE DATABASE $global:db1")
            $global:server.Query("CREATE DATABASE $global:db2")
            $global:server.Query("CREATE DATABASE $global:db3")
            $global:server.Query("CREATE DATABASE [$global:db4]")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }
        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $global:db1, $global:db2, $global:db3, $global:db4 -Confirm:$false -ErrorAction SilentlyContinue
            Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $global:db1, $global:db2, $global:db3, $global:db4 -ErrorAction SilentlyContinue
        }

        It "Skips over offline databases nicely" {
            $global:server.Query("ALTER DATABASE $global:db3 SET OFFLINE WITH ROLLBACK IMMEDIATE")
            $result = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $global:db3
            $result | Should -Be $null
            $global:server.Query("ALTER DATABASE $global:db3 SET ONLINE WITH ROLLBACK IMMEDIATE")
        }

        It "Refuses to accept multiple source databases with a single name target" {
            { New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $global:db1, $global:db2 -Name "dbatools_Snapped" -WarningAction SilentlyContinue } | Should Throw
        }

        It "Halts when path is not accessible" {
            { New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $global:db1 -Path B:\Funnydbatoolspath -EnableException -WarningAction SilentlyContinue } | Should Throw
        }

        It "Creates snaps for multiple dbs by default" {
            $results = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $global:db1, $global:db2
            $results | Should -Not -Be $null
            foreach ($result in $results) {
                $result.SnapshotOf -in @($global:db1, $global:db2) | Should -Be $true
            }
        }

        It "Creates snap with the correct name" {
            $result = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $global:db1 -Name "dbatools_SnapMe_right"
            $result | Should -Not -Be $null
            $result.SnapshotOf | Should -Be $global:db1
            $result.Name | Should -Be "dbatools_SnapMe_right"
        }

        It "Creates snap with the correct name template" {
            $result = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $global:db2 -NameSuffix "dbatools_SnapMe_{0}_funny"
            $result | Should -Not -Be $null
            $result.SnapshotOf | Should -Be $global:db2
            $result.Name | Should -Be ("dbatools_SnapMe_{0}_funny" -f $global:db2)
        }

        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $global:db2 | Select-Object -First 1
            $ExpectedPropsDefault = "ComputerName", "CreateDate", "InstanceName", "Name", "SnapshotOf", "SqlInstance", "DiskUsage"
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }

        It "Creates multiple snaps for db with dot in the name (see #8829)" {
            $results = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $global:db4
            $results | Should -Not -Be $null
            foreach ($result in $results) {
                $result.SnapshotOf -in @($global:db4) | Should -Be $true
            }
            Start-Sleep -Seconds 2
            $results = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -Database $global:db4
            $results | Should -Not -Be $null
            foreach ($result in $results) {
                $result.SnapshotOf -in @($global:db4) | Should -Be $true
            }
        }
    }
}