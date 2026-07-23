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
        # Grow the log by a fixed delta from its live size rather than shrinking to a fixed target.
        # A fixed small target (the old 13312KB) is unreachable on SQL 2022's 72MB default log, and
        # MODIFY FILE cannot shrink below the current size. Growing works on any SQL default. This
        # grown size is the snapshot-time log size; Restore-DbaDbSnapshot reverts the log to it, and
        # the "Honors the Snapshot parameter" test asserts against $db1LogSizeTarget.
        $server.Databases.Refresh()
        $db1LogSizeStart = [int]$server.Databases[$db1].LogFiles[0].Size
        $db1LogSizeTarget = $db1LogSizeStart + 16384
        $server.Query("ALTER DATABASE $db1 MODIFY FILE ( NAME = N'$($db1)_log', SIZE = $($db1LogSizeTarget)KB )")
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
            # Capture the log size at snapshot time (nothing changes it between the BeforeEach
            # snapshot and this revert). Restore-DbaDbSnapshot must return the log to this size;
            # capturing it live keeps the assertion correct regardless of what an earlier test in
            # this Context left the log at (an earlier revert can reset it off the BeforeAll grow).
            $server.Databases[$db1].Refresh()
            $server.Databases[$db1].LogFiles.Refresh()
            $db1LogSizeAtSnapshot = [int]$server.Databases[$db1].LogFiles[0].Size

            $result = Restore-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $db1_snap1 -EnableException -Force
            $result.Name | Should -Be $db1
            $result.Status | Should -Be "Normal"

            # restoring from a specific snapshot drops the OTHER snapshots of the same database but
            # leaves the one restored from, so exactly $db1_snap1 remains
            $result = Get-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $db1
            $result.SnapshotOf | Should -Be $db1
            $result.Name | Should -Be $db1_snap1

            # the log size has been restored to the snapshot-time size (Restore-DbaDbSnapshot fixes
            # the SQL Server bug that resets log growth settings during a snapshot restore)
            $server.Databases[$db1].Refresh()
            $server.Databases[$db1].LogFiles.Refresh()
            [int]$server.Databases[$db1].LogFiles[0].Size | Should -Be $db1LogSizeAtSnapshot
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
}