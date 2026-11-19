#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaInstanceAuditSpecification",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaInstanceAuditSpecification" -Tag IntegrationTests {
    BeforeAll {
        $specServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $specTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $specAudit = "dbatoolsci_ias_${specTag}_audit"
        $specAuditOff = "dbatoolsci_ias_${specTag}_audit_off"
        $specOn = "dbatoolsci_ias_${specTag}_on"
        $specOff = "dbatoolsci_ias_${specTag}_off"
        $specMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)

        # The audits stay disabled, so nothing is ever written to the application log; one specification is ON, one OFF.
        # A server audit takes one server audit specification, so each specification has an audit of its own.
        $null = $specServer.Query("CREATE SERVER AUDIT [$specAudit] TO APPLICATION_LOG WITH (ON_FAILURE = CONTINUE)")
        $null = $specServer.Query("CREATE SERVER AUDIT [$specAuditOff] TO APPLICATION_LOG WITH (ON_FAILURE = CONTINUE)")
        $null = $specServer.Query("CREATE SERVER AUDIT SPECIFICATION [$specOn] FOR SERVER AUDIT [$specAudit] ADD (FAILED_LOGIN_GROUP) WITH (STATE = ON)")
        $null = $specServer.Query("CREATE SERVER AUDIT SPECIFICATION [$specOff] FOR SERVER AUDIT [$specAuditOff] ADD (SUCCESSFUL_LOGIN_GROUP) WITH (STATE = OFF)")

        # Independent read: the catalog views, on the test's own connection.
        $catalogSql = "SELECT s.name, s.server_specification_id, s.is_state_enabled, a.name AS audit_name, s.create_date, s.modify_date FROM sys.server_audit_specifications AS s LEFT JOIN sys.server_audits AS a ON a.audit_guid = s.audit_guid"
        function Get-NativeSpecCatalog {
            @($specServer.Query($catalogSql))
        }
    }

    AfterAll {
        foreach ($name in $specOn, $specOff) {
            $null = $specServer.Query("IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'$name') BEGIN ALTER SERVER AUDIT SPECIFICATION [$name] WITH (STATE = OFF); DROP SERVER AUDIT SPECIFICATION [$name]; END")
        }
        foreach ($name in $specAudit, $specAuditOff) {
            $null = $specServer.Query("IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$name') DROP SERVER AUDIT [$name]")
        }
    }

    It "returns every server audit specification the catalog lists, decorated as the pin decorates them" {
        # The other PowerShell edition's lane may add or drop its own specifications on this instance meanwhile, so the
        # catalog is read before and after: every name in both reads comes back, and nothing outside them does.
        $catalog = Get-NativeSpecCatalog
        @($catalog | Where-Object name -in $specOn, $specOff).Count | Should -Be 2
        $results = @(Get-DbaInstanceAuditSpecification -SqlInstance $TestConfig.InstanceSingle -ErrorVariable specErrors)
        $catalogAfter = Get-NativeSpecCatalog
        $specErrors | Should -BeNullOrEmpty
        $stableNames = @($catalog.name | Where-Object { $PSItem -in $catalogAfter.name })
        @($stableNames | Where-Object { $PSItem -notin $results.Name }) | Should -BeNullOrEmpty
        @($results.Name | Where-Object { $PSItem -notin $catalog.name -and $PSItem -notin $catalogAfter.name }) | Should -BeNullOrEmpty
        @($results.Name | Select-Object -Unique).Count | Should -Be $results.Count
        foreach ($result in $results) {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.ServerAuditSpecification]
            $result.ComputerName | Should -BeExactly $specServer.ComputerName
            $result.InstanceName | Should -BeExactly $specServer.ServiceName
            $result.SqlInstance | Should -BeExactly $specServer.DomainInstanceName
            $result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join "," | Should -BeExactly "ComputerName,InstanceName,SqlInstance,ID,Name,AuditName,Enabled,CreateDate,DateLastModified,Guid"
        }

        # The catalog values are compared on this test's own specifications, which nothing else changes meanwhile.
        foreach ($result in @($results | Where-Object Name -in $specOn, $specOff)) {
            $row = $catalog | Where-Object name -eq $result.Name
            $result.ID | Should -Be $row.server_specification_id
            $result.AuditName | Should -BeExactly $row.audit_name
            $result.Enabled | Should -Be ([bool]$row.is_state_enabled)
            $result.CreateDate | Should -Be $row.create_date
            $result.DateLastModified | Should -Be $row.modify_date
        }

        $on = $results | Where-Object Name -eq $specOn
        $on.Enabled | Should -BeTrue
        $on.AuditName | Should -BeExactly $specAudit
        $off = $results | Where-Object Name -eq $specOff
        $off.Enabled | Should -BeFalse
        $off.AuditName | Should -BeExactly $specAuditOff
    }

    It "replaces its notes when the same server's object comes back" {
        $first = Get-DbaInstanceAuditSpecification -SqlInstance $specServer | Where-Object Name -eq $specOn
        $second = Get-DbaInstanceAuditSpecification -SqlInstance $specServer | Where-Object Name -eq $specOn
        $second.SqlInstance | Should -BeExactly $first.SqlInstance
        @($second.PSObject.Properties | Where-Object Name -eq "SqlInstance").Count | Should -Be 1
        @($second.PSObject.Properties | Where-Object Name -eq "ComputerName").Count | Should -Be 1
        @($second.PSObject.Properties | Where-Object Name -eq "InstanceName").Count | Should -Be 1
    }

    It "returns the specifications of each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $warnings = @()
        $results = @(@($TestConfig.InstanceSingle, $specMissing, $TestConfig.InstanceSingle) | Get-DbaInstanceAuditSpecification -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        @($results | Where-Object Name -eq $specOn).Count | Should -Be 2
        @($results | Where-Object Name -eq $specOff).Count | Should -Be 2
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceAuditSpecification] Failure | Error connecting to [$specMissing]: "))
    }

    It "reads several named instances" {
        $results = @(Get-DbaInstanceAuditSpecification -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle)
        @($results | Where-Object Name -eq $specOn).Count | Should -Be 2
    }

    It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        { Get-DbaInstanceAuditSpecification -SqlInstance $specMissing -EnableException -WarningAction SilentlyContinue } | Should -Throw
    }

    Context "A login denied the server audit specification catalog" {
        BeforeAll {
            # The pin reads $server.ServerAuditSpecifications outside any try. A SQL login whose master user is denied SELECT
            # on sys.server_audit_specifications connects (Connect-DbaInstance's own SELECT succeeds), and the read then
            # faults. sysadmin ignores DENY, so the login has no server role.
            $denyName = "dbatoolsci_ias_${specTag}_deny"
            $denyPassword = "Ias-" + [guid]::NewGuid().ToString("N")
            $denyCred = New-Object System.Management.Automation.PSCredential -ArgumentList $denyName, (ConvertTo-SecureString -String $denyPassword -AsPlainText -Force)
            $null = $specServer.Query("CREATE LOGIN [$denyName] WITH PASSWORD = N'$denyPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")
            $null = $specServer.Query("USE [master]; CREATE USER [$denyName] FOR LOGIN [$denyName]; DENY SELECT ON OBJECT::sys.server_audit_specifications TO [$denyName];")

            function New-NativeDeniedServer {
                Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $denyCred -EnableException
            }

            # The pin's record for this fault: the engine's foreach over a collection whose GetEnumerator throws.
            function Assert-NativeSpecReadFault {
                param($Record)
                ($Record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "ExceptionInGetEnumerator"
                $Record.Exception | Should -BeOfType [System.Management.Automation.ExtendedTypeSystemException]
                $Record.Exception.InnerException | Should -BeOfType [Microsoft.SqlServer.Management.Common.ExecutionFailureException]
                $Record.Exception.Message | Should -BeExactly ('The following exception occurred while trying to enumerate the collection: "{0}".' -f $Record.Exception.InnerException.Message)
                $Record.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::NotSpecified)
                "$($Record.TargetObject)" | Should -BeExactly ""
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeSpecOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaInstanceAuditSpecification -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaInstanceAuditSpecification", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaInstanceAuditSpecification @Arguments; "next statement"').AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output   = @($outsideOutput)
                        Errors   = @($outsideShell.Streams.Error)
                        Warnings = @($outsideShell.Streams.Warning)
                        Stop     = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }
        }

        AfterAll {
            foreach ($row in @($specServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$denyName';"))) {
                $null = $specServer.Query("KILL $($row.session_id);")
            }
            $null = $specServer.Query("USE [master]; IF USER_ID(N'$denyName') IS NOT NULL DROP USER [$denyName];")
            $null = $specServer.Query("IF SUSER_ID(N'$denyName') IS NOT NULL DROP LOGIN [$denyName];")
        }

        It "writes each instance's read fault and goes on, outside any try" {
            $outside = Invoke-NativeSpecOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Warnings.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 2
            foreach ($record in $outside.Errors) {
                Assert-NativeSpecReadFault -Record $record
            }
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "stops at the first read fault under -EnableException" {
            $outside = Invoke-NativeSpecOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeSpecReadFault -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "lets a caller's try catch the first read fault" {
            $first = New-NativeDeniedServer
            $second = New-NativeDeniedServer
            $callerOutput = @(try { Get-DbaInstanceAuditSpecification -SqlInstance $first, $second; "after" } catch { $_ })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeSpecReadFault -Record $callerOutput[0]
        }

        It "stops at the first read fault under -ErrorAction Stop, outside a try" {
            $outside = Invoke-NativeSpecOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeSpecReadFault -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
            $loginAudit = "dbatoolsci_iaslogin_${loginTag}_audit"
            $loginSpec = "dbatoolsci_iaslogin_${loginTag}_spec"
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $null = $loginServer.Query("CREATE SERVER AUDIT [$loginAudit] TO APPLICATION_LOG WITH (ON_FAILURE = CONTINUE)")
            $null = $loginServer.Query("CREATE SERVER AUDIT SPECIFICATION [$loginSpec] FOR SERVER AUDIT [$loginAudit] ADD (FAILED_LOGIN_GROUP) WITH (STATE = OFF)")
        }

        AfterAll {
            $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM sys.server_audit_specifications WHERE name = N'$loginSpec') BEGIN ALTER SERVER AUDIT SPECIFICATION [$loginSpec] WITH (STATE = OFF); DROP SERVER AUDIT SPECIFICATION [$loginSpec]; END")
            $null = $loginServer.Query("IF EXISTS (SELECT 1 FROM sys.server_audits WHERE name = N'$loginAudit') DROP SERVER AUDIT [$loginAudit]")
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaInstanceAuditSpecification -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException | Where-Object Name -eq $loginSpec)
            $result.Count | Should -Be 1
            $result[0].AuditName | Should -BeExactly $loginAudit
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaInstanceAuditSpecification -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaInstanceAuditSpecification -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # Server audit specifications do not exist in Azure SQL Database (sys.server_audit_specifications applies to
            # SQL Server and Azure SQL Managed Instance only), and SMO's ServerAuditSpecifications is null there:
            # https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-server-audit-specifications-transact-sql
            # The pin returns nothing, with no warning and no error, on a plain call and under -EnableException
            # (evidence/pin-auditspec-azure-20261105.txt, both editions); the port refuses it (correction azure-unsupported).
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

        # Correction azure-unsupported: the pin's silent empty result reads as "no specifications" for an engine that has
        # none to read; the port refuses Azure SQL Database as Connect-DbaInstance -AzureUnsupported does.
        It "refuses Azure SQL Database with the connection warning and returns nothing" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $null -eq $azure.ServerAuditSpecifications | Should -BeTrue
            $azureWarnings = @()
            $azureErrors = @()
            $azurePriorErrors = @($global:Error)
            @(Get-DbaInstanceAuditSpecification -SqlInstance $azure -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors).Count | Should -Be 0
            $azureAddedErrors = @($global:Error | Where-Object { $azurePriorErrors -notcontains $PSItem })
            $azureWarnings.Count | Should -Be 1
            $azureWarnings[0].Message | Should -Match ([regex]::Escape("[Get-DbaInstanceAuditSpecification] Failure | Azure SQL Database not supported") + '$')

            # The port's record, measured on both editions by port probe 55498c70 (evidence/port-azrefusal-55498c70-20261105.txt):
            # one record, the same object in -ErrorVariable and in $Error, the target the server name the input shows in brackets.
            $azureErrors.Count | Should -Be 1
            $azureAddedErrors.Count | Should -Be 1
            [object]::ReferenceEquals($azureAddedErrors[0], $azureErrors[0]) | Should -BeTrue
            $azureRecord = $azureErrors[0]
            $azureRecord.FullyQualifiedErrorId | Should -BeExactly "dbatools_Get-DbaInstanceAuditSpecification"
            "$($azureRecord.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $azureRecord.CategoryInfo.Reason | Should -BeExactly "Exception"
            $azureRecord.TargetObject | Should -BeOfType [System.String]
            ("[" + $azureRecord.TargetObject + "]") | Should -BeExactly "$azure"
            $azureRecord.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $azureRecord.Exception.Message | Should -BeExactly "Azure SQL Database not supported"
            $azureRecord.Exception.InnerException | Should -Not -BeNullOrEmpty
            $azureRecord.Exception.InnerException.Message | Should -BeExactly "Azure SQL Database not supported"
        }

        It "throws the connection refusal for Azure SQL Database under -EnableException" {
            $azureCaught = $null
            try {
                $null = Get-DbaInstanceAuditSpecification -SqlInstance $azure -EnableException -WarningAction SilentlyContinue
            } catch {
                $azureCaught = $PSItem
            }
            $azureCaught | Should -Not -BeNullOrEmpty
            $azureCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            $azureCaught.Exception.ToString() | Should -BeLike "*Azure SQL Database not supported*"
        }
    }
}
