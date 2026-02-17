#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Restore-DbaDbSnapshot",
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
                "InputObject",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaProcess -SqlInstance $TestConfig.InstanceSingle | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $db1 = "dbatoolsci_RestoreSnap1"
        $db1_snap1 = "dbatoolsci_RestoreSnap1_snapshotted1"
        $db1_snap2 = "dbatoolsci_RestoreSnap1_snapshotted2"
        $db2 = "dbatoolsci_RestoreSnap2"
        $db2_snap1 = "dbatoolsci_RestoreSnap2_snapshotted1"
        Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2
        Get-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 | Remove-DbaDatabase
        $server.Query("CREATE DATABASE $db1")
        $server.Query("ALTER DATABASE $db1 MODIFY FILE ( NAME = N'$($db1)_log', SIZE = 13312KB )")
        $server.Query("CREATE DATABASE $db2")
        $server.Query("CREATE TABLE [$db1].[dbo].[Example] (id int identity, name nvarchar(max))")
        $server.Query("INSERT INTO [$db1].[dbo].[Example] values ('sample')")
        $server.Query("CREATE TABLE [$db2].[dbo].[Example] (id int identity, name nvarchar(max))")
        $server.Query("INSERT INTO [$db2].[dbo].[Example] values ('sample')")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 -ErrorAction SilentlyContinue
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Parameters validation" {
        It "Stops if no Database or Snapshot" {
            { Restore-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw "You must specify*"
        }
        It "Is nice by default" {
            { Restore-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle *> $null } | Should -Not -Throw "You must specify*"
        }
    }
    Context "Operations on snapshots" {
        BeforeEach {
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1 -Name $db1_snap1 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1 -Name $db1_snap2 -ErrorAction SilentlyContinue
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2 -Name $db2_snap1 -ErrorAction SilentlyContinue
        }
        AfterEach {
            Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1, $db2 -ErrorAction SilentlyContinue
        }

        It "Honors the Database parameter, restoring only snapshots of that database" {
            $result = Restore-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2 -EnableException -Force
            $result.Status | Should -Be "Normal"
            $result.Name | Should -Be $db2

            $server.Query("INSERT INTO [$db1].[dbo].[Example] values ('sample2')")
            $result = Restore-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1 -Force
            $result.Name | Should -Be $db1

            # the other snapshot has been dropped
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1
            $result.Count | Should -Be 1

            # the query doesn't return records inserted before the restore
            $result = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceSingle -Query "SELECT * FROM [$db1].[dbo].[Example]" -QueryTimeout 10
            $result.id | Should -Be 1
        }

        It "Honors the Snapshot parameter" {
            $result = Restore-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $db1_snap1 -EnableException -Force -OutVariable "global:dbatoolsciOutput"
            $result.Name | Should -Be $db1
            $result.Status | Should -Be "Normal"

            # the other snapshot has been dropped
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1
            $result.SnapshotOf | Should -Be $db1
            $result.Database.Name | Should -Be $db1_snap

            # the log size has been restored to the correct size
            $server.databases[$db1].Logfiles.Size | Should -Be 13312
        }

        It "Stops if multiple snapshot for the same db are passed" {
            $result = Restore-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $db1_snap1, $db1_snap2 *> $null
            $result | Should -Be $null
        }

        It "has the correct default properties" {
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db2
            $ExpectedPropsDefault = 'ComputerName', 'CreateDate', 'InstanceName', 'Name', 'SnapshotOf', 'SqlInstance', 'DiskUsage'
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedPropsDefault | Sort-Object)
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Database]
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Status",
                "IsAccessible",
                "RecoveryModel",
                "LogReuseWaitStatus",
                "SizeMB",
                "Compatibility",
                "Collation",
                "Owner",
                "Encrypted",
                "LastFullBackup",
                "LastDiffBackup",
                "LastLogBackup"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.Database"
        }
    }
}