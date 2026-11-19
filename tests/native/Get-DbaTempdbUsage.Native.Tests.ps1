#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- read-only DMV query; no ShouldProcess in the pin.

BeforeAll {
    function Invoke-TempdbUsageOutsideTry([hashtable]$arguments) {
        $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $type = (Get-Command Get-DbaTempdbUsage -CommandType Cmdlet).ImplementingType
        $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Get-DbaTempdbUsage', $type, $null
        $state.Commands.Add($entry)
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
        $shell = [powershell]::Create()
        $output = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        try {
            $runspace.Open()
            $shell.Runspace = $runspace
            $runspace.SessionStateProxy.SetVariable('NativeTempdbNext', $false)
            $body = { param($readArguments) Get-DbaTempdbUsage @readArguments; $global:NativeTempdbNext = $true }
            $null = $shell.AddScript($body.ToString()).AddArgument($arguments)
            $stop = $null
            try { $null = $shell.Invoke($null, $output) } catch { $stop = $PSItem }
            [pscustomobject]@{ Output = @($output); Errors = @($shell.Streams.Error); Stop = $stop; NextStatement = $runspace.SessionStateProxy.GetVariable('NativeTempdbNext') }
        } finally { $shell.Dispose(); $runspace.Dispose(); $output.Dispose() }
    }

    # A second session whose running request holds a filled temporary table while it waits, so its task has tempdb
    # pages allocated and none deallocated when the command reads the DMVs.
    function Start-NativeTempdbHolder($server, $database) {
        $connection = $server.ConnectionContext.Copy()
        $connection.NonPooledConnection = $true
        $connection.DatabaseName = $database
        $token = 'native_tempdb_' + [guid]::NewGuid().ToString('N')
        $connection.Connect()
        try {
            $sqlConnection = $connection.SqlConnectionObject
            $spidCommand = $sqlConnection.CreateCommand()
            $spidCommand.CommandText = 'SELECT @@SPID;'
            $spid = [int]$spidCommand.ExecuteScalar()
            $holdCommand = $sqlConnection.CreateCommand()
            $holdCommand.CommandTimeout = 120
            $holdCommand.CommandText = "CREATE TABLE #$token (id int NOT NULL, pad char(4000) NOT NULL); INSERT INTO #$token (id, pad) SELECT TOP (64) 1, 'x' FROM sys.all_objects; WAITFOR DELAY '00:01:30';"
            $task = $holdCommand.ExecuteNonQueryAsync()
            $held = $false
            $poll = [System.Diagnostics.Stopwatch]::StartNew()
            while (-not $held -and $poll.ElapsedMilliseconds -lt 30000 -and -not $task.IsCompleted) {
                $held = [int]$server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.dm_exec_requests WHERE session_id = $spid AND wait_type = N'WAITFOR';") -eq 1
                if (-not $held) { Start-Sleep -Milliseconds 100 }
            }
            $held | Should -BeTrue
            [pscustomobject]@{ Connection = $connection; Command = $holdCommand; Task = $task; Spid = $spid; Database = $database }
        } catch { $connection.Disconnect(); throw }
    }
    function Stop-NativeTempdbHolder($fixture) {
        try {
            $fixture.Command.Cancel()
            try { $null = $fixture.Task.Wait(30000) } catch { $null = $PSItem }
        } finally { $fixture.Connection.Disconnect() }
        $fixture.Task.IsCompleted | Should -BeTrue
    }
    function Assert-NativeTempdbUsage($server, $fixture, $rows) {
        $matches = @($rows | Where-Object { $_.Spid -eq $fixture.Spid })
        $matches.Count | Should -Be 1
        $spid = [int]$fixture.Spid
        $expected = @($server.Query("SELECT SUM(u.user_objects_alloc_page_count) * 8 AS UserAllocated, SUM(u.user_objects_dealloc_page_count) * 8 AS UserDeallocated, SUM(u.internal_objects_alloc_page_count) * 8 AS InternalAllocated, SUM(u.internal_objects_dealloc_page_count) * 8 AS InternalDeallocated, MAX(t.user_objects_alloc_page_count) * 8 AS SessionUserAllocated, MAX(s.login_name) AS LoginName FROM tempdb.sys.dm_db_task_space_usage AS u JOIN sys.dm_db_session_space_usage AS t ON t.session_id = u.session_id JOIN sys.dm_exec_sessions AS s ON s.session_id = u.session_id WHERE u.session_id = $spid;"))
        $expected.Count | Should -Be 1
        $row = $matches[0]
        $row.CurrentUserAllocatedKB | Should -BeGreaterThan 0
        $row.CurrentUserAllocatedKB | Should -Be $expected[0].UserAllocated
        $row.UserDeallocatedKB | Should -Be $expected[0].UserDeallocated
        $row.InternalAllocatedKB | Should -Be $expected[0].InternalAllocated
        $row.InternalDeallocatedKB | Should -Be $expected[0].InternalDeallocated
        $row.TotalUserAllocatedKB | Should -Be ($expected[0].SessionUserAllocated + $expected[0].UserAllocated)
        $row.CurrentUserAllocatedKB | Should -BeOfType long
        $row.LoginName | Should -BeExactly $expected[0].LoginName
        $row.StatementCommand | Should -BeExactly 'WAITFOR'
        $row.QueryText | Should -BeLike '*WAITFOR*'
        $row.Database | Should -BeExactly $fixture.Database
        $row.StartTime | Should -BeOfType datetime
        $row.IsUserProcess | Should -BeTrue
        $row.ProcedureName | Should -BeOfType System.DBNull
        @($row.PSObject.Properties.Name | Select-Object -First 8) | Should -BeExactly @('ComputerName', 'InstanceName', 'SqlInstance', 'Spid', 'StatementCommand', 'QueryText', 'ProcedureName', 'StartTime')
    }
}

