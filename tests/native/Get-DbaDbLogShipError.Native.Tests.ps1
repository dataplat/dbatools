#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbLogShipError",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads msdb.

Describe "Get-DbaDbLogShipError native" -Tag IntegrationTests {
    BeforeAll {
        # Unique per leg and run: the lanes of one SQL version share this instance and its msdb, so every assertion reads only this run's rows.
        $nativeSuffix = [Guid]::NewGuid().ToString("N").Substring(0, 12)
        $nativePrefix = "dbatoolsci_logship_$($nativeSuffix)_"
        $dbPrimary = "$($nativePrefix)p"
        $dbSecondary = "$($nativePrefix)s"
        $dbSharedA = "$($nativePrefix)sharea"
        $dbSharedB = "$($nativePrefix)shareb"
        $dbUnicode = "$($nativePrefix)" + [string][char]0x65E5 + [string][char]0x672C + [string][char]0x8A9E
        $primaryId = [Guid]::NewGuid().ToString()
        $unicodeId = [Guid]::NewGuid().ToString()
        $secondaryId = [Guid]::NewGuid().ToString()
        $sharedId = [Guid]::NewGuid().ToString()
        $orphanId = [Guid]::NewGuid().ToString()
        $lowLogin = "$($nativePrefix)low"
        $lowPassword = "Lg!" + [Guid]::NewGuid().ToString("N")
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -NonPooledConnection

        $primarySql = "INSERT msdb.dbo.log_shipping_primary_databases (primary_id, primary_database, backup_directory, backup_share, backup_retention_period, backup_job_id, monitor_server, monitor_server_security_mode, user_specified_monitor, backup_compression) VALUES ('{0}', N'{1}', N'C:\native', N'\\native\native', 4320, '{2}', N'native', 1, 0, 2);"
        $secondarySql = "INSERT msdb.dbo.log_shipping_secondary_databases (secondary_database, secondary_id, restore_delay, restore_all, restore_mode, disconnect_users, block_size, buffer_count, max_transfer_size) VALUES (N'{0}', '{1}', 0, 1, 0, 0, -1, -1, -1);"
        $errorSql = "INSERT msdb.dbo.log_shipping_monitor_error_detail (agent_id, agent_type, session_id, database_name, sequence_number, log_time, log_time_utc, message, source, help_url) VALUES ('{0}', {1}, {2}, {3}, {4}, '2026-01-01T10:00:{5:00}', '2026-01-01T09:00:{5:00}', N'{6}', N'native', N'');"

        # A log shipping job writes the primary database for backup, the secondary database for restore and nothing for copy:
        # https://learn.microsoft.com/sql/relational-databases/system-tables/log-shipping-monitor-error-detail-transact-sql
        $fixture = @(
            ($primarySql -f $primaryId, $dbPrimary, [Guid]::NewGuid())
            ($primarySql -f $unicodeId, $dbUnicode, [Guid]::NewGuid())
            ($secondarySql -f $dbSecondary, $secondaryId)
            ($secondarySql -f $dbSharedA, $sharedId)
            ($secondarySql -f $dbSharedB, $sharedId)
            ($errorSql -f $primaryId, 0, 1, "N'$dbPrimary'", 1, 0, "backup first")
            ($errorSql -f $primaryId, 0, 1, "N'$dbPrimary'", 2, 1, "backup second")
            ($errorSql -f $secondaryId, 1, 2, "N''", 1, 2, "copy")
            ($errorSql -f $secondaryId, 2, 3, "N'$dbSecondary'", 1, 3, "restore")
            ($errorSql -f $primaryId, 9, 4, "N'$dbPrimary'", 1, 4, "unknown agent")
            ($errorSql -f $sharedId, 2, 5, "N'$dbSharedA'", 1, 5, "restore of shared a")
            ($errorSql -f $sharedId, 1, 6, "N''", 1, 6, "copy of shared")
            ($errorSql -f $sharedId, 1, 7, "NULL", 1, 7, "copy with no name")
            ($errorSql -f $sharedId, 2, 8, "N'$($nativePrefix)gone'", 1, 8, "restore of a removed database")
            ($errorSql -f $orphanId, 0, 9, "N'$($nativePrefix)orphan'", 1, 9, "no database row")
            ($errorSql -f $unicodeId, 0, 10, "N'$dbUnicode'", 1, 10, "unicode")
        )
        foreach ($statement in $fixture) {
            $null = $nativeServer.ConnectionContext.ExecuteNonQuery($statement)
        }

        # A login that connects but cannot read msdb, for the failed read.
        $null = $nativeServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$lowLogin] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $lowCredential = New-Object System.Management.Automation.PSCredential($lowLogin, (ConvertTo-SecureString $lowPassword -AsPlainText -Force))
        $lowServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $lowCredential -NonPooledConnection

        function Get-NativeOwnRow {
            param($Rows)
            @($Rows | Where-Object Database -like "$nativePrefix*")
        }

        $allOwnCount = @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer)).Count
    }

    AfterAll {
        if ($lowServer) {
            $lowServer.ConnectionContext.Disconnect()
        }
        $cleanup = @(
            "DELETE msdb.dbo.log_shipping_monitor_error_detail WHERE agent_id IN ('$primaryId', '$unicodeId', '$secondaryId', '$sharedId', '$orphanId');"
            "DELETE msdb.dbo.log_shipping_primary_databases WHERE primary_id IN ('$primaryId', '$unicodeId');"
            "DELETE msdb.dbo.log_shipping_secondary_databases WHERE secondary_id IN ('$secondaryId', '$sharedId');"
        )
        foreach ($statement in $cleanup) {
            $null = $nativeServer.ConnectionContext.ExecuteNonQuery($statement)
        }
        for ($attempt = 0; $attempt -lt 10; $attempt++) {
            try {
                $sessions = $nativeServer.ConnectionContext.ExecuteWithResults("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowLogin'").Tables[0].Rows
                foreach ($row in $sessions) {
                    $null = $nativeServer.ConnectionContext.ExecuteNonQuery("KILL $($row.session_id);")
                }
                $null = $nativeServer.ConnectionContext.ExecuteNonQuery("IF SUSER_ID(N'$lowLogin') IS NOT NULL DROP LOGIN [$lowLogin];")
                break
            } catch {
                if ($attempt -eq 9) { throw }
                Start-Sleep -Seconds 1
            }
        }
        $nativeServer.ConnectionContext.Disconnect()
    }

    Context "Rows" {
        It "returns one object per error, in log time order, with the pinned properties" {
            $rows = @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary, $dbSecondary)
            ($rows.Message -join "|") | Should -BeExactly "backup first|backup second|copy|restore|unknown agent"
            ($rows[0].PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database,Instance,Action,SessionID,SequenceNumber,LogTime,Message"
            $rows[0].GetType().FullName | Should -BeExactly "System.Management.Automation.PSCustomObject"
            ($rows[0].PSObject.TypeNames -join ",") | Should -BeExactly "System.Management.Automation.PSCustomObject,System.Object"
            $rows[0].ComputerName | Should -Not -BeNullOrEmpty
            $rows[0].InstanceName | Should -Not -BeNullOrEmpty
            $rows[0].SqlInstance | Should -Not -BeNullOrEmpty
            $rows[0].Database | Should -BeExactly $dbPrimary
            $rows[0].Instance | Should -BeExactly "Primary"
            $rows[0].Action | Should -BeExactly "Backup"
            $rows[0].SessionID | Should -BeOfType [int]
            $rows[0].SessionID | Should -Be 1
            $rows[1].SequenceNumber | Should -BeOfType [int]
            $rows[1].SequenceNumber | Should -Be 2
            $rows[0].LogTime | Should -BeOfType [datetime]
            $rows[0].LogTime | Should -Be ([datetime]"2026-01-01T10:00:00")
            $rows[2].Database | Should -BeExactly $dbSecondary
            $rows[2].Instance | Should -BeExactly "Secondary"
            $rows[2].Action | Should -BeExactly "Copy"
            $rows[3].Action | Should -BeExactly "Restore"
        }

        It "gives an unknown agent type an empty action" {
            $rows = @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary | Where-Object Message -eq "unknown agent")
            $rows.Count | Should -Be 1
            $rows[0].Action | Should -BeExactly ""
        }

        It "leaves out an error whose log shipping id no database row holds" {
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer))
            @($rows | Where-Object Message -eq "no database row").Count | Should -Be 0
        }

        It "leaves the connection in the database it found" {
            $contextServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database tempdb -NonPooledConnection
            try {
                @(Get-DbaDbLogShipError -SqlInstance $contextServer -Database $dbSecondary).Count | Should -Be 2
                $contextServer.ConnectionContext.CurrentDatabase | Should -BeExactly "tempdb"
            } finally {
                $contextServer.ConnectionContext.Disconnect()
            }
        }
    }

    Context "Filters" {
        It "-Database takes exact names, without regard to case and without wildcards" {
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbSecondary).Count | Should -Be 2
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbSecondary.ToUpperInvariant()).Count | Should -Be 2
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database "$($nativePrefix)*").Count | Should -Be 0
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database "$($nativePrefix)nosuch").Count | Should -Be 0
        }

        It "-Database filters only when PowerShell reads it as true" {
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -Database "")).Count | Should -Be $allOwnCount
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -Database @())).Count | Should -Be $allOwnCount
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $null)).Count | Should -Be $allOwnCount
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -Database "", "")).Count | Should -Be 0
        }

        It "-ExcludeDatabase takes exact names, without regard to case and without wildcards" {
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -ExcludeDatabase $dbPrimary) | Where-Object Database -eq $dbPrimary).Count | Should -Be 0
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -ExcludeDatabase $dbPrimary.ToUpperInvariant()) | Where-Object Database -eq $dbPrimary).Count | Should -Be 0
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -ExcludeDatabase "$($nativePrefix)*")).Count | Should -Be $allOwnCount
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -ExcludeDatabase "")).Count | Should -Be $allOwnCount
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary -ExcludeDatabase $dbPrimary).Count | Should -Be 0
        }

        It "-Action keeps the named actions without regard to case" {
            $rows = @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary, $dbSecondary -Action backup)
            ($rows.Message -join "|") | Should -BeExactly "backup first|backup second"
            ($rows.Action | Select-Object -Unique) | Should -BeExactly "Backup"
            $rows = @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary, $dbSecondary -Action Restore, Copy)
            ($rows.Message -join "|") | Should -BeExactly "copy|restore"
        }

        It "-Action refuses a value outside the set through the binder" {
            { Get-DbaDbLogShipError -SqlInstance $nativeServer -Action Nope } | Should -Throw -ErrorId "ParameterArgumentValidationError*"
        }

        It "-DateTimeFrom and -DateTimeTo include their own second" {
            $rows = @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary, $dbSecondary -DateTimeFrom "2026-01-01T10:00:01" -DateTimeTo "2026-01-01T10:00:02")
            ($rows.Message -join "|") | Should -BeExactly "backup second|copy"
        }

        It "-DateTimeFrom and -DateTimeTo filter at the smallest date" {
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary -DateTimeFrom ([datetime]::MinValue)).Count | Should -Be 3
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary -DateTimeTo ([datetime]::MinValue)).Count | Should -Be 0
        }

        It "-DateTimeFrom compares the clock value and ignores its Kind" {
            $utcFrom = [datetime]::SpecifyKind([datetime]"2026-01-01T10:00:01", [System.DateTimeKind]::Utc)
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary -DateTimeFrom $utcFrom).Count | Should -Be 2
        }

        It "-DateTimeFrom reads a date string by the invariant culture, as the pinned [datetime] parameter does" {
            $savedCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
            try {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo("de-DE")
                @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary -DateTimeFrom "12/31/2025").Count | Should -Be 3
            } finally {
                [System.Threading.Thread]::CurrentThread.CurrentCulture = $savedCulture
            }
        }

        It "-Primary and -Secondary keep their role and together keep nothing" {
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary, $dbSecondary -Primary)).Instance | Select-Object -Unique | Should -BeExactly "Primary"
            @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary, $dbSecondary -Secondary)).Instance | Select-Object -Unique | Should -BeExactly "Secondary"
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary, $dbSecondary -Primary -Secondary).Count | Should -Be 0
        }

        It "-Primary:`$false and -Secondary:`$false filter nothing" -Tag "NativeChecklist:switch-false" {
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbPrimary, $dbSecondary -Primary:$false -Secondary:$false).Count | Should -Be 5
        }
    }

    Context "Several instances" {
        It "reads each instance of an array and of the pipeline" -Tag "NativeChecklist:pipeline-multiple" {
            @(Get-DbaDbLogShipError -SqlInstance $nativeServer, $nativeServer -Database $dbSecondary).Count | Should -Be 4
            @($nativeServer, $nativeServer | Get-DbaDbLogShipError -Database $dbSecondary).Count | Should -Be 4
        }

        It "writes the verbose message on an instance that holds no error" {
            # The fixture rows live on InstanceSingle; this instance is empty unless a real log shipping job failed on it.
            $multiServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -NonPooledConnection
            try {
                $recorded = $multiServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM msdb.dbo.log_shipping_monitor_error_detail;")
                $messages = @(Get-DbaDbLogShipError -SqlInstance $multiServer -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No log shipping errors found" })
                $messages.Count | Should -Be $(if ($recorded -eq 0) { 1 } else { 0 })
            } finally {
                $multiServer.ConnectionContext.Disconnect()
            }
        }
    }

    Context "Failed connection" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $connectWarnings = @()
            $rows = @(Get-DbaDbLogShipError -SqlInstance "TCP:127.0.0.1,1", $nativeServer -Database $dbSecondary -WarningAction SilentlyContinue -WarningVariable connectWarnings)
            $rows.Count | Should -Be 2
            @($connectWarnings).Count | Should -Be 1
            ($connectWarnings -join " ") | Should -BeLike "*Failure | *"
        }

        It "throws the original fault under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $thrown = $null
            try {
                $null = Get-DbaDbLogShipError -SqlInstance "TCP:127.0.0.1,1" -EnableException
            } catch {
                $thrown = $PSItem
            }
            $thrown | Should -Not -BeNullOrEmpty
            $thrown.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbLogShipError*"
            $thrown.CategoryInfo.Category.ToString() | Should -BeExactly "ConnectionError"
            "$($thrown.TargetObject)" | Should -BeExactly "TCP:127.0.0.1,1"
        }
    }

    Context "Failed read" {
        BeforeAll {
            $deniedMessage = "An exception occurred while executing a Transact-SQL statement or batch.The SELECT permission was denied on the object 'log_shipping_secondary_databases', database 'msdb', schema 'dbo'.*The SELECT permission was denied on the object 'log_shipping_primary_databases', database 'msdb', schema 'dbo'.*The SELECT permission was denied on the object 'log_shipping_monitor_error_detail', database 'msdb', schema 'dbo'."
        }

        It "reports the Query method's record and no row" {
            $readErrors = @()
            $rows = @(Get-DbaDbLogShipError -SqlInstance $lowServer -ErrorAction SilentlyContinue -ErrorVariable readErrors)
            $rows.Count | Should -Be 0
            @($readErrors).Count | Should -Be 1
            $record = @($readErrors)[0]
            $record.FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException,*"
            $record.CategoryInfo.Category.ToString() | Should -BeExactly "NotSpecified"
            $record.CategoryInfo.Reason | Should -BeExactly "MethodInvocationException"
            $record.TargetObject | Should -BeNullOrEmpty
            $record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
            $record.Exception.Message | Should -BeLike ("Exception calling ""Query"" with ""1"" argument(s): ""$deniedMessage""")
            $record.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
            $record.Exception.InnerException.Message | Should -BeLike $deniedMessage
            $record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
            $record.Exception.InnerException.InnerException.Message | Should -BeLike $deniedMessage
            $record.Exception.InnerException.InnerException.InnerException | Should -BeNullOrEmpty
        }

        It "reports the same record under -EnableException, which the pinned read ignores" -Tag "NativeChecklist:enable-exception" {
            $readErrors = @()
            $rows = @(Get-DbaDbLogShipError -SqlInstance $lowServer -EnableException -ErrorAction SilentlyContinue -ErrorVariable readErrors)
            $rows.Count | Should -Be 0
            @($readErrors)[0].FullyQualifiedErrorId | Should -BeLike "ScriptMethodRuntimeException,*"
        }

        It "goes on to the next instance after a failed read" -Tag "NativeChecklist:multi-instance-failure" {
            $readErrors = @()
            $rows = @(Get-DbaDbLogShipError -SqlInstance $lowServer, $nativeServer -Database $dbSecondary -ErrorAction SilentlyContinue -ErrorVariable readErrors)
            $rows.Count | Should -Be 2
            @($readErrors).Count | Should -Be 1
        }

        It "writes no row for a failed instance of an array" {
            $readErrors = @()
            $rows = @(Get-DbaDbLogShipError -SqlInstance $nativeServer, $lowServer -Database $dbSecondary -ErrorAction SilentlyContinue -ErrorVariable readErrors)
            $rows.Count | Should -Be 2
            @($readErrors).Count | Should -Be 1
        }

        It "writes no row for a failed instance of the pipeline" {
            $readErrors = @()
            $rows = @($nativeServer, $lowServer | Get-DbaDbLogShipError -Database $dbSecondary -ErrorAction SilentlyContinue -ErrorVariable readErrors)
            $rows.Count | Should -Be 2
            @($readErrors).Count | Should -Be 1
        }
    }

    Context "Database names" {
        It "returns a database name outside the server code page" {
            $rows = @(Get-NativeOwnRow -Rows (Get-DbaDbLogShipError -SqlInstance $nativeServer) | Where-Object Message -eq "unicode")
            $rows.Count | Should -Be 1
            $rows[0].Database | Should -BeExactly $dbUnicode
        }

        It "finds a database name outside the server code page with -Database" {
            $rows = @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbUnicode)
            ($rows.Message -join "|") | Should -BeExactly "unicode"
        }
    }

    Context "Secondary databases sharing a secondary id" {
        It "lists a restore error only under the database it names" {
            (@(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbSharedA).Message -join "|") | Should -Match "restore of shared a"
            (@(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $dbSharedB).Message -join "|") | Should -Not -Match "restore of shared a"
        }

        It "lists a copy error under every database of the id" {
            foreach ($name in $dbSharedA, $dbSharedB) {
                $messages = @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $name).Message
                $messages | Should -Contain "copy of shared"
                $messages | Should -Contain "copy with no name"
            }
        }

        It "keeps an error that names no database of its id under each of them" {
            foreach ($name in $dbSharedA, $dbSharedB) {
                @(Get-DbaDbLogShipError -SqlInstance $nativeServer -Database $name).Message | Should -Contain "restore of a removed database"
            }
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Unique per leg and run: the instance is shared.
            $loginDatabase = "$($nativePrefix)login"
            $loginId = [Guid]::NewGuid().ToString()
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection
            $null = $loginServer.ConnectionContext.ExecuteNonQuery(($primarySql -f $loginId, $loginDatabase, [Guid]::NewGuid()))
            $null = $loginServer.ConnectionContext.ExecuteNonQuery(($errorSql -f $loginId, 0, 1, "N'$loginDatabase'", 1, 0, "login row"))
        }

        AfterAll {
            $null = $loginServer.ConnectionContext.ExecuteNonQuery("DELETE msdb.dbo.log_shipping_monitor_error_detail WHERE agent_id = '$loginId';")
            $null = $loginServer.ConnectionContext.ExecuteNonQuery("DELETE msdb.dbo.log_shipping_primary_databases WHERE primary_id = '$loginId';")
            $loginServer.ConnectionContext.Disconnect()
        }

        It "works with -SqlCredential" {
            $rows = @(Get-DbaDbLogShipError -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDatabase -EnableException)
            ($rows.Message -join "|") | Should -BeExactly "login row"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $rows = @(Get-DbaDbLogShipError -SqlInstance $loginInstance -Database $loginDatabase -WarningVariable loginWarnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure | *Login failed for user*"
        }

        It "throws without the credential under -EnableException, as the pinned function does" {
            # The pinned catch around Connect-DbaInstance is a Stop-Function, which throws under -EnableException.
            $thrown = $null
            try {
                $null = Get-DbaDbLogShipError -SqlInstance $loginInstance -Database $loginDatabase -EnableException
            } catch {
                $thrown = $PSItem
            }
            $thrown | Should -Not -BeNullOrEmpty
            $thrown.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbLogShipError*"
            $thrown.CategoryInfo.Category.ToString() | Should -BeExactly "ConnectionError"
        }
    }
}

Describe "Get-DbaDbLogShipError Azure refusal" -Tag IntegrationTests, NativeChecklist:azure-sqldb {
    It "refuses Azure SQL Database, which has no log shipping" {
        # Log shipping syntax and the msdb tables are absent from Azure SQL Database:
        # https://learn.microsoft.com/azure/azure-sql/database/transact-sql-tsql-differences-sql-server#t-sql-syntax-not-supported-in-azure-sql-database
        $azureServer = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $errorDetail = $PSItem.Exception
                    $resuming = $false
                    while ($errorDetail) {
                        if ($errorDetail.Number -in 40613, -2 -or $errorDetail -is [System.TimeoutException]) { $resuming = $true }
                        $errorDetail = $errorDetail.InnerException
                    }
                    if (-not $resuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            @(Get-DbaDbLogShipError -SqlInstance $azureServer -EnableException:$false -ErrorAction SilentlyContinue -WarningAction SilentlyContinue -WarningVariable azureWarnings).Count | Should -Be 0
            ($azureWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            { Get-DbaDbLogShipError -SqlInstance $azureServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
        } finally {
            if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
        }
    }
}
