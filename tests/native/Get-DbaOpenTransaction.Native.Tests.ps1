#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- read-only DMV query; no ShouldProcess in the pin.

BeforeAll {
    function Invoke-OpenTransactionOutsideTry([hashtable]$arguments) {
        $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $type = (Get-Command Get-DbaOpenTransaction -CommandType Cmdlet).ImplementingType
        $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Get-DbaOpenTransaction', $type, $null
        $state.Commands.Add($entry)
        $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
        $shell = [powershell]::Create()
        $output = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
        try {
            $runspace.Open()
            $shell.Runspace = $runspace
            $runspace.SessionStateProxy.SetVariable('NativeOpenNext', $false)
            $body = { param($readArguments) Get-DbaOpenTransaction @readArguments; $global:NativeOpenNext = $true }
            $null = $shell.AddScript($body.ToString()).AddArgument($arguments)
            $stop = $null
            try { $null = $shell.Invoke($null, $output) } catch { $stop = $PSItem }
            [pscustomobject]@{ Output = @($output); Errors = @($shell.Streams.Error); Stop = $stop; NextStatement = $runspace.SessionStateProxy.GetVariable('NativeOpenNext') }
        } finally { $shell.Dispose(); $runspace.Dispose(); $output.Dispose() }
    }
    function New-NativeOpenTransaction($server, $database = 'tempdb') {
        $connection = $server.ConnectionContext.Copy()
        $connection.NonPooledConnection = $true
        $connection.DatabaseName = $database
        $token = 'native_open_' + [guid]::NewGuid().ToString('N')
        try {
            $connection.Connect()
            $spid = [int]$connection.ExecuteScalar('SELECT @@SPID;')
            $connection.BeginTransaction()
            $null = $connection.ExecuteNonQuery("CREATE TABLE dbo.[$token] (id int NOT NULL); INSERT INTO dbo.[$token] VALUES (1);") # teardown-ok: each caller rolls this transaction back in AfterAll or finally and verifies the table is absent; setup failures disconnect and roll back.
            [pscustomobject]@{ Connection = $connection; Spid = $spid; Token = $token; Database = $database }
        } catch { $connection.Disconnect(); throw }
    }
    function Remove-NativeOpenTransaction($server, $fixture) {
        try { $fixture.Connection.RollBackTransaction() } finally { $fixture.Connection.Disconnect() }
        $catalog = $fixture.Database.Replace(']', ']]')
        $server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM [$catalog].sys.tables WHERE name=N'$($fixture.Token)';") | Should -Be 0
    }
    function Assert-NativeOpenTransaction($server, $fixture, $rows) {
        $matches = @($rows | Where-Object { $_.Spid -eq $fixture.Spid -and $_.Database -eq $fixture.Database })
        $matches.Count | Should -Be 1
        $databaseLiteral = $fixture.Database.Replace("'", "''")
        $expected = @($server.Query("SELECT t.database_transaction_begin_time AS BeginTime, t.database_transaction_log_bytes_used AS Used, t.database_transaction_log_bytes_reserved AS Reserved, s.login_name AS Login FROM sys.dm_tran_database_transactions AS t JOIN sys.dm_tran_session_transactions AS st ON st.transaction_id=t.transaction_id JOIN sys.dm_exec_sessions AS s ON s.session_id=st.session_id WHERE st.session_id=$([int]$fixture.Spid) AND t.database_id=DB_ID(N'$databaseLiteral');"))
        $expected.Count | Should -Be 1
        $matches[0].BeginTime | Should -Be $expected[0].BeginTime
        $matches[0].LogBytesUsed | Should -Be $expected[0].Used
        $matches[0].LogBytesReserved | Should -Be $expected[0].Reserved
        $matches[0].Login | Should -Be $expected[0].Login
        $matches[0].LastQuery | Should -BeLike ('*' + $fixture.Token + '*')
        $matches[0].BeginTime | Should -BeOfType datetime
        $matches[0].LogBytesUsed | Should -BeOfType long
        @($matches[0].PSObject.Properties.Name | Select-Object -First 11) | Should -BeExactly @('ComputerName', 'InstanceName', 'SqlInstance', 'Spid', 'Login', 'Database', 'BeginTime', 'LogBytesUsed', 'LogBytesReserved', 'LastQuery', 'LastPlan')
        $previous = [datetime]::MinValue
        foreach ($row in $rows) {
            if ($row.BeginTime -is [datetime]) { $row.BeginTime | Should -BeGreaterOrEqual $previous; $previous = $row.BeginTime }
        }
    }
}