Describe 'Native Get-DbaTempdbUsage real tempdb usage' -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $fixture = Start-NativeTempdbHolder $server 'master'
    }
    AfterAll { if ($fixture) { Stop-NativeTempdbHolder $fixture } }
    It 'returns the running session holding tempdb pages with its real allocation values' {
        Assert-NativeTempdbUsage $server $fixture @(Get-DbaTempdbUsage -SqlInstance $server -EnableException)
    }
    It 'reads arrays and pipeline instances with EnableException false' -Tag NativeChecklist:pipeline-multiple, NativeChecklist:switch-false {
        $rows = @($server, $server | Get-DbaTempdbUsage -EnableException:$false)
        @($rows | Where-Object { $_.Spid -eq $fixture.Spid }).Count | Should -Be 2
        $rows = @(Get-DbaTempdbUsage -SqlInstance $server, $server -EnableException:$false)
        @($rows | Where-Object { $_.Spid -eq $fixture.Spid }).Count | Should -Be 2
    }
    It 'continues after a connection failure and stops with EnableException' -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $rows = @(Get-DbaTempdbUsage -SqlInstance 'tcp:127.0.0.1,1', $server -WarningVariable warnings -WarningAction SilentlyContinue)
        Assert-NativeTempdbUsage $server $fixture $rows
        "$warnings" | Should -BeLike '*Failure*'
        { Get-DbaTempdbUsage -SqlInstance 'tcp:127.0.0.1,1', $server -EnableException } | Should -Throw -ErrorId 'dbatools_Get-DbaTempdbUsage*'
    }
}

