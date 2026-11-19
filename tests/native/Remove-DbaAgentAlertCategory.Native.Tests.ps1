#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentAlertCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativePrefix = "native_remove_alert_category_" + [Guid]::NewGuid().ToString("N")
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $nativeOwnedNames = New-Object System.Collections.Generic.List[string]
        function New-NativeRemovalFixture {
            param([string]$Suffix)
            $name = "${nativePrefix}_$Suffix"
            $nativeOwnedNames.Add($name)
            $category = New-Object Microsoft.SqlServer.Management.Smo.Agent.AlertCategory -ArgumentList $nativeServer.JobServer, $name
            $category.Create()
            $category
        }
        function Remove-NativeFixtureExternally {
            param([string]$Name)
            # Keep the pipeline object's Existing state while another SMO object removes its SQL row.
            $otherServer = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $nativeServer.ConnectionContext
            $otherCategory = $otherServer.JobServer.AlertCategories[$Name]
            $otherCategory.Drop()
        }
        function Get-NativeRemovalFixture {
            param([string]$Name)
            $nativeServer.JobServer.AlertCategories.Refresh()
            $nativeServer.JobServer.AlertCategories[$Name]
        }
        if (-not ([System.Management.Automation.PSTypeName]"NativeRemoveAlertCategoryTests.ConfirmationHost").Type) {
            Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
namespace NativeRemoveAlertCategoryTests {
    public sealed class ConfirmationUI : PSHostUserInterface {
        private readonly PSHostRawUserInterface raw;
        public readonly Queue<string> Answers;
        public int PromptCount;
        public ConfirmationUI(PSHostRawUserInterface raw, string[] answers) { this.raw = raw; Answers = new Queue<string>(answers); }
        public override PSHostRawUserInterface RawUI { get { return raw; } }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
            PromptCount++;
            if (Answers.Count == 0) throw new InvalidOperationException("Unexpected confirmation request: " + message);
            string answer = Answers.Dequeue();
            for (int i = 0; i < choices.Count; i++)
                if (String.Equals(choices[i].Label.Replace("&", ""), answer, StringComparison.OrdinalIgnoreCase)) return i;
            throw new InvalidOperationException("Requested confirmation answer was unavailable: " + answer);
        }
        public override string ReadLine() { throw new InvalidOperationException("Unexpected input request"); }
        public override SecureString ReadLineAsSecureString() { throw new InvalidOperationException("Unexpected secret input request"); }
        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> fields) { throw new InvalidOperationException("Unexpected field input request"); }
        public override PSCredential PromptForCredential(string caption, string message, string user, string target) { throw new InvalidOperationException("Unexpected credential request"); }
        public override PSCredential PromptForCredential(string caption, string message, string user, string target, PSCredentialTypes types, PSCredentialUIOptions options) { throw new InvalidOperationException("Unexpected credential request"); }
        public override void Write(string value) { }
        public override void Write(ConsoleColor foreground, ConsoleColor background, string value) { }
        public override void WriteLine(string value) { }
        public override void WriteErrorLine(string value) { }
        public override void WriteDebugLine(string value) { }
        public override void WriteProgress(long sourceId, ProgressRecord record) { }
        public override void WriteVerboseLine(string value) { }
        public override void WriteWarningLine(string value) { }
    }
    public sealed class ConfirmationHost : PSHost {
        private readonly Guid id = Guid.NewGuid();
        public readonly ConfirmationUI TestUI;
        public ConfirmationHost(PSHostRawUserInterface raw, string[] answers) { TestUI = new ConfirmationUI(raw, answers); }
        public override Guid InstanceId { get { return id; } }
        public override string Name { get { return "NativeAlertCategoryConfirmation"; } }
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
        function Invoke-NativeRemoveAlertCategoryPlainRead {
            param([hashtable]$Parameters, [switch]$Capture, [switch]$CallerTry)
            $state = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $type = (Get-Command Remove-DbaAgentAlertCategory -CommandType Cmdlet).ImplementingType
            $state.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList 'Remove-DbaAgentAlertCategory', $type, $null))
            $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($state)
            $shell = [System.Management.Automation.PowerShell]::Create()
            try {
                $runspace.Open()
                $shell.Runspace = $runspace
                $Parameters = $Parameters.Clone()
                $runspace.SessionStateProxy.SetVariable('nativeReadErrors', @())
                $Parameters.ErrorVariable = 'global:nativeReadErrors'
                # Direct invocation has no caller try inherited from Pester or fixture cleanup.
                if ($CallerTry) {
                    $body = {
                        param($Arguments)
                        try { Remove-DbaAgentAlertCategory @Arguments }
                        catch { $global:nativeCaughtRead = $PSItem }
                    }
                    $null = $shell.AddScript($body.ToString()).AddArgument($Parameters)
                } else {
                    $null = $shell.AddCommand('Remove-DbaAgentAlertCategory').AddParameters($Parameters)
                }
                if ($Capture) {
                    $output = New-Object 'System.Management.Automation.PSDataCollection[psobject]'
                    $failure = $null
                    try { $null = $shell.Invoke($null, $output) } catch { $failure = $PSItem }
                    [pscustomobject]@{
                        Results = @($output)
                        Errors = @($shell.Streams.Error)
                        Warnings = @($shell.Streams.Warning)
                        Failure = $failure
                        Reason = $shell.InvocationStateInfo.Reason
                        Caught = $runspace.SessionStateProxy.GetVariable('nativeCaughtRead')
                        ErrorVariable = @($runspace.SessionStateProxy.GetVariable('nativeReadErrors'))
                        History = @($runspace.SessionStateProxy.GetVariable('Error'))
                        State = $shell.InvocationStateInfo.State
                    }
                } else {
                    $shell.Commands.Commands[0].MergeMyResults([System.Management.Automation.Runspaces.PipelineResultTypes]::Error, [System.Management.Automation.Runspaces.PipelineResultTypes]::Output)
                    $shell.Invoke()
                }
            } finally { $shell.Dispose(); $runspace.Dispose() }
        }

        function Assert-NativeReadRecord {
            param($Entry, $Reference, [string]$EntryType = 'ErrorRecord', [switch]$CountFailure, [switch]$Unstopped)
            $Entry.GetType().FullName | Should -BeExactly "System.Management.Automation.$EntryType"
            $record = $Entry
            if ($Entry -is [System.Management.Automation.IContainsErrorRecord]) { $record = $Entry.ErrorRecord }
            if ($CountFailure) {
                $id = 'dbatools_Get-DbaAgentAlertCategory'
                if (-not $Unstopped) { $id += ',Dataplat.Dbatools.Commands.RemoveDbaAgentAlertCategoryCommand' }
                $record.FullyQualifiedErrorId | Should -BeExactly $id
                $record.CategoryInfo.Category | Should -Be 'NotSpecified'
                $record.CategoryInfo.Reason | Should -BeExactly 'Exception'
                $record.CategoryInfo.Activity | Should -BeExactly $(if ($Unstopped) { '' } else { 'Remove-DbaAgentAlertCategory' })
                $record.CategoryInfo.TargetName | Should -BeExactly "[$deniedCategoryName]"
                $record.CategoryInfo.TargetType | Should -BeExactly 'AlertCategory'
                $record.TargetObject | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.AlertCategory
                $record.TargetObject.Name | Should -BeExactly $deniedCategoryName
                # The pin's Stop-Function unwraps the SQL cause and wraps it once in System.Exception.
                $expectedException = $Reference.Exception
                while ($expectedException.InnerException) { $expectedException = $expectedException.InnerException }
                $record.Exception.GetType().FullName | Should -BeExactly 'System.Exception'
                $record.Exception.Message | Should -BeExactly $expectedException.Message
                $actualException = $record.Exception.InnerException
            } else {
                $record.FullyQualifiedErrorId | Should -BeExactly 'ExceptionInGetEnumerator,Dataplat.Dbatools.Commands.RemoveDbaAgentAlertCategoryCommand'
                $record.CategoryInfo.Category | Should -Be $Reference.CategoryInfo.Category
                $record.CategoryInfo.Reason | Should -BeExactly $Reference.CategoryInfo.Reason
                $record.CategoryInfo.Activity | Should -BeExactly 'Remove-DbaAgentAlertCategory'
                $record.CategoryInfo.TargetName | Should -BeExactly $Reference.CategoryInfo.TargetName
                $record.CategoryInfo.TargetType | Should -BeExactly $Reference.CategoryInfo.TargetType
                $record.TargetObject | Should -Be $Reference.TargetObject
                $expectedException = $Reference.Exception
                $actualException = $record.Exception
            }
            while ($expectedException) {
                $actualException | Should -Not -BeNullOrEmpty
                $actualException.GetType().FullName | Should -BeExactly $expectedException.GetType().FullName
                $actualException.Message | Should -BeExactly $expectedException.Message
                $actualException = $actualException.InnerException
                $expectedException = $expectedException.InnerException
            }
            $actualException | Should -BeNullOrEmpty
        }

        function Invoke-NativeRemoveAlertCategoryConfirmation {
            param([hashtable]$Parameters, [object[]]$Instances, [string[]]$Answers = @(), [string]$Preference = "High", [switch]$InheritedWhatIf)
            $nativeConfirmationHost = New-Object NativeRemoveAlertCategoryTests.ConfirmationHost -ArgumentList $Host.UI.RawUI, $Answers
            $nativeConfirmationState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $nativeScheduleType = (Get-Command Remove-DbaAgentAlertCategory -CommandType Cmdlet).ImplementingType
            $nativeConfirmationCommand = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Remove-DbaAgentAlertCategory", $nativeScheduleType, $null
            $nativeConfirmationState.Commands.Add($nativeConfirmationCommand)
            $nativeConfirmationRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeConfirmationHost, $nativeConfirmationState)
            $nativeConfirmationShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $nativeConfirmationRunspace.Open()
                $nativeConfirmationRunspace.SessionStateProxy.SetVariable("ConfirmPreference", $Preference)
                $nativeConfirmationRunspace.SessionStateProxy.SetVariable("WhatIfPreference", [bool]$InheritedWhatIf)
                $nativeConfirmationShell.Runspace = $nativeConfirmationRunspace
                $null = $nativeConfirmationShell.AddCommand("Remove-DbaAgentAlertCategory").AddParameters($Parameters)
                $nativeConfirmationResults = @($nativeConfirmationShell.Invoke([System.Collections.IEnumerable]$Instances))
                if ($nativeConfirmationShell.HadErrors) { throw $nativeConfirmationShell.Streams.Error[0] }
                [pscustomobject]@{
                    Results         = $nativeConfirmationResults
                    PromptCount     = $nativeConfirmationHost.TestUI.PromptCount
                    Remaining       = $nativeConfirmationHost.TestUI.Answers.Count
                    FinalPreference = $nativeConfirmationRunspace.SessionStateProxy.GetVariable("ConfirmPreference")
                    FinalWhatIf     = $nativeConfirmationRunspace.SessionStateProxy.GetVariable("WhatIfPreference")
                }
            } finally {
                $nativeConfirmationShell.Dispose()
                $nativeConfirmationRunspace.Dispose()
            }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $nativeServer.JobServer.AlertCategories.Refresh()
        foreach ($name in $nativeOwnedNames) {
            $category = $nativeServer.JobServer.AlertCategories[$name]
            if ($null -ne $category) { $category.Drop() }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "refuses Azure SQL Database and continues removal on the next instance" -Tag NativeChecklist:azure-sqldb {
        $azureCategoryServer = $null
        $azureCategoryFixture = New-NativeRemovalFixture "azure_continue"
        $azureCategoryName = $azureCategoryFixture.Name
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azureCategoryServer = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $_.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException] -or $azureError.Message -match 'timed out|timeout|wait operation') { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $azureCategoryServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureCategoryWarnings = @()
            @(Remove-DbaAgentAlertCategory -SqlInstance $azureCategoryServer -Category $azureCategoryName -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureCategoryWarnings).Count | Should -Be 0
            ($azureCategoryWarnings -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            { Remove-DbaAgentAlertCategory -SqlInstance $azureCategoryServer -Category $azureCategoryName -Confirm:$false -EnableException } | Should -Throw "*Azure SQL Database not supported*"
            $azureCategoryRemoved = @(Remove-DbaAgentAlertCategory -SqlInstance @($azureCategoryServer, $nativeServer) -Category $azureCategoryName -Confirm:$false -EnableException:$false -WarningAction SilentlyContinue)
            $azureCategoryRemoved.Count | Should -Be 1
            $azureCategoryRemoved[0].IsRemoved | Should -BeTrue
            Get-NativeRemovalFixture $azureCategoryName | Should -BeNullOrEmpty
        } finally {
            if ($azureCategoryServer) { $azureCategoryServer.ConnectionContext.Disconnect() }
        }
    }

    It "buffers a live collection and reports every deletion in order" {
        $first = New-NativeRemovalFixture "collection_a"
        $second = New-NativeRemovalFixture "collection_b"
        $names = @($first.Name, $second.Name)
        $nativeServer.JobServer.AlertCategories.Refresh()
        $result = @($nativeServer.JobServer.AlertCategories | Where-Object Name -In $names | Remove-DbaAgentAlertCategory -Confirm:$false)
        $result.Count | Should -Be 2
        ($result.Name -join ",") | Should -BeExactly ($names -join ",")
        foreach ($row in $result) {
            ($row.PSObject.Properties.Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,Status,IsRemoved"
            $row.Status | Should -BeExactly "Dropped"
            $row.IsRemoved | Should -BeTrue
            $row.SqlInstance | Should -Not -BeNullOrEmpty
            Get-NativeRemovalFixture $row.Name | Should -BeNullOrEmpty
        }
    }

    It "warns for a failed middle input and still removes later input" -Tag NativeChecklist:pipeline-multiple, NativeChecklist:enable-exception, NativeChecklist:switch-false {
        $first = New-NativeRemovalFixture "warning_a"
        $missing = New-NativeRemovalFixture "warning_b"
        $last = New-NativeRemovalFixture "warning_c"
        $names = @($first.Name, $missing.Name, $last.Name)
        Remove-NativeFixtureExternally $missing.Name
        $splatNativeRemove = @{
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeWarnings"
        }
        $nativeWarnings = @()
        $result = @(@($first, $missing, $last) | Remove-DbaAgentAlertCategory @splatNativeRemove)
        $result.Count | Should -Be 3
        ($result.Name -join ",") | Should -BeExactly ($names -join ",")
        $result[0].IsRemoved | Should -BeTrue
        $result[1].IsRemoved | Should -BeFalse
        $result[1].Status | Should -Not -BeNullOrEmpty
        $result[2].IsRemoved | Should -BeTrue
        ($nativeWarnings -join " ") | Should -BeLike "*Failed removing the SQL Agent alert category*"
        Get-NativeRemovalFixture $names[0] | Should -BeNullOrEmpty
        Get-NativeRemovalFixture $names[2] | Should -BeNullOrEmpty
    }

    It "preserves earlier output and stops after a failed input with EnableException" -Tag NativeChecklist:enable-exception {
        $first = New-NativeRemovalFixture "throw_a"
        $missing = New-NativeRemovalFixture "throw_b"
        $last = New-NativeRemovalFixture "throw_c"
        $firstName = $first.Name
        $lastName = $last.Name
        Remove-NativeFixtureExternally $missing.Name
        $observed = New-Object System.Collections.Generic.List[object]
        {
            @($first, $missing, $last) | Remove-DbaAgentAlertCategory -Confirm:$false -EnableException | ForEach-Object { $observed.Add($_) }
        } | Should -Throw
        $observed.Count | Should -Be 1
        $observed[0].Name | Should -BeExactly $firstName
        $observed[0].IsRemoved | Should -BeTrue
        Get-NativeRemovalFixture $firstName | Should -BeNullOrEmpty
        Get-NativeRemovalFixture $lastName | Should -Not -BeNullOrEmpty
    }

    It "leaves the category intact under WhatIf and declined confirmation" -Tag NativeChecklist:whatif-confirm {
        $category = New-NativeRemovalFixture "protected"
        $name = $category.Name
        $splatNativeWhatIf = @{
            InputObject = $category
            WhatIf      = $true
            Confirm     = $false
        }
        @(Remove-DbaAgentAlertCategory @splatNativeWhatIf).Count | Should -Be 0
        Get-NativeRemovalFixture $name | Should -Not -BeNullOrEmpty
        $splatNativeConfirmation = @{
            Parameters = @{ InputObject = $category; Confirm = $true }
            Answers    = @("No")
            Instances  = @()
        }
        $declined = Invoke-NativeRemoveAlertCategoryConfirmation @splatNativeConfirmation
        $declined.PromptCount | Should -Be 1
        @($declined.Results).Count | Should -Be 0
        Get-NativeRemovalFixture $name | Should -Not -BeNullOrEmpty
    }

    It "continues after a failed instance and removes selected categories from the valid instance" -Tag NativeChecklist:multi-instance-failure {
        $nativeInstanceCategory = New-NativeRemovalFixture "instance_continue"
        $nativeInstanceCategoryName = $nativeInstanceCategory.Name
        $nativeInstanceWarnings = @()
        $splatNativeInstanceRemove = @{
            SqlInstance     = @("Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False", $TestConfig.InstanceSingle)
            Category        = $nativeInstanceCategoryName
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeInstanceWarnings"
        }
        $nativeInstanceResult = @(Remove-DbaAgentAlertCategory @splatNativeInstanceRemove)
        $nativeInstanceResult.Count | Should -Be 1
        $nativeInstanceResult[0].Name | Should -BeExactly $nativeInstanceCategoryName
        $nativeInstanceResult[0].IsRemoved | Should -BeTrue
        ($nativeInstanceWarnings -join " ") | Should -BeLike "*Failure*"
        Get-NativeRemovalFixture $nativeInstanceCategoryName | Should -BeNullOrEmpty
    }

    It "does not remove categories after a denied read and honors termination preferences" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        foreach ($deniedProcedure in @("sp_help_category", "sp_help_alert")) {
            $deniedCategory = New-NativeRemovalFixture "read_$deniedProcedure"
            $deniedCategoryName = $deniedCategory.Name
            $deniedUser = "$($nativePrefix)_user_$deniedProcedure"
            $deniedServer = $null
            $deniedUserCreated = $false
            try {
                $nativeServer.Databases["msdb"].ExecuteNonQuery("CREATE USER [$deniedUser] WITHOUT LOGIN; ALTER ROLE [SQLAgentReaderRole] ADD MEMBER [$deniedUser];")
                $deniedUserCreated = $true
                if ($deniedProcedure -eq 'sp_help_alert') { $nativeServer.Databases["msdb"].ExecuteNonQuery("GRANT EXECUTE ON dbo.sp_help_alert TO [$deniedUser];") }
                $splatDeniedReadConnection = @{
                    SqlInstance = $TestConfig.InstanceSingle
                    Database = "msdb"
                    NonPooledConnection = $true
                    ClientName = $deniedUser
                    EnableException = $true
                }
                $deniedServer = Connect-DbaInstance @splatDeniedReadConnection
                $deniedServer.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = '$deniedUser';") | Out-Null
                $deniedServer.ConnectionContext.ExecuteScalar("SELECT USER_NAME();") | Should -BeExactly $deniedUser
                # Category enumeration works for this reader; alert enumeration already refuses
                # without sysalerts metadata, with the measured SQL18750 rather than SQL229.
                $deniedReadPriorErrorAction = $ErrorActionPreference
                try {
                    $ErrorActionPreference = "Stop"
                    @($deniedServer.JobServer.AlertCategories | Where-Object Name -EQ $deniedCategoryName).Count | Should -Be 1
                    if ($deniedProcedure -eq 'sp_help_alert') {
                        $directAlertFailure = $null
                        try { $null = @($deniedServer.JobServer.Alerts | ForEach-Object Name) } catch { $directAlertFailure = $PSItem }
                        $directAlertFailure | Should -Not -BeNullOrEmpty
                        $directAlertCause = $directAlertFailure.Exception
                        while ($directAlertCause.InnerException) { $directAlertCause = $directAlertCause.InnerException }
                        $directAlertCause.Number | Should -Be 18750
                        $directAlertCause.Message | Should -BeExactly "sp_help_alert: The parameter '@order_by' is not valid."
                    }
                } finally {
                    $ErrorActionPreference = $deniedReadPriorErrorAction
                }
                $deniedServer.ConnectionContext.Disconnect()
                $deniedServer = $null
                if ($deniedProcedure -eq 'sp_help_category') {
                    $nativeServer.Databases["msdb"].ExecuteNonQuery("DENY EXECUTE ON OBJECT::dbo.[$deniedProcedure] TO [$deniedUser];")
                }
                # A fresh connection avoids reusing SMO collections populated by the positive control.
                $splatDeniedReadConnection.ClientName = "$($deniedUser)_denied"
                $deniedServer = Connect-DbaInstance @splatDeniedReadConnection
                $deniedServer.ConnectionContext.ExecuteNonQuery("EXECUTE AS USER = '$deniedUser';") | Out-Null
                $deniedServer.ConnectionContext.ExecuteScalar("SELECT USER_NAME();") | Should -BeExactly $deniedUser
                $verifiedServer = Connect-DbaInstance -SqlInstance $deniedServer -EnableException
                [Object]::ReferenceEquals($deniedServer, $verifiedServer) | Should -BeTrue

                # The second case must reach the nested alert-count read after selecting a category.
                if ($deniedProcedure -eq "sp_help_alert") {
                    @($deniedServer.JobServer.AlertCategories | Where-Object Name -EQ $deniedCategoryName).Count | Should -Be 1
                }
                $splatDeniedRead = @{
                    SqlInstance = $deniedServer
                    Category = $deniedCategoryName
                    Confirm = $false
                    EnableException = $false
                    ErrorAction = "Continue"
                }
                if ($deniedProcedure -eq 'sp_help_alert') {
                    # Pin Get-DbaAgentAlertCategory:95-108 catches this read inside its loop.
                    # The nested Stop-Function warns and continues, including under ErrorAction Stop.
                    foreach ($action in @('Continue', 'Stop')) {
                        $splatDeniedRead.ErrorAction = $action
                        $capture = Invoke-NativeRemoveAlertCategoryPlainRead -Parameters $splatDeniedRead -Capture
                        $capture.Results.Count | Should -Be 0
                        $capture.Errors.Count | Should -Be 0
                        $capture.Failure | Should -BeNullOrEmpty
                        $capture.Warnings.Count | Should -Be 1
                        $capture.Warnings[0].Message | Should -BeLike '*[[]Get-DbaAgentAlertCategory[]]*Something went wrong getting the alert category*'
                        $capture.Warnings[0].Message | Should -BeLike '*sp_help_alert*'
                    }
                    $splatDeniedRead.ErrorAction = 'Continue'
                    $caughtCountFailure = $null
                    $countWarnings = @()
                    try { $countOutput = @(Remove-DbaAgentAlertCategory @splatDeniedRead -WarningAction SilentlyContinue -WarningVariable countWarnings) }
                    catch { $caughtCountFailure = $PSItem }
                    $caughtCountFailure | Should -BeNullOrEmpty
                    $countOutput.Count | Should -Be 0
                    $countWarnings.Count | Should -Be 1
                } else {
                    $directCategoryFailure = $null
                    try { $null = @($deniedServer.JobServer.AlertCategories | Where-Object Name -EQ $deniedCategoryName) }
                    catch { $directCategoryFailure = $PSItem }
                    $directCategoryFailure | Should -Not -BeNullOrEmpty
                    $deniedReadStream = @(Invoke-NativeRemoveAlertCategoryPlainRead -Parameters $splatDeniedRead)
                    $deniedReadStream.Count | Should -Be 1
                    $deniedReadStream[0] | Should -BeOfType System.Management.Automation.ErrorRecord
                    $deniedReadCause = $deniedReadStream[0].Exception
                    while ($deniedReadCause.InnerException) { $deniedReadCause = $deniedReadCause.InnerException }
                    $deniedReadCause.Number | Should -Be 229
                    $deniedReadCause.Message | Should -Match 'sp_help_category'
                    # Exercise ErrorAction Stop with no caller try in the invoked runspace.
                    $splatDeniedRead.SqlInstance = @($nativeServer, $deniedServer)
                    $splatDeniedRead.ErrorAction = 'Stop'
                    $stopped = Invoke-NativeRemoveAlertCategoryPlainRead -Parameters $splatDeniedRead -Capture
                    $stopped.State.ToString() | Should -BeExactly 'Failed'
                    $stopped.Failure | Should -Not -BeNullOrEmpty
                    $stopped.Results.Count | Should -Be 0
                    # Both pin and native stop through Invoke's terminal reason, not an error-stream entry.
                    $stopped.Errors.Count | Should -Be 0
                    Assert-NativeReadRecord $stopped.Reason $directCategoryFailure 'ActionPreferenceStopException'
                }
                Get-NativeRemovalFixture $deniedCategoryName | Should -Not -BeNullOrEmpty

                # Measured on both editions by denied-read-records-20261117.ps1. Keep every
                # EV/history entry: script duplicates/caught-fault entries are not manufactured
                # by the native command (installed engine-record rules, 2026-11-12 points 1-4).
                $isCountFailure = $deniedProcedure -eq 'sp_help_alert'
                $reference = if ($isCountFailure) { $directAlertFailure } else { $directCategoryFailure }
                foreach ($mode in @('plain', 'silent', 'stop', 'enable', 'try')) {
                    $splatDeniedRead.SqlInstance = $deniedServer
                    $splatDeniedRead.EnableException = $mode -eq 'enable'
                    $splatDeniedRead.ErrorAction = $(if ($mode -eq 'stop') { 'Stop' } elseif ($mode -eq 'silent') { 'SilentlyContinue' } else { 'Continue' })
                    $capture = Invoke-NativeRemoveAlertCategoryPlainRead -Parameters $splatDeniedRead -Capture -CallerTry:($mode -eq 'try')
                    $capture.Results.Count | Should -Be 0
                    $capture.ErrorVariable.Count | Should -Be 1
                    $capture.History.Count | Should -Be 1
                    $entryType = if ($mode -eq 'enable' -or (-not $isCountFailure -and $mode -eq 'try')) { 'CmdletInvocationException' } elseif (-not $isCountFailure -and $mode -eq 'stop') { 'ActionPreferenceStopException' } else { 'ErrorRecord' }
                    $historyType = if ($mode -eq 'try') { 'ErrorRecord' } else { $entryType }
                    $unstoppedCount = $isCountFailure -and $mode -ne 'enable'
                    Assert-NativeReadRecord $capture.ErrorVariable[0] $reference $entryType -CountFailure:$isCountFailure -Unstopped:$unstoppedCount
                    Assert-NativeReadRecord $capture.History[0] $reference $historyType -CountFailure:$isCountFailure -Unstopped:$unstoppedCount
                    $capture.Errors.Count | Should -Be $(if (-not $isCountFailure -and $mode -eq 'plain') { 1 } else { 0 })
                    if ($capture.Errors.Count -eq 1) { Assert-NativeReadRecord $capture.Errors[0] $reference }
                    $capture.Warnings.Count | Should -Be $(if ($unstoppedCount) { 1 } else { 0 })
                    if ($unstoppedCount) {
                        $capture.Warnings[0].Message | Should -Match ('\[Get-DbaAgentAlertCategory\] Something went wrong getting the alert category ' + [regex]::Escape("[$deniedCategoryName]") + ' on .* \| ' + [regex]::Escape($directAlertCause.Message) + '$')
                    }
                    $shouldFail = $mode -eq 'enable' -or (-not $isCountFailure -and $mode -eq 'stop')
                    $capture.State.ToString() | Should -BeExactly $(if ($shouldFail) { 'Failed' } else { 'Completed' })
                    if ($shouldFail) {
                        $capture.Failure | Should -Not -BeNullOrEmpty
                        Assert-NativeReadRecord $capture.Reason $reference $entryType -CountFailure:$isCountFailure
                    } else {
                        $capture.Failure | Should -BeNullOrEmpty
                    }
                    if (-not $isCountFailure -and $mode -eq 'try') {
                        Assert-NativeReadRecord $capture.Caught $reference
                    } else {
                        $capture.Caught | Should -BeNullOrEmpty
                    }
                    Get-NativeRemovalFixture $deniedCategoryName | Should -Not -BeNullOrEmpty
                }

                $terminationModes = if ($deniedProcedure -eq 'sp_help_alert') { @('EnableException') } else { @('ErrorAction', 'EnableException', 'CallerTry') }
                foreach ($terminationMode in $terminationModes) {
                    $splatDeniedRead.SqlInstance = @($nativeServer, $deniedServer)
                    $splatDeniedRead.EnableException = ($terminationMode -eq "EnableException")
                    $splatDeniedRead.ErrorAction = $(if ($terminationMode -eq "ErrorAction") { "Stop" } else { "Continue" })
                    $beforeFailureOutput = New-Object "System.Collections.Generic.List[object]"
                    $readFailure = $null
                    try {
                        Remove-DbaAgentAlertCategory @splatDeniedRead | ForEach-Object { $beforeFailureOutput.Add($PSItem) }
                    } catch { $readFailure = $PSItem }
                    $readFailure | Should -Not -BeNullOrEmpty
                    if ($deniedProcedure -eq 'sp_help_category') {
                        ($readFailure.FullyQualifiedErrorId -split ',')[0] | Should -BeExactly ($directCategoryFailure.FullyQualifiedErrorId -split ',')[0]
                        $readFailure.CategoryInfo.Category | Should -Be $directCategoryFailure.CategoryInfo.Category
                        $readFailure.CategoryInfo.Reason | Should -BeExactly $directCategoryFailure.CategoryInfo.Reason
                        $readFailure.Exception.GetType().FullName | Should -BeExactly $directCategoryFailure.Exception.GetType().FullName
                        $readFailure.Exception.Message | Should -BeExactly $directCategoryFailure.Exception.Message
                    } else {
                        $readFailure.FullyQualifiedErrorId | Should -BeLike 'dbatools_Get-DbaAgentAlertCategory*'
                    }
                    $beforeFailureOutput.Count | Should -Be 0
                    Get-NativeRemovalFixture $deniedCategoryName | Should -Not -BeNullOrEmpty
                }

                $splatDeniedRead.SqlInstance = @($deniedServer, $nativeServer)
                $splatDeniedRead.EnableException = $false
                $splatDeniedRead.ErrorAction = "Continue"
                $continued = Invoke-NativeRemoveAlertCategoryPlainRead -Parameters $splatDeniedRead -Capture
                $continued.Results.Count | Should -Be 1
                $continued.Results[0].Name | Should -BeExactly $deniedCategoryName
                $continued.Results[0].IsRemoved | Should -BeTrue
                $continued.Failure | Should -BeNullOrEmpty
                if ($deniedProcedure -eq 'sp_help_alert') {
                    $continued.Errors.Count | Should -Be 0
                    $continued.Warnings.Count | Should -Be 1
                } else {
                    $continued.Errors.Count | Should -Be 1
                }
                Get-NativeRemovalFixture $deniedCategoryName | Should -BeNullOrEmpty
            } finally {
                if ($null -ne $deniedServer) { $deniedServer.ConnectionContext.Disconnect() }
                if ($deniedUserCreated) { $nativeServer.Databases["msdb"].ExecuteNonQuery("DROP USER [$deniedUser];") }
            }
        }
    }

    It "preserves nested-array conversion and literal name filtering" {
        $selected = New-NativeRemovalFixture "selected"
        $kept = New-NativeRemovalFixture "kept"
        $selectedName = $selected.Name
        $keptName = $kept.Name
        $splatNativeSelection = @{
            SqlInstance = $TestConfig.InstanceSingle
            Category    = @(@($selectedName, $keptName), $selectedName.ToUpperInvariant(), "${nativePrefix}*")
            Confirm     = $false
        }
        $result = @(Remove-DbaAgentAlertCategory @splatNativeSelection)
        $result.Count | Should -Be 1
        $result[0].Name | Should -BeExactly $selectedName
        Get-NativeRemovalFixture $selectedName | Should -BeNullOrEmpty
        Get-NativeRemovalFixture $keptName | Should -Not -BeNullOrEmpty
    }
}

