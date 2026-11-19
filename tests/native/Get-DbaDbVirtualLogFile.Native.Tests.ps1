#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbVirtualLogFile",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads virtual log file metadata.

Describe "Native Get-DbaDbVirtualLogFile" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Unique per leg and run. The fixture's connection is never given to the command.
        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
        $mainDb = "dbatoolsci_nvl_$random"
        $secondDb = "dbatoolsci_nvl2_$random"
        $offlineDb = "dbatoolsci_nvloff_$random"
        $staleDb = "dbatoolsci_nvlstale_$random"
        $allDatabases = @($mainDb, $secondDb, $offlineDb, $staleDb)
        foreach ($name in $allDatabases) {
            $null = $server.Query("CREATE DATABASE [$name];")
        }
        $null = $server.Query("ALTER DATABASE [$offlineDb] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        $server.Databases.Refresh()

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($name in $allDatabases) {
            $null = $server.Query("USE [master]; IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET ONLINE; ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $server.ConnectionContext.Disconnect()
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output" {
        It "returns one plain object per virtual log file, with the pinned properties in their order and the values DBCC LOGINFO holds" {
            $engine = @($server.Databases[$mainDb].ExecuteWithResults("DBCC LOGINFO").Tables[0].Rows)
            $null = $server.Query("USE [master];")
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $mainDb)

            $engine.Count | Should -BeGreaterThan 0
            $result.Count | Should -Be $engine.Count
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Database", "RecoveryUnitId", "FileId", "FileSize", "StartOffset", "FSeqNo", "Status", "Parity", "CreateLsn")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            for ($index = 0; $index -lt $engine.Count; $index++) {
                $result[$index].Database | Should -BeExactly $mainDb
                $result[$index].FileId | Should -Be $engine[$index].FileId
                $result[$index].FileSize | Should -Be $engine[$index].FileSize
                $result[$index].FileSize.GetType().FullName | Should -BeExactly $engine[$index].FileSize.GetType().FullName
                $result[$index].StartOffset | Should -Be $engine[$index].StartOffset
                $result[$index].CreateLsn | Should -Be $engine[$index].CreateLSN
            }
        }

        It "leaves the caller's connection in its database" {
            $caller = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
            try {
                $null = $caller.ConnectionContext.ExecuteNonQuery("USE [tempdb];")
                @(Get-DbaDbVirtualLogFile -SqlInstance $caller -Database $mainDb).Count | Should -BeGreaterThan 0
                $caller.ConnectionContext.ExecuteScalar("SELECT DB_NAME();") | Should -BeExactly "tempdb"
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }
    }

    Context "Selection" {
        It "matches -Database without regard to case and reads each database once" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $secondDb.ToUpperInvariant(), $mainDb, $mainDb)
            @($result.Database | Select-Object -Unique | Sort-Object) | Should -BeExactly @($secondDb, $mainDb | Sort-Object)
            $single = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $mainDb)
            @($result | Where-Object Database -eq $mainDb).Count | Should -Be $single.Count
        }

        It "reads nothing and says nothing for a name that does not exist" {
            $result = Get-DbaDbVirtualLogFile -SqlInstance $instance -Database "dbatoolsci_nvlabsent_$random" -WarningVariable warnings
            $result | Should -BeNullOrEmpty
            $warnings | Should -BeNullOrEmpty
        }

        It "treats a null, an empty or one blank -Database as no filter, and two blank names as a filter" {
            foreach ($form in @{ Database = $null }, @{ Database = @() }, @{ Database = "" }) {
                $scan = @(Get-DbaDbVirtualLogFile -SqlInstance $instance @form -WarningAction SilentlyContinue)
                $scan.Database | Should -Contain $mainDb
            }
            @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database "", "").Count | Should -Be 0
        }

        It "expands a wildcard in -Database" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database "dbatoolsci_nvl?_$random", "DBATOOLSCI_NVL_*$random")
            @($result.Database | Select-Object -Unique | Sort-Object) | Should -BeExactly @($secondDb, $mainDb | Sort-Object)
        }

        It "expands a wildcard in -ExcludeDatabase" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $mainDb, $secondDb -ExcludeDatabase "dbatoolsci_nvl2_?*")
            @($result.Database | Select-Object -Unique) | Should -BeExactly $mainDb
        }

        It "leaves out a database named in -ExcludeDatabase, without regard to case" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $mainDb, $secondDb -ExcludeDatabase $secondDb.ToUpperInvariant())
            @($result.Database | Select-Object -Unique) | Should -BeExactly $mainDb
        }

        It "leaves out system databases even when named, and reads them under -IncludeSystemDBs" -Tag "NativeChecklist:switch-false" {
            $default = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database master, $mainDb)
            @($default.Database | Select-Object -Unique) | Should -BeExactly $mainDb
            $off = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database master, $mainDb -IncludeSystemDBs:$false)
            @($off.Database | Select-Object -Unique) | Should -BeExactly $mainDb
            $included = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database master, $mainDb -IncludeSystemDBs)
            $included.Database | Should -Contain "master"
            $included.Database | Should -Contain $mainDb
        }
    }

    Context "A database that cannot be opened" {
        BeforeAll {
            $skipText = "Skipping [$offlineDb] on $instance because it is not accessible, so its virtual log files cannot be read"
        }

        It "warns of it by name and reads the others" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $offlineDb, $mainDb -WarningVariable warnings -WarningAction SilentlyContinue)
            @($result.Database | Select-Object -Unique) | Should -BeExactly $mainDb
            @($warnings).Count | Should -Be 1
            "$warnings".Contains($skipText) | Should -BeTrue
        }

        It "stays a warning under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $result = Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $offlineDb -EnableException -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            "$warnings".Contains($skipText) | Should -BeTrue
        }

        It "says nothing of it once it is excluded" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $offlineDb, $mainDb -ExcludeDatabase $offlineDb -WarningVariable warnings)
            @($result.Database | Select-Object -Unique) | Should -BeExactly $mainDb
            $warnings | Should -BeNullOrEmpty
        }
    }

    Context "A database that stops answering after it was read as accessible" {
        BeforeAll {
            # The connection keeps what it read of the database, so it still says accessible when another session has taken the database offline.
            $stale = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
            foreach ($candidate in $stale.Databases) {
                $null = $candidate.IsAccessible
                $null = $candidate.IsSystemObject
            }
            $null = $server.Query("ALTER DATABASE [$staleDb] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
            $offlineMessage = "Database '$staleDb' cannot be opened because it is offline."
        }

        AfterAll {
            $stale.ConnectionContext.Disconnect()
        }

        It "warns with the server's message and reads the next" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $stale -Database $staleDb, $mainDb -WarningVariable warnings -WarningAction SilentlyContinue)
            @($result.Database | Select-Object -Unique) | Should -BeExactly $mainDb
            @($warnings).Count | Should -Be 1
            "$warnings" | Should -BeLike "*Unable to query $staleDb on *. | $offlineMessage"
        }

        It "throws the server's error under -EnableException, with the database as its target" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            try {
                $null = Get-DbaDbVirtualLogFile -SqlInstance $stale -Database $staleDb -EnableException -WarningAction SilentlyContinue
            } catch {
                $record = $PSItem
            }
            $record | Should -Not -BeNullOrEmpty
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbVirtualLogFile*"
            $record.TargetObject.Name | Should -BeExactly $staleDb
            $record.Exception.Message | Should -BeExactly $offlineMessage
            $record.Exception.InnerException | Should -BeOfType Microsoft.Data.SqlClient.SqlException
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $single = @(Get-DbaDbVirtualLogFile -SqlInstance $instance -Database $mainDb)
            @($instance, $instance | Get-DbaDbVirtualLogFile -Database $mainDb).Count | Should -Be ($single.Count * 2)
        }

        It "warns of a failed instance and goes on, and throws it under -EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance "127.0.0.1,1", $instance -Database $mainDb -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            @($result.Database | Select-Object -Unique) | Should -BeExactly $mainDb
            "$warnings" | Should -BeLike "*Failure | *refused*"

            { Get-DbaDbVirtualLogFile -SqlInstance "127.0.0.1,1", $instance -Database $mainDb -EnableException } | Should -Throw -ExpectedMessage "*refused*" -ErrorId "dbatools_Get-DbaDbVirtualLogFile*"
        }
    }
}

