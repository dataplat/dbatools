#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentJobCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativeCategoryPrefix = "native_Job_category_" + [Guid]::NewGuid().ToString("N")
        $nativeCategoryNames = @("${nativeCategoryPrefix}_a", "${nativeCategoryPrefix}_b")
        $nativeOwnedNames = $nativeCategoryNames + @("${nativeCategoryPrefix}_pipeline", "${nativeCategoryPrefix}_throw", "${nativeCategoryPrefix}_whatif", "${nativeCategoryPrefix}_decline", "${nativeCategoryPrefix}_force")
        $nativeNestedParts = @("${nativeCategoryPrefix}_n1", "${nativeCategoryPrefix}_n2")
        $nativeNestedJoinedName = $nativeNestedParts -join " "
        $nativeNestedSingleName = "${nativeCategoryPrefix}_n3"
        $nativeOwnedNames += $nativeNestedParts + @($nativeNestedJoinedName, $nativeNestedSingleName)
        $nativeCategoryServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $nativeBadInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"
        function Get-NativeCategoryFixture {
            param([string]$Name)
            $nativeCategoryServer.JobServer.JobCategories.Refresh()
            @($nativeCategoryServer.JobServer.JobCategories | Where-Object Name -EQ $Name)
        }
        if (-not ([System.Management.Automation.PSTypeName]"NativeJobCategoryTests.ConfirmationHost").Type) {
            Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
namespace NativeJobCategoryTests {
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
        public override string Name { get { return "NativeJobCategoryConfirmation"; } }
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
        function Invoke-NativeJobCategoryConfirmation {
            param([hashtable]$Parameters, [object[]]$Instances, [string[]]$Answers = @(), [string]$Preference = "High", [switch]$InheritedWhatIf)
            $nativeConfirmationHost = New-Object NativeJobCategoryTests.ConfirmationHost -ArgumentList $Host.UI.RawUI, $Answers
            $nativeConfirmationState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $nativeScheduleType = (Get-Command New-DbaAgentJobCategory -CommandType Cmdlet).ImplementingType
            $nativeConfirmationCommand = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "New-DbaAgentJobCategory", $nativeScheduleType, $null
            $nativeConfirmationState.Commands.Add($nativeConfirmationCommand)
            $nativeConfirmationRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeConfirmationHost, $nativeConfirmationState)
            $nativeConfirmationShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $nativeConfirmationRunspace.Open()
                $nativeConfirmationRunspace.SessionStateProxy.SetVariable("ConfirmPreference", $Preference)
                $nativeConfirmationRunspace.SessionStateProxy.SetVariable("WhatIfPreference", [bool]$InheritedWhatIf)
                $nativeConfirmationShell.Runspace = $nativeConfirmationRunspace
                $null = $nativeConfirmationShell.AddCommand("New-DbaAgentJobCategory").AddParameters($Parameters)
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
        $nativeCategoryServer.JobServer.JobCategories.Refresh()
        foreach ($nativeOwnedName in $nativeOwnedNames) {
            $nativeCleanupCategory = $nativeCategoryServer.JobServer.JobCategories[$nativeOwnedName]
            if ($null -ne $nativeCleanupCategory) { $nativeCleanupCategory.Drop() }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "creates typed categories and preserves output and duplicate behavior" {
        $splatNativeCreate = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = $nativeCategoryNames
            CategoryType    = "multiserverjob"
            Confirm         = $false
            EnableException = $true
        }
        $nativeCreated = @(New-DbaAgentJobCategory @splatNativeCreate)
        $nativeCreated.Count | Should -Be 2
        $nativeCreated | Should -BeOfType Microsoft.SqlServer.Management.Smo.Agent.JobCategory
        $nativeCreated[0].Name | Should -BeExactly $nativeCategoryNames[0]
        $nativeCreated[1].Name | Should -BeExactly $nativeCategoryNames[1]
        $nativeCreated[0].JobCount | Should -Be 0
        $nativeCreated[0].SqlInstance | Should -Not -BeNullOrEmpty
        ($nativeCreated[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") |
            Should -BeExactly "ComputerName,InstanceName,SqlInstance,Name,ID,CategoryType,JobCount"
        $nativeCreated | ForEach-Object { $PSItem.CategoryType | Should -Be "MultiServerJob" }
        foreach ($nativeCreatedName in $nativeCategoryNames) {
            @(Get-NativeCategoryFixture $nativeCreatedName).Count | Should -Be 1
        }
        $splatNativeCreate.Category = $nativeCategoryNames[0].ToUpperInvariant()
        $splatNativeCreate.EnableException = $false
        $splatNativeCreate.WarningAction = "SilentlyContinue"
        $splatNativeCreate.WarningVariable = "nativeDuplicateWarnings"
        $nativeDuplicateWarnings = @()
        @(New-DbaAgentJobCategory @splatNativeCreate).Count | Should -Be 0
        ($nativeDuplicateWarnings -join " ") | Should -BeLike "*already exists*"
        $splatNativeCreate.EnableException = $true
        { New-DbaAgentJobCategory @splatNativeCreate } | Should -Throw "*already exists*"
    }

    It "converts nested category names without flattening their elements" {
        $splatNativeNested = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = @($nativeNestedParts, $nativeNestedSingleName)
            Confirm         = $false
            EnableException = $true
        }
        $nativeNested = @(New-DbaAgentJobCategory @splatNativeNested)
        $nativeNested.Count | Should -Be 2
        $nativeNested[0].Name | Should -BeExactly $nativeNestedJoinedName
        $nativeNested[1].Name | Should -BeExactly $nativeNestedSingleName
        @(Get-NativeCategoryFixture $nativeNestedJoinedName).Count | Should -Be 1
        @(Get-NativeCategoryFixture $nativeNestedSingleName).Count | Should -Be 1
        foreach ($nativePart in $nativeNestedParts) {
            @(Get-NativeCategoryFixture $nativePart).Count | Should -Be 0
        }
    }

    It "does not create a category under WhatIf even with Force" {
        $splatNativeWhatIf = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = "${nativeCategoryPrefix}_whatif"
            Force           = $true
            WhatIf          = $true
            EnableException = $true
        }
        @(New-DbaAgentJobCategory @splatNativeWhatIf).Count | Should -Be 0
        @(Get-NativeCategoryFixture $splatNativeWhatIf.Category).Count | Should -Be 0
    }

    It "honors an explicit declined confirmation and restores preferences" {
        $nativeDeclineParameters = @{
            Category        = "${nativeCategoryPrefix}_decline"
            Force           = $true
            Confirm         = $true
            EnableException = $true
        }
        $splatNativeDecline = @{
            Parameters = $nativeDeclineParameters
            Instances  = @($TestConfig.InstanceSingle)
            Answers    = @("No")
            Preference = "High"
        }
        $nativeDeclined = Invoke-NativeJobCategoryConfirmation @splatNativeDecline
        $nativeDeclined.PromptCount | Should -Be 1
        $nativeDeclined.Remaining | Should -Be 0
        $nativeDeclined.Results.Count | Should -Be 0
        $nativeDeclined.FinalPreference | Should -Be "High"
        @(Get-NativeCategoryFixture $nativeDeclineParameters.Category).Count | Should -Be 0

        $nativeForceParameters = @{
            Category        = "${nativeCategoryPrefix}_force"
            Force           = $true
            EnableException = $true
        }
        $splatNativeForce = @{
            Parameters = $nativeForceParameters
            Instances  = @($TestConfig.InstanceSingle)
            Answers    = @()
            Preference = "Low"
        }
        $nativeForced = Invoke-NativeJobCategoryConfirmation @splatNativeForce
        $nativeForced.PromptCount | Should -Be 0
        $nativeForced.Results.Count | Should -Be 1
        $nativeForced.FinalPreference | Should -Be "Low"
        @(Get-NativeCategoryFixture $nativeForceParameters.Category).Count | Should -Be 1
    }

    It "continues past a failed middle instance and detects the final duplicate" {
        $nativePipelineWarnings = @()
        $splatNativePipeline = @{
            Category        = "${nativeCategoryPrefix}_pipeline"
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativePipelineWarnings"
        }
        $nativePipelineResult = @($TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle | New-DbaAgentJobCategory @splatNativePipeline)
        $nativePipelineResult.Count | Should -Be 1
        $nativePipelineResult[0].Name | Should -BeExactly $splatNativePipeline.Category
        ($nativePipelineWarnings -join " ") | Should -BeLike "*Failure*"
        ($nativePipelineWarnings -join " ") | Should -BeLike "*already exists*"
        @(Get-NativeCategoryFixture $splatNativePipeline.Category).Count | Should -Be 1
    }

    It "streams the created category before EnableException terminates at the failed input" {
        $nativeStreamed = New-Object "System.Collections.Generic.List[object]"
        $nativeCaught = $null
        $splatNativeThrow = @{
            Category        = "${nativeCategoryPrefix}_throw"
            Confirm         = $false
            EnableException = $true
        }
        try {
            $TestConfig.InstanceSingle, $nativeBadInstance, $TestConfig.InstanceSingle |
                New-DbaAgentJobCategory @splatNativeThrow |
                ForEach-Object { $nativeStreamed.Add($PSItem) }
        } catch {
            $nativeCaught = $PSItem
        }
        $nativeStreamed.Count | Should -Be 1
        $nativeStreamed[0].Name | Should -BeExactly $splatNativeThrow.Category
        $nativeCaught | Should -Not -BeNullOrEmpty
        $nativeCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        $nativeCaught.TargetObject | Should -BeExactly "TCP:127.0.0.1,1"
        @(Get-NativeCategoryFixture $splatNativeThrow.Category).Count | Should -Be 1
    }
}