Describe "Remove-DbaAgentAlertCategory SQL authentication" -Tag IntegrationTests, NativeChecklist:sql-login {
    BeforeAll {
        $loginCategoryPrefix = "native_removealert_login_$([guid]::NewGuid().ToString("N"))"
        $loginCategoryNames = @("${loginCategoryPrefix}_removed", "${loginCategoryPrefix}_denied", "${loginCategoryPrefix}_throw")
        $splatLoginConnection = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            EnableException = $true
        }
        $loginCategoryServer = Connect-DbaInstance @splatLoginConnection
        foreach ($loginCategoryCreateName in $loginCategoryNames) {
            $loginCategoryFixture = New-Object Microsoft.SqlServer.Management.Smo.Agent.AlertCategory($loginCategoryServer.JobServer, $loginCategoryCreateName)
            $loginCategoryFixture.Create()
        }
    }

    AfterAll {
        if ($null -ne $loginCategoryServer) {
            $loginCategoryServer.JobServer.AlertCategories.Refresh()
            foreach ($loginCategoryCleanupName in $loginCategoryNames) {
                $loginCategoryCleanup = $loginCategoryServer.JobServer.AlertCategories[$loginCategoryCleanupName]
                if ($null -ne $loginCategoryCleanup) { $loginCategoryCleanup.Drop() }
            }
        }
    }

    It "removes a category with SQL credentials" {
        $splatLoginCategory = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            SqlCredential   = $TestConfig.SqlLoginCred
            Category        = $loginCategoryNames[0]
            Confirm         = $false
            EnableException = $true
        }
        $loginCategoryOutput = @(Remove-DbaAgentAlertCategory @splatLoginCategory)
        $loginCategoryOutput.Count | Should -Be 1
        $loginCategoryOutput[0].Name | Should -BeExactly $loginCategoryNames[0]
        $loginCategoryOutput[0].IsRemoved | Should -BeTrue
        $loginCategoryServer.JobServer.AlertCategories.Refresh()
        $loginCategoryServer.JobServer.AlertCategories[$loginCategoryNames[0]] | Should -BeNullOrEmpty
    }

    It "warns without output or removal when SQL credentials are omitted" {
        $loginCategoryWarnings = @()
        $splatLoginCategoryDenied = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Category        = $loginCategoryNames[1]
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "loginCategoryWarnings"
        }
        # No commit can run the pin: the base ships the cmdlet, and the pin predates src/ and cannot be built.
        # Verbatim refs/pins/dbatools-2026-10-22:public/Remove-DbaAgentAlertCategory.ps1:104-113:
        # process {
        #     if ($SqlInstance) {
        #         $params = $PSBoundParameters
        #         $null = $params.Remove('WhatIf')
        #         $null = $params.Remove('Confirm')
        #         $agentCategories = Get-DbaAgentAlertCategory @params
        #     } else {
        #         $agentCategories += $InputObject
        #     }
        # }
        # Verbatim refs/pins/dbatools-2026-10-22:public/Get-DbaAgentAlertCategory.ps1:81-86:
        # foreach ($instance in $SqlInstance) {
        #     try {
        #         $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #     } catch {
        #         Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #     }
        # EnableException remains in the splat; the quoted forwarding path contains no catch to swallow the callee's error.
        @(Remove-DbaAgentAlertCategory @splatLoginCategoryDenied).Count | Should -Be 0
        $loginCategoryWarnings | Should -Not -BeNullOrEmpty
        $loginCategoryServer.JobServer.AlertCategories.Refresh()
        $loginCategoryServer.JobServer.AlertCategories[$loginCategoryNames[1]] | Should -Not -BeNullOrEmpty
    }

    It "throws without removing with EnableException when SQL credentials are omitted" {
        # The pinned function forwards bound EnableException to Get-DbaAgentAlertCategory, whose connection catch invokes Stop-Function.
        $splatLoginCategoryThrow = @{
            SqlInstance     = $TestConfig.InstanceSqlLogin
            Category        = $loginCategoryNames[2]
            Confirm         = $false
            EnableException = $true
        }
        # No commit can run the pin: the base ships the cmdlet, and the pin predates src/ and cannot be built.
        # Verbatim refs/pins/dbatools-2026-10-22:public/Remove-DbaAgentAlertCategory.ps1:104-113:
        # process {
        #     if ($SqlInstance) {
        #         $params = $PSBoundParameters
        #         $null = $params.Remove('WhatIf')
        #         $null = $params.Remove('Confirm')
        #         $agentCategories = Get-DbaAgentAlertCategory @params
        #     } else {
        #         $agentCategories += $InputObject
        #     }
        # }
        # Verbatim refs/pins/dbatools-2026-10-22:public/Get-DbaAgentAlertCategory.ps1:81-86:
        # foreach ($instance in $SqlInstance) {
        #     try {
        #         $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        #     } catch {
        #         Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
        #     }
        # EnableException remains in the splat; the quoted forwarding path contains no catch to swallow the callee's error.
        { Remove-DbaAgentAlertCategory @splatLoginCategoryThrow } | Should -Throw
        $loginCategoryServer.JobServer.AlertCategories.Refresh()
        $loginCategoryServer.JobServer.AlertCategories[$loginCategoryNames[2]] | Should -Not -BeNullOrEmpty
    }
}
