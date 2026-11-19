#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaAgentSchedule",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "New-DbaAgentSchedule native behavior" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativeSchedulePrefix = "native_schedule_$([Guid]::NewGuid().ToString("N"))"
        $nativeScheduleServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeScheduleJobName = "${nativeSchedulePrefix}_decline_job"
        $nativeScheduleJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeScheduleServer.JobServer, $nativeScheduleJobName
        $nativeScheduleJob.Create()
        $nativeScheduleJob.ApplyToTargetServer("(local)")
        $nativeScheduleJob.Refresh()
        $nativeScheduleAttachmentCases = @(
            [pscustomobject]@{
                Suffix = "same_instance"
                Server = $nativeScheduleServer
                Target = $TestConfig.InstanceSingle
            }
        )
        if ($TestConfig.InstanceMulti1 -and $TestConfig.InstanceMulti1 -ne $TestConfig.InstanceSingle) {
            $nativeScheduleAttachmentCases += [pscustomobject]@{
                Suffix = "other_instance"
                Server = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -EnableException)
                Target = $TestConfig.InstanceMulti1
            }
        }
        foreach ($nativeAttachmentCase in $nativeScheduleAttachmentCases) {
            $nativeAttachmentJobName = "${nativeSchedulePrefix}_$($nativeAttachmentCase.Suffix)_job"
            foreach ($nativeAttachmentServer in @($nativeScheduleServer, $nativeAttachmentCase.Server | Select-Object -Unique)) {
                $nativeAttachmentJob = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job -ArgumentList $nativeAttachmentServer.JobServer, $nativeAttachmentJobName
                $nativeAttachmentJob.Create()
                $nativeAttachmentJob.ApplyToTargetServer("(local)")
            }
        }
        $nativeScheduleBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        $nativeScheduleParameters = @{
            FrequencyType           = "Daily"
            FrequencyInterval       = 1
            FrequencySubdayType     = "Once"
            FrequencySubdayInterval = 1
            StartDate               = (Get-Date).AddDays(2).ToString("yyyyMMdd")
            EndDate                 = (Get-Date).AddDays(4).ToString("yyyyMMdd")
            StartTime               = "010000"
            EndTime                 = "020000"
            EnableException         = $true
        }
        function Get-NativeScheduleFixture {
            param([string]$Name)
            # Read through SMO, independently of both Schedule cmdlets.
            $nativeScheduleServer.JobServer.SharedSchedules.Refresh()
            @($nativeScheduleServer.JobServer.SharedSchedules | Where-Object Name -EQ $Name)
        }
        if (-not ([System.Management.Automation.PSTypeName]"NativeScheduleTests.ConfirmationHost").Type) {
            Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
namespace NativeScheduleTests {
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
        public override string Name { get { return "NativeScheduleConfirmation"; } }
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
        function Invoke-NativeScheduleConfirmation {
            param([hashtable]$Parameters, [object[]]$Instances, [string[]]$Answers = @(), [string]$Preference = "High", [switch]$InheritedWhatIf)
            $nativeConfirmationHost = New-Object NativeScheduleTests.ConfirmationHost -ArgumentList $Host.UI.RawUI, $Answers
            $nativeConfirmationState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $nativeScheduleType = (Get-Command New-DbaAgentSchedule -CommandType Cmdlet).ImplementingType
            $nativeConfirmationCommand = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "New-DbaAgentSchedule", $nativeScheduleType, $null
            $nativeConfirmationState.Commands.Add($nativeConfirmationCommand)
            $nativeConfirmationRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeConfirmationHost, $nativeConfirmationState)
            $nativeConfirmationShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $nativeConfirmationRunspace.Open()
                $nativeConfirmationRunspace.SessionStateProxy.SetVariable("ConfirmPreference", $Preference)
                $nativeConfirmationRunspace.SessionStateProxy.SetVariable("WhatIfPreference", [bool]$InheritedWhatIf)
                $nativeConfirmationShell.Runspace = $nativeConfirmationRunspace
                $null = $nativeConfirmationShell.AddCommand("New-DbaAgentSchedule").AddParameters($Parameters)
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        # The unique prefix also catches a creation that failed before returning output.
        foreach ($nativeScheduleCleanupServer in @($nativeScheduleAttachmentCases.Server | Select-Object -Unique)) {
            $nativeScheduleCleanupServer.JobServer.Jobs.Refresh()
            foreach ($nativeScheduleCleanupJob in @($nativeScheduleCleanupServer.JobServer.Jobs | Where-Object Name -Like "${nativeSchedulePrefix}_*")) {
                $nativeScheduleCleanupJob.Drop()
            }
            $nativeScheduleCleanupServer.JobServer.SharedSchedules.Refresh()
            foreach ($nativeScheduleCleanup in @($nativeScheduleCleanupServer.JobServer.SharedSchedules | Where-Object Name -Like "${nativeSchedulePrefix}_*")) {
                $nativeScheduleCleanup.Drop()
            }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "warns for a failed middle record and creates distinct schedules for both valid records" {
        $splatNativeContinue = $nativeScheduleParameters.Clone()
        $splatNativeContinue.Schedule = "${nativeSchedulePrefix}_continue"
        $splatNativeContinue.EnableException = $false
        $splatNativeContinue.Confirm = $false
        $splatNativeContinue.WarningVariable = "nativeScheduleWarnings"
        $splatNativeContinue.WarningAction = "SilentlyContinue"
        $nativeScheduleWarnings = @()
        $nativeContinuedSchedules = @($TestConfig.InstanceSingle, $nativeScheduleBadInstance, $TestConfig.InstanceSingle | New-DbaAgentSchedule @splatNativeContinue)
        $nativeContinuedSchedules.Count | Should -Be 2
        $nativeContinuedSchedules[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobSchedule
        $nativeContinuedSchedules[0].ScheduleUid | Should -Not -Be $nativeContinuedSchedules[1].ScheduleUid
        ($nativeScheduleWarnings -join " ") | Should -BeLike "*Failure*"
        $nativeContinuedRows = @(Get-NativeScheduleFixture $splatNativeContinue.Schedule)
        $nativeContinuedRows.Count | Should -Be 2
        foreach ($nativeContinuedSchedule in $nativeContinuedSchedules) {
            $nativeContinuedRows.ScheduleUid | Should -Contain $nativeContinuedSchedule.ScheduleUid
            $nativeContinuedSchedule.ScheduleName | Should -BeExactly $splatNativeContinue.Schedule
            $nativeContinuedSchedule.ComputerName | Should -Not -BeNullOrEmpty
            $nativeContinuedSchedule.Description | Should -BeLike "Occurs every day at *"
        }
    }

    It "streams the first created schedule before EnableException terminates at the failed middle record" {
        $splatNativeThrow = $nativeScheduleParameters.Clone()
        $splatNativeThrow.Schedule = "${nativeSchedulePrefix}_throw"
        $splatNativeThrow.Confirm = $false
        $nativeStreamedSchedules = New-Object "System.Collections.Generic.List[object]"
        $nativeScheduleCaught = $null
        try {
            $TestConfig.InstanceSingle, $nativeScheduleBadInstance, $TestConfig.InstanceSingle |
                New-DbaAgentSchedule @splatNativeThrow |
                ForEach-Object { $nativeStreamedSchedules.Add($PSItem) }
        } catch { $nativeScheduleCaught = $PSItem }
        $nativeStreamedSchedules.Count | Should -Be 1
        $nativeScheduleCaught | Should -Not -BeNullOrEmpty
        $nativeScheduleCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeScheduleCaught.TargetObject.GetType().FullName | Should -Be "System.String"
        $nativeScheduleCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
        $nativeThrownRows = @(Get-NativeScheduleFixture $splatNativeThrow.Schedule)
        $nativeThrownRows.Count | Should -Be 1
        $nativeThrownRows[0].ScheduleUid | Should -Be $nativeStreamedSchedules[0].ScheduleUid
    }

    It "leaves SQL unchanged under WhatIf even when Force is explicitly supplied" {
        $splatNativeWhatIf = $nativeScheduleParameters.Clone()
        $splatNativeWhatIf.SqlInstance = $TestConfig.InstanceSingle
        $splatNativeWhatIf.Schedule = "${nativeSchedulePrefix}_whatif"
        $splatNativeWhatIf.Force = $true
        $splatNativeWhatIf.WhatIf = $true
        $splatNativeWhatIf.Confirm = $false
        @(New-DbaAgentSchedule @splatNativeWhatIf).Count | Should -Be 0
        @(Get-NativeScheduleFixture $splatNativeWhatIf.Schedule).Count | Should -Be 0
    }

    It "declines explicit confirmation without creating a schedule even with Force" {
        $nativeDeclineParameters = $nativeScheduleParameters.Clone()
        $nativeDeclineParameters.Schedule = "${nativeSchedulePrefix}_decline"
        $nativeDeclineParameters.Job = $nativeScheduleJobName
        $nativeDeclineParameters.Force = $true
        $nativeDeclineParameters.Confirm = $true
        $nativeScheduleJob.JobType | Should -Be "Local"
        $nativeScheduleJob.JobSchedules.Refresh()
        $nativeScheduleJob.JobSchedules.Count | Should -Be 0
        $splatNativeDecline = @{
            Parameters = $nativeDeclineParameters
            Instances  = @($TestConfig.InstanceSingle)
            Answers    = @("No", "Yes")
            Preference = "High"
        }
        $nativeDeclined = Invoke-NativeScheduleConfirmation @splatNativeDecline
        $nativeDeclined.PromptCount | Should -Be 1
        $nativeDeclined.Remaining | Should -Be 1
        $nativeDeclined.Results.Count | Should -Be 0
        $nativeDeclined.FinalPreference | Should -Be "High"
        @(Get-NativeScheduleFixture $nativeDeclineParameters.Schedule).Count | Should -Be 0
        $nativeScheduleServer.JobServer.Jobs.Refresh()
        $nativeDeclinedJob = $nativeScheduleServer.JobServer.Jobs[$nativeScheduleJobName]
        $nativeDeclinedJob.JobSchedules.Refresh()
        $nativeDeclinedJob.JobSchedules.Count | Should -Be 0
    }

    It "still requests explicit confirmation when FrequencyText selects effective Force defaults" {
        $nativeTextParameters = @{
            Schedule        = "${nativeSchedulePrefix}_text_decline"
            FrequencyText   = "Every 5 minutes"
            Confirm         = $true
            EnableException = $true
        }
        $splatNativeText = @{
            Parameters = $nativeTextParameters
            Instances  = @($TestConfig.InstanceSingle)
            Answers    = @("No")
        }
        $nativeTextDeclined = Invoke-NativeScheduleConfirmation @splatNativeText
        $nativeTextDeclined.PromptCount | Should -Be 1
        $nativeTextDeclined.Remaining | Should -Be 0
        $nativeTextDeclined.Results.Count | Should -Be 0
        @(Get-NativeScheduleFixture $nativeTextParameters.Schedule).Count | Should -Be 0
    }

    It "does not emit a prior schedule after a second record declines creation" {
        $nativeRepeatParameters = $nativeScheduleParameters.Clone()
        $nativeRepeatParameters.Schedule = "${nativeSchedulePrefix}_repeat"
        $nativeRepeatParameters.Confirm = $true
        $splatNativeRepeat = @{
            Parameters = $nativeRepeatParameters
            Instances  = @($TestConfig.InstanceSingle, $TestConfig.InstanceSingle)
            Answers    = @("Yes", "No")
        }
        $nativeRepeated = Invoke-NativeScheduleConfirmation @splatNativeRepeat
        $nativeRepeated.PromptCount | Should -Be 2
        $nativeRepeated.Remaining | Should -Be 0
        $nativeRepeated.Results.Count | Should -Be 1
        $nativeRepeatedRows = @(Get-NativeScheduleFixture $nativeRepeatParameters.Schedule)
        $nativeRepeatedRows.Count | Should -Be 1
        $nativeRepeatedRows[0].ScheduleUid | Should -Be $nativeRepeated.Results[0].ScheduleUid
    }

    It "does not offer attachment of a prior schedule when a later instance declines creation" {
        foreach ($nativeAttachmentCase in $nativeScheduleAttachmentCases) {
            $nativeAttachmentParameters = $nativeScheduleParameters.Clone()
            $nativeAttachmentParameters.Schedule = "${nativeSchedulePrefix}_$($nativeAttachmentCase.Suffix)"
            $nativeAttachmentParameters.Job = "${nativeSchedulePrefix}_$($nativeAttachmentCase.Suffix)_job"
            $nativeAttachmentParameters.Confirm = $true
            $splatNativeAttachment = @{
                Parameters = $nativeAttachmentParameters
                Instances  = @($TestConfig.InstanceSingle, $nativeAttachmentCase.Target)
                Answers    = @("Yes", "No", "No", "Yes")
            }
            # The final Yes exposes any forbidden attach after declining the second creation.
            $nativeAttachmentResult = Invoke-NativeScheduleConfirmation @splatNativeAttachment
            $nativeAttachmentResult.PromptCount | Should -Be 3
            $nativeAttachmentResult.Remaining | Should -Be 1
            $nativeAttachmentResult.Results.Count | Should -Be 1
            $nativeAttachmentCreated = @(Get-NativeScheduleFixture $nativeAttachmentParameters.Schedule)
            $nativeAttachmentCreated.Count | Should -Be 1
            $nativeAttachmentCreated[0].ScheduleUid | Should -Be $nativeAttachmentResult.Results[0].ScheduleUid
            foreach ($nativeAttachmentReadServer in @($nativeScheduleServer, $nativeAttachmentCase.Server | Select-Object -Unique)) {
                $nativeAttachmentReadServer.JobServer.Jobs.Refresh()
                $nativeAttachmentReadJob = $nativeAttachmentReadServer.JobServer.Jobs[$nativeAttachmentParameters.Job]
                $nativeAttachmentReadJob.JobSchedules.Refresh()
                $nativeAttachmentReadJob.JobSchedules.Count | Should -Be 0
            }
            if ($nativeAttachmentCase.Suffix -eq "other_instance") {
                $nativeAttachmentCase.Server.JobServer.SharedSchedules.Refresh()
                @($nativeAttachmentCase.Server.JobServer.SharedSchedules | Where-Object Name -EQ $nativeAttachmentParameters.Schedule).Count | Should -Be 0
            }
        }
    }

    It "uses Force only for inherited confirmation while preserving WhatIf and restoring caller preferences" {
        foreach ($nativePreferenceCase in @("create", "whatif", "override")) {
            $nativePreferenceParameters = $nativeScheduleParameters.Clone()
            $nativePreferenceParameters.Schedule = "${nativeSchedulePrefix}_preference_$nativePreferenceCase"
            $nativePreferenceParameters.Force = $true
            if ($nativePreferenceCase -eq "override") { $nativePreferenceParameters.WhatIf = $false }
            $splatNativePreference = @{
                Parameters      = $nativePreferenceParameters
                Instances       = @($TestConfig.InstanceSingle)
                Preference      = "Low"
                InheritedWhatIf = ($nativePreferenceCase -ne "create")
            }
            $nativePreferenceResult = Invoke-NativeScheduleConfirmation @splatNativePreference
            $nativePreferenceResult.PromptCount | Should -Be 0
            $nativePreferenceResult.FinalPreference | Should -Be "Low"
            $nativePreferenceResult.FinalWhatIf | Should -Be ($nativePreferenceCase -ne "create")
            $nativePreferenceExpected = if ($nativePreferenceCase -eq "whatif") { 0 } else { 1 }
            $nativePreferenceResult.Results.Count | Should -Be $nativePreferenceExpected
            @(Get-NativeScheduleFixture $nativePreferenceParameters.Schedule).Count | Should -Be $nativePreferenceExpected
        }
    }
}
