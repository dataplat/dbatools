#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbSnapshot",
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
                "Snapshot",
                "ExcludeSnapshot",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

# Targets only InstanceSingle because it's the only one where Snapshots can happen
Describe $CommandName -Tag IntegrationTests {
    Context "Operations on snapshots" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
            $db1 = "dbatoolsci_GetSnap"
            $db1_snap1 = "dbatoolsci_GetSnap_snapshotted1"
            $db1_snap2 = "dbatoolsci_GetSnap_snapshotted2"
            $db2 = "dbatoolsci_GetSnap2"
            $db2_snap1 = "dbatoolsci_GetSnap2_snapshotted"
            Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 | Remove-DbaDatabase
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1 -Name $db1_snap1 -WarningAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1 -Name $db1_snap2 -WarningAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2 -Name $db2_snap1 -WarningAction SilentlyContinue

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gets all snapshots by default" {
            $results = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle
            ($results | Where-Object Name -Like "dbatoolsci_GetSnap*").Count | Should -Be 3
        }

        It "Honors the Database parameter, returning only snapshots of that database" {
            $results = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1
            $results.Count | Should -Be 2
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2
            $result.SnapshotOf | Should -Be $db2
            $result.SnapshotOf | Should -Be $db2
        }

        It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
            $alldbs = (Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
            $results = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -ExcludeDatabase $alldbs
            $results.Count | Should -Be 3
        }

        It "Honors the Snapshot parameter" {
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $db1_snap1
            $result.Name | Should -Be $db1_snap1
            $result.SnapshotOf | Should -Be $db1
            $result.Name | Should -Be $db1_snap1
            $result.SnapshotOf | Should -Be $db1
        }

        It "Honors the ExcludeSnapshot parameter" {
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -ExcludeSnapshot $db1_snap1 -Database $db1
            $result.Name | Should -Be $db1_snap2
            $result.Name | Should -Be $db1_snap2
        }

        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2
            $ExpectedPropsDefault = "ComputerName", "CreateDate", "InstanceName", "Name", "SnapshotOf", "SqlInstance", "DiskUsage"
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputDb = "dbatoolsci_SnapOutput"
            $outputSnap = "dbatoolsci_SnapOutput_snap"
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $outputDb
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $outputDb -Name $outputSnap -WarningAction SilentlyContinue
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $outputSnap

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $outputSnap -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $outputDb -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Database"
        }

        It "Has the expected default display properties" {
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "SnapshotOf", "CreateDate", "DiskUsage")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has working alias property SnapshotOf" {
            $result[0].psobject.Properties["SnapshotOf"] | Should -Not -BeNullOrEmpty
            $result[0].psobject.Properties["SnapshotOf"].MemberType | Should -Be "AliasProperty"
        }
    }
}