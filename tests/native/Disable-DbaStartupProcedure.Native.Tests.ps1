#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Disable-DbaStartupProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
# Azure SQL Database: Azure SQL Database has no automatic execution at server startup: https://learn.microsoft.com/sql/relational-databases/stored-procedures/execute-a-stored-procedure#automatic-execution-at-startup

Describe "Native Disable-DbaStartupProcedure" -Tag IntegrationTests {
    BeforeAll {
        if (-not ([System.Management.Automation.PSTypeName]"NativeStartupTests.ConfirmationHost").Type) {
            Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
namespace NativeStartupTests {
    public sealed class ConfirmationUI : PSHostUserInterface {
        private readonly PSHostRawUserInterface raw;
        public readonly List<string> Prompts = new List<string>();
        public readonly List<string> Writes = new List<string>();
        public ConfirmationUI(PSHostRawUserInterface raw) { this.raw = raw; }
        public override PSHostRawUserInterface RawUI { get { return raw; } }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
            Prompts.Add(message);
            for (int i = 0; i < choices.Count; i++)
                if (String.Equals(choices[i].Label.Replace("&", ""), "No", StringComparison.OrdinalIgnoreCase)) return i;
            throw new InvalidOperationException("Confirmation did not offer No");
        }
        public override string ReadLine() { throw new InvalidOperationException("Unexpected input request"); }
        public override SecureString ReadLineAsSecureString() { throw new InvalidOperationException("Unexpected secret input request"); }
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> fields) { throw new InvalidOperationException("Unexpected field input request"); }
        public override PSCredential PromptForCredential(string caption, string message, string user, string target) { throw new InvalidOperationException("Unexpected credential request"); }
        public override PSCredential PromptForCredential(string caption, string message, string user, string target, PSCredentialTypes types, PSCredentialUIOptions options) { throw new InvalidOperationException("Unexpected credential request"); }
        public override void Write(string value) { Writes.Add(value); }
        public override void Write(ConsoleColor foreground, ConsoleColor background, string value) { Writes.Add(value); }
        public override void WriteLine(string value) { Writes.Add(value); }
        public override void WriteErrorLine(string value) { }
        public override void WriteDebugLine(string value) { }
        public override void WriteProgress(long sourceId, ProgressRecord record) { }
        public override void WriteVerboseLine(string value) { }
        public override void WriteWarningLine(string value) { }
    }
    public sealed class ConfirmationHost : PSHost {
        private readonly Guid id = Guid.NewGuid();
        public readonly ConfirmationUI TestUI;
        public ConfirmationHost(PSHostRawUserInterface raw) { TestUI = new ConfirmationUI(raw); }
        public override Guid InstanceId { get { return id; } }
        public override string Name { get { return "NativeStartupConfirmation"; } }
        public override Version Version { get { return new Version(1, 0); } }
        public override CultureInfo CurrentCulture { get { return CultureInfo.GetCultureInfo("en-US"); } }
        public override CultureInfo CurrentUICulture { get { return CultureInfo.GetCultureInfo("en-US"); } }
        public override PSHostUserInterface UI { get { return TestUI; } }
        public override void EnterNestedPrompt() { throw new InvalidOperationException("Unexpected nested prompt"); }
        public override void ExitNestedPrompt() { throw new InvalidOperationException("Unexpected nested prompt exit"); }
        public override void SetShouldExit(int exitCode) { throw new InvalidOperationException("Unexpected exit request"); }
        public override void NotifyBeginApplication() { }
        public override void NotifyEndApplication() { }
    }
}
"@
        }
        function Invoke-NativeStartupConfirmation {
            param([hashtable]$Parameters, [object[]]$PipelineObjects = @())
            $confirmationHost = New-Object NativeStartupTests.ConfirmationHost -ArgumentList $Host.UI.RawUI
            $confirmationState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $startupType = (Get-Command Disable-DbaStartupProcedure -CommandType Cmdlet).ImplementingType
            $confirmationCommand = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Disable-DbaStartupProcedure", $startupType, $null
            $confirmationState.Commands.Add($confirmationCommand)
            $confirmationRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($confirmationHost, $confirmationState)
            $confirmationShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $confirmationRunspace.Open()
                $confirmationRunspace.SessionStateProxy.SetVariable("ConfirmPreference", "High")
                $confirmationShell.Runspace = $confirmationRunspace
                $null = $confirmationShell.AddCommand("Disable-DbaStartupProcedure").AddParameters($Parameters)
                $confirmationResults = if ($PipelineObjects.Count) {
                    @($confirmationShell.Invoke([System.Collections.IEnumerable]$PipelineObjects))
                } else {
                    @($confirmationShell.Invoke())
                }
                if ($confirmationShell.HadErrors) { throw $confirmationShell.Streams.Error[0] }
                [pscustomobject]@{
                    Results = @($confirmationResults)
                    Prompts = @($confirmationHost.TestUI.Prompts.ToArray())
                    Writes = @($confirmationHost.TestUI.Writes.ToArray())
                }
            } finally {
                $confirmationShell.Dispose()
                $confirmationRunspace.Dispose()
            }
        }
        function Get-NativeStartupSqlName($name) { '[dbo].[' + $name.Replace(']', ']]') + ']' }
        function Get-NativeStartupFlag($server, $name) {
            $literal = $name.Replace("'", "''")
            [int]$server.ConnectionContext.ExecuteScalar("SELECT is_auto_executed FROM master.sys.procedures WHERE schema_id = SCHEMA_ID(N'dbo') AND name = N'$literal'")
        }
        function Set-NativeStartupFlag($server, $name, $enabled) {
            $literal = (Get-NativeStartupSqlName $name).Replace("'", "''")
            $value = if ($enabled) { 'on' } else { 'off' }
            $null = $server.ConnectionContext.ExecuteNonQuery("EXEC master.sys.sp_procoption @ProcName=N'$literal', @OptionName='startup', @OptionValue='$value'")
            $server.Databases['master'].StoredProcedures.Refresh()
            $server.Databases['master'].StoredProcedures[$name, 'dbo'].Refresh()
        }
        $startupServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -Database master -EnableException
        $startupNames = @(1..8 | ForEach-Object { 'native_disable_startup_' + [guid]::NewGuid().ToString('N') })
        $startupNames[0] += "_quote']"
        $startupCreated = New-Object System.Collections.ArrayList
        foreach ($name in $startupNames) {
            $qualified = Get-NativeStartupSqlName $name
            $null = $startupServer.ConnectionContext.ExecuteNonQuery("CREATE PROCEDURE $qualified AS SELECT 1")
            $null = $startupCreated.Add($name)
        }
    }
    BeforeEach {
        foreach ($name in $startupCreated) { Set-NativeStartupFlag $startupServer $name $true }
    }
    AfterAll {
        if ($startupServer) {
            foreach ($name in $startupCreated) {
                Set-NativeStartupFlag $startupServer $name $false
                $qualified = Get-NativeStartupSqlName $name
                $null = $startupServer.ConnectionContext.ExecuteNonQuery("DROP PROCEDURE $qualified")
            }
        }
    }

    It "returns every named procedure in the requested order" -Tag NativeChecklist:switch-false {
        $names = @($startupNames[0], $startupNames[1])
        $result = @(Disable-DbaStartupProcedure -SqlInstance $startupServer -StartupProcedure @($names | ForEach-Object { Get-NativeStartupSqlName $_ }) -WhatIf:$false -Confirm:$false -EnableException)
        $result.Count | Should -Be 2
        for ($index = 0; $index -lt 2; $index++) {
            $result[$index].Name | Should -BeExactly $names[$index]
            $result[$index].Schema | Should -BeExactly 'dbo'
            $result[$index].Action | Should -BeExactly 'Disable'
            $result[$index].Status | Should -BeTrue
            $result[$index].Note | Should -BeExactly 'Disable succeded'
            $result[$index].Database | Should -BeExactly 'master'
            $result[$index].ComputerName | Should -Not -BeNullOrEmpty
            $result[$index].Startup | Should -BeFalse
            (Get-NativeStartupFlag $startupServer $names[$index]) | Should -Be 0
        }
    }

    It "returns every procedure supplied as an InputObject array" {
        $procedures = @($startupServer.Databases['master'].StoredProcedures[$startupNames[2], 'dbo'], $startupServer.Databases['master'].StoredProcedures[$startupNames[3], 'dbo'])
        $result = @(Disable-DbaStartupProcedure -InputObject $procedures -Confirm:$false -EnableException)
        $result.Count | Should -Be 2
        for ($index = 0; $index -lt 2; $index++) {
            $result[$index].Name | Should -BeExactly $procedures[$index].Name
            $result[$index].Status | Should -BeTrue
            $result[$index].Note | Should -BeExactly 'Disable succeded'
            (Get-NativeStartupFlag $startupServer $procedures[$index].Name) | Should -Be 0
        }
    }

    It "processes both piped procedures once and preserves the already-disabled result" -Tag NativeChecklist:pipeline-multiple {
        $procedures = @($startupServer.Databases['master'].StoredProcedures[$startupNames[2], 'dbo'], $startupServer.Databases['master'].StoredProcedures[$startupNames[3], 'dbo'])
        $result = @($procedures | Disable-DbaStartupProcedure -Confirm:$false -EnableException)
        $result.Count | Should -Be 2
        @($result | Where-Object Status).Count | Should -Be 2
        $result[0].Name | Should -BeExactly $startupNames[2]
        $result[1].Name | Should -BeExactly $startupNames[3]
        foreach ($procedure in $procedures) { (Get-NativeStartupFlag $startupServer $procedure.Name) | Should -Be 0 }
        $again = Disable-DbaStartupProcedure -InputObject $procedures[0] -Confirm:$false -EnableException
        $again.Status | Should -BeFalse
        $again.Note | Should -BeExactly 'Action Disable already performed'
    }

    It "resolves a procedure name without an explicit schema" {
        $name = $startupNames[4]
        $result = Disable-DbaStartupProcedure -SqlInstance $startupServer -StartupProcedure $name -Confirm:$false -EnableException
        $result.Name | Should -BeExactly $name
        $result.Status | Should -BeTrue
        (Get-NativeStartupFlag $startupServer $name) | Should -Be 0
    }

    It "keeps the startup flag and returns a skipped result under WhatIf" -Tag NativeChecklist:whatif-confirm {
        $name = $startupNames[5]
        $result = Disable-DbaStartupProcedure -SqlInstance $startupServer -StartupProcedure (Get-NativeStartupSqlName $name) -WhatIf -Confirm:$false -EnableException
        $result.Status | Should -BeFalse
        $result.Note | Should -BeExactly 'Disable skipped'
        (Get-NativeStartupFlag $startupServer $name) | Should -Be 1
    }

    It "identifies each named procedure in confirmation and WhatIf text" -Tag NativeChecklist:whatif-confirm {
        $names = @($startupNames[0], $startupNames[1])
        $parameters = @{ SqlInstance = $startupServer; StartupProcedure = @($names | ForEach-Object { Get-NativeStartupSqlName $_ }); Confirm = $true; EnableException = $true }
        $declined = Invoke-NativeStartupConfirmation -Parameters $parameters
        $declined.Results.Count | Should -Be 2
        $declined.Prompts.Count | Should -Be 2
        foreach ($name in $names) { (Get-NativeStartupFlag $startupServer $name) | Should -Be 1 }
        for ($index = 0; $index -lt 2; $index++) {
            $declined.Results[$index].Note | Should -BeExactly 'Disable skipped'
            $declined.Prompts[$index] | Should -Match ([regex]::Escape($startupServer.Name))
            $declined.Prompts[$index] | Should -Match ([regex]::Escape('Setting Startup status of ' + (Get-NativeStartupSqlName $names[$index]) + ' to False'))
        }
        $parameters.WhatIf = $true
        $preview = Invoke-NativeStartupConfirmation -Parameters $parameters
        $preview.Results.Count | Should -Be 2
        $preview.Prompts.Count | Should -Be 0
        ($preview.Writes -join '') | Should -Match ([regex]::Escape($startupServer.Name))
        foreach ($name in $names) {
            (Get-NativeStartupFlag $startupServer $name) | Should -Be 1
            ($preview.Writes -join '') | Should -Match ([regex]::Escape('Setting Startup status of ' + (Get-NativeStartupSqlName $name) + ' to False'))
        }
    }

    It "identifies each supplied procedure in confirmation text" -Tag NativeChecklist:whatif-confirm {
        $procedures = @($startupServer.Databases['master'].StoredProcedures[$startupNames[2], 'dbo'], $startupServer.Databases['master'].StoredProcedures[$startupNames[3], 'dbo'])
        foreach ($usePipeline in @($false, $true)) {
            $parameters = @{ Confirm = $true; EnableException = $true }
            if ($usePipeline) {
                $declined = Invoke-NativeStartupConfirmation -Parameters $parameters -PipelineObjects $procedures
            } else {
                $parameters.InputObject = $procedures
                $declined = Invoke-NativeStartupConfirmation -Parameters $parameters
            }
            $declined.Results.Count | Should -Be 2
            $declined.Prompts.Count | Should -Be 2
            foreach ($procedure in $procedures) { (Get-NativeStartupFlag $startupServer $procedure.Name) | Should -Be 1 }
            for ($index = 0; $index -lt 2; $index++) {
                $declined.Results[$index].Note | Should -BeExactly 'Disable skipped'
                $declined.Prompts[$index] | Should -Match ([regex]::Escape($startupServer.Name))
                $declined.Prompts[$index] | Should -Match ([regex]::Escape('Setting Startup status of ' + (Get-NativeStartupSqlName $procedures[$index].Name) + ' to False'))
            }
        }
    }

    It "continues after a failed instance and throws when EnableException is set" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $name = $startupNames[6]
        $qualified = Get-NativeStartupSqlName $name
        $warnings = @()
        $result = @(Disable-DbaStartupProcedure -SqlInstance @('tcp:127.0.0.1,1', $startupServer) -StartupProcedure $qualified -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $result.Count | Should -Be 1
        $result[0].Status | Should -BeTrue
        ($warnings -join ' ') | Should -Match 'Failure'
        (Get-NativeStartupFlag $startupServer $name) | Should -Be 0
        { Disable-DbaStartupProcedure -SqlInstance 'tcp:127.0.0.1,1' -StartupProcedure $qualified -Confirm:$false -EnableException } | Should -Throw
    }

    It "preserves missing-parameter and missing-procedure warnings" -Tag NativeChecklist:enable-exception {
        $warnings = @()
        @(Disable-DbaStartupProcedure -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
        ($warnings -join ' ') | Should -Match ([regex]::Escape('You must supply either a SqlInstance or an InputObject .'))
        { Disable-DbaStartupProcedure -SqlInstance $startupServer -EnableException } | Should -Throw '*You must specify one or more Startup Procedures*'
        $name = $startupNames[7]
        $warnings = @()
        $result = @(Disable-DbaStartupProcedure -SqlInstance $startupServer -StartupProcedure @(('dbo.native_missing_' + [guid]::NewGuid().ToString('N')), (Get-NativeStartupSqlName $name)) -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $result.Count | Should -Be 1
        $result[0].Status | Should -BeTrue
        ($warnings -join ' ') | Should -Match 'does not exist'
    }

    It "reports the actual startup flag after a denied alteration" {
        $deniedStartupName = $startupNames[7]
        $deniedStartupQualified = Get-NativeStartupSqlName $deniedStartupName
        $deniedStartupUser = "native_startup_reader_" + [guid]::NewGuid().ToString("N")
        $deniedStartupServer = $null
        $deniedStartupUserCreated = $false
        try {
            $startupServer.Databases["master"].ExecuteNonQuery("CREATE USER [$deniedStartupUser] WITHOUT LOGIN; GRANT VIEW DEFINITION ON OBJECT::$deniedStartupQualified TO [$deniedStartupUser];")
            $deniedStartupUserCreated = $true
            $splatDeniedStartupConnection = @{
                SqlInstance = $TestConfig.InstanceSingle
                Database = "master"
                NonPooledConnection = $true
                ClientName = $deniedStartupUser
                EnableException = $true
            }
            $deniedStartupServer = Connect-DbaInstance @splatDeniedStartupConnection
            $deniedStartupProcedure = $deniedStartupServer.Databases["master"].StoredProcedures[$deniedStartupName, "dbo"]
            $deniedStartupProcedure | Should -Not -BeNullOrEmpty
            $deniedStartupProcedure.Startup | Should -BeTrue
            $deniedStartupServer.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = '$deniedStartupUser';") | Out-Null
            $deniedStartupServer.ConnectionContext.ExecuteScalar("SELECT USER_NAME();") | Should -BeExactly $deniedStartupUser
            # sp_procoption requires sysadmin; this user can read the flag but cannot change it.
            # https://learn.microsoft.com/sql/relational-databases/system-stored-procedures/sp-procoption-transact-sql
            foreach ($deniedStartupEnableException in @($false, $true)) {
                $deniedStartupProcedure.Refresh()
                $deniedStartupProcedure.Startup | Should -BeTrue
                $splatDeniedStartup = @{
                    InputObject = $deniedStartupProcedure
                    Confirm = $false
                    EnableException = $deniedStartupEnableException
                }
                $deniedStartupResult = @(Disable-DbaStartupProcedure @splatDeniedStartup)
                $deniedStartupResult.Count | Should -Be 1
                $deniedStartupResult[0].Name | Should -BeExactly $deniedStartupName
                $deniedStartupResult[0].Status | Should -BeFalse
                $deniedStartupResult[0].Note | Should -BeExactly "Disable failed"
                (Get-NativeStartupFlag $startupServer $deniedStartupName) | Should -Be 1
                $deniedStartupResult[0].Startup | Should -BeTrue
            }
        } finally {
            if ($deniedStartupServer) { $deniedStartupServer.ConnectionContext.Disconnect() }
            if ($deniedStartupUserCreated) { $startupServer.Databases["master"].ExecuteNonQuery("DROP USER [$deniedStartupUser];") }
        }
    }

    It "disables a startup procedure with SQL credentials and rejects missing credentials" -Tag NativeChecklist:sql-login {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -Database master -EnableException
        $name = 'native_disable_login_' + [guid]::NewGuid().ToString('N')
        $qualified = Get-NativeStartupSqlName $name
        $created = $false
        $startupLockServer = $null
        $startupLockAcquired = $false
        try {
            # All startup-flag fixtures on this shared instance use this same resource.
            $splatStartupLock = @{
                SqlInstance = $TestConfig.InstanceSqlLogin
                SqlCredential = $TestConfig.SqlLoginCred
                Database = "master"
                NonPooledConnection = $true
                ClientName = "native-startup-lock-" + [guid]::NewGuid().ToString("N")
                EnableException = $true
            }
            $startupLockServer = Connect-DbaInstance @splatStartupLock
            $startupLockServer.ConnectionContext.AutoDisconnectMode = [Microsoft.SqlServer.Management.Common.AutoDisconnectMode]::NoAutoDisconnect
            $startupLockServer.ConnectionContext.StatementTimeout = 125
            $startupLockServer.ConnectionContext.Connect()
            $startupLockResult = [int]$startupLockServer.ConnectionContext.ExecuteScalar("DECLARE @result int; EXEC @result = master.sys.sp_getapplock @Resource=N'dbatools-native-startup-flag', @LockMode=N'Exclusive', @LockOwner=N'Session', @LockTimeout=120000; SELECT @result;")
            $startupLockResult | Should -BeGreaterOrEqual 0
            $startupLockAcquired = $true
            $null = $server.ConnectionContext.ExecuteNonQuery("CREATE PROCEDURE $qualified AS SELECT 1")
            $created = $true
            Set-NativeStartupFlag $server $name $true
            $startupLockServer.ConnectionContext.ExecuteScalar("SELECT APPLOCK_MODE(N'public', N'dbatools-native-startup-flag', N'Session');") | Should -BeExactly "Exclusive"
            $result = Disable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -StartupProcedure $qualified -Confirm:$false -EnableException
            $result.Status | Should -BeTrue
            (Get-NativeStartupFlag $server $name) | Should -Be 0
            $warnings = @()
            @(Disable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSqlLogin -StartupProcedure $qualified -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match 'Failure'
            # The pin catches its direct Connect-DbaInstance call and calls Stop-Function using this command's EnableException.
            { Disable-DbaStartupProcedure -SqlInstance $TestConfig.InstanceSqlLogin -StartupProcedure $qualified -Confirm:$false -EnableException } | Should -Throw
        } finally {
            try {
                if ($created) {
                    try { Set-NativeStartupFlag $server $name $false } finally {
                        $null = $server.ConnectionContext.ExecuteNonQuery("DROP PROCEDURE $qualified")
                    }
                }
            } finally {
                if ($startupLockServer) {
                    try {
                        if ($startupLockAcquired) {
                            $startupUnlockResult = [int]$startupLockServer.ConnectionContext.ExecuteScalar("DECLARE @result int; EXEC @result = master.sys.sp_releaseapplock @Resource=N'dbatools-native-startup-flag', @LockOwner=N'Session'; SELECT @result;")
                            $startupUnlockResult | Should -BeGreaterOrEqual 0
                        }
                    } finally {
                        $startupLockServer.ConnectionContext.Disconnect()
                    }
                }
            }
        }
    }

    It "refuses Azure startup operations through instance and object input" -Tag NativeChecklist:azure-sqldb {
        $azure = $null
        $created = $false
        $name = 'native_disable_azure_' + [guid]::NewGuid().ToString('N')
        $qualified = Get-NativeStartupSqlName $name
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $errorCause = $_.Exception
                    $isResuming = $false
                    while ($errorCause) {
                        if ($errorCause.Number -in 40613, -2, 258 -or $errorCause -is [System.TimeoutException] -or ($errorCause -is [System.ComponentModel.Win32Exception] -and $errorCause.NativeErrorCode -in 258, 10060)) { $isResuming = $true }
                        $errorCause = $errorCause.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
            $warnings = @()
            @(Disable-DbaStartupProcedure -SqlInstance $azure -StartupProcedure $qualified -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            { Disable-DbaStartupProcedure -SqlInstance $azure -StartupProcedure $qualified -Confirm:$false -EnableException } | Should -Throw '*Azure SQL Database not supported*'
            $null = $azure.ConnectionContext.ExecuteNonQuery("CREATE PROCEDURE $qualified AS SELECT 1")
            $created = $true
            $azure.Databases[$TestConfig.AzureSqlDbName].StoredProcedures.Refresh()
            $procedure = $azure.Databases[$TestConfig.AzureSqlDbName].StoredProcedures[$name, 'dbo']
            $procedure | Should -Not -BeNullOrEmpty
            $warnings = @()
            @(Disable-DbaStartupProcedure -InputObject $procedure -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings).Count | Should -Be 0
            ($warnings -join ' ') | Should -Match ([regex]::Escape('Azure SQL Database not supported'))
            { Disable-DbaStartupProcedure -InputObject $procedure -Confirm:$false -EnableException } | Should -Throw '*Azure SQL Database not supported*'
        } finally {
            if ($azure) {
                if ($created) { $null = $azure.ConnectionContext.ExecuteNonQuery("DROP PROCEDURE $qualified") }
                $azure.ConnectionContext.Disconnect()
            }
        }
    }
}
