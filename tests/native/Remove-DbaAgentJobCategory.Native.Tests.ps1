#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgentJobCategory",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- SQL Server Agent job categories live in msdb on an instance; Azure SQL Database has no SQL Server Agent.

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $nativePrefix = "native_remove_job_category_" + [Guid]::NewGuid().ToString("N")
        $nativeServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $nativeOwnedNames = New-Object System.Collections.Generic.List[string]
        function New-NativeRemovalFixture {
            param([string]$Suffix, [string]$FixtureType = "LocalJob")
            $name = "${nativePrefix}_$Suffix"
            $nativeOwnedNames.Add($name)
            $category = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory -ArgumentList $nativeServer.JobServer, $name
            $category.CategoryType = $FixtureType
            $category.Create()
            $category
        }
        function Remove-NativeFixtureExternally {
            param([string]$Name)
            # Keep the pipeline object's Existing state while another SMO object removes its SQL row.
            $otherServer = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $nativeServer.ConnectionContext
            $otherCategory = $otherServer.JobServer.JobCategories[$Name]
            $otherCategory.Drop()
        }
        function Get-NativeRemovalFixture {
            param([string]$Name)
            $nativeServer.JobServer.JobCategories.Refresh()
            $nativeServer.JobServer.JobCategories[$Name]
        }
        if (-not ([System.Management.Automation.PSTypeName]"NativeRemoveJobCategoryTests.ConfirmationHost").Type) {
            Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
namespace NativeRemoveJobCategoryTests {
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
        function Invoke-NativeRemoveJobCategoryConfirmation {
            param([hashtable]$Parameters, [object[]]$Instances, [string[]]$Answers = @(), [string]$Preference = "High", [switch]$InheritedWhatIf)
            $nativeConfirmationHost = New-Object NativeRemoveJobCategoryTests.ConfirmationHost -ArgumentList $Host.UI.RawUI, $Answers
            $nativeConfirmationState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $nativeScheduleType = (Get-Command Remove-DbaAgentJobCategory -CommandType Cmdlet).ImplementingType
            $nativeConfirmationCommand = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Remove-DbaAgentJobCategory", $nativeScheduleType, $null
            $nativeConfirmationState.Commands.Add($nativeConfirmationCommand)
            $nativeConfirmationRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeConfirmationHost, $nativeConfirmationState)
            $nativeConfirmationShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $nativeConfirmationRunspace.Open()
                $nativeConfirmationRunspace.SessionStateProxy.SetVariable("ConfirmPreference", $Preference)
                $nativeConfirmationRunspace.SessionStateProxy.SetVariable("WhatIfPreference", [bool]$InheritedWhatIf)
                $nativeConfirmationShell.Runspace = $nativeConfirmationRunspace
                $null = $nativeConfirmationShell.AddCommand("Remove-DbaAgentJobCategory").AddParameters($Parameters)
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
        $nativeServer.JobServer.JobCategories.Refresh()
        foreach ($name in $nativeOwnedNames) {
            $category = $nativeServer.JobServer.JobCategories[$name]
            if ($null -ne $category) { $category.Drop() }
        }
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "buffers a live collection and reports every deletion in order" -Tag "NativeChecklist:pipeline-multiple" {
        $first = New-NativeRemovalFixture "collection_a"
        $second = New-NativeRemovalFixture "collection_b"
        $names = @($first.Name, $second.Name)
        $nativeServer.JobServer.JobCategories.Refresh()
        $result = @($nativeServer.JobServer.JobCategories | Where-Object Name -In $names | Remove-DbaAgentJobCategory -Confirm:$false)
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

    It "warns for a failed middle input and still removes later input" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
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
        $result = @(@($first, $missing, $last) | Remove-DbaAgentJobCategory @splatNativeRemove)
        $result.Count | Should -Be 3
        ($result.Name -join ",") | Should -BeExactly ($names -join ",")
        $result[0].IsRemoved | Should -BeTrue
        $result[1].IsRemoved | Should -BeFalse
        $result[1].Status | Should -Not -BeNullOrEmpty
        $result[2].IsRemoved | Should -BeTrue
        ($nativeWarnings -join " ") | Should -BeLike "*Failed removing the SQL Agent job category(-ies)*"
        Get-NativeRemovalFixture $names[0] | Should -BeNullOrEmpty
        Get-NativeRemovalFixture $names[2] | Should -BeNullOrEmpty
    }

    It "removes on the reachable instance and warns for the unreachable one" -Tag "NativeChecklist:multi-instance-failure" {
        $nativeReachable = New-NativeRemovalFixture "instances"
        $nativeReachableName = $nativeReachable.Name
        $nativeWarnings = @()
        $splatNativeInstances = @{
            SqlInstance     = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False", $TestConfig.InstanceSingle
            Category        = $nativeReachableName
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativeWarnings"
        }
        $result = @(Remove-DbaAgentJobCategory @splatNativeInstances)
        $result.Count | Should -Be 1
        $result[0].Name | Should -BeExactly $nativeReachableName
        $result[0].IsRemoved | Should -BeTrue
        ($nativeWarnings -join " ") | Should -BeLike "*Failure*"
        Get-NativeRemovalFixture $nativeReachableName | Should -BeNullOrEmpty
    }

    It "preserves earlier output and stops after a failed input with EnableException" -Tag "NativeChecklist:enable-exception" {
        $first = New-NativeRemovalFixture "throw_a"
        $missing = New-NativeRemovalFixture "throw_b"
        $last = New-NativeRemovalFixture "throw_c"
        $firstName = $first.Name
        $lastName = $last.Name
        Remove-NativeFixtureExternally $missing.Name
        $observed = New-Object System.Collections.Generic.List[object]
        {
            @($first, $missing, $last) | Remove-DbaAgentJobCategory -Confirm:$false -EnableException | ForEach-Object { $observed.Add($_) }
        } | Should -Throw
        $observed.Count | Should -Be 1
        $observed[0].Name | Should -BeExactly $firstName
        $observed[0].IsRemoved | Should -BeTrue
        Get-NativeRemovalFixture $firstName | Should -BeNullOrEmpty
        Get-NativeRemovalFixture $lastName | Should -Not -BeNullOrEmpty
    }

    It "leaves the category intact under WhatIf and declined confirmation" -Tag "NativeChecklist:whatif-confirm" {
        $category = New-NativeRemovalFixture "protected"
        $name = $category.Name
        $splatNativeWhatIf = @{
            InputObject = $category
            WhatIf      = $true
            Confirm     = $false
        }
        @(Remove-DbaAgentJobCategory @splatNativeWhatIf).Count | Should -Be 0
        Get-NativeRemovalFixture $name | Should -Not -BeNullOrEmpty
        $splatNativeConfirmation = @{
            Parameters = @{ InputObject = $category; Confirm = $true }
            Answers    = @("No")
            Instances  = @()
        }
        $declined = Invoke-NativeRemoveJobCategoryConfirmation @splatNativeConfirmation
        $declined.PromptCount | Should -Be 1
        @($declined.Results).Count | Should -Be 0
        Get-NativeRemovalFixture $name | Should -Not -BeNullOrEmpty
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
        $result = @(Remove-DbaAgentJobCategory @splatNativeSelection)
        $result.Count | Should -Be 1
        $result[0].Name | Should -BeExactly $selectedName
        Get-NativeRemovalFixture $selectedName | Should -BeNullOrEmpty
        Get-NativeRemovalFixture $keptName | Should -Not -BeNullOrEmpty
    }

    It "removes only matching named categories with a scalar CategoryType" {
        $nativeScalarLocal = New-NativeRemovalFixture "type_scalar_local"
        $nativeScalarMulti = New-NativeRemovalFixture "type_scalar_multi" "MultiServerJob"
        $nativeScalarUnselected = New-NativeRemovalFixture "type_scalar_unselected"
        $nativeScalarName = $nativeScalarLocal.Name
        $splatNativeScalarType = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = @($nativeScalarName, $nativeScalarMulti.Name)
            CategoryType    = "localjob"
            Confirm         = $false
            EnableException = $true
        }
        $nativeScalarResults = @(Remove-DbaAgentJobCategory @splatNativeScalarType)
        $nativeScalarResults.Count | Should -Be 1
        $nativeScalarResults[0].Name | Should -BeExactly $nativeScalarName
        $nativeScalarResults[0].IsRemoved | Should -BeTrue
        Get-NativeRemovalFixture $nativeScalarName | Should -BeNullOrEmpty
        (Get-NativeRemovalFixture $nativeScalarMulti.Name).CategoryType.ToString() | Should -BeExactly "MultiServerJob"
        Get-NativeRemovalFixture $nativeScalarUnselected.Name | Should -Not -BeNullOrEmpty
    }

    It "matches any listed CategoryType while preserving the name filter" {
        $nativeListLocal = New-NativeRemovalFixture "type_list_local"
        $nativeListMulti = New-NativeRemovalFixture "type_list_multi" "MultiServerJob"
        $nativeListUnselected = New-NativeRemovalFixture "type_list_unselected"
        $nativeListNames = @($nativeListLocal.Name, $nativeListMulti.Name)
        $splatNativeListTypes = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = $nativeListNames
            CategoryType    = @("LocalJob", "MultiServerJob")
            Confirm         = $false
            EnableException = $false
        }
        $nativeListResults = @(Remove-DbaAgentJobCategory @splatNativeListTypes)
        $nativeListResults.Count | Should -Be 2
        foreach ($nativeListName in $nativeListNames) {
            $nativeListResults.Name | Should -Contain $nativeListName
            Get-NativeRemovalFixture $nativeListName | Should -BeNullOrEmpty
        }
        foreach ($nativeListResult in $nativeListResults) { $nativeListResult.IsRemoved | Should -BeTrue }
        Get-NativeRemovalFixture $nativeListUnselected.Name | Should -Not -BeNullOrEmpty
    }

    It "preserves type-filtered categories under WhatIf and high-impact declined confirmation" {
        $nativeSafeLocal = New-NativeRemovalFixture "type_safe_local"
        $nativeSafeMulti = New-NativeRemovalFixture "type_safe_multi" "MultiServerJob"
        $nativeSafeNames = @($nativeSafeLocal.Name, $nativeSafeMulti.Name)
        $splatNativeTypeWhatIf = @{
            SqlInstance     = $TestConfig.InstanceSingle
            Category        = $nativeSafeNames
            CategoryType    = @("LocalJob", "MultiServerJob")
            WhatIf          = $true
            Confirm         = $false
            EnableException = $true
        }
        @(Remove-DbaAgentJobCategory @splatNativeTypeWhatIf).Count | Should -Be 0
        foreach ($nativeSafeName in $nativeSafeNames) {
            Get-NativeRemovalFixture $nativeSafeName | Should -Not -BeNullOrEmpty
        }
        $splatNativeTypeDecline = @{
            Parameters = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Category        = $nativeSafeNames
                CategoryType    = @("LocalJob", "MultiServerJob")
                EnableException = $true
            }
            Answers    = @("No", "No")
            Instances  = @()
            Preference = "High"
        }
        $nativeTypeDeclined = Invoke-NativeRemoveJobCategoryConfirmation @splatNativeTypeDecline
        $nativeTypeDeclined.PromptCount | Should -Be 2
        $nativeTypeDeclined.Remaining | Should -Be 0
        @($nativeTypeDeclined.Results).Count | Should -Be 0
        foreach ($nativeSafeName in $nativeSafeNames) {
            Get-NativeRemovalFixture $nativeSafeName | Should -Not -BeNullOrEmpty
        }
    }
}

