#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbExtentDiff",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares [CmdletBinding()] without SupportsShouldProcess and changes nothing; the WhatIf and Confirm entries in its help name parameters it does not have.

Describe "Get-DbaDbExtentDiff native" -Tag IntegrationTests {
    BeforeAll {
        function New-ExtentDatabase {
            param($Target, [string]$Name)
            $escaped = $Name.Replace("]", "]]")
            $null = $Target.ConnectionContext.ExecuteNonQuery("CREATE DATABASE [$escaped];")
        }

        # SINGLE_USER ends any connection still in the database before the drop.
        function Remove-ExtentDatabase {
            param($Target, [string[]]$Name)
            $existing = @($Target.Query("SELECT name FROM sys.databases")).name
            foreach ($dbName in $Name) {
                if ($dbName -in $existing) {
                    $escaped = $dbName.Replace("]", "]]")
                    $null = $Target.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$escaped] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$escaped];")
                }
            }
        }

        # Runs the older branch's two reads directly: every instance in the lab is new enough to take the view instead.
        function Read-ExtentBitmap {
            param($Target, [string]$Name)
            $commandType = (Get-Command -Name "Get-DbaDbExtentDiff" -CommandType Cmdlet).ImplementingType
            $bindingFlags = [System.Reflection.BindingFlags]"Static, NonPublic"
            $names = New-Object System.Collections.Generic.List[string]
            $names.Add($Name)
            $groups = $commandType.GetMethod("ReadMasterFiles", $bindingFlags).Invoke($null, @($Target.PSObject.BaseObject, $names.PSObject.BaseObject))
            $readPages = $commandType.GetMethod("ReadPages", $bindingFlags)
            foreach ($group in $groups) {
                $readPages.Invoke($null, @($Target.PSObject.BaseObject, [string]$group.Key, $group.Value.PSObject.BaseObject))
            }
        }

        # Unique per leg and run (lane-safe); AfterAll drops the databases.
        $prefix = "native_extent_" + [Guid]::NewGuid().ToString("N")
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $dbNameA = "${prefix}_a"
        $dbNameB = "${prefix}_b"
        $dbNameBracket = "${prefix}_c]d"
        $dbNameQuote = "${prefix}_e'f"
        $dbNameWide = "${prefix}_" + [char]0x4E2D + [char]0x6587
        $allNames = @($dbNameA, $dbNameB, $dbNameBracket, $dbNameQuote, $dbNameWide)
        foreach ($name in $allNames) {
            New-ExtentDatabase -Target $server -Name $name
        }

        # B's data file is larger than A's, so a read of the wrong database shows.
        $sizeOfB = @($server.Query("SELECT size FROM sys.master_files WHERE database_id = DB_ID(N'$dbNameB') AND file_id = 1"))[0].size
        $newSizeOfB = [int][math]::Ceiling($sizeOfB / 128) + 16
        $null = $server.Query("ALTER DATABASE [$dbNameB] MODIFY FILE (NAME = N'$dbNameB', SIZE = ${newSizeOfB}MB);")

        # Changed extents for the bitmap to show.
        $null = $server.Query("CREATE TABLE [$dbNameA].dbo.native_extent (filler CHAR(8000) NOT NULL);")
        $null = $server.Query("INSERT [$dbNameA].dbo.native_extent (filler) SELECT TOP (64) 'x' FROM sys.all_objects;")

        $badInstance = "TCP:127.0.0.1,1"
        $outputProperties = @("ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "ExtentsTotal", "ExtentsChanged", "ChangedPerc")
    }

    AfterAll {
        Remove-ExtentDatabase -Target $server -Name $allNames
    }

    Context "Results" {
        It "returns the pinned columns and the engine's numbers for the database" {
            $results = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA -EnableException)
            $results.Count | Should -Be 1
            $result = $results[0]
            @($result.PSObject.Properties.Name) | Should -Be $outputProperties
            $result.ComputerName | Should -BeExactly $server.ComputerName
            $result.InstanceName | Should -BeExactly $server.ServiceName
            $result.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $result.DatabaseName | Should -BeExactly $dbNameA
            $result.ExtentsTotal | Should -BeOfType [long]
            $result.ExtentsChanged | Should -BeOfType [long]
            $result.ChangedPerc | Should -BeOfType [decimal]
            $expectedPercent = [decimal]100 * $result.ExtentsChanged / $result.ExtentsTotal
            [math]::Abs($result.ChangedPerc - $expectedPercent) | Should -BeLessOrEqual ([decimal]0.01)

            $inDatabase = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA -NonPooledConnection -EnableException
            try {
                $engineTotal = @($inDatabase.Query("SELECT SUM(total_page_count) / 8 AS ExtentsTotal FROM sys.dm_db_file_space_usage"))[0].ExtentsTotal
            } finally {
                $null = $inDatabase | Disconnect-DbaInstance
            }
            $result.ExtentsTotal | Should -Be $engineTotal
        }

        It "reads each named database, not the one the connection is on" {
            $results = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameB -EnableException)
            $results.Count | Should -Be 2
            ($results | Where-Object DatabaseName -eq $dbNameB).ExtentsTotal | Should -BeGreaterThan ($results | Where-Object DatabaseName -eq $dbNameA).ExtentsTotal
        }

        It "reads a database with a closing bracket in its name" {
            $results = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $dbNameBracket -EnableException)
            $results.DatabaseName | Should -BeExactly $dbNameBracket
            $results.ExtentsTotal | Should -BeGreaterThan 0
        }

        It "takes the connection it opened back out of the connection hash" {
            $connections = [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections
            $existing = @($connections.Keys)
            $null = Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA -EnableException
            @($connections.Keys | Where-Object { $PSItem -notin $existing }) | Should -BeNullOrEmpty
        }
    }

    # refs/pins/dbatools-2026-10-22:public/Get-DbaDbExtentDiff.ps1:202-205 closes only the connection it opened:
    #         if ($isNewConnection) {
    #             $null = $server | Disconnect-DbaInstance
    #         }
    # Disconnect-DbaInstance's catch (public/Disconnect-DbaInstance.ps1:119-121, Stop-Function "Failed to disconnect $object"
    # -Continue) would put a record in the caller's -ErrorVariable. Its try runs ServerConnection.Disconnect(), which closes the
    # SqlConnection; Learn: an application can call Close more than one time and no exception is generated. The harshest real
    # failure the lab can give that close is a session the server already ended, so these tests kill the session first.
    Context "Closing a connection whose session the server already ended" {
        BeforeAll {
            # Lists and kills sessions on its own non-pooled connection, so its session id stays fixed. Only a session of this
            # process whose last batch read the file-space view and that was not open before is killed (lane-safe).
            $killer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            function Get-ExtentReaderSession {
                $sessionSql = "SELECT s.session_id FROM sys.dm_exec_sessions AS s INNER JOIN sys.dm_exec_connections AS c ON c.session_id = s.session_id CROSS APPLY sys.dm_exec_sql_text(c.most_recent_sql_handle) AS t WHERE s.host_process_id = $([int]$PID) AND s.session_id <> @@SPID AND t.text LIKE N'%dm_db_file_space_usage%';"
                $rows = $killer.ConnectionContext.ExecuteWithResults($sessionSql).Tables[0].Rows
                @($rows | ForEach-Object { [int]$PSItem.session_id })
            }
        }

        AfterAll {
            $null = $killer | Disconnect-DbaInstance
        }

        It "closes the connection it opened without a record after the server killed that session" {
            $before = Get-ExtentReaderSession
            $killed = New-Object System.Collections.Generic.List[int]
            $connections = [Dataplat.Dbatools.Connection.ConnectionHost]::ActiveConnections
            $existing = @($connections.Keys)
            $closeErrors = @()
            $closeWarnings = @()
            # The row reaches ForEach-Object before the command's finally runs the close, so the kill lands between them.
            $results = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA -ErrorVariable closeErrors -WarningVariable closeWarnings -WarningAction SilentlyContinue | ForEach-Object {
                    foreach ($sessionId in (Get-ExtentReaderSession)) {
                        if ($sessionId -notin $before) {
                            $null = $killer.ConnectionContext.ExecuteNonQuery("KILL $([int]$sessionId);")
                            $killed.Add($sessionId)
                        }
                    }
                    $PSItem
                })
            $killed.Count | Should -Be 1
            $results.DatabaseName | Should -BeExactly $dbNameA
            $closeErrors | Should -BeNullOrEmpty
            $closeWarnings | Should -BeNullOrEmpty
            @($connections.Keys | Where-Object { $PSItem -notin $existing }) | Should -BeNullOrEmpty
        }

        It "ServerConnection.Disconnect() raises nothing on a non-pooled connection whose session the server killed" {
            $ended = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            try {
                $endedSession = [int]$ended.ConnectionContext.ExecuteScalar("SELECT @@SPID;")
                $null = $killer.ConnectionContext.ExecuteNonQuery("KILL $endedSession;")
                { $ended.ConnectionContext.Disconnect() } | Should -Not -Throw
                $ended.ConnectionContext.SqlConnectionObject.State | Should -Be "Closed"
            } finally {
                $null = $ended | Disconnect-DbaInstance
            }
        }
    }

    Context "Filters" {
        It "matches -Database wildcards, as the help documents" {
            $results = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database "${prefix}_?" -EnableException)
            ($results.DatabaseName | Sort-Object) | Should -Be @($dbNameA, $dbNameB)
        }

        It "matches -ExcludeDatabase wildcards, as the help documents" {
            $results = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA, $dbNameB -ExcludeDatabase "*_b" -EnableException)
            $results.DatabaseName | Should -BeExactly $dbNameA
        }

        It "compares -Database ignoring case, as -In does" {
            $results = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $dbNameA.ToUpperInvariant() -EnableException)
            $results.DatabaseName | Should -BeExactly $dbNameA
        }

        It "reads every database for a -Database value that is false, as the pinned if does" {
            $results = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database "" -EnableException)
            $results.DatabaseName | Should -Contain $dbNameA
            $results.DatabaseName | Should -Contain "master"
        }

        It "skips a database that is not accessible, at Verbose" {
            $offlineName = "${prefix}_offline"
            New-ExtentDatabase -Target $server -Name $offlineName
            try {
                $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
                $server.Databases.Refresh()
                $streams = @(Get-DbaDbExtentDiff -SqlInstance $TestConfig.InstanceSingle -Database $offlineName, $dbNameA -EnableException -Verbose 4>&1)
                $rows = @($streams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })
                $rows.DatabaseName | Should -BeExactly $dbNameA
                $verboseText = @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message }) -join " "
                $verboseText | Should -Match ([regex]::Escape("[$offlineName] is not accessible on"))
            } finally {
                $null = $server.ConnectionContext.ExecuteNonQuery("ALTER DATABASE [$offlineName] SET ONLINE;")
                Remove-ExtentDatabase -Target $server -Name $offlineName
            }
        }
    }

    # refs/pins/dbatools-2026-10-22:public/Get-DbaDbExtentDiff.ps1, the process block, has no try around
    #                     $DBCCPageResults = $server.Query($DBCCPageQueryDMV)
    # so a failed read is a statement fault: a plain call writes the record and goes on, and a caller's try catches it and
    # the command goes no further (the StatementFault section, harness-edits.md, 2026-11-02, point 4).
    Context "A database that cannot be read" {
        BeforeAll {
            # Enumerating fills the caller's collection, so it still holds the dropped database, accessible as it was when it
            # was read, and the read of its file space is what fails. Its name sorts between A and B, so a database is read
            # before the failure and one after it.
            $goneName = "${prefix}_a_gone"
            New-ExtentDatabase -Target $server -Name $goneName
            $caller = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection -EnableException
            $held = @($caller.Databases | Where-Object { $PSItem.Name -in $dbNameA, $goneName, $dbNameB -and $PSItem.IsAccessible })
            Remove-ExtentDatabase -Target $server -Name $goneName
            $readNames = @($dbNameA, $goneName, $dbNameB)
            $queryMessage = 'Exception calling "Query" with "1" argument(s): *'

            function Assert-ExtentReadRecord {
                param($Record)
                $Record | Should -BeOfType [System.Management.Automation.ErrorRecord]
                $Record.Exception | Should -BeOfType [System.Management.Automation.MethodInvocationException]
                $Record.Exception.Message | Should -BeLike $queryMessage
                $Record.Exception.Message | Should -BeLike "*$goneName*"
                $Record.FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
                $Record.TargetObject | Should -BeNullOrEmpty
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-ExtentOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command -Name "Get-DbaDbExtentDiff" -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbExtentDiff", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaDbExtentDiff @Arguments; "next statement"').AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [PSCustomObject]@{
                        Rows   = @($outsideOutput | Where-Object { $PSItem.PSObject.Properties.Name -contains "DatabaseName" })
                        Next   = @($outsideOutput | Where-Object { "$($PSItem.PSObject.BaseObject)" -ceq "next statement" }).Count -gt 0
                        Errors = @($outsideShell.Streams.Error)
                        Stop   = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }
        }

        AfterAll {
            if ($caller) {
                $null = $caller | Disconnect-DbaInstance
            }
            Remove-ExtentDatabase -Target $server -Name $goneName
        }

        It "holds the three databases in name order, the dropped one between the two others" {
            $held.Name | Should -Be $readNames
        }

        It "gives no row for a database it failed to read" {
            $outside = Invoke-ExtentOutsideTry @{ SqlInstance = $caller; Database = $readNames }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-ExtentReadRecord -Record $outside.Errors[0]
            $outside.Rows.DatabaseName | Should -Be @($dbNameA, $dbNameB)
            $outside.Next | Should -BeTrue

            $only = Invoke-ExtentOutsideTry @{ SqlInstance = $caller; Database = $goneName }
            $only.Rows.Count | Should -Be 0
            $only.Errors.Count | Should -Be 1
            Assert-ExtentReadRecord -Record $only.Errors[0]
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-ExtentOutsideTry @{ SqlInstance = $caller; Database = $readNames; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-ExtentReadRecord -Record $outside.Errors[0]
            $outside.Rows.DatabaseName | Should -BeExactly $dbNameA
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-ExtentOutsideTry @{ SqlInstance = $caller; Database = $readNames; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType [System.Management.Automation.ActionPreferenceStopException]
            Assert-ExtentReadRecord -Record $outside.Stop.ErrorRecord
            $outside.Rows.DatabaseName | Should -BeExactly $dbNameA
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $failure = $null
            $after = $false
            $rows = New-Object System.Collections.ArrayList
            try {
                Get-DbaDbExtentDiff -SqlInstance $caller -Database $readNames | ForEach-Object { $null = $rows.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            Assert-ExtentReadRecord -Record $failure
            $after | Should -BeFalse
            @($rows).DatabaseName | Should -BeExactly $dbNameA
        }
    }

    Context "The older DBCC PAGE branch" {
        It "reads the file sizes and the changed extents from the bitmaps" {
            $pages = @($server.Query("SELECT SUM(size) AS pages FROM sys.master_files WHERE database_id = DB_ID(N'$dbNameA') AND type_desc = N'ROWS'"))[0].pages
            $results = @(Read-ExtentBitmap -Target $server -Name $dbNameA)
            $results.Count | Should -Be 1
            @($results[0].PSObject.Properties.Name) | Should -Be $outputProperties
            $results[0].DatabaseName | Should -BeExactly $dbNameA
            $results[0].ExtentsTotal | Should -Be ($pages / 8)
            $results[0].ExtentsChanged | Should -BeGreaterThan 0
            $results[0].ChangedPerc | Should -Be ([math]::Round($results[0].ExtentsChanged / $results[0].ExtentsTotal * 100, 2))
        }

        It "reads a database with a quote in its name through DBCC PAGE" {
            $results = @(Read-ExtentBitmap -Target $server -Name $dbNameQuote)
            $results.DatabaseName | Should -BeExactly $dbNameQuote
            $results.ExtentsTotal | Should -BeGreaterThan 0
        }

        It "reads a database named outside the code page through DBCC PAGE" {
            $results = @(Read-ExtentBitmap -Target $server -Name $dbNameWide)
            $results.DatabaseName | Should -BeExactly $dbNameWide
            $results.ExtentsTotal | Should -BeGreaterThan 0
        }
    }

    Context "Instances" {
        It "reads every piped instance" -Tag NativeChecklist:pipeline-multiple {
            $results = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle | Get-DbaDbExtentDiff -Database $dbNameA -EnableException)
            $results.DatabaseName | Should -Be @($dbNameA, $dbNameA)
        }

        # refs/pins/dbatools-2026-10-22:public/Get-DbaDbExtentDiff.ps1, the process block:
        #         try {
        #             $server = Connect-DbaInstance @splatConnect
        #         } catch {
        #             Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #         }
        #
        # Connect-DbaInstance throws by default, so this catch runs, and -EnableException reaches this Stop-Function.
        It "warns for an instance it cannot connect to and still reads the next one" -Tag NativeChecklist:multi-instance-failure {
            $connectWarnings = @()
            $results = @(Get-DbaDbExtentDiff -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameA -WarningVariable connectWarnings -WarningAction SilentlyContinue)
            ($connectWarnings -join " ") | Should -BeLike "*Error occurred while establishing connection to*"
            $results.DatabaseName | Should -BeExactly $dbNameA
        }

        It "throws for an instance it cannot connect to under -EnableException" -Tag NativeChecklist:enable-exception {
            { Get-DbaDbExtentDiff -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameA -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $falseWarnings = @()
            $results = @(Get-DbaDbExtentDiff -SqlInstance $badInstance, $TestConfig.InstanceSingle -Database $dbNameA -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            ($falseWarnings -join " ") | Should -BeLike "*Error occurred while establishing connection to*"
            $results.DatabaseName | Should -BeExactly $dbNameA
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "${prefix}_login"
            New-ExtentDatabase -Target $loginServer -Name $loginDbName
        }

        AfterAll {
            if ($loginServer) {
                Remove-ExtentDatabase -Target $loginServer -Name $loginDbName
            }
        }

        It "works with -SqlCredential" {
            $loginWarnings = @()
            $results = @(Get-DbaDbExtentDiff -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDbName -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $results.DatabaseName | Should -BeExactly $loginDbName
            $results.ExtentsTotal | Should -BeGreaterThan 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaDbExtentDiff -SqlInstance $loginInstance -Database $loginDbName -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Error occurred while establishing connection to*"
        }

        It "throws without the credential under -EnableException, as the pinned function does" {
            { Get-DbaDbExtentDiff -SqlInstance $loginInstance -Database $loginDbName -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }
}

Describe "Get-DbaDbExtentDiff native on Azure SQL Database" -Tag IntegrationTests {
    # sys.dm_db_file_space_usage applies to Azure SQL Database
    # (https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-db-file-space-usage-transact-sql).
    It "reads the extents of an Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
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
            $engineRows = @($azureServer.ConnectionContext.ExecuteWithResults("SELECT SUM(total_page_count) / 8 AS ExtentsTotal, SUM(modified_extent_page_count) / 8 AS ExtentsChanged, 100.0 * SUM(modified_extent_page_count)/SUM(total_page_count) AS ChangedPerc FROM sys.dm_db_file_space_usage;").Tables[0].Rows)
            $azureErrors = @()
            $splatAzureExtents = @{
                SqlInstance     = $azureServer
                Database        = $TestConfig.AzureSqlDbName
                EnableException = $true
                ErrorVariable   = "azureErrors"
                ErrorAction     = "SilentlyContinue"
            }
            $azureRows = @(Get-DbaDbExtentDiff @splatAzureExtents)
            $azureRows.Count | Should -Be 1 -Because "the engine reports version $($azureServer.Version), total $($engineRows[0].ExtentsTotal), changed $($engineRows[0].ExtentsChanged), percent $($engineRows[0].ChangedPerc), and the command reported [$($azureErrors -join ' ')]"
            $azureRows[0].DatabaseName | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
            $azureRows[0].ExtentsTotal | Should -Be $engineRows[0].ExtentsTotal
            # Six legs share the database, so its changed extents can move between the two reads; the row must agree with itself.
            $azureRows[0].ExtentsChanged | Should -BeOfType [long]
            $azureRows[0].ChangedPerc | Should -BeOfType [decimal]
            $expectedAzurePercent = [decimal]100 * $azureRows[0].ExtentsChanged / $azureRows[0].ExtentsTotal
            [math]::Abs($azureRows[0].ChangedPerc - $expectedAzurePercent) | Should -BeLessOrEqual ([decimal]0.01)
            $azureServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()") | Should -Be $TestConfig.AzureSqlDbName
        } finally {
            $azureServer.ConnectionContext.Disconnect()
        }
    }
}
