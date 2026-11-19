#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbMailLog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads the Database Mail log.

Describe "Native Get-DbaDbMailLog" -Tag IntegrationTests {
    BeforeAll {
        # The legs of one SQL version share the instance: every assertion reads only the rows of this run's own marker.
        $instance = $TestConfig.InstanceSingle
        $server = Connect-DbaInstance -SqlInstance $instance -EnableException
        $marker = "dbatoolsci_nml_$(Get-Random)"
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        foreach ($eventType in 0, 1, 2, 3) {
            $null = $server.Query("INSERT INTO msdb.dbo.sysmail_log (event_type, log_date, description, process_id, mailitem_id, account_id, last_mod_date, last_mod_user) VALUES ($eventType, '2018-12-09T12:18:14.920', N'native $eventType', 4890, NULL, NULL, '2018-12-09T12:18:14.920', N'$marker');")
        }
        $ownTypes = {
            param($Rows)
            @($Rows | Where-Object Login -eq $marker | ForEach-Object { $PSItem.EventType }) -join ","
        }
    }

    AfterAll {
        $null = $server.Query("DELETE FROM msdb.dbo.sysmail_log WHERE last_mod_user = N'$marker';")
    }

    Context "Output" {
        It "returns the rows of the view with the pinned columns and values" {
            $identity = @($server.Query("SELECT SERVERPROPERTY('MachineName') AS ComputerName, ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName, SERVERPROPERTY('ServerName') AS SqlInstance;"))[0]
            $view = @($server.Query("SELECT log_id FROM msdb.dbo.sysmail_event_log WHERE last_mod_user = N'$marker' ORDER BY log_id;"))
            $result = @(Get-DbaDbMailLog -SqlInstance $instance -EnableException | Where-Object Login -eq $marker)
            $result.Count | Should -Be 4
            (@($result | ForEach-Object { $PSItem.LogId }) -join ",") | Should -BeExactly (@($view | ForEach-Object { $PSItem.log_id }) -join ",")
            (@($result | ForEach-Object { $PSItem.EventType }) -join ",") | Should -BeExactly "Success,Information,Warning,Error"
            (@($result[0].Table.Columns | ForEach-Object { $PSItem.ColumnName }) -join ",") |
                Should -BeExactly "ComputerName,InstanceName,SqlInstance,LogId,EventType,LogDate,Description,ProcessId,MailItemId,AccountId,LastModDate,LastModUser,Login"
            foreach ($row in $result) {
                $row | Should -BeOfType System.Data.DataRow
                $row.ComputerName | Should -Be $identity.ComputerName
                $row.InstanceName | Should -Be $identity.InstanceName
                $row.SqlInstance | Should -Be $identity.SqlInstance
                $row.LogDate | Should -Be ([datetime]"2018-12-09T12:18:14.920")
                $row.LastModDate | Should -Be ([datetime]"2018-12-09T12:18:14.920")
                $row.LastModUser | Should -BeExactly $marker
                $row.ProcessId | Should -Be 4890
                $row.MailItemId | Should -BeOfType System.DBNull
                $row.AccountId | Should -BeOfType System.DBNull
            }
            $result[3].Description | Should -BeExactly "native 3"
        }

        It "shows the pinned default view" {
            $row = Get-DbaDbMailLog -SqlInstance $instance -EnableException | Where-Object Login -eq $marker | Select-Object -First 1
            ($row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
                Should -BeExactly "ComputerName,InstanceName,SqlInstance,LogDate,EventType,Description,Login"
        }

        It "stops quietly when downstream takes only the first row" {
            foreach ($enableException in $false, $true) {
                $first = @(Get-DbaDbMailLog -SqlInstance $instance, $badInstance -Since "2018-12-09" -EnableException:$enableException -WarningAction SilentlyContinue | Select-Object -First 1)
                $first.Count | Should -Be 1
            }
        }

        It "reads a server object and takes the pinned positions" {
            & $ownTypes (Get-DbaDbMailLog -SqlInstance $server -EnableException) | Should -BeExactly "Success,Information,Warning,Error"
            & $ownTypes (Get-DbaDbMailLog $instance $null "2018-12-09" Warning -EnableException) | Should -BeExactly "Warning"
        }
    }

    Context "-Type" {
        It "selects each documented value, without regard to case" {
            foreach ($case in @(
                    @{ Value = "Error"; Expected = "Error" },
                    @{ Value = "Warning"; Expected = "Warning" },
                    @{ Value = "Success"; Expected = "Success" },
                    @{ Value = "Information"; Expected = "Information" },
                    @{ Value = "error"; Expected = "Error" },
                    @{ Value = "INFORMATION"; Expected = "Information" }
                )) {
                & $ownTypes (Get-DbaDbMailLog -SqlInstance $instance -Type $case.Value -EnableException) | Should -BeExactly $case.Expected
            }
            & $ownTypes (Get-DbaDbMailLog -SqlInstance $instance -Type Internal -EnableException) | Should -BeExactly ""
        }

        It "selects several values in log order, and an empty array selects all" {
            & $ownTypes (Get-DbaDbMailLog -SqlInstance $instance -Type Error, Information -EnableException) | Should -BeExactly "Information,Error"
            & $ownTypes (Get-DbaDbMailLog -SqlInstance $instance -Type @() -EnableException) | Should -BeExactly "Success,Information,Warning,Error"
        }

        It "refuses a value outside the set and a null, by the pinned validation" {
            { Get-DbaDbMailLog -SqlInstance $instance -Type Bogus } | Should -Throw -ErrorId "ParameterArgumentValidationError,*"
            { Get-DbaDbMailLog -SqlInstance $instance -Type Bogus } | Should -Throw "*The argument `"Bogus`" does not belong to the set `"Error,Warning,Success,Information,Internal`"*"
            { Get-DbaDbMailLog -SqlInstance $instance -Type "" } | Should -Throw -ErrorId "ParameterArgumentValidationError,*"
            { Get-DbaDbMailLog -SqlInstance $instance -Type $null } | Should -Throw -ErrorId "ParameterArgumentValidationError,*"
        }
    }

    Context "-Since" {
        It "keeps events on or after the value" {
            & $ownTypes (Get-DbaDbMailLog -SqlInstance $instance -Since "2018-12-09" -EnableException) | Should -BeExactly "Success,Information,Warning,Error"
            & $ownTypes (Get-DbaDbMailLog -SqlInstance $instance -Since "2018-12-09T12:18:14" -EnableException) | Should -BeExactly "Success,Information,Warning,Error"
            & $ownTypes (Get-DbaDbMailLog -SqlInstance $instance -Since "2018-12-09T12:18:15" -EnableException) | Should -BeExactly ""
            @(Get-DbaDbMailLog -SqlInstance $instance -Since "2999-01-01" -EnableException).Count | Should -Be 0
        }

        It "combines with -Type" {
            & $ownTypes (Get-DbaDbMailLog -SqlInstance $instance -Since "2018-12-09" -Type Warning -EnableException) | Should -BeExactly "Warning"
        }

        It "refuses a null and a text that is no date, by the pinned conversion" {
            { Get-DbaDbMailLog -SqlInstance $instance -Since $null } | Should -Throw "*Cannot convert null to type `"System.DateTime`"*"
            { Get-DbaDbMailLog -SqlInstance $instance -Since notadate } | Should -Throw "*Cannot convert value `"notadate`" to type `"System.DateTime`"*"
        }

        It "reports a date the engine's datetime cannot hold as a failed read" -Tag "NativeChecklist:switch-false", "NativeChecklist:enable-exception" {
            $warnings = @()
            @(Get-DbaDbMailLog -SqlInstance $instance -Since ([datetime]::MinValue) -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMailLog\] Failure \| An exception occurred while executing a Transact-SQL statement or batch\.The conversion of a varchar data type to a datetime data type resulted in an out-of-range value\.$"

            $failure = $null
            try {
                $null = Get-DbaDbMailLog -SqlInstance $instance -Since ([datetime]::MinValue) -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.Exception.Message | Should -BeLike "An exception occurred while executing a Transact-SQL statement or batch.The conversion of a varchar data type*"
            $failure.Exception.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.MethodInvocationException"
            $failure.Exception.InnerException.Message | Should -BeLike "Exception calling `"Query`" with `"1`" argument(s): *"
            $failure.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly "System.Management.Automation.RuntimeException"
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailLog*"
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
            $failure.TargetObject | Should -BeNullOrEmpty
        }
    }

    Context "The debug stream" {
        It "reports the filtered query, with the line ends of the pinned source" {
            $debugBefore = $global:DebugPreference
            try {
                $global:DebugPreference = "Continue"
                $stream = @(Get-DbaDbMailLog -SqlInstance $instance -Since "2999-01-01" -Type Error, INFORMATION -EnableException 5>&1)
            } finally {
                $global:DebugPreference = $debugBefore
            }
            $query = @($stream | Where-Object { $PSItem -is [System.Management.Automation.DebugRecord] -and $PSItem.Message -like "*sysmail_event_log*" })
            $query.Count | Should -Be 1
            $query[0].Message | Should -BeLike "*FROM msdb.dbo.sysmail_event_log WHERE log_date >= CONVERT(datetime,'2999-01-01T00:00:00',126) AND LOWER(event_type) IN ('error', 'information')"
            $query[0].Message.Contains("`r") | Should -BeFalse
            $query[0].Message.Contains("`n") | Should -BeTrue
        }
    }

    Context "Instances" {
        It "reads several instances, piped or named" -Tag "NativeChecklist:pipeline-multiple" {
            @($instance, $instance | Get-DbaDbMailLog -EnableException | Where-Object Login -eq $marker).Count | Should -Be 8
            @(Get-DbaDbMailLog -SqlInstance $instance, $instance -EnableException | Where-Object Login -eq $marker).Count | Should -Be 8
        }

        It "reads and says nothing with no instance" -Tag "NativeChecklist:enable-exception" {
            foreach ($form in @{ }, @{ SqlInstance = $null }, @{ SqlInstance = @() }) {
                $warnings = @()
                @(Get-DbaDbMailLog @form -EnableException -WarningVariable warnings).Count | Should -Be 0
                $warnings.Count | Should -Be 0
            }
            $warnings = @()
            @($null | Get-DbaDbMailLog -EnableException -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 0
        }

        It "passes a piped null in silence and reads the next record" {
            $warnings = @()
            & $ownTypes ($null, $instance | Get-DbaDbMailLog -Type Error -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings) | Should -BeExactly "Error"
            $warnings.Count | Should -Be 0
        }

        It "warns of a failed instance and reads the others" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = @()
            $result = @(Get-DbaDbMailLog -SqlInstance $instance, $badInstance, $instance -Type Error -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings | Where-Object Login -eq $marker)
            $result.Count | Should -Be 2
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMailLog\] Failure \| "
        }

        It "streams the rows before it throws for a failed instance under -EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                Get-DbaDbMailLog -SqlInstance $instance, $badInstance, $instance -Type Error -EnableException | Where-Object Login -eq $marker | ForEach-Object { $null = $streamed.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            $streamed.Count | Should -Be 1
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailLog*"
            $failure.CategoryInfo.Category | Should -Be "ConnectionError"
            $failure.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
        }

        It "warns of a null element and reads the others, and throws it under -EnableException" {
            foreach ($value in @(@($null, $instance), @($instance, $null))) {
                $warnings = @()
                & $ownTypes (Get-DbaDbMailLog -SqlInstance $value -Type Error -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings) | Should -BeExactly "Error"
                $warnings.Count | Should -Be 1
                "$($warnings[0])" | Should -Match "\[Get-DbaDbMailLog\] Failure \| Cannot bind argument to parameter 'SqlInstance' because it is null\.$"
            }

            $failure = $null
            try {
                $null = Get-DbaDbMailLog -SqlInstance @($null, $instance) -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it is null."
            $failure.Exception.InnerException | Should -BeOfType System.Management.Automation.ParameterBindingException
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbMailLog*"
            $failure.CategoryInfo.Category | Should -Be "InvalidData"
            $failure.TargetObject | Should -BeNullOrEmpty
        }
    }
}

Describe "Native Get-DbaDbMailLog over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        # sqlwhale22 is shared: the row and the login are unique per leg and run.
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        $loginMarker = "dbatoolsci_nmll_$(Get-Random)"
        $lowName = "dbatoolsci_nmlow_$(Get-Random)"
        $lowPassword = "Nml-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        $null = $loginServer.Query("INSERT INTO msdb.dbo.sysmail_log (event_type, log_date, description, process_id, mailitem_id, account_id, last_mod_date, last_mod_user) VALUES (1, '2018-12-09T12:18:14.920', N'native login', 4890, NULL, NULL, '2018-12-09T12:18:14.920', N'$loginMarker');")
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF;")
        $deniedMessage = "An exception occurred while executing a Transact-SQL statement or batch.The SELECT permission was denied on the object 'sysmail_event_log', database 'msdb', schema 'dbo'."
    }

    AfterAll {
        $null = $loginServer.Query("DELETE FROM msdb.dbo.sysmail_log WHERE last_mod_user = N'$loginMarker';")
        $null = $loginServer.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'KILL ' + CAST(session_id AS nvarchar(10)) + N';' FROM sys.dm_exec_sessions WHERE login_name = N'$lowName'; EXEC sys.sp_executesql @kill;")
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbMailLog -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException | Where-Object Login -eq $loginMarker)
            $result.Count | Should -Be 1
            $result[0].EventType | Should -BeExactly "Information"
        }

        It "warns without the credential" {
            $warnings = @()
            @(Get-DbaDbMailLog -SqlInstance $loginInstance -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbMailLog\] Failure \| Error connecting to \[.+\]: Login failed"
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            $failure = $null
            try {
                $null = Get-DbaDbMailLog -SqlInstance $loginInstance -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeLike "Login failed*"
            $failure.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "A login that cannot read the log" {
        It "warns and goes on to the next instance" {
            $warnings = @()
            @($loginInstance, $loginInstance | Get-DbaDbMailLog -SqlCredential $lowCred -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            $warnings.Count | Should -Be 2
            "$($warnings[1])" | Should -Match ("\[Get-DbaDbMailLog\] Failure \| " + [regex]::Escape($deniedMessage) + "$")
        }

        It "throws the pinned record under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaDbMailLog -SqlInstance $loginInstance -SqlCredential $lowCred -EnableException
            } catch {
                $failure = $PSItem
            }
            $failure.Exception.Message | Should -BeExactly $deniedMessage
            $failure.Exception.InnerException.Message | Should -BeExactly "Exception calling `"Query`" with `"1`" argument(s): `"$deniedMessage`""
            $failure.CategoryInfo.Category | Should -Be "NotSpecified"
        }
    }
}

Describe "Native Get-DbaDbMailLog on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
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
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001 -or $azureError.Message -like "*No such host is known*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
    }

    AfterAll {
        if ($azureServer) {
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    # msdb and Database Mail are absent from Azure SQL Database:
    # https://learn.microsoft.com/azure/azure-sql/database/features-comparison#features-of-sql-database-and-sql-managed-instance
    It "refuses Azure SQL Database, which has no Database Mail" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = @()
        @(Get-DbaDbMailLog -SqlInstance $azureServer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -BeLike "*Failure | *Azure SQL Database not supported*"
        { Get-DbaDbMailLog -SqlInstance $azureServer -EnableException } | Should -Throw "*Azure SQL Database not supported*"
    }
}