Describe "$CommandName native metadata" -Tag NativeMetadata {
    BeforeAll {
        function Get-NativeMetadataFailure {
            param([scriptblock]$Action, [switch]$Wrapped)
            $failure = $null
            $completed = $false
            try {
                $null = & $Action
                $completed = $true
            } catch {
                $failure = $_.Exception
            }
            $completed | Should -BeFalse
            $failure | Should -Not -BeNullOrEmpty
            $chain = @()
            for ($current = $failure; $null -ne $current; $current = $current.InnerException) {
                $chain += $current
            }
            $metadataFailures = @($chain | Where-Object { $_ -is [Dataplat.Dbatools.Exceptions.NativeMetadataException] })
            $metadataFailures.Count | Should -Be 1
            if ($Wrapped) {
                $argumentFailures = @($chain | Where-Object { $_ -is [System.Management.Automation.PSArgumentException] })
                $argumentFailures.Count | Should -Be 1
                [object]::ReferenceEquals($argumentFailures[0].InnerException, $metadataFailures[0]) | Should -BeTrue
            }
            $metadataFailures[0]
        }
    }

    It "rejects <Mode> script metadata before getter execution or target fallback" -TestCases @(
        @{ Mode = "Direct" }
        @{ Mode = "Alias" }
        @{ Mode = "ConvertedAlias" }
    ) {
        param($Mode)
        # These fixtures never connect. Notes keep successful conversion out of live SMO reads.
        $nativeMetadataServer = (New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList "native-metadata-fixture")
        $nativeMetadataCalls = (New-Object 'System.Collections.Generic.List[object]')
        $nativeMetadataServer.PSObject.Properties.Add((New-Object System.Management.Automation.PSNoteProperty -ArgumentList "NativeMetadataCalls", $nativeMetadataCalls))
        $nativeMetadataServer.PSObject.Properties.Add((New-Object System.Management.Automation.PSNoteProperty -ArgumentList "NetPort", 1433))
        $nativeMetadataServer.PSObject.Properties.Add((New-Object System.Management.Automation.PSNoteProperty -ArgumentList "DbaInstanceName", "MSSQLSERVER"))
        $nativeMetadataGetter = {
            $this.NativeMetadataCalls.Add("getter")
            "metadata-host"
        }
        $nativeMetadataTerminal = "ComputerName"
        if ($Mode -ne "Direct") { $nativeMetadataTerminal = "MetadataSource" }
        $nativeMetadataServer.PSObject.Properties.Add((New-Object System.Management.Automation.PSScriptProperty -ArgumentList $nativeMetadataTerminal, $nativeMetadataGetter))
        if ($Mode -ne "Direct") {
            $nativeMetadataServer.PSObject.Properties.Add((New-Object System.Management.Automation.PSAliasProperty -ArgumentList "MetadataAlias", "MetadataSource"))
            if ($Mode -eq "ConvertedAlias") {
                $nativeMetadataServer.PSObject.Properties.Add((New-Object System.Management.Automation.PSAliasProperty -ArgumentList "ComputerName", "MetadataAlias", ([string])))
            } else {
                $nativeMetadataServer.PSObject.Properties.Add((New-Object System.Management.Automation.PSAliasProperty -ArgumentList "ComputerName", "MetadataAlias"))
            }
        }

        $nativeSavedTargets = [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms
        $nativeSavedTargetList = [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist
        $nativeSavedTypedTargets = [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms
        $nativeSavedTypedTargetList = [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransformList
        try {
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms = (New-Object 'System.Collections.Generic.Dictionary[string,System.Management.Automation.ScriptBlock]')
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist = (New-Object Dataplat.Dbatools.Message.TransformList)
            [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms = (New-Object 'System.Collections.Generic.Dictionary[string,Dataplat.Dbatools.Message.NativeMessageTransform]')
            [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransformList = (New-Object Dataplat.Dbatools.Message.NativeTransformList)
            $nativeMetadataTransform = (New-Object Dataplat.Dbatools.Message.NativeMessageTransform -ArgumentList ([Dataplat.Dbatools.Message.NativeTransformKind]::ServerFullSmoName))
            [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms.Add("microsoft.sqlserver.management.smo.server", $nativeMetadataTransform)

            $nativeReaderFailure = Get-NativeMetadataFailure {
                [Dataplat.Dbatools.Connection.SmoServerExtensions]::GetPSProperty($nativeMetadataServer, "ComputerName")
            }
            $nativeReaderFailure.Message | Should -Match ([regex]::Escape("ComputerName"))
            $nativeReaderFailure.Message | Should -Match ([regex]::Escape($nativeMetadataTerminal))
            $nativeMetadataCalls.Count | Should -Be 0

            $null = Get-NativeMetadataFailure -Wrapped -Action {
                (New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList ([object]$nativeMetadataServer))
            }
            $nativeMetadataCalls.Count | Should -Be 0

            $nativeMetadataRequest = (New-Object Dataplat.Dbatools.Message.MessageService+MessageRequest)
            $nativeMetadataRequest.FunctionName = "Remove-DbaAgentJobCategory"
            $nativeMetadataRequest.ModuleName = "dbatools"
            $nativeMetadataErrorsBefore = @([Dataplat.Dbatools.Message.MessageHost]::GetTransformErrors())
            $null = Get-NativeMetadataFailure -Wrapped -Action {
                [Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeMetadataRequest, $nativeMetadataServer)
            }
            $nativeMetadataCalls.Count | Should -Be 0
            $nativeMetadataErrorsAfter = @([Dataplat.Dbatools.Message.MessageHost]::GetTransformErrors())
            $nativeMetadataErrorsAfter.Count | Should -Be $nativeMetadataErrorsBefore.Count
            for ($nativeErrorIndex = 0; $nativeErrorIndex -lt $nativeMetadataErrorsBefore.Count; $nativeErrorIndex++) {
                [object]::ReferenceEquals($nativeMetadataErrorsBefore[$nativeErrorIndex], $nativeMetadataErrorsAfter[$nativeErrorIndex]) | Should -BeTrue
            }

            $nativeMetadataServer.PSObject.Properties.Remove("ComputerName")
            $nativeMetadataServer.PSObject.Properties.Add((New-Object System.Management.Automation.PSNoteProperty -ArgumentList "ComputerName", "metadata-host"))
            $nativeMetadataInstance = (New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList ([object]$nativeMetadataServer))
            $nativeMetadataInstance.FullSmoName | Should -BeExactly "metadata-host"
            $nativeMetadataTarget = @([Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeMetadataRequest, $nativeMetadataServer))
            $nativeMetadataTarget.Count | Should -Be 1
            [string]$nativeMetadataTarget[0] | Should -BeExactly "metadata-host"
            $nativeMetadataCalls.Count | Should -Be 0
        } finally {
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms = $nativeSavedTargets
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist = $nativeSavedTargetList
            [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms = $nativeSavedTypedTargets
            [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransformList = $nativeSavedTypedTargetList
        }
    }
}


Describe "$CommandName native message extensions" -Tag NativeMessageExtensions {
    BeforeAll {
        $nativeTransformModuleRoot = (Get-Module $ModuleName).ModuleBase
        if (-not ([System.Management.Automation.PSTypeName]"NativeMessageTransformTests.Probe").Type) {
            $splatNativeFixtureCompiler = @{}
            $nativeFixtureReferences = @([System.Management.Automation.PSObject].Assembly.Location, [Dataplat.Dbatools.Commands.DbaBaseCmdlet].Assembly.Location)
            if ($PSVersionTable.PSEdition -eq "Core") {
                $nativeFixtureReferences += @(Get-ChildItem "$PSHOME/ref/*.dll" | Select-Object -ExpandProperty FullName)
                # Compile against loaded host SMA; suppress only its known version-unification diagnostic.
                $splatNativeFixtureCompiler.CompilerOptions = @("/nowarn:1701")
            } else {
                $nativeFixtureReferences += @("System.dll", "System.Core.dll")
            }
            Add-Type -ReferencedAssemblies $nativeFixtureReferences @splatNativeFixtureCompiler -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Commands;
using Dataplat.Dbatools.Message;
namespace NativeMessageTransformTests {
    [Cmdlet("Test", "NativeMessageTransform")]
    public sealed class Probe : DbaBaseCmdlet {
        [Parameter] public string Message { get; set; }
        [Parameter] public ErrorRecord[] Records { get; set; }
        protected override void ProcessRecord() {
            var request = new MessageService.MessageRequest {
                FunctionName = "Test-Transform", ModuleName = "fixture",
                Message = Message, Level = MessageLevel.Warning, ErrorRecord = Records
            };
            MessageService.Write(this, request);
            WriteObject("completed");
        }
    }
    public sealed class StreamObserver {
        public readonly List<string> Order = new List<string>();
        public bool LoggedBeforeError;
        private readonly string marker;
        public StreamObserver(string marker) { this.marker = marker; }
        public void Attach(PowerShell shell) {
            shell.Streams.Warning.DataAdded += WarningAdded;
            shell.Streams.Error.DataAdded += ErrorAdded;
        }
        private void WarningAdded(object sender, DataAddedEventArgs args) { Order.Add("warning"); }
        private void ErrorAdded(object sender, DataAddedEventArgs args) {
            Order.Add("error");
            ObserveLog();
        }
        public void Terminated() {
            Order.Add("terminating-error");
            ObserveLog();
        }
        private void ObserveLog() {
            foreach (LogEntry entry in LogHost.GetLog())
                if (entry.Message == marker) LoggedBeforeError = true;
        }
    }
}
'@
        }
        function Set-NativeLegacyPair {
            param([bool]$IsException, [object]$Exact, [object]$Conditional)
            if ($IsException) {
                [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms = $Exact
                [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList = $Conditional
            } else {
                [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms = $Exact
                [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist = $Conditional
            }
        }
        function Invoke-NativeLegacyResolution {
            param([object]$Item, [bool]$IsException = $false)
            $nativeMarker = [Guid]::NewGuid().ToString()
            $nativeRecords = $null
            $nativeTransformShell.Commands.Clear()
            $null = $nativeTransformShell.AddCommand("Write-Message").AddParameter("Message", $nativeMarker)
            $null = $nativeTransformShell.AddParameter("FunctionName", "Test-Transform").AddParameter("ModuleName", "fixture")
            if ($IsException) {
                $nativeRecords = [System.Management.Automation.ErrorRecord[]]@(
                    (New-Object System.Management.Automation.ErrorRecord -ArgumentList $Item, "fixture", ([System.Management.Automation.ErrorCategory]::NotSpecified), $null)
                )
                $null = $nativeTransformShell.AddParameter("ErrorRecord", $nativeRecords)
            } else {
                $null = $nativeTransformShell.AddParameter("Target", $Item)
            }
            $null = $nativeTransformShell.Invoke()
            $nativeTransformShell.HadErrors | Should -BeFalse
            if ($IsException) {
                [pscustomobject]@{ Result = $nativeRecords[0].Exception }
            } else {
                $nativeLogs = @([Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object { $_.Message.Contains($nativeMarker) })
                $nativeLogs.Count | Should -Be 1
                [pscustomobject]@{ Result = $nativeLogs[0].TargetObject }
            }
        }
        function Assert-NativeTargetCollection {
            param([string]$Expected, [object]$Actual)
            ($Actual -is [System.Collections.ObjectModel.Collection[System.Management.Automation.PSObject]]) | Should -BeTrue
            $Actual.Count | Should -Be 1
            [string]$Actual[0] | Should -BeExactly $Expected
        }
        function Invoke-NativeLegacyRegistration {
            param([bool]$IsException)
            $nativeTransformShell.Commands.Clear()
            $null = $nativeTransformShell.AddCommand("Register-DbaMessageTransform")
            if ($IsException) {
                $null = $nativeTransformShell.AddParameter("ExceptionType", "System.InvalidOperationException").AddParameter("ScriptBlock", { $args[0] })
            } else {
                $null = $nativeTransformShell.AddParameter("TargetType", "System.String").AddParameter("ScriptBlock", { "caller" })
            }
            $null = $nativeTransformShell.Invoke()
            $nativeTransformShell.HadErrors | Should -BeFalse
        }
    }

    BeforeEach {
        $nativeSavedMessageState = @{
            Targets = [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms
            Exceptions = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms
            TargetList = [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist
            ExceptionList = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList
            NativeTargets = [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms
            NativeExceptions = [Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransforms
            NativeTargetList = [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransformList
            NativeExceptionList = [Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransformList
            Events = [Dataplat.Dbatools.Message.MessageHost]::Events
            DisableVerbosity = [Dataplat.Dbatools.Message.MessageHost]::DisableVerbosity
        }
        [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms = New-Object 'System.Collections.Generic.Dictionary[string,System.Management.Automation.ScriptBlock]'
        [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms = New-Object 'System.Collections.Generic.Dictionary[string,System.Management.Automation.ScriptBlock]'
        [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist = New-Object Dataplat.Dbatools.Message.TransformList
        [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList = New-Object Dataplat.Dbatools.Message.TransformList
        [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms = New-Object 'System.Collections.Generic.Dictionary[string,Dataplat.Dbatools.Message.NativeMessageTransform]'
        [Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransforms = New-Object 'System.Collections.Generic.Dictionary[string,Dataplat.Dbatools.Message.NativeMessageTransform]'
        [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransformList = New-Object Dataplat.Dbatools.Message.NativeTransformList
        [Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransformList = New-Object Dataplat.Dbatools.Message.NativeTransformList
        [Dataplat.Dbatools.Message.MessageHost]::Events = New-Object 'System.Collections.Generic.Dictionary[string,Dataplat.Dbatools.Message.MessageEventSubscription]'
        [Dataplat.Dbatools.Message.MessageHost]::DisableVerbosity = $false
        [Dataplat.Dbatools.Message.BuiltinMessageTransforms]::Register()
        $nativeTransformState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault2()
        $nativeTransformState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Test-NativeMessageTransform", ([NativeMessageTransformTests.Probe]), $null))
        $nativeTransformState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Write-Message", ([Dataplat.Dbatools.Commands.WriteMessageCommand]), $null))
        $nativeTransformRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeTransformState)
        $nativeTransformShell = [System.Management.Automation.PowerShell]::Create()
        $nativeTransformRunspace.Open()
        $nativeTransformShell.Runspace = $nativeTransformRunspace
        $nativeRegistrationSource = [IO.File]::ReadAllText((Join-Path $nativeTransformModuleRoot "private/functions/message/Register-DbaMessageTransform.ps1"))
        $null = $nativeTransformShell.AddScript($nativeRegistrationSource).Invoke()
        $nativeTransformShell.HadErrors | Should -BeFalse
        $nativeTransformShell.Commands.Clear()
    }

    AfterEach {
        try {
            if ($null -ne $nativeTransformShell) { $nativeTransformShell.Dispose() }
            if ($null -ne $nativeTransformRunspace) { $nativeTransformRunspace.Dispose() }
        } finally {
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms = $nativeSavedMessageState.Targets
            [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms = $nativeSavedMessageState.Exceptions
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist = $nativeSavedMessageState.TargetList
            [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList = $nativeSavedMessageState.ExceptionList
            [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransforms = $nativeSavedMessageState.NativeTargets
            [Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransforms = $nativeSavedMessageState.NativeExceptions
            [Dataplat.Dbatools.Message.MessageHost]::NativeTargetTransformList = $nativeSavedMessageState.NativeTargetList
            [Dataplat.Dbatools.Message.MessageHost]::NativeExceptionTransformList = $nativeSavedMessageState.NativeExceptionList
            [Dataplat.Dbatools.Message.MessageHost]::Events = $nativeSavedMessageState.Events
            [Dataplat.Dbatools.Message.MessageHost]::DisableVerbosity = $nativeSavedMessageState.DisableVerbosity
        }
    }

    It "rejects matching scripts without invocation or fallback: exception=<IsException>, conditional=<Conditional>, null=<NullScript>" -TestCases @(
        @{ IsException = $false; Conditional = $false; NullScript = $false }
        @{ IsException = $false; Conditional = $true; NullScript = $false }
        @{ IsException = $true; Conditional = $false; NullScript = $false }
        @{ IsException = $true; Conditional = $true; NullScript = $false }
        @{ IsException = $false; Conditional = $false; NullScript = $true }
        @{ IsException = $false; Conditional = $true; NullScript = $true }
        @{ IsException = $true; Conditional = $false; NullScript = $true }
        @{ IsException = $true; Conditional = $true; NullScript = $true }
    ) {
        param($IsException, $Conditional, $NullScript)
        $nativeTransformRunspace.SessionStateProxy.SetVariable("NativeTransformCallbackWasInvoked", $false)
        $nativeCallback = $null
        if (-not $NullScript) { $nativeCallback = [scriptblock]::Create('$global:NativeTransformCallbackWasInvoked = $true; $args[0]') }
        $nativeItem = if ($IsException) { New-Object System.Exception -ArgumentList "original" } else { New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList "fixture" }
        $nativeTypeName = $nativeItem.GetType().FullName.ToLowerInvariant()
        if ($Conditional) {
            $nativeKind = if ($IsException) { [Dataplat.Dbatools.Message.TransformType]::Exception } else { [Dataplat.Dbatools.Message.TransformType]::Target }
            $nativeCondition = New-Object Dataplat.Dbatools.Message.TransformCondition -ArgumentList $nativeTypeName, "fixture", "Test-*", $nativeCallback, $nativeKind
            if ($IsException) { [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList.Add($nativeCondition) }
            else { [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist.Add($nativeCondition) }
        } elseif ($IsException) {
            [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms[$nativeTypeName] = $nativeCallback
        } else {
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms[$nativeTypeName] = $nativeCallback
        }
        $nativeRequest = New-Object Dataplat.Dbatools.Message.MessageService+MessageRequest
        $nativeRequest.FunctionName = "Test-Transform"
        $nativeRequest.ModuleName = "fixture"
        $nativeErrorsBefore = @([Dataplat.Dbatools.Message.MessageHost]::GetTransformErrors()).Count
        $nativeRejection = $null
        try {
            if ($IsException) { $null = [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativeItem) }
            else { $null = [Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeRequest, $nativeItem) }
        } catch {
            for ($nativeFailure = $_.Exception; $null -ne $nativeFailure; $nativeFailure = $nativeFailure.InnerException) {
                if ($nativeFailure -is [System.NotSupportedException]) { $nativeRejection = $nativeFailure; break }
            }
        }
        $nativeRejection | Should -Not -BeNullOrEmpty
        $nativeRejection.Message.ToLowerInvariant() | Should -Match ([regex]::Escape($nativeTypeName))
        $nativeRejection.Message | Should -Match "Test-Transform"
        $nativeRejection.Message | Should -Match "fixture"
        $nativeTransformRunspace.SessionStateProxy.GetVariable("NativeTransformCallbackWasInvoked") | Should -BeFalse
        @([Dataplat.Dbatools.Message.MessageHost]::GetTransformErrors()).Count | Should -Be $nativeErrorsBefore
        [Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeRequest, $null) | Should -BeNullOrEmpty
        [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $null) | Should -BeNullOrEmpty
    }

    It "seeds legacy defaults and retains every cleared pair identity: exception=<IsException>" -TestCases @(
        @{ IsException = $false }
        @{ IsException = $true }
    ) {
        param($IsException)
        $nativeSql = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Data.SqlClient.SqlException])
        $nativeItem = if ($IsException) { New-Object System.Exception -ArgumentList "outer", $nativeSql } else { New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList "fixture" }
        Invoke-NativeLegacyRegistration $IsException
        if ($IsException) {
            [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms.Count | Should -Be 1
            [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList.GetAll().Length | Should -Be 1
            [object]::ReferenceEquals($nativeSql, (Invoke-NativeLegacyResolution $nativeItem $true).Result) | Should -BeTrue
            $nativeFirstExact = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransforms
            $nativeFirstList = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList
        } else {
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms.Count | Should -Be 3
            Assert-NativeTargetCollection "caller" (Invoke-NativeLegacyResolution "input").Result
            Assert-NativeTargetCollection "fixture" (Invoke-NativeLegacyResolution $nativeItem).Result
            $nativeFirstExact = [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms
            $nativeFirstList = [Dataplat.Dbatools.Message.MessageHost]::TargetTransformlist
        }
        $nativeFirstExact.Clear()
        foreach ($nativeCondition in $nativeFirstList.GetAll()) { $nativeFirstList.Remove($nativeCondition) }
        [object]::ReferenceEquals($nativeItem, (Invoke-NativeLegacyResolution $nativeItem $IsException).Result) | Should -BeTrue
        $nativeSecondExact = New-Object 'System.Collections.Generic.Dictionary[string,System.Management.Automation.ScriptBlock]'
        $nativeSecondList = New-Object Dataplat.Dbatools.Message.TransformList
        Set-NativeLegacyPair $IsException $nativeSecondExact $nativeSecondList
        Invoke-NativeLegacyRegistration $IsException
        $nativeSecondExact.Clear()
        foreach ($nativeCondition in $nativeSecondList.GetAll()) { $nativeSecondList.Remove($nativeCondition) }
        Set-NativeLegacyPair $IsException $nativeFirstExact $nativeFirstList
        [object]::ReferenceEquals($nativeItem, (Invoke-NativeLegacyResolution $nativeItem $IsException).Result) | Should -BeTrue
        Set-NativeLegacyPair $IsException $nativeFirstExact $nativeSecondList
        if ($IsException) { [object]::ReferenceEquals($nativeSql, (Invoke-NativeLegacyResolution $nativeItem $true).Result) | Should -BeTrue }
        else { Assert-NativeTargetCollection "fixture" (Invoke-NativeLegacyResolution $nativeItem).Result }
        Set-NativeLegacyPair $IsException $nativeSecondExact $nativeSecondList
        [object]::ReferenceEquals($nativeItem, (Invoke-NativeLegacyResolution $nativeItem $IsException).Result) | Should -BeTrue
        Invoke-NativeLegacyRegistration $IsException
        $nativeSecondExact.Count | Should -Be 1
        $nativeSecondList.GetAll().Length | Should -Be 0
        [object]::ReferenceEquals($nativeItem, (Invoke-NativeLegacyResolution $nativeItem $IsException).Result) | Should -BeTrue
    }

    It "keeps unchanged record identity and transformed record metadata" {
        $nativeSql = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Data.SqlClient.SqlException])
        $nativeTarget = New-Object object
        $nativePlain = New-Object System.Exception -ArgumentList "unchanged"
        $nativeUnchanged = New-Object System.Management.Automation.ErrorRecord -ArgumentList $nativePlain, "plain", ([System.Management.Automation.ErrorCategory]::NotSpecified), $null
        $nativeOuter = New-Object System.Exception -ArgumentList "outer", $nativeSql
        $nativeRecords = [System.Management.Automation.ErrorRecord[]]@(
            (New-Object System.Management.Automation.ErrorRecord -ArgumentList $nativeOuter, "sql", ([System.Management.Automation.ErrorCategory]::InvalidOperation), $nativeTarget)
            $nativeUnchanged
        )
        $null = $nativeTransformShell.AddCommand("Test-NativeMessageTransform").AddParameter("Message", ([Guid]::NewGuid().ToString())).AddParameter("Records", $nativeRecords)
        $nativeOutput = @($nativeTransformShell.Invoke())
        $nativeTransformShell.HadErrors | Should -BeFalse
        [string]$nativeOutput[0] | Should -BeExactly "completed"
        [object]::ReferenceEquals($nativeSql, $nativeRecords[0].Exception) | Should -BeTrue
        $nativeRecords[0].FullyQualifiedErrorId | Should -BeExactly "sql"
        $nativeRecords[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
        [object]::ReferenceEquals($nativeTarget, $nativeRecords[0].TargetObject) | Should -BeTrue
        [object]::ReferenceEquals($nativeUnchanged, $nativeRecords[1]) | Should -BeTrue
    }

    # Operator decision D4 option A: native processing ignores the library-owned legacy defaults that a
    # first caller registration or the explicit legacy initializer seeds, and rejects only a matching
    # caller registration, with the original exception attached.
    It "keeps native results for other types after a caller registration seeds the legacy defaults: exception=<IsException>" -TestCases @(
        @{ IsException = $false }
        @{ IsException = $true }
    ) {
        param($IsException)
        Invoke-NativeLegacyRegistration $IsException
        $nativeRequest = New-Object Dataplat.Dbatools.Message.MessageService+MessageRequest
        $nativeRequest.FunctionName = "Test-Transform"
        $nativeRequest.ModuleName = "fixture"
        $nativeErrorsBefore = @([Dataplat.Dbatools.Message.MessageHost]::GetTransformErrors()).Count
        $nativeRejection = $null
        if ($IsException) {
            [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList.GetAll().Length | Should -Be 1
            $nativeSql = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Data.SqlClient.SqlException])
            $nativeOuter = New-Object System.Exception -ArgumentList "outer", $nativeSql
            $nativeOther = New-Object System.ArgumentException -ArgumentList "unrelated failure"
            $nativeResolved = [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativeOuter)
            [object]::ReferenceEquals($nativeSql, $nativeResolved) | Should -BeTrue
            $nativeResolved = [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativeOther)
            [object]::ReferenceEquals($nativeOther, $nativeResolved) | Should -BeTrue
            $nativeCallerItem = New-Object System.InvalidOperationException -ArgumentList "real failure"
            try {
                $null = [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativeCallerItem)
            } catch {
                for ($nativeFailure = $_.Exception; $null -ne $nativeFailure; $nativeFailure = $nativeFailure.InnerException) {
                    if ($nativeFailure -is [System.NotSupportedException]) { $nativeRejection = $nativeFailure; break }
                }
            }
            $nativeRejection | Should -Not -BeNullOrEmpty
            $nativeRejection.Message | Should -Match "system\.invalidoperationexception"
            [object]::ReferenceEquals($nativeCallerItem, $nativeRejection.InnerException) | Should -BeTrue
        } else {
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms.Count | Should -Be 3
            $nativeInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList "fixture"
            $nativeResolved = [Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeRequest, $nativeInstance)
            Assert-NativeTargetCollection "fixture" $nativeResolved
            try {
                $null = [Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeRequest, "input")
            } catch {
                for ($nativeFailure = $_.Exception; $null -ne $nativeFailure; $nativeFailure = $nativeFailure.InnerException) {
                    if ($nativeFailure -is [System.NotSupportedException]) { $nativeRejection = $nativeFailure; break }
                }
            }
            $nativeRejection | Should -Not -BeNullOrEmpty
            $nativeRejection.Message | Should -Match "system\.string"
        }
        @([Dataplat.Dbatools.Message.MessageHost]::GetTransformErrors()).Count | Should -Be $nativeErrorsBefore
    }

    It "applies native defaults in a native cmdlet after a caller registration seeds the legacy defaults" {
        Invoke-NativeLegacyRegistration $true
        $nativeSql = [System.Runtime.Serialization.FormatterServices]::GetUninitializedObject([Microsoft.Data.SqlClient.SqlException])
        $nativeOuter = New-Object System.Exception -ArgumentList "outer", $nativeSql
        $nativeRecords = [System.Management.Automation.ErrorRecord[]]@(
            (New-Object System.Management.Automation.ErrorRecord -ArgumentList $nativeOuter, "sql", ([System.Management.Automation.ErrorCategory]::InvalidOperation), $null)
        )
        $nativeTransformShell.Commands.Clear()
        $null = $nativeTransformShell.AddCommand("Test-NativeMessageTransform").AddParameter("Message", ([Guid]::NewGuid().ToString())).AddParameter("Records", $nativeRecords)
        $nativeOutput = @($nativeTransformShell.Invoke())
        $nativeTransformShell.HadErrors | Should -BeFalse
        [string]$nativeOutput[0] | Should -BeExactly "completed"
        [object]::ReferenceEquals($nativeSql, $nativeRecords[0].Exception) | Should -BeTrue
    }

    It "never rejects because of the explicit legacy initializer alone" {
        [Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register()
        [Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register()
        [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms.Count | Should -Be 2
        [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList.GetAll().Length | Should -Be 1
        $nativeRequest = New-Object Dataplat.Dbatools.Message.MessageService+MessageRequest
        $nativeRequest.FunctionName = "Test-Transform"
        $nativeRequest.ModuleName = "fixture"
        $nativePlain = New-Object System.Exception -ArgumentList "plain"
        $nativeResolved = [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativePlain)
        [object]::ReferenceEquals($nativePlain, $nativeResolved) | Should -BeTrue
        $nativeResolved = [Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeRequest, (New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList "fixture"))
        Assert-NativeTargetCollection "fixture" $nativeResolved
    }

    It "rejects a caller condition whether it is listed before or after the library wildcard: callerFirst=<CallerFirst>" -TestCases @(
        @{ CallerFirst = $true }
        @{ CallerFirst = $false }
    ) {
        param($CallerFirst)
        $nativeCallerCondition = New-Object Dataplat.Dbatools.Message.TransformCondition -ArgumentList "system.invalid*", "*", "*", ([scriptblock]::Create('$args[0]')), ([Dataplat.Dbatools.Message.TransformType]::Exception)
        if ($CallerFirst) {
            [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList.Add($nativeCallerCondition)
            [Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register("Exception")
        } else {
            [Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register("Exception")
            [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList.Add($nativeCallerCondition)
        }
        $nativeConditions = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList.GetAll()
        $nativeConditions.Length | Should -Be 2
        $nativeExpectedFirst = if ($CallerFirst) { "system.invalid*" } else { "*" }
        $nativeConditions[0].TypeName | Should -BeExactly $nativeExpectedFirst
        $nativeRequest = New-Object Dataplat.Dbatools.Message.MessageService+MessageRequest
        $nativeRequest.FunctionName = "Test-Transform"
        $nativeRequest.ModuleName = "fixture"
        $nativeCallerItem = New-Object System.InvalidOperationException -ArgumentList "real failure"
        $nativeRejection = $null
        try {
            $null = [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativeCallerItem)
        } catch {
            for ($nativeFailure = $_.Exception; $null -ne $nativeFailure; $nativeFailure = $nativeFailure.InnerException) {
                if ($nativeFailure -is [System.NotSupportedException]) { $nativeRejection = $nativeFailure; break }
            }
        }
        $nativeRejection | Should -Not -BeNullOrEmpty
        [object]::ReferenceEquals($nativeCallerItem, $nativeRejection.InnerException) | Should -BeTrue
        $nativeOther = New-Object System.ArgumentException -ArgumentList "unrelated failure"
        $nativeResolved = [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativeOther)
        [object]::ReferenceEquals($nativeOther, $nativeResolved) | Should -BeTrue
    }

    It "rejects a seeded default whose script a caller replaced: exception=<IsException>" -TestCases @(
        @{ IsException = $false }
        @{ IsException = $true }
    ) {
        param($IsException)
        $nativeRequest = New-Object Dataplat.Dbatools.Message.MessageService+MessageRequest
        $nativeRequest.FunctionName = "Test-Transform"
        $nativeRequest.ModuleName = "fixture"
        $nativeCallerScript = [scriptblock]::Create('$global:NativeTransformCallbackWasInvoked = $true; $args[0]')
        $nativeTransformRunspace.SessionStateProxy.SetVariable("NativeTransformCallbackWasInvoked", $false)
        $nativeRejection = $null
        if ($IsException) {
            [Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register("Exception")
            $nativeSeeded = [Dataplat.Dbatools.Message.MessageHost]::ExceptionTransformList.GetAll()
            $nativeSeeded.Length | Should -Be 1
            $nativeSeeded[0].TypeName | Should -BeExactly "*"
            $nativeItem = New-Object System.InvalidOperationException -ArgumentList "real failure"
            [object]::ReferenceEquals($nativeItem, [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativeItem)) | Should -BeTrue
            $nativeSeeded[0].ScriptBlock = $nativeCallerScript
            try {
                $null = [Dataplat.Dbatools.Message.MessageService]::ResolveException($null, $nativeRequest, $nativeItem)
            } catch {
                for ($nativeFailure = $_.Exception; $null -ne $nativeFailure; $nativeFailure = $nativeFailure.InnerException) {
                    if ($nativeFailure -is [System.NotSupportedException]) { $nativeRejection = $nativeFailure; break }
                }
            }
            $nativeRejection | Should -Not -BeNullOrEmpty
            [object]::ReferenceEquals($nativeItem, $nativeRejection.InnerException) | Should -BeTrue
        } else {
            [Dataplat.Dbatools.Message.LegacyMessageTransforms]::Register("Target")
            $nativeItem = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList "fixture"
            Assert-NativeTargetCollection "fixture" ([Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeRequest, $nativeItem))
            [Dataplat.Dbatools.Message.MessageHost]::TargetTransforms["dataplat.dbatools.parameter.dbainstanceparameter"] = $nativeCallerScript
            try {
                $null = [Dataplat.Dbatools.Message.MessageService]::ResolveTarget($null, $nativeRequest, $nativeItem)
            } catch {
                for ($nativeFailure = $_.Exception; $null -ne $nativeFailure; $nativeFailure = $nativeFailure.InnerException) {
                    if ($nativeFailure -is [System.NotSupportedException]) { $nativeRejection = $nativeFailure; break }
                }
            }
            $nativeRejection | Should -Not -BeNullOrEmpty
            $nativeRejection.Message | Should -Match "dataplat\.dbatools\.parameter\.dbainstanceparameter"
        }
        $nativeTransformRunspace.SessionStateProxy.GetVariable("NativeTransformCallbackWasInvoked") | Should -BeFalse
    }

    It "rejects native events after logging and respects error action: stop=<Stop>, matching=<Matching>" -TestCases @(
        @{ Stop = $false; Matching = $true }
        @{ Stop = $true; Matching = $true }
        @{ Stop = $false; Matching = $false }
    ) {
        param($Stop, $Matching)
        $nativeMarker = [Guid]::NewGuid().ToString()
        $nativeTransformRunspace.SessionStateProxy.SetVariable("NativeEventCallbackWasInvoked", $false)
        $nativeEvent = New-Object Dataplat.Dbatools.Message.MessageEventSubscription
        $nativeEvent.Name = "fixture-event"
        $nativeEvent.FunctionNameFilter = if ($Matching) { "Test-Transform" } else { "Other-Transform" }
        $nativeEvent.ScriptBlock = [scriptblock]::Create('$global:NativeEventCallbackWasInvoked = $true')
        [Dataplat.Dbatools.Message.MessageHost]::Events["fixture-event"] = $nativeEvent
        $nativeObserver = New-Object NativeMessageTransformTests.StreamObserver -ArgumentList $nativeMarker
        $nativeObserver.Attach($nativeTransformShell)
        $nativeErrorAction = if ($Stop) { [System.Management.Automation.ActionPreference]::Stop } else { [System.Management.Automation.ActionPreference]::Continue }
        $null = $nativeTransformShell.AddCommand("Test-NativeMessageTransform").AddParameter("Message", $nativeMarker).AddParameter("ErrorAction", $nativeErrorAction)
        $nativeOutput = New-Object 'System.Collections.Generic.List[System.Management.Automation.PSObject]'
        $nativeStopped = $null
        try {
            $nativeTransformShell.Invoke($null, [System.Collections.Generic.IList[System.Management.Automation.PSObject]]$nativeOutput)
        } catch {
            $nativeStopped = $_.Exception
            while ($nativeStopped -is [System.Management.Automation.MethodInvocationException] -or $nativeStopped -is [System.Reflection.TargetInvocationException]) {
                $nativeStopped = $nativeStopped.InnerException
            }
            ($nativeStopped -is [System.Management.Automation.RuntimeException]) | Should -BeTrue
            $nativeObserver.Terminated()
        }
        $nativeExpectedErrors = if ($Matching -and -not $Stop) { 1 } else { 0 }
        $nativeTransformShell.Streams.Error.Count | Should -Be $nativeExpectedErrors
        if ($Matching) {
            if ($Stop) { $nativeStopped | Should -Not -BeNullOrEmpty }
            $nativeObserver.LoggedBeforeError | Should -BeTrue
            $nativeError = if ($Stop) { $nativeStopped.ErrorRecord } else { $nativeTransformShell.Streams.Error[0] }
            $nativeError | Should -Not -BeNullOrEmpty
            ($nativeError.Exception -is [System.NotSupportedException]) | Should -BeTrue
            $nativeError.FullyQualifiedErrorId | Should -BeExactly "NativeMessageEventNotSupported,NativeMessageTransformTests.Probe"
            $nativeError.CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
            $nativeError.TargetObject | Should -BeExactly "fixture-event"
            $nativeExpectedOrder = if ($Stop) { "warning,terminating-error" } else { "warning,error" }
            ($nativeObserver.Order -join ",") | Should -BeExactly $nativeExpectedOrder
        } else {
            ($nativeObserver.Order -join ",") | Should -BeExactly "warning"
        }
        if ($Stop) {
            $nativeStopped | Should -Not -BeNullOrEmpty
            $nativeTransformShell.InvocationStateInfo.State | Should -Be ([System.Management.Automation.PSInvocationState]::Failed)
            $nativeOutput.Count | Should -Be 0
        } else {
            $nativeStopped | Should -BeNullOrEmpty
            $nativeOutput.Count | Should -Be 1
            [string]$nativeOutput[0] | Should -BeExactly "completed"
        }
        $nativeTransformRunspace.SessionStateProxy.GetVariable("NativeEventCallbackWasInvoked") | Should -BeFalse
    }
}

Describe "Native Remove-DbaAgentJobCategory over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginCategoryName = "native_remove_category_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginCategory = New-Object Microsoft.SqlServer.Management.Smo.Agent.JobCategory -ArgumentList $loginServer.JobServer, $loginCategoryName
            $loginCategory.CategoryType = "LocalJob"
            $loginCategory.Create()
        }
        AfterAll {
            if ($loginServer) {
                $loginServer.JobServer.JobCategories.Refresh()
                $loginCleanup = $loginServer.JobServer.JobCategories[$loginCategoryName]
                if ($null -ne $loginCleanup) { $loginCleanup.Drop() }
            }
        }

        It "fails cleanly without the credential: a warning, no output and the category kept" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Category        = $loginCategoryName
                Confirm         = $false
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Remove-DbaAgentJobCategory @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
            $loginServer.JobServer.JobCategories.Refresh()
            $loginServer.JobServer.JobCategories[$loginCategoryName] | Should -Not -BeNullOrEmpty
        }

        It "fails cleanly without the credential: -EnableException throws" {
            $splatLoginThrow = @{
                SqlInstance     = $loginInstance
                Category        = $loginCategoryName
                Confirm         = $false
                EnableException = $true
            }
            { Remove-DbaAgentJobCategory @splatLoginThrow } | Should -Throw
        }

        It "works with -SqlCredential" {
            $splatLoginRemove = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Category        = $loginCategoryName
                Confirm         = $false
                EnableException = $true
            }
            $loginRows = @(Remove-DbaAgentJobCategory @splatLoginRemove)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly $loginCategoryName
            $loginRows[0].IsRemoved | Should -BeTrue
            $loginServer.JobServer.JobCategories.Refresh()
            $loginServer.JobServer.JobCategories[$loginCategoryName] | Should -BeNullOrEmpty
        }
    }
}
