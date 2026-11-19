#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaInstanceAudit",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaInstanceAudit" -Tag IntegrationTests {
    BeforeAll {
        $auditServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $auditTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $auditFile = "dbatoolsci_ia_${auditTag}_a"
        $auditApp = "dbatoolsci_ia_${auditTag}_b"
        $auditMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        # A folder that exists on the instance's host, with a trailing backslash for the pin's TrimEnd. The audits stay
        # disabled, so no audit file is ever written there.
        $auditFolder = $auditServer.ErrorLogPath.TrimEnd("\") + "\"
        $null = $auditServer.Query("CREATE SERVER AUDIT [$auditFile] TO FILE (FILEPATH = N'$auditFolder', MAXSIZE = 10 MB, MAX_ROLLOVER_FILES = 1, RESERVE_DISK_SPACE = OFF) WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)")
        $null = $auditServer.Query("CREATE SERVER AUDIT [$auditApp] TO APPLICATION_LOG WITH (ON_FAILURE = CONTINUE)")

        # Independent reads: the catalog views name both audits and give only the FILE audit a file row; the pin's
        # FullName is built from the SMO FilePath and FileName of the audit, read here on the test's own connection.
        $catalogSql = "SELECT a.name, f.log_file_path FROM sys.server_audits AS a LEFT JOIN sys.server_file_audits AS f ON f.audit_id = a.audit_id WHERE a.name IN (N'$auditFile', N'$auditApp')"
        $auditCatalog = @($auditServer.Query($catalogSql))
        $auditServer.Audits.Refresh()
        $auditComputer = $auditServer.ComputerName

        function Get-NativeAuditExpectedName {
            param([string]$Name)
            $smo = $auditServer.Audits[$Name]
            "$(([string]$smo.FilePath).TrimEnd("\"))\$($smo.FileName)"
        }
    }

    AfterAll {
        foreach ($name in $auditFile, $auditApp) {
            $null = $auditServer.Query("IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$name') DROP SERVER AUDIT [$name]")
        }
    }

    It "returns the named audits decorated as the pin decorates them" {
        $auditCatalog.Count | Should -Be 2
        ($auditCatalog | Where-Object name -eq $auditFile).log_file_path | Should -Not -BeOfType [System.DBNull]
        ($auditCatalog | Where-Object name -eq $auditApp).log_file_path | Should -BeOfType [System.DBNull]
        $results = @(Get-DbaInstanceAudit -SqlInstance $TestConfig.InstanceSingle -Audit $auditFile, $auditApp -ErrorVariable auditErrors)
        $auditErrors | Should -BeNullOrEmpty
        @($results.Name | Sort-Object) -join "," | Should -BeExactly (@($auditFile, $auditApp) -join ",")
        foreach ($result in $results) {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Audit]
            $result.ComputerName | Should -BeExactly $auditServer.ComputerName
            $result.InstanceName | Should -BeExactly $auditServer.ServiceName
            $result.SqlInstance | Should -BeExactly $auditServer.DomainInstanceName
            $result.IsEnabled | Should -Be $false
            $result.IsEnabled | Should -Be $result.Enabled
            $expected = Get-NativeAuditExpectedName -Name $result.Name
            $result.FullName | Should -BeExactly $expected
            $result.RemoteFullName | Should -BeExactly ("\\$auditComputer\" + $expected.Replace(":", "$"))
            $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,IsEnabled,OnFailure,MaximumFiles,MaximumFileSize,MaximumFileSizeUnit,MaximumRolloverFiles,QueueDelay,ReserveDiskSpace,FullName"
        }
        $file = $results | Where-Object Name -eq $auditFile
        $file.FullName | Should -Not -BeLike '*\\*'
        $file.FullName | Should -BeLike "$($auditFolder.TrimEnd("\"))\*"
    }

    It "matches -Audit and -ExcludeAudit names ignoring case, and returns every audit without them" {
        $upper = @(Get-DbaInstanceAudit -SqlInstance $TestConfig.InstanceSingle -Audit $auditFile.ToUpperInvariant())
        $upper.Name | Should -BeExactly $auditFile

        $excluded = @(Get-DbaInstanceAudit -SqlInstance $TestConfig.InstanceSingle -Audit $auditFile, $auditApp -ExcludeAudit $auditFile.ToUpperInvariant())
        $excluded.Name | Should -BeExactly $auditApp

        # The other PowerShell edition's lane may add or drop its own audits on this instance meanwhile, so the catalog is
        # read before and after: every name in both reads comes back, and nothing outside them does.
        $catalogAll = @($auditServer.Query("SELECT name FROM sys.server_audits").name)
        $all = @(Get-DbaInstanceAudit -SqlInstance $TestConfig.InstanceSingle)
        $catalogAfter = @($auditServer.Query("SELECT name FROM sys.server_audits").name)
        @($catalogAll | Where-Object { $PSItem -in $catalogAfter -and $PSItem -notin $all.Name }) | Should -BeNullOrEmpty
        @($all.Name | Where-Object { $PSItem -notin $catalogAll -and $PSItem -notin $catalogAfter }) | Should -BeNullOrEmpty
        @($all.Name | Select-Object -Unique).Count | Should -Be $all.Count
        @($all | Where-Object Name -in $auditFile, $auditApp).Count | Should -Be 2

        @(Get-DbaInstanceAudit -SqlInstance $TestConfig.InstanceSingle -Audit $auditMissing).Count | Should -Be 0
    }

    It "decorates the same audit again when it is listed twice" {
        $first = Get-DbaInstanceAudit -SqlInstance $auditServer -Audit $auditFile
        $second = Get-DbaInstanceAudit -SqlInstance $auditServer -Audit $auditFile
        $second.FullName | Should -BeExactly $first.FullName
        @($second.PSObject.Properties | Where-Object Name -eq "FullName").Count | Should -Be 1
    }

    It "returns the audits of each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $warnings = @()
        $results = @(@($TestConfig.InstanceSingle, $auditMissing, $TestConfig.InstanceSingle) | Get-DbaInstanceAudit -Audit $auditFile -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $results.Count | Should -Be 2
        @($results.Name | Select-Object -Unique) | Should -BeExactly $auditFile
        $warnings.Count | Should -Be 1
        # One line naming the command, the failure message and the instance (brackets matched literally).
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceAudit] Failure | Error connecting to [$auditMissing]: "))
    }

    It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        { Get-DbaInstanceAudit -SqlInstance $auditMissing -EnableException -WarningAction SilentlyContinue } | Should -Throw
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginAudit = "dbatoolsci_ialogin_" + [guid]::NewGuid().ToString("N").Substring(0, 10)
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $null = $loginServer.Query("CREATE SERVER AUDIT [$loginAudit] TO APPLICATION_LOG WITH (ON_FAILURE = CONTINUE)")
        }

        AfterAll {
            $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$loginAudit') DROP SERVER AUDIT [$loginAudit]")
        }

        It "works with -SqlCredential" {
            $result = Get-DbaInstanceAudit -SqlInstance $loginInstance -SqlCredential $loginCred -Audit $loginAudit -EnableException
            $result.Name | Should -BeExactly $loginAudit
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaInstanceAudit -SqlInstance $loginInstance -Audit $loginAudit -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaInstanceAudit -SqlInstance $loginInstance -Audit $loginAudit -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    # The one statement fault of the pin, the read of $server.Audits, sits in no try. A SQL login whose master user is denied
    # SELECT on sys.server_audits connects, then that read fails. Measured on the pin on both editions (probe enum-fault,
    # evidence/pin-enumfault-b28d1bfe-20261105.txt): a plain call writes ExceptionInGetEnumerator over SMO's
    # ExecutionFailureException and goes on; a caller's try catches it; -ErrorAction Stop stops there. The login lives on
    # the shared SQL-login instance under a unique name and is dropped in AfterAll.
    Context "An audit read denied after a successful connection" {
        BeforeAll {
            $deniedInstance = $TestConfig.InstanceSqlLogin
            $deniedAdmin = Connect-DbaInstance -SqlInstance $deniedInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $deniedName = "dbatoolsci_iadeny_" + [guid]::NewGuid().ToString("N").Substring(0, 10)
            $deniedPassword = "P@ss" + [guid]::NewGuid().ToString("N") + "!"
            $deniedCred = New-Object System.Management.Automation.PSCredential -ArgumentList $deniedName, (ConvertTo-SecureString -String $deniedPassword -AsPlainText -Force)
            $null = $deniedAdmin.Query("USE [master]; CREATE LOGIN [$deniedName] WITH PASSWORD = N'$deniedPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master]; CREATE USER [$deniedName] FOR LOGIN [$deniedName]; DENY SELECT ON sys.server_audits TO [$deniedName];")
            $deniedCallers = New-Object System.Collections.ArrayList

            function New-NativeDeniedCaller {
                $caller = Connect-DbaInstance -SqlInstance $deniedInstance -SqlCredential $deniedCred -NonPooledConnection -EnableException
                $null = $deniedCallers.Add($caller)
                return $caller
            }

            # Independent read: the engine's own enumeration of the denied collection gives the record the command must write.
            $deniedFault = $null
            $referenceCaller = New-NativeDeniedCaller
            try {
                foreach ($deniedAudit in $referenceCaller.Audits) { }
            } catch {
                $deniedFault = $PSItem
            }

            function Assert-NativeAuditFault {
                param($Record)
                $Record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
                $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
                $Record.Exception.GetType().FullName | Should -BeExactly $deniedFault.Exception.GetType().FullName
                $Record.Exception.Message | Should -BeExactly $deniedFault.Exception.Message
                $Record.Exception.Message | Should -BeExactly 'The following exception occurred while trying to enumerate the collection: "An exception occurred while executing a Transact-SQL statement or batch.".'
                $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeAuditCall {
                param([hashtable]$Arguments, [string]$Script = 'param($Arguments) Get-DbaInstanceAudit @Arguments | ForEach-Object { "row: " + $PSItem.Name }; "next statement"')
                $callState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $callType = (Get-Command Get-DbaInstanceAudit -CommandType Cmdlet).ImplementingType
                $callEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaInstanceAudit", $callType, $null
                $callState.Commands.Add($callEntry)
                $callRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($callState)
                $callShell = [System.Management.Automation.PowerShell]::Create()
                $callOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $callStop = $null
                try {
                    $callRunspace.Open()
                    $callShell.Runspace = $callRunspace
                    $null = $callShell.AddScript($Script).AddArgument($Arguments)
                    try {
                        $null = $callShell.Invoke($null, $callOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $callStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output = @($callOutput | ForEach-Object { "$PSItem" })
                        Errors = @($callShell.Streams.Error)
                        Stop   = $callStop
                    }
                } finally {
                    $callShell.Dispose()
                    $callRunspace.Dispose()
                }
            }
        }

        AfterAll {
            foreach ($caller in $deniedCallers) {
                try {
                    $caller.ConnectionContext.Disconnect()
                } catch {
                    # A caller may already be closed; the KILL below ends what is left.
                }
            }
            # Each KILL has its own TRY: a session may end between the SELECT and its KILL.
            $null = $deniedAdmin.Query("DECLARE @kill nvarchar(max) = N''; SELECT @kill += N'BEGIN TRY KILL ' + CAST(session_id AS nvarchar(10)) + N'; END TRY BEGIN CATCH END CATCH; ' FROM sys.dm_exec_sessions WHERE login_name = N'$deniedName'; EXEC sys.sp_executesql @kill;")
            $null = $deniedAdmin.Query("USE [master]; IF DATABASE_PRINCIPAL_ID(N'$deniedName') IS NOT NULL DROP USER [$deniedName]; IF SUSER_ID(N'$deniedName') IS NOT NULL DROP LOGIN [$deniedName];")
        }

        It "writes the record the denied read gives and goes on to the next instance" {
            $deniedFault | Should -Not -BeNullOrEmpty
            $call = Invoke-NativeAuditCall -Arguments @{ SqlInstance = @((New-NativeDeniedCaller), $auditServer) }
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 1
            Assert-NativeAuditFault -Record $call.Errors[0]
            $call.Output | Should -Contain "row: $auditFile"
            $call.Output | Should -Contain "row: $auditApp"
            $call.Output[-1] | Should -BeExactly "next statement"
        }

        # The pin's $audits | Where-Object fails the same way and leaves $audits the collection, so its foreach reads it again.
        It "writes it again for the filter, whose read faults first" {
            $call = Invoke-NativeAuditCall -Arguments @{ SqlInstance = @((New-NativeDeniedCaller), $auditServer); Audit = $auditFile }
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 2
            Assert-NativeAuditFault -Record $call.Errors[0]
            Assert-NativeAuditFault -Record $call.Errors[1]
            ($call.Output -join ",") | Should -BeExactly "row: $auditFile,next statement"
        }

        It "lets a caller's try catch it, and the command does not go on" {
            $script = 'param($Arguments) try { Get-DbaInstanceAudit @Arguments | ForEach-Object { "row: " + $PSItem.Name }; "after the call" } catch { "caught: " + $PSItem.FullyQualifiedErrorId }; "next statement"'
            $call = Invoke-NativeAuditCall -Arguments @{ SqlInstance = @((New-NativeDeniedCaller), $auditServer); Audit = $auditFile } -Script $script
            $call.Stop | Should -BeNullOrEmpty
            $call.Output.Count | Should -Be 2
            $call.Output[0] | Should -BeLike "caught: ExceptionInGetEnumerator,*"
            $call.Output[1] | Should -BeExactly "next statement"
        }

        # Keep-going rule: -EnableException stops at the record (corrections.json, acceptedDifferences statement-fault-records).
        It "stops at the record under -EnableException, and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $call = Invoke-NativeAuditCall -Arguments @{ SqlInstance = @((New-NativeDeniedCaller), $auditServer); Audit = $auditFile; EnableException = $true }
            $call.Stop | Should -BeNullOrEmpty
            $call.Errors.Count | Should -Be 1
            Assert-NativeAuditFault -Record $call.Errors[0]
            ($call.Output -join ",") | Should -BeExactly "next statement"
        }

        # Outside any try, -ErrorAction Stop has the effect PowerShell gives the record a compiled command writes: the script stops there.
        It "turns the record into the stop -ErrorAction Stop gives, outside any try" {
            $call = Invoke-NativeAuditCall -Arguments @{ SqlInstance = @((New-NativeDeniedCaller), $auditServer); Audit = $auditFile; ErrorAction = "Stop" }
            $call.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeAuditFault -Record $call.Stop.ErrorRecord
            $call.Output | Should -Not -Contain "next statement"
            $call.Output | Should -Not -Contain "row: $auditFile"
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # Server audits do not exist in Azure SQL Database: sys.server_audits applies to SQL Server and Azure SQL
            # Managed Instance only, and Azure SQL Database auditing is configured on the logical server outside T-SQL.
            # https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-server-audits-transact-sql
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
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
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        # The pin returns no row there and says nothing (probe evidence pin-instanceaudit-20261105.txt and
        # pin-audits-azure-db-20261105.txt, both editions), the same answer as an instance with no audit. Fleet.md step 4
        # (operator, 2026-10-28): a command Azure SQL Database cannot support refuses it as Connect-DbaInstance
        # -AzureUnsupported does (correction azure-refusal).
        It "refuses Azure SQL Database, which has no server audits, and goes on to the next instance" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            foreach ($splat in @(@{ }, @{ Audit = $auditFile }, @{ ExcludeAudit = "dbatoolsci_none" })) {
                $azureWarnings = @()
                $rows = @(Get-DbaInstanceAudit -SqlInstance $azure, $TestConfig.InstanceSingle @splat -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureWarnings)
                $azureWarnings.Count | Should -Be 1
                "$($azureWarnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceAudit] Failure | ") + ".*" + [regex]::Escape("Azure SQL Database not supported"))
                @($rows | Where-Object SqlInstance -ne $auditServer.DomainInstanceName).Count | Should -Be 0
                @($rows | Where-Object Name -eq $auditFile).Count | Should -Be 1
            }
        }

        It "throws the Azure SQL Database refusal under -EnableException" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureCaught = $null
            try {
                $null = Get-DbaInstanceAudit -SqlInstance $azure -EnableException -WarningAction SilentlyContinue
            } catch {
                $azureCaught = $PSItem
            }
            $azureCaught | Should -Not -BeNullOrEmpty
            "$($azureCaught.Exception.Message)" | Should -Match ([regex]::Escape("Azure SQL Database not supported"))
            $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
