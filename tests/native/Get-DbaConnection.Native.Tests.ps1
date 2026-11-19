#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaConnection",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads sys.dm_exec_connections.

Describe "Get-DbaConnection native" -Tag IntegrationTests {
    BeforeAll {
        $connectionColumns = @(
            "ComputerName", "InstanceName", "SqlInstance", "SessionId", "MostRecentSessionId",
            "ConnectTime", "Transport", "ProtocolType", "ProtocolVersion", "EndpointId",
            "EncryptOption", "AuthScheme", "NodeAffinity", "Reads", "Writes", "LastRead", "LastWrite",
            "PacketSize", "ClientNetworkAddress", "ClientTcpPort", "ServerNetworkAddress", "ServerTcpPort",
            "ConnectionId", "ParentConnectionId", "MostRecentSqlHandle"
        )
        # An endpoint nothing listens on: the connect fails at once.
        $badInstance = "TCP:127.0.0.1,1"

        function Get-NativeOwnSession {
            param($Server)
            $Server.ConnectionContext.ExecuteWithResults("SELECT @@SPID AS SessionId").Tables[0].Rows[0].SessionId
        }
    }

    Context "Connection rows" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "returns the query's DataRows with the pinned columns in order, the caller's own connection among them" {
            $ownSession = Get-NativeOwnSession -Server $server
            $rows = @(Get-DbaConnection -SqlInstance $server -EnableException)
            (Get-NativeOwnSession -Server $server) | Should -Be $ownSession
            $rows.Count | Should -BeGreaterThan 0
            foreach ($row in $rows) {
                $row | Should -BeOfType System.Data.DataRow
                (@($row.Table.Columns.ColumnName) -join ",") | Should -BeExactly ($connectionColumns -join ",")
            }
            $rows[0].Table.Columns["SessionId"].DataType | Should -Be ([int])
            $rows[0].Table.Columns["ConnectTime"].DataType | Should -Be ([datetime])
            $rows[0].Table.Columns["ConnectionId"].DataType | Should -Be ([guid])
            $rows[0].Table.Columns["MostRecentSqlHandle"].DataType | Should -Be ([byte[]])
            $ownRows = @($rows | Where-Object SessionId -eq $ownSession)
            $ownRows.Count | Should -Be 1
            $ownRows[0].AuthScheme | Should -BeIn "NTLM", "Kerberos"
            $ownRows[0].InstanceName | Should -Not -BeNullOrEmpty
        }

        It "queries every instance in an array and every piped instance, in order" -Tag NativeChecklist:pipeline-multiple {
            $ownSession = Get-NativeOwnSession -Server $server
            $arrayRows = @(Get-DbaConnection -SqlInstance @($server, $server) -EnableException)
            @($arrayRows | Where-Object SessionId -eq $ownSession).Count | Should -Be 2
            $pipedRows = @(@($server, $server) | Get-DbaConnection -EnableException)
            @($pipedRows | Where-Object SessionId -eq $ownSession).Count | Should -Be 2
            (Get-NativeOwnSession -Server $server) | Should -Be $ownSession
        }
    }

    Context "Connect failures" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        }

        It "warns 'Failure' for an instance it cannot connect to and still queries the next one" -Tag NativeChecklist:multi-instance-failure {
            $ownSession = Get-NativeOwnSession -Server $server
            $connectWarnings = @()
            $rows = @(Get-DbaConnection -SqlInstance $badInstance, $server -WarningVariable connectWarnings -WarningAction SilentlyContinue)
            $connectWarnings.Count | Should -Be 1
            "$connectWarnings" | Should -BeLike "*Failure*"
            @($rows | Where-Object SessionId -eq $ownSession).Count | Should -Be 1
        }

        It "stops at the instance it cannot connect to under -EnableException, with category ConnectionError" -Tag NativeChecklist:enable-exception {
            $seen = New-Object System.Collections.ArrayList
            $connectCaught = $null
            try {
                Get-DbaConnection -SqlInstance $badInstance, $server -EnableException | ForEach-Object { $null = $seen.Add($PSItem) }
            } catch {
                $connectCaught = $PSItem
            }
            $connectCaught | Should -Not -BeNullOrEmpty
            $connectCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaConnection*"
            $connectCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $seen.Count | Should -Be 0
        }

        It "warns and moves on for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            $ownSession = Get-NativeOwnSession -Server $server
            $falseWarnings = @()
            $rows = @(Get-DbaConnection -SqlInstance $badInstance, $server -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue)
            $falseWarnings.Count | Should -Be 1
            @($rows | Where-Object SessionId -eq $ownSession).Count | Should -Be 1
        }
    }

    Context "A query that fails" {
        BeforeAll {
            # A uniquely named login (lane-safe) on the shared SQL-login instance with no server state permission and a
            # user in master denied SELECT on sys.dm_exec_connections, so the connect succeeds and the query fails with
            # the server's permission error (Microsoft Learn, "System dynamic management views and functions",
            # Permissions: a DENY to a user in master blocks the object in every database context).
            # AfterAll removes the user and the login even when a test fails.
            $loginInstance = $TestConfig.InstanceSqlLogin
            $adminServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $weakLogin = "dbatoolsci_cnx_deny_" + [Guid]::NewGuid().ToString("N").Substring(0, 12)
            $weakPassword = "Aa1!" + [Guid]::NewGuid().ToString("N")
            $adminServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$weakLogin] WITH PASSWORD = N'$weakPassword', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;")
            $adminServer.Databases["master"].ExecuteNonQuery("CREATE USER [$weakLogin] FOR LOGIN [$weakLogin]; DENY SELECT ON sys.dm_exec_connections TO [$weakLogin];")
            $weakCred = New-Object System.Management.Automation.PSCredential($weakLogin, (ConvertTo-SecureString -String $weakPassword -AsPlainText -Force))
        }

        AfterAll {
            $dropServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $TestConfig.SqlLoginCred -NonPooledConnection -EnableException
            try {
                # Pooled sessions of the weak login would block DROP LOGIN; the name is unique to this run.
                $dropServer.ConnectionContext.ExecuteNonQuery("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CONVERT(nvarchar(10), session_id) + N'; ' FROM sys.dm_exec_sessions WHERE login_name = N'$weakLogin' AND session_id <> @@SPID; EXEC (@kill);")
            } finally {
                try {
                    $dropServer.Databases["master"].ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$weakLogin') DROP USER [$weakLogin];")
                } finally {
                    $dropServer.ConnectionContext.ExecuteNonQuery("IF EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'$weakLogin') DROP LOGIN [$weakLogin];")
                    $dropServer.ConnectionContext.Disconnect()
                }
            }
        }

        It "has a fixture login that connects but cannot read sys.dm_exec_connections" {
            $weakServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $weakCred -NonPooledConnection -EnableException
            try {
                $weakServer.ConnectionContext.ExecuteScalar("SELECT 1") | Should -Be 1
                { $weakServer.ConnectionContext.ExecuteWithResults("SELECT session_id FROM sys.dm_exec_connections") } | Should -Throw
            } finally {
                $weakServer.ConnectionContext.Disconnect()
            }
        }

        It "warns 'Failure' with the server's permission error for each instance whose query fails, and moves on" {
            $queryWarnings = @()
            $rows = @(Get-DbaConnection -SqlInstance $loginInstance, $loginInstance -SqlCredential $weakCred -WarningVariable queryWarnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            $queryWarnings.Count | Should -Be 2
            foreach ($queryWarning in $queryWarnings) {
                "$queryWarning" | Should -BeLike "*Failure*"
                "$queryWarning" | Should -BeLike "*permission was denied*"
            }
        }

        It "throws the query's failure under -EnableException, as its Stop-Function does" {
            $queryCaught = $null
            try {
                $null = Get-DbaConnection -SqlInstance $loginInstance -SqlCredential $weakCred -EnableException
            } catch {
                $queryCaught = $PSItem
            }
            $queryCaught | Should -Not -BeNullOrEmpty
            $queryCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaConnection*"
            $failureText = @()
            $failure = $queryCaught.Exception
            while ($failure) {
                $failureText += $failure.Message
                $failure = $failure.InnerException
            }
            ($failureText -join " ") | Should -BeLike "*Exception calling `"Query`"*permission was denied*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb): no commit can run the pinned function, because the base already ships the compiled
        # Get-DbaConnection cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaConnection.ps1:98-103
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        # Without the credential the connect fails and Stop-Function -Continue warns "Failure" and moves on; under
        # -EnableException the same Stop-Function throws with category ConnectionError.
        It "works with -SqlCredential, its own connection authenticated by SQL" {
            $loginWarnings = @()
            $rows = @(Get-DbaConnection -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -EnableException -WarningVariable loginWarnings)
            $loginWarnings.Count | Should -Be 0
            $rows.Count | Should -BeGreaterThan 0
            @($rows | Where-Object AuthScheme -eq "SQL").Count | Should -BeGreaterThan 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $rows = @(Get-DbaConnection -SqlInstance $loginInstance -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $rows.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $noLoginCaught = $null
            try {
                $null = Get-DbaConnection -SqlInstance $loginInstance -EnableException
            } catch {
                $noLoginCaught = $PSItem
            }
            $noLoginCaught | Should -Not -BeNullOrEmpty
            $noLoginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "Azure SQL Database" {
        It "returns the connections of an Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
            $splatAzureConnection = @{
                SqlInstance     = $TestConfig.AzureSqlDbServer
                Database        = $TestConfig.AzureSqlDbName
                SqlCredential   = $TestConfig.AzureSqlDbCred
                EnableException = $true
            }
            $azureServer = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureServer = Connect-DbaInstance @splatAzureConnection
                    $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
                    break
                } catch {
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            try {
                $rows = @(Get-DbaConnection -SqlInstance $azureServer -EnableException)
                $rows.Count | Should -BeGreaterThan 0
                (@($rows[0].Table.Columns.ColumnName) -join ",") | Should -BeExactly ($connectionColumns -join ",")
                @($rows | Where-Object AuthScheme -eq "SQL").Count | Should -BeGreaterThan 0
            } finally {
                $azureServer.ConnectionContext.Disconnect()
            }
        }
    }
}
