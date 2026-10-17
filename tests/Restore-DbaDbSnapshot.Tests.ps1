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
            $result = Restore-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Snapshot $db1_snap1 -EnableException -Force
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

    Context "When the restore fails for another reason than a deadlock" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            # A login with a user in the database, and so in its snapshot, sees both, but has no permission to restore, so
            # the restore fails at once and without a deadlock. A session that holds the database is no good trigger: the
            # restore waits for its lock for an unpredictable time before it fails.
            $deniedDb = "dbatoolsci_RestoreSnap3_$(Get-Random)"
            $deniedSnap = "$($deniedDb)_snapshotted"
            $deniedLogin = "dbatoolsci_snaprestore_$(Get-Random)"
            $deniedPassword = ConvertTo-SecureString "dbatools.IO$(Get-Random)" -AsPlainText -Force
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Name $deniedDb
            $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $deniedLogin -SecurePassword $deniedPassword
            $null = New-DbaDbUser -SqlInstance $TestConfig.InstanceSingle -Database $deniedDb -Login $deniedLogin
            $null = New-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $deniedDb -Name $deniedSnap
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            # Only a deadlock counts the tries, and the -Continue after any other failure continued the retry loop, so
            # the command ran the same failing restore without end. It runs in a runspace of its own, so that a regression
            # is stopped after a minute instead of holding up the test run. The runspace imports the manifest: an import of
            # the psm1 without a command line skips the type data. It has none of the default parameter values of the
            # tests, so Confirm is passed here.
            $splatFailingRestore = @{
                SqlInstance   = $TestConfig.InstanceSingle
                SqlCredential = New-Object System.Management.Automation.PSCredential($deniedLogin, $deniedPassword)
                Snapshot      = $deniedSnap
                Confirm       = $false
            }
            $restoreRunspace = [runspacefactory]::CreateRunspace()
            $restoreRunspace.Open()
            $importShell = [powershell]::Create()
            $importShell.Runspace = $restoreRunspace
            $manifestPath = Join-Path -Path (Get-Module -Name $ModuleName | Select-Object -First 1).ModuleBase -ChildPath "$ModuleName.psd1"
            $null = $importShell.AddCommand("Import-Module").AddParameter("Name", $manifestPath).Invoke()
            $importShell.Dispose()

            $restoreShell = [powershell]::Create()
            $restoreShell.Runspace = $restoreRunspace
            $null = $restoreShell.AddCommand("Restore-DbaDbSnapshot").AddParameters($splatFailingRestore)
            $restoreAsync = $restoreShell.BeginInvoke()
            $restoreFinished = $restoreAsync.AsyncWaitHandle.WaitOne([timespan]::FromSeconds(60))
            if (-not $restoreFinished) {
                $restoreShell.Stop()
            }
            $restoreWarnings = @($restoreShell.Streams.Warning | ForEach-Object { $PSItem.Message })
            $restoreShell.Dispose()
            $restoreRunspace.Dispose()
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Remove-DbaDbSnapshot -SqlInstance $TestConfig.InstanceSingle -Database $deniedDb -ErrorAction SilentlyContinue
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceSingle -Database $deniedDb -ErrorAction SilentlyContinue
            Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $deniedLogin -ErrorAction SilentlyContinue
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Gives up instead of trying again and again" {
            $restoreFinished | Should -BeTrue
        }

        It "Warns once about the failed restore" {
            @($restoreWarnings | Where-Object { $PSItem -like "*Failure attempting to restore*" }).Count | Should -Be 1
        }
    }
}