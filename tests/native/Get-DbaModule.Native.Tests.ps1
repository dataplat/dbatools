#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param($ModuleName = "dbatools", $CommandName = "Get-DbaModule", $PSDefaultParameterValues = $TestConfig.Defaults)
# NativeChecklist: whatif-confirm N/A -- read-only metadata; the pinned command has no ShouldProcess.

Describe "Native Get-DbaModule metadata" -Tag IntegrationTests {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $dbName = "native_module_" + [guid]::NewGuid().ToString("N") + "_q']"
        $database = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $server, $dbName
        $database.Create()
        $null = $database.ExecuteNonQuery("CREATE PROCEDURE dbo.native_module_proc AS SELECT 17 AS value;")
        $null = $database.ExecuteNonQuery("CREATE VIEW dbo.native_module_view AS SELECT 19 AS value;")
        $null = $database.ExecuteNonQuery("CREATE FUNCTION dbo.native_module_function() RETURNS int AS BEGIN RETURN 23; END;")
        function Invoke-ModuleOutsideTry([hashtable]$arguments) {
            $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $type = (Get-Command Get-DbaModule -CommandType Cmdlet).ImplementingType
            $entry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaModule", $type, $null
            $state.Commands.Add($entry)
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $shell = [powershell]::Create()
            $output = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            try {
                $runspace.Open()
                $shell.Runspace = $runspace
                $body = { param($readArguments) Get-DbaModule @readArguments }
                $null = $shell.AddScript($body.ToString()).AddArgument($arguments)
                $stop = $null
                try { $null = $shell.Invoke($null, $output) } catch { $stop = $PSItem }
                [pscustomobject]@{ Output = @($output); Errors = @($shell.Streams.Error); Stop = $stop }
            } finally { $shell.Dispose(); $runspace.Dispose(); $output.Dispose() }
        }
    }
    AfterAll {
        if ($server -and $dbName) {
            $server.Databases.Refresh()
            if ($server.Databases[$dbName]) { $server.KillDatabase($dbName) }
            $server.Databases.Refresh()
            $server.Databases.Contains($dbName) | Should -BeFalse
        }
    }
    It "returns the catalog values and hides only Definition from the default display" {
        $rows = @(Get-DbaModule -SqlInstance $server -Database $dbName -ExcludeSystemObjects -EnableException)
        $raw = @($database.Query("SELECT o.name, o.object_id, SCHEMA_NAME(o.schema_id) AS schema_name, o.type_desc, o.create_date, o.modify_date, o.is_ms_shipped, m.definition, OBJECTPROPERTY(o.object_id, 'ExecIsStartUp') AS startup FROM sys.sql_modules m JOIN sys.objects o ON o.object_id=m.object_id WHERE o.is_ms_shipped=0 ORDER BY o.modify_date;"))
        $rows.Count | Should -Be 3
        $rows.Name | Should -BeExactly $raw.name
        $previous = [datetime]::MinValue
        foreach ($row in $rows) {
            $expected = $raw | Where-Object name -eq $row.Name
            $row.ComputerName | Should -BeExactly $server.ComputerName
            $row.InstanceName | Should -BeExactly $server.ServiceName
            $row.SqlInstance | Should -BeExactly $server.DomainInstanceName
            $row.Database | Should -BeExactly $dbName
            $row.ObjectID | Should -Be $expected.object_id
            $row.SchemaName | Should -BeExactly $expected.schema_name
            $row.Type | Should -BeExactly $expected.type_desc
            $row.CreateDate | Should -Be $expected.create_date
            $row.ModifyDate | Should -Be $expected.modify_date
            $row.ModifyDate | Should -BeGreaterOrEqual $previous
            $previous = $row.ModifyDate
            $row.IsMsShipped | Should -Be $expected.is_ms_shipped
            $row.ExecIsStartUp | Should -Be $expected.startup
            $row.Definition | Should -BeExactly $expected.definition
            @($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames) | Should -Not -Contain "Definition"
        }
    }
    It "filters types and databases and accepts explicit false switches" -Tag NativeChecklist:switch-false {
        $rows = @(Get-DbaModule -SqlInstance $server -Database $dbName -Type View, ScalarFunction -ExcludeSystemObjects:$false -ExcludeSystemDatabases:$false -EnableException:$false)
        @($rows.Type | Sort-Object) | Should -BeExactly @("SQL_SCALAR_FUNCTION", "VIEW")
        @(Get-DbaModule -SqlInstance $server -Database $dbName -ExcludeDatabase $dbName).Count | Should -Be 0
        @(Get-DbaModule -SqlInstance $server -Database master -ExcludeSystemDatabases).Count | Should -Be 0
        @(Get-DbaModule -SqlInstance $server -Database $dbName -ModifiedSince ([datetime]::MaxValue)).Count | Should -Be 0
    }
    It "accepts multiple explicit instances and piped database objects" -Tag NativeChecklist:pipeline-multiple {
        @(Get-DbaModule -SqlInstance $server, $server -Database $dbName -Type View).Count | Should -Be 2
        @($database, $database | Get-DbaModule -Type View).Count | Should -Be 2
    }
    It "does not replay earlier databases across instance pipeline records" -Tag NativeChecklist:pipeline-multiple {
        $rows = @($server, $server | Get-DbaModule -Database $dbName -Type View)
        $rows.Count | Should -Be 2
    }
    It "honors documented database wildcard selection" {
        $pattern = $dbName.Substring(0, $dbName.Length - 4) + "*"
        $rows = @(Get-DbaModule -SqlInstance $server -Database $pattern -Type View)
        $rows.Count | Should -Be 1
        $rows[0].Database | Should -BeExactly $dbName
        @(Get-DbaModule -SqlInstance $server -Database $pattern -ExcludeDatabase $dbName).Count | Should -Be 0
    }
    It "preserves the subsecond ModifiedSince boundary" {
        $modified = [datetime]$database.Query("SELECT modify_date FROM sys.objects WHERE name=N'native_module_proc';").modify_date
        @(Get-DbaModule -InputObject $database -Type StoredProcedure -ModifiedSince $modified).Count | Should -Be 1
        @(Get-DbaModule -InputObject $database -Type StoredProcedure -ModifiedSince $modified.AddMilliseconds(1)).Count | Should -Be 0
    }
    It "returns documented default constraints and their definitions" {
        try {
            $null = $database.ExecuteNonQuery("CREATE TABLE dbo.native_module_table (value int CONSTRAINT native_module_default DEFAULT (31));")
            $expected = $database.Query("SELECT name, object_id, definition, create_date, modify_date FROM sys.default_constraints WHERE name=N'native_module_default';")
            $rows = @(Get-DbaModule -InputObject $database -Type DefaultConstraint -EnableException)
            $rows.Count | Should -Be 1
            $rows[0].Name | Should -BeExactly $expected.name
            $rows[0].ObjectID | Should -Be $expected.object_id
            $rows[0].Definition | Should -BeExactly $expected.definition
            $rows[0].Type | Should -BeExactly "DEFAULT_CONSTRAINT"
            $rows[0].CreateDate | Should -Be $expected.create_date
            $rows[0].ModifyDate | Should -Be $expected.modify_date
        } finally {
            $null = $database.ExecuteNonQuery("IF OBJECT_ID(N'dbo.native_module_table', 'U') IS NOT NULL DROP TABLE dbo.native_module_table;")
            $database.Query("SELECT COUNT(*) AS count FROM sys.objects WHERE name IN (N'native_module_table', N'native_module_default');").count | Should -Be 0
        }
    }
    It "continues after a failed connection even with EnableException as the nested pin does" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $rows = @(Get-DbaModule -SqlInstance "tcp:127.0.0.1,1", $server -Database $dbName -Type View -EnableException -WarningVariable warnings -WarningAction SilentlyContinue)
        $rows.Count | Should -Be 1
        "$warnings" | Should -BeLike "*Failure*"
        @(Get-DbaModule -EnableException:$false -WarningVariable missing -WarningAction SilentlyContinue).Count | Should -Be 0
        "$missing" | Should -BeLike "*You must pipe in a database or specify a SqlInstance*"
        { Get-DbaModule -EnableException } | Should -Throw -ExpectedMessage "*You must pipe in a database or specify a SqlInstance*"
    }
    It "continues after a query fault and stops for caller try or explicit stop modes" -Tag NativeChecklist:enable-exception, NativeChecklist:multi-instance-failure {
        $login = "native_module_read_" + [guid]::NewGuid().ToString("N")
        $password = "Nm!" + [guid]::NewGuid().ToString("N")
        $connection = $null
        try {
            $null = $server.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$login] WITH PASSWORD=N'$password', CHECK_POLICY=OFF;")
            $null = $database.ExecuteNonQuery("CREATE USER [$login] FOR LOGIN [$login]; GRANT VIEW DEFINITION TO [$login]; DENY SELECT ON OBJECT::sys.sql_modules TO [$login];")
            $connection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $server.Name, $login, $password
            $connection.NonPooledConnection = $true
            $connection.TrustServerCertificate = $true
            $connection.DatabaseName = $dbName
            $connection.Connect()
            $lowServer = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $connection
            $lowDatabase = $lowServer.Databases[$dbName]
            $connection.ExecuteScalar("SELECT SUSER_SNAME();") | Should -BeExactly $login
            $lowDatabase.IsAccessible | Should -BeTrue
            $denied = $null
            try { $null = $lowDatabase.ExecuteWithResults("SELECT * FROM sys.sql_modules;") } catch { $denied = $PSItem.Exception }
            $numbers = @()
            for ($cause = $denied; $null -ne $cause; $cause = $cause.InnerException) {
                if ($null -ne $cause.Number) { $numbers += $cause.Number }
            }
            $numbers | Should -Contain 229
            foreach ($mode in "Plain", "CallerTry", "EnableException", "ErrorAction") {
                $arguments = @{ InputObject = @($lowDatabase, $database); Type = "View"; EnableException = ($mode -eq "EnableException"); ErrorAction = $(if ($mode -eq "ErrorAction") { "Stop" } else { "Continue" }) }
                $rows = New-Object "System.Collections.Generic.List[object]"
                $errors = @()
                if ($mode -eq "CallerTry") {
                    try { Get-DbaModule @arguments | ForEach-Object { $rows.Add($PSItem) } } catch { $errors = @($PSItem) }
                } else {
                    $invocation = Invoke-ModuleOutsideTry $arguments
                    foreach ($row in $invocation.Output) { $rows.Add($row) }
                    if ($mode -eq "ErrorAction") {
                        $invocation.Stop.Exception.InnerException | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
                        $errors = @($invocation.Stop.Exception.InnerException.ErrorRecord)
                    } else { $errors = $invocation.Errors }
                }
                $errors.Count | Should -Be 1
                $errors[0].FullyQualifiedErrorId | Should -BeExactly "ScriptMethodRuntimeException,Dataplat.Dbatools.Commands.GetDbaModuleCommand"
                $errors[0].Exception.Message | Should -BeLike '*Exception calling "Query" with "2" argument(s):*permission was denied*'
                $errors[0].TargetObject | Should -BeNullOrEmpty
                if ($mode -eq "Plain") {
                    $invocation.Stop | Should -BeNullOrEmpty
                    $rows.Count | Should -Be 1
                    $rows[0].Name | Should -BeExactly "native_module_view"
                } else { $rows.Count | Should -Be 0 }
            }
        } finally {
            if ($connection) { $connection.Disconnect() }
            try { $null = $database.ExecuteNonQuery("IF USER_ID(N'$login') IS NOT NULL DROP USER [$login];") }
            finally {
                $null = $server.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$login') IS NOT NULL DROP LOGIN [$login];")
                $server.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.server_principals WHERE name=N'$login';") | Should -Be 0
            }
        }
    }
}