Describe 'Native Get-DbaTempdbUsage SQL authentication' -Tag IntegrationTests {
    It 'reads tempdb usage with SqlCredential and fails cleanly without it' -Tag NativeChecklist:sql-login {
        $admin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $fixture = Start-NativeTempdbHolder $admin 'master'
        try {
            Assert-NativeTempdbUsage $admin $fixture @(Get-DbaTempdbUsage -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException)
            @(Get-DbaTempdbUsage -SqlInstance $TestConfig.InstanceSqlLogin -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            "$warnings" | Should -BeLike '*Failure*Login failed*'
            { Get-DbaTempdbUsage -SqlInstance $TestConfig.InstanceSqlLogin -EnableException } | Should -Throw -ErrorId 'dbatools_Get-DbaTempdbUsage*'
        } finally { Stop-NativeTempdbHolder $fixture }
    }
}

Describe 'Native Get-DbaTempdbUsage Azure SQL Database' -Tag IntegrationTests {
    It 'reads a running session holding tempdb pages on the database' -Tag NativeChecklist:azure-sqldb {
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                break
            } catch {
                $retry = $false
                for ($cause = $PSItem.Exception; $null -ne $cause; $cause = $cause.InnerException) {
                    if ($cause.Number -in 40613, -2 -or $cause -is [TimeoutException] -or ($cause -is [System.ComponentModel.Win32Exception] -and $cause.NativeErrorCode -eq 258)) { $retry = $true }
                }
                if (-not $retry -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $fixture = Start-NativeTempdbHolder $azure $TestConfig.AzureSqlDbName
        try { Assert-NativeTempdbUsage $azure $fixture @(Get-DbaTempdbUsage -SqlInstance $azure -EnableException) }
        finally { Stop-NativeTempdbHolder $fixture }
    }
}

Describe 'Native Get-DbaTempdbUsage query failures' -Tag IntegrationTests {
    BeforeAll {
        $admin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $login = 'native_tempdb_read_' + [guid]::NewGuid().ToString('N')
        $password = 'No!' + [guid]::NewGuid().ToString('N')
        $null = $admin.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$login] WITH PASSWORD=N'$password', CHECK_POLICY=OFF;")
        $connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $admin.Name, $login, $password
        $connection.NonPooledConnection = $true
        $connection.TrustServerCertificate = $true
        $connection.DatabaseName = 'master'
        $connection.Connect()
        $low = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $connection
        $boundLow = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $low
        $boundAdmin = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $admin
        $connection.ExecuteScalar('SELECT SUSER_SNAME();') | Should -BeExactly $login
        $expected = $null
        try { $null = $low.Query('SELECT * FROM sys.dm_db_session_space_usage;') } catch { $expected = $PSItem }
        $expected | Should -Not -BeNullOrEmpty
        $expected.Exception.Message | Should -BeLike '*permission was denied*'
        $fixture = Start-NativeTempdbHolder $admin 'master'
    }
    AfterAll {
        if ($fixture) { Stop-NativeTempdbHolder $fixture }
        if ($connection) { $connection.Disconnect() }
        if ($admin -and $login) {
            $null = $admin.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$login') IS NOT NULL DROP LOGIN [$login];")
            $admin.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.server_principals WHERE name=N'$login';") | Should -Be 0
        }
    }
    It 'preserves the denied Query record and honors plain caller try and explicit stop modes' -Tag NativeChecklist:enable-exception, NativeChecklist:multi-instance-failure {
        foreach ($mode in 'Plain', 'CallerTry', 'EnableException', 'ErrorAction') {
            $arguments = @{ SqlInstance = @($boundLow, $boundAdmin); EnableException = ($mode -eq 'EnableException'); ErrorAction = $(if ($mode -eq 'ErrorAction') { 'Stop' } else { 'Continue' }) }
            $rows = New-Object 'System.Collections.Generic.List[object]'
            $errors = @()
            if ($mode -eq 'CallerTry') {
                try { Get-DbaTempdbUsage @arguments | ForEach-Object { $rows.Add($PSItem) } } catch { $errors = @($PSItem) }
            } else {
                $invocation = Invoke-TempdbUsageOutsideTry $arguments
                foreach ($row in $invocation.Output) { $rows.Add($row) }
                if ($mode -eq 'ErrorAction') {
                    $invocation.Stop.Exception.InnerException | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                    $errors = @($invocation.Stop.Exception.InnerException.ErrorRecord)
                } else { $errors = $invocation.Errors }
            }
            $errors.Count | Should -Be 1 -Because $mode
            $errors[0].FullyQualifiedErrorId | Should -BeExactly (($expected.FullyQualifiedErrorId -split ',')[0] + ',Dataplat.Dbatools.Commands.GetDbaTempdbUsageCommand')
            $errors[0].CategoryInfo.Category | Should -Be $expected.CategoryInfo.Category
            $errors[0].TargetObject | Should -BeNullOrEmpty
            $actualCause = $errors[0].Exception
            for ($expectedCause = $expected.Exception; $null -ne $expectedCause; $expectedCause = $expectedCause.InnerException) {
                $actualCause | Should -Not -BeNullOrEmpty
                $actualCause.GetType().FullName | Should -BeExactly $expectedCause.GetType().FullName
                $actualCause.Message | Should -BeExactly $expectedCause.Message
                $actualCause = $actualCause.InnerException
            }
            $actualCause | Should -BeNullOrEmpty
            if ($mode -eq 'Plain') {
                $invocation.Stop | Should -BeNullOrEmpty
                $invocation.NextStatement | Should -BeTrue
                Assert-NativeTempdbUsage $admin $fixture $rows
            } else { $rows.Count | Should -Be 0 -Because $mode }
        }
    }
}
