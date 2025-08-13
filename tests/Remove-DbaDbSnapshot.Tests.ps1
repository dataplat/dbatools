#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbSnapshot",
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
                "Snapshot",
                "InputObject",
                "AllSnapshots",
                "Force",
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
        Get-DbaProcess -SqlInstance $TestConfig.instance2 | Where-Object Program -match dbatools | Stop-DbaProcess -Confirm:$false -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $db1 = "dbatoolsci_RemoveSnap"
        $db1_snap1 = "dbatoolsci_RemoveSnap_snapshotted1"
        $db1_snap2 = "dbatoolsci_RemoveSnap_snapshotted2"
        $db2 = "dbatoolsci_RemoveSnap2"
        $db2_snap1 = "dbatoolsci_RemoveSnap2_snapshotted"
        Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db1, $db2 -Confirm:$false
        Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        $server.Query("CREATE DATABASE $db1")
        $server.Query("CREATE DATABASE $db2")
    }
    AfterAll {
        Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db1, $db2 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaDatabase -Confirm:$false -SqlInstance $TestConfig.instance2 -Database $db1, $db2 -ErrorAction SilentlyContinue
    }
    Context "Parameters validation" {
        It "Stops if no Database or AllDatabases" {
            { Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -EnableException -WarningAction SilentlyContinue } | Should -Throw "*You must pipe*"
        }
        It "Is nice by default" {
            { Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 *> $null } | Should -Not -Throw
        }
    }

    Context "Operations on snapshots" {
        BeforeEach {
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db1 -Name $db1_snap1 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db1 -Name $db1_snap2 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db2 -Name $db2_snap1 -ErrorAction SilentlyContinue
        }
        AfterEach {
            Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db1, $db2 -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Honors the Database parameter, dropping only snapshots of that database" {
            $results = Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db1 -Confirm:$false
            $results.Count | Should -BeExactly 2
            $result = Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db2 -Confirm:$false
            $result.Name | Should -BeExactly $db2_snap1
        }

        It "Honors the ExcludeDatabase parameter, returning relevant snapshots" {
            $alldbs = (Get-DbaDatabase -SqlInstance $TestConfig.instance2 | Where-Object IsDatabaseSnapShot -eq $false | Where-Object Name -notin @($db1, $db2)).Name
            $results = Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -ExcludeDatabase $alldbs -Confirm:$false
            $results.Count | Should -BeExactly 3
        }
        It "Honors the Snapshot parameter" {
            $result = Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Snapshot $db1_snap1 -Confirm:$false
            $result.Name | Should -BeExactly $db1_snap1
        }
        It "Works with piped snapshots" {
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Snapshot $db1_snap1 | Remove-DbaDbSnapshot -Confirm:$false
            $result.Name | Should -BeExactly $db1_snap1
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Snapshot $db1_snap1
            $result | Should -BeNullOrEmpty
        }
        It "Has the correct default properties" {
            $result = Remove-DbaDbSnapshot -SqlInstance $TestConfig.instance2 -Database $db2 -Confirm:$false
            $ExpectedPropsDefault = "ComputerName", "Name", "InstanceName", "SqlInstance", "Status"
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -BeExactly ($ExpectedPropsDefault | Sort-Object)
        }
    }
}