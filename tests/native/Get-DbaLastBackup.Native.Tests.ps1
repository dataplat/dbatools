#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaLastBackup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares [CmdletBinding()] without SupportsShouldProcess and changes nothing; it only reads msdb backup history.
# NativeChecklist: platform cross-platform -- no Windows-only API

Describe "Get-DbaLastBackup native" -Tag IntegrationTests {
    BeforeAll {
        function Remove-BackupDatabase {
            param($Target, [string[]]$Name)
            $existing = @($Target.Query("SELECT name FROM sys.databases")).name
            foreach ($dbName in $Name) {
                if ($dbName -in $existing) {
                    $null = $Target.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$dbName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$dbName];")
                }
                $null = $Target.ConnectionContext.ExecuteNonQuery("EXEC msdb.dbo.sp_delete_database_backuphistory @database_name = N'$dbName';")
            }
        }

        # Backups to NUL write no file, and msdb records them as any other backup.
        function Backup-ToNul {
            param($Target, [string]$Name)
            $null = $Target.ConnectionContext.ExecuteNonQuery("BACKUP DATABASE [$Name] TO DISK = N'NUL';")
            $null = $Target.ConnectionContext.ExecuteNonQuery("BACKUP DATABASE [$Name] TO DISK = N'NUL' WITH DIFFERENTIAL;")
            $null = $Target.ConnectionContext.ExecuteNonQuery("BACKUP LOG [$Name] TO DISK = N'NUL';")
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-LastBackupOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command -Name "Get-DbaLastBackup" -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaLastBackup", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaLastBackup @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [PSCustomObject]@{
                    Rows   = @($outsideOutput | Where-Object { $PSItem.PSObject.Properties.Name -contains "LastFullBackup" })
                    Next   = @($outsideOutput | Where-Object { "$($PSItem.PSObject.BaseObject)" -ceq "next statement" }).Count -gt 0
                    Errors = @($outsideShell.Streams.Error)
                    Stop   = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        # Unique per leg and run (lane-safe); AfterAll drops the databases and their history.
        $prefix = "native_lastbackup_" + [Guid]::NewGuid().ToString("N")
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $dbBacked = "${prefix}_a"
        $dbNew = "${prefix}_b"
        $dbOldLog = "${prefix}_c"
        $allNames = @($dbBacked, $dbNew, $dbOldLog)
        foreach ($name in $allNames) {
            $null = $server.ConnectionContext.ExecuteNonQuery("CREATE DATABASE [$name]; ALTER DATABASE [$name] SET RECOVERY FULL;")
        }
        Backup-ToNul -Target $server -Name $dbBacked
        Backup-ToNul -Target $server -Name $dbOldLog
        # The log backup of C finished two days and thirty minutes ago: its hours part is 0, its age more than a day.
        $null = $server.ConnectionContext.ExecuteNonQuery("UPDATE msdb.dbo.backupset SET backup_start_date = DATEADD(MINUTE, -2911, GETDATE()), backup_finish_date = DATEADD(MINUTE, -2910, GETDATE()) WHERE database_name = N'$dbOldLog' AND type = 'L';")

        $badInstance = "TCP:127.0.0.1,1"
        $outputProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "RecoveryModel", "LastFullBackup", "LastDiffBackup", "LastLogBackup", "SinceFull", "SinceDiff", "SinceLog", "LastFullBackupIsCopyOnly", "LastDiffBackupIsCopyOnly", "LastLogBackupIsCopyOnly", "DatabaseCreated", "DaysSinceDbCreated", "Status")
        $defaultView = @("ComputerName", "InstanceName", "SqlInstance", "Database", "LastFullBackup", "LastDiffBackup", "LastLogBackup")
    }

    AfterAll {
        Remove-BackupDatabase -Target $server -Name $allNames
    }

    Context "Results" {
        It "reports the newest backup of each type as msdb holds it" {
            $independent = @{ }
            foreach ($row in @($server.Query("SELECT type, MAX(backup_finish_date) AS finish FROM msdb.dbo.backupset WHERE database_name = N'$dbBacked' GROUP BY type"))) {
                $independent[$row.type] = $row.finish
            }
            $independent.Keys.Count | Should -Be 3

            $results = @(Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbBacked -EnableException)
            $results.Count | Should -Be 1
            $result = $results[0]
            @($result.PSObject.Properties.Name) | Should -Be $outputProperties
            @($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Be $defaultView
            $result.ComputerName | Should -BeExactly $server.ComputerName
            $result.InstanceName | Should -BeExactly $server.ServiceName
            $result.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result.Database | Should -BeExactly $dbBacked
            "$($result.RecoveryModel)" | Should -BeExactly "Full"
            $result.LastFullBackup | Should -BeOfType [Dataplat.Dbatools.Utility.DbaDateTime]
            [datetime]$result.LastFullBackup | Should -Be $independent["D"]
            [datetime]$result.LastDiffBackup | Should -Be $independent["I"]
            [datetime]$result.LastLogBackup | Should -Be $independent["L"]
            $result.SinceFull | Should -BeOfType [Dataplat.Dbatools.Utility.DbaTimeSpan]
            $result.SinceFull.Days | Should -Be 0
            $result.LastFullBackupIsCopyOnly | Should -BeFalse
            $result.LastDiffBackupIsCopyOnly | Should -BeFalse
            $result.LastLogBackupIsCopyOnly | Should -BeFalse
            $result.DatabaseCreated | Should -Be $server.Databases[$dbBacked].CreateDate
            $result.DaysSinceDbCreated | Should -Be 0
            $result.Status | Should -BeExactly "OK"
        }

        It "gives empty dates and copy-only flags for a database never backed up" {
            $result = @(Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbNew -EnableException)[0]
            $result.LastFullBackup | Should -BeNullOrEmpty
            $result.LastDiffBackup | Should -BeNullOrEmpty
            $result.LastLogBackup | Should -BeNullOrEmpty
            $result.LastFullBackupIsCopyOnly | Should -BeNullOrEmpty
            $result.LastLogBackupIsCopyOnly | Should -BeNullOrEmpty
        }

        # Named databases only: other lanes create and drop theirs on the same instance meanwhile.
        It "leaves out tempdb and the excluded databases, in the instance's order" {
            $results = @(Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database "TEMPDB", "master", $dbBacked, $dbNew -ExcludeDatabase $dbNew.ToUpper() -EnableException)
            $server.Databases.Refresh()
            $expected = @($server.Databases.Name | Where-Object { $PSItem -in "master", $dbBacked })
            $results.Database | Should -Be $expected
        }
    }

    Context "Corrections" {
        It "matches -Database wildcards, as the help documents" {
            $results = @(Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database "${prefix}_*" -EnableException)
            @($results.Database | Sort-Object) | Should -Be $allNames
            @(Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbNew -EnableException).Database | Should -BeExactly $dbNew
        }

        It "reports a database created today and never backed up as new, as the help documents" {
            $result = @(Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbNew -EnableException)[0]
            $result.DaysSinceDbCreated | Should -Be 0
            $result.Status | Should -BeExactly "New database, not backed up yet"
        }

        It "reports a log backup older than a day as overdue, whatever its hours part" {
            $result = @(Get-DbaLastBackup -SqlInstance $TestConfig.InstanceSingle -Database $dbOldLog -EnableException)[0]
            $result.SinceFull.Days | Should -Be 0
            $result.SinceDiff.Days | Should -Be 0
            $result.SinceLog.TotalHours | Should -BeGreaterThan 24
            $result.Status | Should -BeExactly "No Log Back Up in the last hour"
        }
    }

    Context "Instances" {
        It "reads every piped instance" -Tag NativeChecklist:pipeline-multiple {
            $results = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Get-DbaLastBackup -Database $dbBacked -EnableException)
            $results.Database | Should -Be @($dbBacked, $dbBacked)
        }

        # refs/pins/dbatools-2026-10-22:public/Get-DbaLastBackup.ps1, the process block:
        #         try {
        #             $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        #         } catch {
        #             Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #         }
        It "warns for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $connectErrors = @()
            $results = @(Get-DbaLastBackup -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbBacked -WarningVariable connectWarnings -ErrorVariable connectErrors -WarningAction SilentlyContinue)
            ($connectWarnings -join " ") | Should -BeLike "*Failure | Error connecting to*"
            $connectErrors.Count | Should -Be 1
            $connectErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaLastBackup*"
            "$($connectErrors[0].CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($connectErrors[0].TargetObject)" | Should -BeExactly $badInstance
            $results.Database | Should -BeExactly $dbBacked
        }

        It "throws for an instance it cannot connect to under -EnableException" -Tag NativeChecklist:enable-exception {
            { Get-DbaLastBackup -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbBacked -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $results = @(Get-DbaLastBackup -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbBacked -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            ($falseWarnings -join " ") | Should -BeLike "*Failure | Error connecting to*"
            $results.Database | Should -BeExactly $dbBacked
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "${prefix}_login"
            $null = $loginServer.ConnectionContext.ExecuteNonQuery("CREATE DATABASE [$loginDbName];")
            $null = $loginServer.ConnectionContext.ExecuteNonQuery("BACKUP DATABASE [$loginDbName] TO DISK = N'NUL';")
        }

        AfterAll {
            if ($loginServer) {
                Remove-BackupDatabase -Target $loginServer -Name $loginDbName
            }
        }

        It "works with -SqlCredential" {
            $loginWarnings = @()
            $results = @(Get-DbaLastBackup -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $results.Database | Should -BeExactly $loginDbName
            $results.LastFullBackup | Should -Not -BeNullOrEmpty
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaLastBackup -SqlInstance $loginInstance -Database $loginDbName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "throws without the credential under -EnableException, as the pinned function does" {
            { Get-DbaLastBackup -SqlInstance $loginInstance -Database $loginDbName -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    # The nested Get-DbaDbBackupHistory reads run $server.ConnectionContext.ExecuteWithResults with no try
    # (refs/pins/dbatools-2026-10-22:public/Get-DbaDbBackupHistory.ps1), so a read the login may not make is a statement
    # fault: written outside any try, caught by a caller's try. A login denied SELECT on msdb.dbo.backupmediafamily makes each main read fail;
    # a backupset denial would also break SMO's own read of the databases (evidence/pin-lastbackup-denied-20261106.txt).
    Context "A backup history read that fails" {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $adminServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $deniedName = "${prefix}_denied"
            $deniedPassword = "N@tive" + [Guid]::NewGuid().ToString("N")
            $null = $adminServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$deniedName] WITH PASSWORD = N'$deniedPassword', CHECK_POLICY = OFF;")
            $null = $adminServer.ConnectionContext.ExecuteNonQuery("USE msdb; CREATE USER [$deniedName] FOR LOGIN [$deniedName]; DENY SELECT ON dbo.backupmediafamily TO [$deniedName]; USE master;")
            $deniedCred = New-Object System.Management.Automation.PSCredential -ArgumentList $deniedName, (ConvertTo-SecureString -String $deniedPassword -AsPlainText -Force)

            function Assert-HistoryReadRecord {
                param($Record)
                $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $Record.Exception | Should -BeOfType [System.Management.Automation.MethodInvocationException]
                $Record.Exception.Message | Should -BeLike 'Exception calling "ExecuteWithResults" with "1" argument(s): *'
                $Record.Exception.InnerException.GetBaseException().Message | Should -BeLike "*SELECT permission was denied*backupmediafamily*"
                $Record.FullyQualifiedErrorId | Should -BeLike "ExecutionFailureException*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            }
        }

        AfterAll {
            if ($adminServer) {
                # The command's pooled connections as that login stay open; a login with a session cannot be dropped.
                foreach ($session in @($adminServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$deniedName'"))) {
                    $null = $adminServer.ConnectionContext.ExecuteNonQuery("KILL $($session.session_id);")
                }
                $null = $adminServer.ConnectionContext.ExecuteNonQuery("USE msdb; IF USER_ID(N'$deniedName') IS NOT NULL DROP USER [$deniedName]; USE master;")
                $null = $adminServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$deniedName') IS NOT NULL DROP LOGIN [$deniedName];")
            }
        }

        It "outside any try, writes each failed read's record and still reports the database" {
            $outside = Invoke-LastBackupOutsideTry @{ SqlInstance = $loginInstance; SqlCredential = $deniedCred; Database = "master" }
            $outside.Stop | Should -BeNullOrEmpty
            # The fork check of each nested read reads only backupset and succeeds; each of the three main reads joins backupmediafamily and fails.
            $outside.Errors.Count | Should -Be 3
            foreach ($record in $outside.Errors) {
                Assert-HistoryReadRecord -Record $record
            }
            $outside.Rows.Count | Should -Be 1
            $outside.Rows[0].Database | Should -BeExactly "master"
            $outside.Rows[0].LastFullBackup | Should -BeNullOrEmpty
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the first record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-LastBackupOutsideTry @{ SqlInstance = $loginInstance; SqlCredential = $deniedCred; Database = "master"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-HistoryReadRecord -Record $outside.Errors[0]
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-LastBackupOutsideTry @{ SqlInstance = $loginInstance; SqlCredential = $deniedCred; Database = "master"; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
            Assert-HistoryReadRecord -Record $outside.Stop.ErrorRecord
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $failure = $null
            $after = $false
            $rows = New-Object System.Collections.ArrayList
            try {
                Get-DbaLastBackup -SqlInstance $loginInstance -SqlCredential $deniedCred -Database "master" | ForEach-Object { $null = $rows.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            Assert-HistoryReadRecord -Record $failure
            $after | Should -BeFalse
            $rows.Count | Should -Be 0
        }
    }

    # refs/pins/dbatools-2026-10-22:public/Get-DbaLastBackup.ps1, the process block, with no try around the read:
    #             if ($ExcludeReplica -and $server.IsHadrEnabled) {
    #                 ...
    #                 $notPreferredDbs = ($server.Query($notPreferredQuery)).DatabaseName
    # When that read fails on a later instance of the same call, the pin keeps the names an earlier instance read and
    # excludes them there (correction replica-read-failure). Only the 2022 availability group has HADR enabled; the
    # operator's decision of 2026-11-06 lets this Context claim it, and it is defined only on the legs that have
    # $TestConfig.InstanceHadr. A SQL login without VIEW SERVER STATE fails the not-preferred query with error 297 while
    # sys.databases and msdb stay readable; granted it, the same login reads the preferred-replica answers
    # (items/Get-DbaLastBackup/evidence/ag-replica-read-20261106.txt and ag-replica-grant-20261106.txt).
    if ($TestConfig.InstanceHadr) {
        Context "replica read failure on the availability group" {
            BeforeAll {
                $notPreferredSql = "SELECT DB_NAME(database_id) AS DatabaseName FROM sys.databases WHERE sys.fn_hadr_backup_is_preferred_replica(DB_NAME(database_id)) = 0"
                $hadrServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr -EnableException
                # The claimed pair is InstanceHadr and its synchronous-commit partner; the group's asynchronous replica is in
                # no test role and is never touched.
                $pairQuery = "SELECT ar.replica_server_name AS ReplicaName FROM sys.availability_replicas AS ar WHERE ar.availability_mode_desc = N'SYNCHRONOUS_COMMIT' AND ar.group_id IN (SELECT rs.group_id FROM sys.dm_hadr_availability_replica_states AS rs WHERE rs.is_local = 1) ORDER BY ar.replica_server_name;"
                $pairNames = @($hadrServer.Query($pairQuery).ReplicaName | Select-Object -Unique)
                if ($pairNames.Count -ne 2) {
                    throw "Expected the availability group pair of $($TestConfig.InstanceHadr), found: $($pairNames -join ', ')"
                }

                # The replica whose not-preferred query, read as the runner's own login, names an availability database is
                # granted VIEW SERVER STATE and goes first; the other gets nothing.
                $replicas = @(foreach ($pairName in $pairNames) {
                        $replicaServer = Connect-DbaInstance -SqlInstance $pairName -EnableException
                        $availabilityNames = @($replicaServer.Query("SELECT database_name AS DatabaseName FROM sys.availability_databases_cluster;").DatabaseName)
                        $notPreferredNames = @($replicaServer.Query($notPreferredSql).DatabaseName | Where-Object { $PSItem -in $availabilityNames })
                        [PSCustomObject]@{
                            Name              = $pairName
                            Server            = $replicaServer
                            NotPreferredNames = $notPreferredNames
                        }
                    })
                $grantedReplica = @($replicas | Where-Object { $PSItem.NotPreferredNames.Count -gt 0 })
                $otherReplica = @($replicas | Where-Object { $PSItem.NotPreferredNames.Count -eq 0 })
                if ($grantedReplica.Count -ne 1 -or $otherReplica.Count -ne 1) {
                    throw "Expected exactly one replica of $($pairNames -join ', ') whose not-preferred query names an availability database"
                }
                $grantedReplica = $grantedReplica[0]
                $otherReplica = $otherReplica[0]

                # Generated here and never written out; created on both replicas, granted on the first only.
                $replicaLogin = "${prefix}_replica"
                $replicaPassword = "N@tive" + [Guid]::NewGuid().ToString("N")
                $replicaCred = New-Object System.Management.Automation.PSCredential -ArgumentList $replicaLogin, (ConvertTo-SecureString -String $replicaPassword -AsPlainText -Force)
                foreach ($replica in $grantedReplica, $otherReplica) {
                    $null = $replica.Server.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$replicaLogin] WITH PASSWORD = N'$replicaPassword', CHECK_POLICY = OFF;")
                }
                $null = $grantedReplica.Server.ConnectionContext.ExecuteNonQuery("GRANT VIEW SERVER STATE TO [$replicaLogin];")

                # Independent reads as the temporary login, before every call: the first replica's not-preferred query names
                # at least one availability database and the later replica's fails with error 297. Either failing fails the It.
                function Get-ReplicaFixtureNames {
                    $grantedRead = Connect-DbaInstance -SqlInstance $grantedReplica.Name -SqlCredential $replicaCred -NonPooledConnection -EnableException
                    try {
                        $grantedNames = @($grantedRead.ConnectionContext.ExecuteWithResults($notPreferredSql).Tables[0].Rows | ForEach-Object { $PSItem.DatabaseName } | Where-Object { $PSItem -in $grantedReplica.NotPreferredNames })
                    } finally {
                        $grantedRead.ConnectionContext.Disconnect()
                    }
                    $grantedNames.Count | Should -BeGreaterThan 0 -Because "the first replica's not-preferred query, read as the temporary login, names an availability database"

                    $otherRead = Connect-DbaInstance -SqlInstance $otherReplica.Name -SqlCredential $replicaCred -NonPooledConnection -EnableException
                    $otherFailure = $null
                    try {
                        $null = $otherRead.ConnectionContext.ExecuteWithResults($notPreferredSql)
                    } catch {
                        $otherFailure = $PSItem.Exception.GetBaseException()
                    } finally {
                        $otherRead.ConnectionContext.Disconnect()
                    }
                    $otherFailure | Should -Not -BeNullOrEmpty -Because "the later replica's not-preferred query, read as the temporary login, fails"
                    $otherFailure.Number | Should -Be 297
                    , $grantedNames
                }

                function Assert-ReplicaReadRecord {
                    param($Record)
                    $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
                    $Record.Exception | Should -BeOfType [System.Management.Automation.MethodInvocationException]
                    $Record.Exception.Message | Should -BeLike 'Exception calling "Query" with "1" argument(s): *'
                    $Record.Exception.GetBaseException().Message | Should -BeLike "*does not have permission to perform this action*"
                    $Record.FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException*"
                    "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
                }
            }

            AfterAll {
                $leftOver = @()
                foreach ($replica in $grantedReplica, $otherReplica) {
                    if (-not $replica -or -not $replicaLogin) {
                        continue
                    }
                    # The command's pooled connections as that login stay open; a login with a session cannot be dropped.
                    foreach ($session in @($replica.Server.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$replicaLogin'"))) {
                        $null = $replica.Server.ConnectionContext.ExecuteNonQuery("KILL $($session.session_id);")
                    }
                    $null = $replica.Server.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$replicaLogin') IS NOT NULL REVOKE VIEW SERVER STATE FROM [$replicaLogin];")
                    $null = $replica.Server.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$replicaLogin') IS NOT NULL DROP LOGIN [$replicaLogin];")
                    $leftOver += @($replica.Server.Query("SELECT name FROM sys.server_principals WHERE name = N'$replicaLogin'"))
                }
                $leftOver.Count | Should -Be 0
            }

            It "keeps the later replica's databases when its replica read fails" {
                $fixtureNames = Get-ReplicaFixtureNames
                $outside = Invoke-LastBackupOutsideTry @{ SqlInstance = $grantedReplica.Name, $otherReplica.Name; SqlCredential = $replicaCred; Database = @($fixtureNames) + "master"; ExcludeReplica = $true }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                Assert-ReplicaReadRecord -Record $outside.Errors[0]
                # The first replica's own read excludes the names it gave; the later replica's failed read excludes nothing.
                @($outside.Rows | Where-Object SqlInstance -eq $grantedReplica.Server.DomainInstanceName).Database | Should -Be @("master")
                $laterNames = @($outside.Rows | Where-Object SqlInstance -eq $otherReplica.Server.DomainInstanceName).Database
                $laterNames | Should -Contain "master"
                foreach ($fixtureName in $fixtureNames) {
                    $laterNames | Should -Contain $fixtureName
                }
                $outside.Next | Should -BeTrue
            }

            It "stops under -EnableException when the later replica's replica read fails" {
                $fixtureNames = Get-ReplicaFixtureNames
                $outside = Invoke-LastBackupOutsideTry @{ SqlInstance = $grantedReplica.Name, $otherReplica.Name; SqlCredential = $replicaCred; Database = @($fixtureNames) + "master"; ExcludeReplica = $true; EnableException = $true }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                Assert-ReplicaReadRecord -Record $outside.Errors[0]
                @($outside.Rows | Where-Object SqlInstance -eq $grantedReplica.Server.DomainInstanceName).Database | Should -Be @("master")
                @($outside.Rows | Where-Object SqlInstance -eq $otherReplica.Server.DomainInstanceName).Count | Should -Be 0
                $outside.Next | Should -BeTrue
            }
        }
    }
}

Describe "Get-DbaLastBackup native on Azure SQL Database" -Tag IntegrationTests {
    # Azure SQL Database has no msdb backup history; sys.dm_database_backups lists a database's automated full (D),
    # differential (I) and log (L) backups
    # (https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-database-backups-azure-sql-database).
    It "reports the newest automated backups of an Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance         = $TestConfig.AzureSqlDbServer
            Database            = $TestConfig.AzureSqlDbName
            SqlCredential       = $TestConfig.AzureSqlDbCred
            ConnectTimeout      = 60
            NonPooledConnection = $true
            EnableException     = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        try {
            $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            # The service takes a log backup every few minutes, so one may finish between the reads: read before and after.
            $readNewest = {
                $newest = @{ }
                foreach ($row in @($azureServer.ConnectionContext.ExecuteWithResults("SELECT backup_type, MAX(backup_finish_date) AS finish FROM sys.dm_database_backups GROUP BY backup_type;").Tables[0].Rows)) {
                    $newest[[string]$row.backup_type] = [datetime]$row.finish
                }
                $newest
            }
            $before = & $readNewest
            $azureErrors = @()
            $splatAzureLastBackup = @{
                SqlInstance   = $azureServer
                Database      = $TestConfig.AzureSqlDbName
                ErrorVariable = "azureErrors"
                ErrorAction   = "SilentlyContinue"
            }
            $azureRows = @(Get-DbaLastBackup @splatAzureLastBackup)
            $after = & $readNewest
            $azureErrors.Count | Should -Be 0 -Because "the command reported [$($azureErrors -join ' ')]"
            $before.Keys.Count | Should -Be 3 -Because "the service keeps full, differential and log backups"
            $azureRows.Count | Should -Be 1
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
            [datetime]$azureRows[0].LastFullBackup | Should -BeIn @($before["D"], $after["D"])
            [datetime]$azureRows[0].LastDiffBackup | Should -BeIn @($before["I"], $after["I"])
            [datetime]$azureRows[0].LastLogBackup | Should -BeIn @($before["L"], $after["L"])
            $azureRows[0].LastFullBackupIsCopyOnly | Should -BeFalse
            $azureRows[0].LastLogBackupIsCopyOnly | Should -BeFalse
            # SMO has no RecoveryModel property on Azure SQL Database; the engine reports it in sys.databases.
            $recoveryModelDesc = $azureServer.ConnectionContext.ExecuteScalar("SELECT recovery_model_desc FROM sys.databases WHERE database_id = DB_ID();")
            $recoveryModelDesc | Should -Not -BeNullOrEmpty
            $azureRows[0].RecoveryModel | Should -BeOfType [Microsoft.SqlServer.Management.Smo.RecoveryModel]
            $azureRows[0].RecoveryModel.ToString() | Should -Be ($recoveryModelDesc -replace "_", "")
        } finally {
            $null = $azureServer | Disconnect-DbaInstance
        }
    }
}