Describe "Native Get-DbaDbVirtualLogFile on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $azureDatabase
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known"). A resume can also end the wait itself:
                # "The wait operation timed out" (Win32Exception 258 under the SqlException) or a TimeoutException.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001) { $isResuming = $true }
                    if ($azureError -is [System.ComponentModel.Win32Exception] -and $azureError.NativeErrorCode -eq 258) { $isResuming = $true }
                    if ($azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    # Read-only. What the server answers to DBCC LOGINFO, read beside the command, decides what the command must do with it, as the pinned function does.
    It "returns what Azure SQL Database answers to DBCC LOGINFO, or warns with its refusal" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"

        $azureRows = $null
        $azureRefusal = $null
        try {
            $azureRows = @($azureServer.Databases[$azureDatabase].ExecuteWithResults("DBCC LOGINFO").Tables[0].Rows)
        } catch {
            $inner = $PSItem.Exception
            while ($inner.InnerException) {
                $inner = $inner.InnerException
            }
            $azureRefusal = $inner.Message
        }

        $result = @(Get-DbaDbVirtualLogFile -SqlInstance $azureServer -Database $azureDatabase -WarningVariable warnings -WarningAction SilentlyContinue)
        if ($null -eq $azureRefusal) {
            $warnings | Should -BeNullOrEmpty
            $result.Count | Should -Be $azureRows.Count
            @($result.Database | Select-Object -Unique) | Should -BeExactly $azureDatabase
        } else {
            $result.Count | Should -Be 0
            @($warnings).Count | Should -Be 1
            "$warnings".Contains("Unable to query $azureDatabase on ") | Should -BeTrue
            "$warnings".Contains($azureRefusal) | Should -BeTrue
        }
    }
}