Describe "Native Get-DbaModule SQL authentication" -Tag IntegrationTests {
    It "reads with SqlCredential and warns without it even with EnableException" -Tag NativeChecklist:sql-login {
        $rows = @(Get-DbaModule -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -Database msdb -Type View -EnableException)
        $rows.Count | Should -BeGreaterThan 0
        $failed = @(Get-DbaModule -SqlInstance $TestConfig.InstanceSqlLogin -Database msdb -EnableException -WarningVariable warnings -WarningAction SilentlyContinue)
        $failed.Count | Should -Be 0
        "$warnings" | Should -BeLike "*Failure*Login failed*"
    }
}

Describe "Native Get-DbaModule Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
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
        $azureView = "native_module_" + [guid]::NewGuid().ToString("N")
        $null = $azure.ConnectionContext.ExecuteNonQuery("CREATE VIEW dbo.[$azureView] AS SELECT 29 AS value;")
        $azureDatabase = $azure.Databases[$TestConfig.AzureSqlDbName]
    }
    AfterAll {
        if ($azure -and $azureView) {
            $null = $azure.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.$azureView', 'V') IS NOT NULL DROP VIEW dbo.[$azureView];")
            $azure.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.views WHERE name=N'$azureView';") | Should -Be 0
        }
    }
    It "reads modules in the connected Azure database" -Tag NativeChecklist:azure-sqldb {
        $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $rows = @($azureDatabase | Get-DbaModule -Type View -EnableException | Where-Object Name -eq $azureView)
        $rows.Count | Should -Be 1
        $rows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        $rows[0].Definition | Should -BeLike "*SELECT 29 AS value*"
    }
}
