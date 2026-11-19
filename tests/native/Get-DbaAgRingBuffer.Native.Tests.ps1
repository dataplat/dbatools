#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaAgRingBuffer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned function declares no SupportsShouldProcess and changes nothing; it only reads sys.dm_os_sys_info and sys.dm_os_ring_buffers.
# NativeMock: "Get-DbaAgRingBuffer.Query handling.uses the scalar timestamp value when building the HADR ring buffer query" -- covered: "Native Get-DbaAgRingBuffer.Query text.builds the HADR ring buffer query from the scalar timestamp"
# NativeMock: "Get-DbaAgRingBuffer.Query handling.routes HADR ring buffer query failures through Stop-Function" -- covered: "Native Get-DbaAgRingBuffer.A query that fails.warns with the pinned message and the ring buffer query's error" and "Native Get-DbaAgRingBuffer.A query that fails.throws the server's error under -EnableException with the pinned category and target"

Describe "Native Get-DbaAgRingBuffer" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $missingHost = "dbatoolsci-nohost-$random"
        $ringBufferTypes = @("RING_BUFFER_HADRDBMGR_API", "RING_BUFFER_HADRDBMGR_STATE", "RING_BUFFER_HADRDBMGR_COMMIT", "RING_BUFFER_HADR_TRANSPORT_STATE")
        $outputProperties = @("ComputerName", "InstanceName", "SqlInstance", "RingBufferType", "RecordId", "EventTime", "Record")
    }

    Context "Rows" {
        It "returns only HADR ring buffer rows with the pinned properties in order" {
            $results = @(Get-DbaAgRingBuffer -SqlInstance $instance -EnableException)
            foreach ($result in $results) {
                @($result.PSObject.Properties.Name) | Should -Be $outputProperties
                $result.RingBufferType | Should -BeIn $ringBufferTypes
                $result.SqlInstance | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context "Query text" {
        It "builds the HADR ring buffer query from the scalar timestamp" {
            $streams = @(Get-DbaAgRingBuffer -SqlInstance $instance -RingBufferType RING_BUFFER_HADRDBMGR_API, RING_BUFFER_HADR_TRANSPORT_STATE -CollectionMinutes 15 -EnableException -Verbose 4>&1)
            $messages = @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            $timestampMessage = @($messages | Where-Object { $PSItem -match "Using current timestamp of (\d+)" })
            $timestampMessage.Count | Should -Be 1
            $null = $timestampMessage[0] -match "Using current timestamp of (\d+)"
            $timestamp = $Matches[1]
            $sqlMessage = @($messages | Where-Object { $PSItem -like "*Executing SQL Statement:*" })
            $sqlMessage.Count | Should -Be 1
            $sqlMessage[0] | Should -Match ("DATEADD\(ms, -1 \* \(" + $timestamp + " - \[timestamp\]\), GETDATE\(\)\)")
            $sqlMessage[0] | Should -Not -Match "System\.Data\.DataRow"
            $sqlMessage[0] | Should -Match "WHERE ring_buffer_type IN \(N'RING_BUFFER_HADRDBMGR_API', N'RING_BUFFER_HADR_TRANSPORT_STATE'\)"
            $sqlMessage[0] | Should -Match "DATEADD\(MINUTE, -15, GETDATE\(\)\)"
        }

        It "queries all four HADR ring buffer types by default" {
            $streams = @(Get-DbaAgRingBuffer -SqlInstance $instance -EnableException -Verbose 4>&1)
            $sqlMessage = @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Executing SQL Statement:*" })
            $sqlMessage.Count | Should -Be 1
            $sqlMessage[0].Message | Should -Match "WHERE ring_buffer_type IN \(N'RING_BUFFER_HADRDBMGR_API', N'RING_BUFFER_HADRDBMGR_STATE', N'RING_BUFFER_HADRDBMGR_COMMIT', N'RING_BUFFER_HADR_TRANSPORT_STATE'\)"
            $sqlMessage[0].Message | Should -Match "DATEADD\(MINUTE, -60, GETDATE\(\)\)"
        }

        It "filters by -RingBufferType" {
            $results = @(Get-DbaAgRingBuffer -SqlInstance $instance -RingBufferType RING_BUFFER_HADR_TRANSPORT_STATE -EnableException)
            foreach ($result in $results) {
                $result.RingBufferType | Should -BeExactly "RING_BUFFER_HADR_TRANSPORT_STATE"
            }
        }
    }

    Context "Pipeline input" -Tag NativeChecklist:pipeline-multiple {
        It "queries every piped instance" {
            $streams = @($instance, $instance | Get-DbaAgRingBuffer -RingBufferType RING_BUFFER_HADRDBMGR_API -EnableException -Verbose 4>&1)
            @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Executing SQL Statement:*" }).Count | Should -Be 2
        }
    }

    Context "An instance that cannot be reached" -Tag NativeChecklist:multi-instance-failure {
        It "warns for that instance and still queries the other" {
            $reachWarnings = @()
            $streams = @(Get-DbaAgRingBuffer -SqlInstance $missingHost, $instance -RingBufferType RING_BUFFER_HADRDBMGR_API -WarningVariable reachWarnings -WarningAction SilentlyContinue -Verbose 4>&1)
            @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Executing SQL Statement:*" }).Count | Should -Be 1
            $reachWarnings.Count | Should -Be 1
            "$reachWarnings" | Should -BeLike "*Failure*"
        }

        It "throws for that instance under -EnableException" -Tag NativeChecklist:enable-exception {
            $reachCaught = $null
            try {
                $null = Get-DbaAgRingBuffer -SqlInstance $missingHost -EnableException
            } catch {
                $reachCaught = $PSItem
            }
            $reachCaught | Should -Not -BeNullOrEmpty
            $reachCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }

        It "only warns for -EnableException:`$false" -Tag NativeChecklist:switch-false {
            { $null = Get-DbaAgRingBuffer -SqlInstance $missingHost -EnableException:$false -WarningAction SilentlyContinue } | Should -Not -Throw
            # The warning is captured outside the scriptblock: -WarningVariable sets the variable in the scope that runs the command.
            $falseWarnings = @()
            $null = Get-DbaAgRingBuffer -SqlInstance $missingHost -EnableException:$false -WarningVariable falseWarnings -WarningAction SilentlyContinue
            "$falseWarnings" | Should -BeLike "*Failure*"
        }
    }

    Context "A query that fails" {
        BeforeAll {
            # The pinned :72 answers the timestamp query and fails the later ring buffer query. A uniquely named login
            # (lane-safe) on the shared SQL-login instance gets VIEW SERVER STATE, so the sys.dm_os_sys_info timestamp
            # query succeeds, and a user in master denied SELECT on sys.dm_os_ring_buffers, so the ring buffer query
            # fails with the server's permission error (Microsoft Learn, "System dynamic management views and
            # functions", Permissions: a DENY to a user in master blocks the object in every database context).
            # AfterAll removes the user and the login even when a test fails.
            $loginInstance = $TestConfig.InstanceSqlLogin
            $adminServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $weakLogin = "dbatoolsci_agrb_deny_" + [Guid]::NewGuid().ToString("N").Substring(0, 12)
            $weakPassword = "Aa1!" + [Guid]::NewGuid().ToString("N")
            $adminServer.ConnectionContext.ExecuteNonQuery("CREATE LOGIN [$weakLogin] WITH PASSWORD = N'$weakPassword', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;")
            $adminServer.ConnectionContext.ExecuteNonQuery("GRANT VIEW SERVER STATE TO [$weakLogin];")
            $adminServer.Databases["master"].ExecuteNonQuery("CREATE USER [$weakLogin] FOR LOGIN [$weakLogin]; DENY SELECT ON sys.dm_os_ring_buffers TO [$weakLogin];")
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

        It "warns with the pinned message and the ring buffer query's error" {
            $failWarnings = @()
            $streams = @(Get-DbaAgRingBuffer -SqlInstance $loginInstance -SqlCredential $weakCred -WarningVariable failWarnings -WarningAction SilentlyContinue -Verbose 4>&1)
            $messages = @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($streams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            # The timestamp query succeeded and the ring buffer query ran.
            @($messages | Where-Object { $PSItem -match "Using current timestamp of \d+" }).Count | Should -Be 1
            @($messages | Where-Object { $PSItem -like "*Executing SQL Statement:*sys.dm_os_ring_buffers*" }).Count | Should -Be 1
            $failWarnings.Count | Should -Be 1
            "$failWarnings" | Should -BeLike "*Failed to query HADR ring buffer data.*"
            "$failWarnings" | Should -BeLike "*permission was denied*dm_os_ring_buffers*"
        }

        It "throws the server's error under -EnableException with the pinned category and target" {
            # Under -EnableException Stop-Function throws the query's own record: its exception carries the query
            # error (the pinned message goes only to the suppressed warning, asserted above), the pinned category
            # InvalidOperation and the instance as target.
            $failStreams = New-Object System.Collections.Generic.List[object]
            $failCaught = $null
            try {
                Get-DbaAgRingBuffer -SqlInstance $loginInstance -SqlCredential $weakCred -EnableException -Verbose 4>&1 | ForEach-Object { $failStreams.Add($PSItem) }
            } catch {
                $failCaught = $PSItem
            }
            $failMessages = @($failStreams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($failStreams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            @($failMessages | Where-Object { $PSItem -match "Using current timestamp of \d+" }).Count | Should -Be 1
            @($failMessages | Where-Object { $PSItem -like "*Executing SQL Statement:*sys.dm_os_ring_buffers*" }).Count | Should -Be 1
            $failCaught | Should -Not -BeNullOrEmpty
            $failCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaAgRingBuffer*"
            $failCaught.CategoryInfo.Category | Should -Be "InvalidOperation"
            "$($failCaught.TargetObject)" | Should -BeLike "*$loginInstance*"
            $failureText = @()
            $failure = $failCaught.Exception
            while ($failure) {
                $failureText += $failure.Message
                $failure = $failure.InnerException
            }
            ($failureText -join " ") | Should -BeLike "*Exception calling `"Query`"*permission was denied*dm_os_ring_buffers*"
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $sqlLoginCred = $TestConfig.SqlLoginCred
        }

        # The missing-credential assertions follow the pinned code quoted below instead of a -Baseline run
        # (watchman 49f13ebb): no commit can run the pinned function, because the base 12b2d4ca0 already ships the
        # compiled Get-DbaAgRingBuffer cmdlet and the pin predates src/ and cannot be built.
        #
        # refs/pins/dbatools-2026-10-22:public/Get-DbaAgRingBuffer.ps1:110-115
        #         foreach ($instance in $SqlInstance) {
        #             try {
        #                 $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
        #             } catch {
        #                 Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #             }
        #
        # Without the credential the connect fails and Stop-Function -Continue warns "Failure" and moves on; under
        # -EnableException the same Stop-Function throws with category ConnectionError.
        It "works with -SqlCredential" {
            $loginWarnings = @()
            $streams = @(Get-DbaAgRingBuffer -SqlInstance $loginInstance -SqlCredential $sqlLoginCred -RingBufferType RING_BUFFER_HADRDBMGR_API -EnableException -WarningVariable loginWarnings -Verbose 4>&1)
            @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Executing SQL Statement:*" }).Count | Should -Be 1
            $loginWarnings.Count | Should -Be 0
        }

        It "fails cleanly without the credential: a warning and no output" {
            $noLoginWarnings = @()
            $results = @(Get-DbaAgRingBuffer -SqlInstance $loginInstance -WarningVariable noLoginWarnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 0
            ($noLoginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential under -EnableException, as the pinned Stop-Function does" {
            $noLoginCaught = $null
            try {
                $null = Get-DbaAgRingBuffer -SqlInstance $loginInstance -EnableException
            } catch {
                $noLoginCaught = $PSItem
            }
            $noLoginCaught | Should -Not -BeNullOrEmpty
            $noLoginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}

Describe "Native Get-DbaAgRingBuffer on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; the command under test runs once per test.
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
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) { $azureServer.ConnectionContext.Disconnect() }
    }

    # Microsoft Learn lists sys.dm_os_ring_buffers and sys.dm_os_sys_info for Azure SQL Database (server admin or
    # the server-state reader role), so the command runs there; it reads only, so the shared database is unchanged.
    It "queries the HADR ring buffers of Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureWarnings = @()
        $streams = @(Get-DbaAgRingBuffer -SqlInstance $azureServer -EnableException -WarningVariable azureWarnings -Verbose 4>&1)
        @($streams | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*Executing SQL Statement:*" }).Count | Should -Be 1
        $azureWarnings.Count | Should -Be 0
        foreach ($result in @($streams | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] })) {
            $result.RingBufferType | Should -BeIn @("RING_BUFFER_HADRDBMGR_API", "RING_BUFFER_HADRDBMGR_STATE", "RING_BUFFER_HADRDBMGR_COMMIT", "RING_BUFFER_HADR_TRANSPORT_STATE")
        }
    }
}