Describe "Native Get-DbaDbVirtualLogFile over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Unique names and cleanup: every leg uses this one shared instance.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $random = Get-Random
        $loginDb = "dbatoolsci_nvllogin_$random"
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection
        $null = $loginServer.Query("CREATE DATABASE [$loginDb];")
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = $loginServer.Query("USE [master]; IF DB_ID(N'$loginDb') IS NOT NULL BEGIN ALTER DATABASE [$loginDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$loginDb]; END;")
        $loginServer.ConnectionContext.Disconnect()
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbVirtualLogFile -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDb -EnableException)
            $result.Count | Should -BeGreaterThan 0
            @($result.Database | Select-Object -Unique) | Should -BeExactly $loginDb
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbVirtualLogFile -SqlInstance $loginInstance -Database $loginDb -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*Login failed*"
        }

        # The connection is the command's own, so the failure throws.
        It "throws the connection failure under -EnableException" {
            { Get-DbaDbVirtualLogFile -SqlInstance $loginInstance -Database $loginDb -EnableException } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbVirtualLogFile*"
        }
    }
}

# A low login's connection in a home database it may no longer connect to. Having read its database list first, the read works and the pinned Database.Query script method
# warns when it cannot go back; whether this login may run DBCC LOGINFO does not matter there, because the read moves the connection either way. Without the list, loading
# it fails first: evidence/pin-vlf-enum-20261103.txt.
Describe "Native Get-DbaDbVirtualLogFile on a connection that cannot go back to its database" -Tag IntegrationTests {
    BeforeAll {
        $restoreInstance = $TestConfig.InstanceSqlLogin
        $restoreCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared.
        $restoreStamp = Get-Random
        $homeName = "dbatoolsci_nvl_home_$restoreStamp"
        $readName = "dbatoolsci_nvl_read_$restoreStamp"
        $nextName = "dbatoolsci_nvl_next_$restoreStamp"
        $lowName = "dbatoolsci_nvl_low_$restoreStamp"
        $lowPassword = "Nvl-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $restoreWarning = "The database context could not be restored to [$homeName]: Exception calling ""ExecuteNonQuery"" with ""1"" argument(s): ""An exception occurred while executing a Transact-SQL statement or batch."""
        $restoreServer = Connect-DbaInstance -SqlInstance $restoreInstance -SqlCredential $restoreCred -EnableException
        foreach ($name in @($homeName, $readName, $nextName)) {
            $null = $restoreServer.Query("CREATE DATABASE [$name];")
        }
        $null = $restoreServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
        $restoreServer.Databases.Refresh()
        $null = $restoreServer.Databases[$homeName].ExecuteNonQuery("CREATE USER [$lowName] FOR LOGIN [$lowName];")
        foreach ($name in @($readName, $nextName)) {
            $null = $restoreServer.Databases[$name].ExecuteNonQuery("CREATE USER [$lowName] FOR LOGIN [$lowName]; ALTER ROLE db_owner ADD MEMBER [$lowName];")
        }

        # A fresh connection of the low login in the home database, then CONNECT denied there. With -ReadList it has read its database list and the two flags first.
        function New-BrokenCaller {
            param([switch]$ReadList)
            $null = $restoreServer.Databases[$homeName].ExecuteNonQuery("GRANT CONNECT TO [$lowName];")
            $caller = Connect-DbaInstance -SqlInstance $restoreInstance -SqlCredential $lowCred -Database $homeName -NonPooledConnection -EnableException
            $null = $caller.ConnectionContext.ExecuteScalar("SELECT 1;")
            if ($ReadList) {
                foreach ($candidate in $caller.Databases) {
                    if ($candidate.Name -in $readName, $nextName) {
                        $null = $candidate.IsAccessible
                        $null = $candidate.IsSystemObject
                    }
                }
            }
            $null = $restoreServer.Databases[$homeName].ExecuteNonQuery("DENY CONNECT TO [$lowName];")
            $caller
        }

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbVirtualLogFile -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbVirtualLogFile", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript('param($Arguments) Get-DbaDbVirtualLogFile @Arguments; "next statement"').AddArgument($Arguments)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output = @($outsideOutput)
                    Rows   = @($outsideOutput | Where-Object { $PSItem.psobject.BaseObject -isnot [string] })
                    Errors = @($outsideShell.Streams.Error)
                    Stop   = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        # As the pin measured on both editions: evidence/pin-vlf-enum-20261103.txt. The engine names the compiled command in the id.
        function Assert-ListFault {
            param($Record)
            $Record.Exception | Should -BeOfType System.Management.Automation.ExtendedTypeSystemException
            $Record.Exception.Message | Should -BeExactly "The following exception occurred while trying to enumerate the collection: ""An exception occurred while executing a Transact-SQL statement or batch.""."
            $Record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.TargetObject | Should -BeNullOrEmpty
        }

        # In red 20261103T0219026629709Z one call of 72 on this shared instance showed no sign of the DENY: no fault at all, on one leg. The likely reading, not measured, is
        # that the DENY reaches the session a moment late. So these three helpers take a fresh connection and try again, at most six times, until the call shows the session
        # has felt it, and the tests assert that call. A port that never reports the fault still fails them, on the last try.
        function Invoke-DeniedOutsideTry {
            param([hashtable]$Arguments, $NextInstance)
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                $broken = New-BrokenCaller
                try {
                    $call = $Arguments.Clone()
                    if ($null -ne $NextInstance) {
                        $call.SqlInstance = @($broken, $NextInstance)
                    } else {
                        $call.SqlInstance = $broken
                    }
                    $outside = Invoke-NativeOutsideTry -Arguments $call
                } finally {
                    $broken.ConnectionContext.Disconnect()
                }
                if ($outside.Errors.Count -gt 0 -or $null -ne $outside.Stop) {
                    break
                }
                Start-Sleep -Seconds 2
            }
            $outside
        }

        function Invoke-DeniedInsideTry {
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                $broken = New-BrokenCaller
                $streamed = New-Object System.Collections.ArrayList
                $failure = $null
                $after = $false
                try {
                    Get-DbaDbVirtualLogFile -SqlInstance $broken, $restoreServer -Database $readName | ForEach-Object { $null = $streamed.Add($PSItem) }
                    $after = $true
                } catch {
                    $failure = $PSItem
                } finally {
                    $broken.ConnectionContext.Disconnect()
                }
                if ($null -ne $failure) {
                    break
                }
                Start-Sleep -Seconds 2
            }
            [pscustomobject]@{ Failure = $failure; After = $after; Streamed = @($streamed) }
        }

        function Invoke-DeniedRestore {
            param([switch]$EnableException)
            for ($attempt = 1; $attempt -le 6; $attempt++) {
                $broken = New-BrokenCaller -ReadList
                $all = New-Object System.Collections.ArrayList
                $record = $null
                try {
                    Get-DbaDbVirtualLogFile -SqlInstance $broken -Database $readName, $nextName -EnableException:$EnableException 3>&1 | ForEach-Object { $null = $all.Add($PSItem) }
                } catch {
                    $record = $PSItem
                }
                $context = $broken.ConnectionContext.CurrentDatabase
                $broken.ConnectionContext.Disconnect()
                if (@($all | Where-Object { $PSItem.Message -ceq $restoreWarning }).Count -gt 0) {
                    break
                }
                Start-Sleep -Seconds 2
            }
            [pscustomobject]@{ All = @($all); Record = $record; Context = $context }
        }
    }

    AfterAll {
        foreach ($row in @($restoreServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';"))) {
            $null = $restoreServer.Query("KILL $($row.session_id);")
        }
        foreach ($name in @($homeName, $readName, $nextName)) {
            $null = $restoreServer.Query("IF DB_ID(N'$name') IS NOT NULL ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
            $null = $restoreServer.Query("IF DB_ID(N'$name') IS NOT NULL DROP DATABASE [$name];")
        }
        $null = $restoreServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
    }

    # As the pin measured on both editions: evidence/pin-vlf-enum-20261103.txt, read-named. The list comes sorted, so $nextName is read first. This login may not run DBCC LOGINFO.
    It "goes on and writes the warning to the stream, once, with the connection where the reads left it" {
        $restored = Invoke-DeniedRestore
        $restored.Record | Should -BeNullOrEmpty
        $restored.All.Count | Should -Be 3
        $restored.All[0].Message | Should -BeExactly $restoreWarning
        $restored.All[1].Message | Should -BeLike "*Unable to query $nextName on *. | User '$lowName' does not have permission to run DBCC LOGINFO."
        $restored.All[2].Message | Should -BeLike "*Unable to query $readName on *. | User '$lowName' does not have permission to run DBCC LOGINFO."
        $restored.Context | Should -BeExactly $nextName
    }

    # read-named-ee.
    It "warns of the restore and then throws the query's error under -EnableException" -Tag "NativeChecklist:enable-exception" {
        $restored = Invoke-DeniedRestore -EnableException
        $restored.Record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbVirtualLogFile*"
        $restored.Record.TargetObject.Name | Should -BeExactly $nextName
        $restored.Record.Exception.Message | Should -BeExactly "User '$lowName' does not have permission to run DBCC LOGINFO."
        $restored.Record.Exception.InnerException | Should -BeOfType Microsoft.Data.SqlClient.SqlException
        $restored.All[0].Message | Should -BeExactly $restoreWarning
        $restored.Context | Should -BeExactly $nextName
    }

    Context "A connection that cannot load its database list" {
        It "outside any try, a plain call writes one record per statement that walks the list and goes on to the next instance" {
            foreach ($form in @(
                    @{ Records = 4; Arguments = @{ } }
                    @{ Records = 5; Arguments = @{ Database = $readName } }
                    @{ Records = 5; Arguments = @{ ExcludeDatabase = $nextName } }
                    @{ Records = 6; Arguments = @{ Database = $readName; ExcludeDatabase = $nextName } }
                    @{ Records = 3; Arguments = @{ IncludeSystemDBs = $true } }
                    @{ Records = 4; Arguments = @{ Database = $readName; IncludeSystemDBs = $true } }
                )) {
                $outside = Invoke-DeniedOutsideTry -Arguments $form.Arguments
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be $form.Records
                foreach ($record in $outside.Errors) {
                    Assert-ListFault -Record $record
                }
                $outside.Rows.Count | Should -Be 0
                ($outside.Output -join ",") | Should -BeExactly "next statement"
            }

            $outside = Invoke-DeniedOutsideTry -Arguments @{ Database = $readName } -NextInstance $restoreServer
            $outside.Errors.Count | Should -Be 5
            @($outside.Rows | ForEach-Object { $PSItem.Database } | Select-Object -Unique) | Should -BeExactly $readName
        }

        It "outside any try, -EnableException ends the command at the fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-DeniedOutsideTry -Arguments @{ Database = $readName; EnableException = $true } -NextInstance $restoreServer
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-ListFault -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outside = Invoke-DeniedOutsideTry -Arguments @{ Database = $readName; ErrorAction = "Stop" } -NextInstance $restoreServer
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-ListFault -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $inside = Invoke-DeniedInsideTry
            $inside.Failure | Should -Not -BeNullOrEmpty
            Assert-ListFault -Record $inside.Failure
            $inside.After | Should -BeFalse
            $inside.Streamed.Count | Should -Be 0
        }
    }
}
