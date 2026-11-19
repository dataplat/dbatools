#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaDacOption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: azure-sqldb N/A -- the command connects to no server; it only builds DacFx option objects locally.

Describe "New-DbaDacOption native option contract" -Tag Native {
    BeforeAll {
        $nativeDacProfile = Join-Path $TestDrive "native.publish.xml"
        $nativeMissingProfile = Join-Path $TestDrive "missing.publish.xml"
        @'
<?xml version="1.0" encoding="utf-8"?>
<Project ToolsVersion="14.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup>
    <TargetDatabaseName>NativeDacOptionFixture</TargetDatabaseName>
    <TargetConnectionString>Server=localhost;Integrated Security=True</TargetConnectionString>
    <ProfileVersionNumber>1</ProfileVersionNumber>
    <AllowIncompatiblePlatform>True</AllowIncompatiblePlatform>
  </PropertyGroup>
</Project>
'@ | Set-Content -LiteralPath $nativeDacProfile -Encoding UTF8
        $nativeDacModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
        $nativeDacCommandType = (Get-Command New-DbaDacOption -CommandType Cmdlet).ImplementingType
        if (-not ([System.Management.Automation.PSTypeName]"NativeDacOptionTests.ConfirmationHost").Type) {
            # Same deterministic host pattern as the canonical native category confirmation tests.
            Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
namespace NativeDacOptionTests {
    public sealed class ConfirmationUI : PSHostUserInterface {
        private readonly PSHostRawUserInterface raw;
        public int PromptCount;
        public ConfirmationUI(PSHostRawUserInterface raw) { this.raw = raw; }
        public override PSHostRawUserInterface RawUI { get { return raw; } }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
            PromptCount++;
            if (PromptCount != 1) throw new InvalidOperationException("Unexpected additional confirmation request");
            for (int i = 0; i < choices.Count; i++)
                if (String.Equals(choices[i].Label.Replace("&", ""), "No", StringComparison.OrdinalIgnoreCase)) return i;
            throw new InvalidOperationException("Confirmation did not offer No");
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
        public ConfirmationHost(PSHostRawUserInterface raw) { TestUI = new ConfirmationUI(raw); }
        public override Guid InstanceId { get { return id; } }
        public override string Name { get { return "NativeDacOptionConfirmation"; } }
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
    }

    It "returns the DacFx option type for <PackageType> <OptionAction>" -TestCases @(
        @{ PackageType = "Dacpac"; OptionAction = "Export"; ExpectedType = "Microsoft.SqlServer.Dac.DacExtractOptions" }
        @{ PackageType = "Bacpac"; OptionAction = "Export"; ExpectedType = "Microsoft.SqlServer.Dac.DacExportOptions" }
        @{ PackageType = "Dacpac"; OptionAction = "Publish"; ExpectedType = "Microsoft.SqlServer.Dac.PublishOptions" }
        @{ PackageType = "Bacpac"; OptionAction = "Publish"; ExpectedType = "Microsoft.SqlServer.Dac.DacImportOptions" }
    ) {
        param($PackageType, $OptionAction, $ExpectedType)
        $options = @(New-DbaDacOption -Type $PackageType -Action $OptionAction -EnableException)
        $options.Count | Should -Be 1
        $options[0].GetType().FullName | Should -Be $ExpectedType
    }

    It "disables deployment script generation by default and supplies deployment options" {
        $options = New-DbaDacOption -Action Publish -EnableException
        $options.GenerateDeploymentScript | Should -BeFalse
        $options.DeployOptions.GetType().FullName | Should -Be "Microsoft.SqlServer.Dac.DacDeployOptions"
    }

    It "lets a profile replace deployment options while preserving explicit script generation" {
        $properties = @{
            DeployOptions = @{ AllowIncompatiblePlatform = $false }
            GenerateDeploymentScript = $true
        }
        $options = New-DbaDacOption -Action Publish -Property $properties -PublishXml $nativeDacProfile -EnableException
        $options.DeployOptions.AllowIncompatiblePlatform | Should -BeTrue
        $options.GenerateDeploymentScript | Should -BeTrue
    }

    It "performs no property initialization or profile loading under WhatIf" {
        $nativeDacWarnings = @()
        $options = @(New-DbaDacOption -Action Publish -PublishXml $nativeMissingProfile -Property @{ MissingProperty = 1 } -WhatIf -EnableException -WarningVariable nativeDacWarnings)
        $options.Count | Should -Be 0
        $nativeDacWarnings.Count | Should -Be 0
    }

    It "warns without output and permits continuation when a profile cannot be loaded" {
        $nativeDacWarnings = @()
        $nativeDacErrors = @()
        $nativeDacCaught = $null
        $nativeDacContinued = $false
        $options = @()
        try {
            $options = @(New-DbaDacOption -Action Publish -PublishXml $nativeMissingProfile -EnableException:$false -WarningAction Continue -WarningVariable nativeDacWarnings -ErrorAction Continue -ErrorVariable nativeDacErrors)
            $nativeDacContinued = $true
        } catch {
            $nativeDacCaught = $_
        }
        $nativeDacCaught | Should -BeNullOrEmpty
        $nativeDacContinued | Should -BeTrue
        $options.Count | Should -Be 0
        $nativeDacWarnings.Count | Should -Be 1
        $nativeDacWarnings[0].Message | Should -Match "Could not load profile\."
        $nativeDacErrors.Count | Should -Be 0
    }

    It "throws a catchable profile failure with EnableException and prevents continuation" {
        $nativeDacCaught = $null
        $nativeDacContinued = $false
        $options = @()
        try {
            $options = @(New-DbaDacOption -Action Publish -PublishXml $nativeMissingProfile -EnableException -ErrorAction Stop)
            $nativeDacContinued = $true
        } catch {
            $nativeDacCaught = $_
        }
        $nativeDacCaught | Should -Not -BeNullOrEmpty
        $nativeDacContinued | Should -BeFalse
        $options.Count | Should -Be 0
        $nativeDacCaught.Exception.Message | Should -Match ([regex]::Escape($nativeMissingProfile))
    }

    It "performs no property initialization or profile loading when confirmation is declined" {
        $nativeDacHost = New-Object NativeDacOptionTests.ConfirmationHost -ArgumentList $Host.UI.RawUI
        $nativeDacState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $nativeDacRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeDacHost, $nativeDacState)
        $nativeDacShell = [System.Management.Automation.PowerShell]::Create()
        try {
            $nativeDacRunspace.Open()
            $nativeDacShell.Runspace = $nativeDacRunspace
            $null = $nativeDacShell.AddCommand("Import-Module").AddParameter("Name", $nativeDacModulePath).AddParameter("ErrorAction", "Stop")
            $null = $nativeDacShell.Invoke()
            $nativeDacShell.Streams.Error.Count | Should -Be 0
            $nativeDacShell.InvocationStateInfo.State | Should -Be "Completed"
            $nativeDacShell.Commands.Clear()
            $null = $nativeDacShell.AddCommand("Get-Command").AddParameter("Name", "New-DbaDacOption").AddParameter("CommandType", "Cmdlet")
            $resolved = @($nativeDacShell.Invoke())
            $resolved.Count | Should -Be 1
            $resolved[0].ImplementingType | Should -Be $nativeDacCommandType
            $nativeDacShell.Commands.Clear()
            $nativeDacShell.Streams.Warning.Clear()
            $nativeDacShell.Streams.Error.Clear()
            $parameters = @{
                Action = "Publish"
                PublishXml = $nativeMissingProfile
                Property = @{ MissingProperty = 1 }
                EnableException = $true
                Confirm = $true
            }
            $null = $nativeDacShell.AddCommand("New-DbaDacOption").AddParameters($parameters)
            $options = @($nativeDacShell.Invoke())
            $nativeDacHost.TestUI.PromptCount | Should -Be 1
            $options.Count | Should -Be 0
            $nativeDacShell.InvocationStateInfo.State | Should -Be "Completed"
            $nativeDacShell.Streams.Error.Count | Should -Be 0
            $nativeDacShell.Streams.Warning.Count | Should -Be 0
        } finally {
            $nativeDacShell.Dispose()
            $nativeDacRunspace.Dispose()
        }
    }

    Context "DeployOptions supplied as a DacDeployOptions object" {
        # Pinned public/New-DbaDacOption.ps1:148-149 passes $Property.DeployOptions to the helper's
        # [hashtable]$Property parameter (:118). A DacDeployOptions object fails that binding with a
        # statement-terminating ParameterArgumentTransformationError. Stop-Function is not involved,
        # so -EnableException changes nothing.
        #
        # Inside any try (every Pester It is one) the source terminates without output. Only a caller
        # with no enclosing try would see it continue, and a compiled cmdlet cannot observe that, so
        # under operator decision D5 (caller-try) the port terminates in both cases with the upstream
        # record identity. The no-try case is checked from a fresh runspace.
        BeforeAll {
            $nativeDacDeployObject = New-Object Microsoft.SqlServer.Dac.DacDeployOptions
            $nativeDacBindingMessage = "Cannot process argument transformation on parameter 'Property'. Cannot convert the ""{0}"" value of type ""Microsoft.SqlServer.Dac.DacDeployOptions"" to type ""System.Collections.Hashtable""." -f $nativeDacDeployObject.ToString()
            $nativeDacIsolatedState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $nativeDacIsolatedRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeDacIsolatedState)
            $nativeDacIsolatedRunspace.Open()
            $nativeDacImportShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $nativeDacImportShell.Runspace = $nativeDacIsolatedRunspace
                $null = $nativeDacImportShell.AddCommand("Import-Module").AddParameter("Name", $nativeDacModulePath).AddParameter("ErrorAction", "Stop")
                $null = $nativeDacImportShell.Invoke()
                $nativeDacIsolatedImportErrors = $nativeDacImportShell.Streams.Error.Count
                $nativeDacImportShell.Commands.Clear()
                $null = $nativeDacImportShell.AddCommand("Get-Command").AddParameter("Name", "New-DbaDacOption").AddParameter("CommandType", "Cmdlet")
                $nativeDacIsolatedCommand = @($nativeDacImportShell.Invoke())
            } finally {
                $nativeDacImportShell.Dispose()
            }

            function Assert-NativeDacBindingRecord {
                param($Record)
                $Record | Should -Not -BeNullOrEmpty
                $Record.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentTransformationError,*"
                $Record.CategoryInfo.Category | Should -Be "InvalidData"
                $Record.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $Record.Exception.Message | Should -BeExactly $nativeDacBindingMessage
            }
        }

        AfterAll {
            if ($nativeDacIsolatedRunspace) {
                $nativeDacIsolatedRunspace.Dispose()
            }
        }

        It "loads the native command in the isolated runspace" {
            $nativeDacIsolatedImportErrors | Should -Be 0
            $nativeDacIsolatedCommand.Count | Should -Be 1
            $nativeDacIsolatedCommand[0].ImplementingType | Should -Be $nativeDacCommandType
        }

        It "terminates without output when no try encloses the call, with EnableException <UseEnableException>" -TestCases @(
            @{ UseEnableException = $false }
            @{ UseEnableException = $true }
        ) {
            param($UseEnableException)
            $nativeDacShell = [System.Management.Automation.PowerShell]::Create()
            try {
                $nativeDacShell.Runspace = $nativeDacIsolatedRunspace
                $parameters = @{
                    Action = "Publish"
                    Property = @{ DeployOptions = $nativeDacDeployObject }
                    EnableException = $UseEnableException
                }
                $null = $nativeDacShell.AddCommand("New-DbaDacOption").AddParameters($parameters)
                $nativeDacOutput = New-Object "System.Collections.Generic.List[System.Management.Automation.PSObject]"
                $nativeDacFailure = $null
                try {
                    $nativeDacShell.Invoke($null, [System.Collections.Generic.IList[System.Management.Automation.PSObject]]$nativeDacOutput)
                } catch {
                    $nativeDacFailure = $_.Exception
                }
                $nativeDacFailure | Should -Not -BeNullOrEmpty
                $nativeDacShell.InvocationStateInfo.State | Should -Be "Failed"
                $nativeDacOutput.Count | Should -Be 0
                $nativeDacShell.Streams.Warning.Count | Should -Be 0
                $nativeDacRecord = $null
                for ($nativeDacChain = $nativeDacShell.InvocationStateInfo.Reason; $null -ne $nativeDacChain; $nativeDacChain = $nativeDacChain.InnerException) {
                    if ($nativeDacChain -is [System.Management.Automation.IContainsErrorRecord] -and $nativeDacChain.ErrorRecord.FullyQualifiedErrorId -like "ParameterArgumentTransformationError,*") {
                        $nativeDacRecord = $nativeDacChain.ErrorRecord
                        break
                    }
                }
                Assert-NativeDacBindingRecord $nativeDacRecord
            } finally {
                $nativeDacShell.Dispose()
            }
        }

        It "terminates into the caller's catch without output, with ErrorAction <ErrorActionName> and EnableException <UseEnableException>" -TestCases @(
            @{ ErrorActionName = "Continue"; UseEnableException = $false }
            @{ ErrorActionName = "Continue"; UseEnableException = $true }
            @{ ErrorActionName = "Stop"; UseEnableException = $false }
            @{ ErrorActionName = "Stop"; UseEnableException = $true }
        ) {
            param($ErrorActionName, $UseEnableException)
            $nativeDacCaught = $null
            $nativeDacContinued = $false
            $options = @()
            try {
                $options = @(New-DbaDacOption -Action Publish -Property @{ DeployOptions = $nativeDacDeployObject } -EnableException:$UseEnableException -ErrorAction $ErrorActionName)
                $nativeDacContinued = $true
            } catch {
                $nativeDacCaught = $_
            }
            $nativeDacContinued | Should -BeFalse
            $options.Count | Should -Be 0
            Assert-NativeDacBindingRecord $nativeDacCaught
        }
    }

    Context "Checklist 1: pipeline input with several objects" {
        # NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input, in the pinned function or the port
        # Not applicable: no New-DbaDacOption parameter accepts pipeline input, in the pinned function
        # or the port, so there is no multi-object pipeline path. The assertion guards that claim.
        It "declares no pipeline-bound parameter" {
            $nativeDacPipelineParameters = @((Get-Command New-DbaDacOption).Parameters.Values | Where-Object {
                    $_.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and ($_.ValueFromPipeline -or $_.ValueFromPipelineByPropertyName) }
                })
            $nativeDacPipelineParameters.Count | Should -Be 0
        }
    }

    Context "Checklist 2: several instances with one failing" {
        # NativeChecklist: multi-instance-failure N/A -- no SqlInstance parameter; options are built locally without connecting
        # Not applicable: the command builds DacFx option objects locally. It has no SqlInstance
        # parameter and never connects, so there is no per-instance failure to isolate.
        It "has no SqlInstance parameter" {
            (Get-Command New-DbaDacOption).Parameters.Keys | Should -Not -Contain "SqlInstance"
        }
    }

    Context "Checklist 3: EnableException on and off for error paths" -Tag "NativeChecklist:enable-exception" {
        # Error paths: the New-DacObject helper failure (below), the profile load failure (the two
        # "profile" tests above) and the DeployOptions binding failure (the DeployOptions context above).
        It "warns without output or error records when the helper fails without EnableException" {
            $nativeDacWarnings = @()
            $nativeDacErrors = @()
            $nativeDacCaught = $null
            $options = @()
            try {
                $options = @(New-DbaDacOption -Action Export -Property @{ MissingProperty = 1 } -EnableException:$false -WarningAction Continue -WarningVariable nativeDacWarnings -ErrorAction Continue -ErrorVariable nativeDacErrors)
            } catch {
                $nativeDacCaught = $_
            }
            $nativeDacCaught | Should -BeNullOrEmpty
            $options.Count | Should -Be 0
            $nativeDacWarnings.Count | Should -Be 1
            $nativeDacWarnings[0].Message | Should -Match "Could not generate object Microsoft\.SqlServer\.Dac\.DacExtractOptions"
            $nativeDacErrors.Count | Should -Be 0
        }

        It "records the helper failure in the global error list when called from a module scope" {
            # A module's session state resolves an unqualified $Error to its own list; Write-Error, which
            # Stop-Function uses, records into the global one.
            $nativeDacScopeModule = New-Module -Name "NativeDacErrorScope$(Get-Random)" -ScriptBlock { }
            try {
                $nativeDacMarker = New-Object System.Management.Automation.ErrorRecord -ArgumentList (New-Object System.Exception "native dac marker"), "NativeDacMarker", "NotSpecified", $null
                $global:Error.Insert(0, $nativeDacMarker)
                $nativeDacScopedOptions = @(& $nativeDacScopeModule {
                        New-DbaDacOption -Action Export -Property @{ MissingProperty = 1 } -EnableException:$false -WarningAction SilentlyContinue
                    })
                $nativeDacScopedOptions.Count | Should -Be 0
                [object]::ReferenceEquals($global:Error[0], $nativeDacMarker) | Should -BeFalse
                $global:Error[0].FullyQualifiedErrorId | Should -BeLike "dbatools_New-DacObject*"
                $global:Error[0].Exception.Message | Should -Match "MissingProperty"
            } finally {
                Remove-Module -ModuleInfo $nativeDacScopeModule -ErrorAction SilentlyContinue
            }
        }

        It "throws the helper failure without output with EnableException" {
            $nativeDacCaught = $null
            $nativeDacContinued = $false
            $options = @()
            try {
                $options = @(New-DbaDacOption -Action Export -Property @{ MissingProperty = 1 } -EnableException)
                $nativeDacContinued = $true
            } catch {
                $nativeDacCaught = $_
            }
            $nativeDacCaught | Should -Not -BeNullOrEmpty
            $nativeDacContinued | Should -BeFalse
            $options.Count | Should -Be 0
            $nativeDacCaught.FullyQualifiedErrorId | Should -BeLike "dbatools_New-DacObject*"
            $nativeDacCaught.Exception.Message | Should -Match "MissingProperty"
        }
    }

    Context "Checklist 4: switches passed explicitly as false" -Tag "NativeChecklist:switch-false" {
        It 'treats -EnableException:$false like the default on success' {
            $options = @(New-DbaDacOption -Action Export -Property @{ CommandTimeout = 7 } -EnableException:$false)
            $options.Count | Should -Be 1
            $options[0].GetType().FullName | Should -Be "Microsoft.SqlServer.Dac.DacExtractOptions"
            $options[0].CommandTimeout | Should -Be 7
        }

        It 'creates the object with -WhatIf:$false and -Confirm:$false' {
            $nativeDacWhatIfOff = @(New-DbaDacOption -Action Publish -WhatIf:$false -EnableException)
            $nativeDacConfirmOff = @(New-DbaDacOption -Action Publish -Confirm:$false -EnableException)
            $nativeDacWhatIfOff.Count | Should -Be 1
            $nativeDacConfirmOff.Count | Should -Be 1
            $nativeDacWhatIfOff[0].DeployOptions.GetType().FullName | Should -Be "Microsoft.SqlServer.Dac.DacDeployOptions"
            $nativeDacConfirmOff[0].DeployOptions.GetType().FullName | Should -Be "Microsoft.SqlServer.Dac.DacDeployOptions"
        }
    }

    Context "Checklist 5: WhatIf and Confirm" -Tag "NativeChecklist:whatif-confirm" {
        # Declined confirmation is covered by the confirmation-host test above.
        It "produces no object, warning or error under WhatIf for <PackageType> <OptionAction>" -TestCases @(
            @{ PackageType = "Dacpac"; OptionAction = "Export" }
            @{ PackageType = "Bacpac"; OptionAction = "Export" }
            @{ PackageType = "Dacpac"; OptionAction = "Publish" }
            @{ PackageType = "Bacpac"; OptionAction = "Publish" }
        ) {
            param($PackageType, $OptionAction)
            $nativeDacWarnings = @()
            $nativeDacErrors = @()
            $options = @(New-DbaDacOption -Type $PackageType -Action $OptionAction -WhatIf -WarningVariable nativeDacWarnings -ErrorVariable nativeDacErrors)
            $options.Count | Should -Be 0
            $nativeDacWarnings.Count | Should -Be 0
            $nativeDacErrors.Count | Should -Be 0
        }
    }
}