Describe 'Native Get-DbaOpenTransaction real transactions' -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $fixture = New-NativeOpenTransaction $server
    }
    AfterAll { if ($fixture) { Remove-NativeOpenTransaction $server $fixture } }
    It 'returns the real session database log values and query in begin-time order' {
        Assert-NativeOpenTransaction $server $fixture @(Get-DbaOpenTransaction -SqlInstance $server -EnableException)
    }
    It 'reads arrays and pipeline instances with EnableException false' -Tag NativeChecklist:pipeline-multiple, NativeChecklist:switch-false {
        $rows = @($server, $server | Get-DbaOpenTransaction -EnableException:$false)
        @($rows | Where-Object { $_.Spid -eq $fixture.Spid -and $_.Database -eq $fixture.Database }).Count | Should -Be 2
        $rows = @(Get-DbaOpenTransaction -SqlInstance $server, $server -EnableException:$false)
        @($rows | Where-Object { $_.Spid -eq $fixture.Spid -and $_.Database -eq $fixture.Database }).Count | Should -Be 2
    }
    It 'continues after a connection failure and stops with EnableException' -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $rows = @(Get-DbaOpenTransaction -SqlInstance 'tcp:127.0.0.1,1', $server -WarningVariable warnings -WarningAction SilentlyContinue)
        Assert-NativeOpenTransaction $server $fixture $rows
        "$warnings" | Should -BeLike '*Failure*'
        { Get-DbaOpenTransaction -SqlInstance 'tcp:127.0.0.1,1', $server -EnableException } | Should -Throw -ErrorId 'dbatools_Get-DbaOpenTransaction*'
    }
}

Describe 'Native Get-DbaOpenTransaction SQL authentication' -Tag IntegrationTests {
    It 'reads transactions with SqlCredential and fails cleanly without it' -Tag NativeChecklist:sql-login {
        $admin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $fixture = New-NativeOpenTransaction $admin
        try {
            Assert-NativeOpenTransaction $admin $fixture @(Get-DbaOpenTransaction -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException)
            @(Get-DbaOpenTransaction -SqlInstance $TestConfig.InstanceSqlLogin -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            "$warnings" | Should -BeLike '*Failure*Login failed*'
            { Get-DbaOpenTransaction -SqlInstance $TestConfig.InstanceSqlLogin -EnableException } | Should -Throw -ErrorId 'dbatools_Get-DbaOpenTransaction*'
        } finally { Remove-NativeOpenTransaction $admin $fixture }
    }
}

Describe 'Native Get-DbaOpenTransaction Azure SQL Database' -Tag IntegrationTests {
    It 'reads an open transaction through the bound database connection' -Tag NativeChecklist:azure-sqldb {
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
        $fixture = New-NativeOpenTransaction $azure $TestConfig.AzureSqlDbName
        try { Assert-NativeOpenTransaction $azure $fixture @(Get-DbaOpenTransaction -SqlInstance $azure -EnableException) }
        finally { Remove-NativeOpenTransaction $azure $fixture }
    }
}

Describe 'Native Get-DbaOpenTransaction query failures' -Tag IntegrationTests {
    BeforeAll {
        $admin = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $login = 'native_open_read_' + [guid]::NewGuid().ToString('N')
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
        try { $null = $low.Query('SELECT * FROM sys.dm_tran_database_transactions;') } catch { $expected = $PSItem }
        $expected | Should -Not -BeNullOrEmpty
        $expected.Exception.Message | Should -BeLike '*permission was denied*'
        $fixture = New-NativeOpenTransaction $admin
    }
    AfterAll {
        if ($fixture) { Remove-NativeOpenTransaction $admin $fixture }
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
                try { Get-DbaOpenTransaction @arguments | ForEach-Object { $rows.Add($PSItem) } } catch { $errors = @($PSItem) }
            } else {
                $invocation = Invoke-OpenTransactionOutsideTry $arguments
                foreach ($row in $invocation.Output) { $rows.Add($row) }
                if ($mode -eq 'ErrorAction') {
                    $invocation.Stop.Exception.InnerException | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                    $errors = @($invocation.Stop.Exception.InnerException.ErrorRecord)
                } else { $errors = $invocation.Errors }
            }
            $errors.Count | Should -Be 1 -Because $mode
            $errors[0].FullyQualifiedErrorId | Should -BeExactly (($expected.FullyQualifiedErrorId -split ',')[0] + ',Dataplat.Dbatools.Commands.GetDbaOpenTransactionCommand')
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
                Assert-NativeOpenTransaction $admin $fixture $rows
            } else { $rows.Count | Should -Be 0 -Because $mode }
        }
    }
}
