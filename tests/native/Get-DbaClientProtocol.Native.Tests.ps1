#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaClientProtocol",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters.
# NativeChecklist: sql-login N/A -- The pinned command has no SqlCredential and opens no SQL Server connection; its Credential is a Windows credential for the computer's WMI.
# NativeChecklist: azure-sqldb N/A -- Client protocols are SQL Server client network settings of a Windows computer, read over the SQL Server WMI provider (SQL Server Configuration Manager, SQL Server on Windows only); Azure SQL Database has no computer or WMI provider to read. https://learn.microsoft.com/sql/database-engine/configure-windows/configure-client-protocols
# The pinned integration Describe is skipped unless $env:appveyor is set, which no leg sets. The native test below covers it (operator decision, 2026-10-31): on the 2017 and 2019 legs it asserts the pinned behaviour on the leg's SQL Server computer; on the 2022 legs, whose computers ship no SQL Native Client, it proves the no-results case.
# NativeSkip: Get-DbaClientProtocol -- covered: Native Get-DbaClientProtocol.Protocols of the leg's SQL Server computer.returns some protocols, or on SQL Server 2022 no protocols
Describe "Native Get-DbaClientProtocol" -Tag IntegrationTests {
    BeforeAll {
        $nativeClientInstance = New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSingle
        $nativeClientComputer = $nativeClientInstance.ComputerName
        $nativeClientFqdn = [System.Net.Dns]::GetHostEntry($nativeClientComputer).HostName
        # A test's case follows the leg's SQL Server version, never what the computer returns.
        $nativeClientMajor = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle).VersionMajor
        $nativeMissingComputer = "nativenx" + [guid]::NewGuid().ToString("N").Substring(0, 12) + ".invalid"

        # Reads over CIM directly the newest ComputerManagement namespace, the one the command selects.
        function Get-NativeClientNamespace($computer) {
            $splatNamespaceQuery = @{
                ComputerName = $computer
                Namespace    = "root\Microsoft\SQLServer"
                Query        = "SELECT * FROM __NAMESPACE WHERE Name LIKE 'ComputerManagement%'"
                ErrorAction  = "Stop"
            }
            (Get-CimInstance @splatNamespaceQuery | Sort-Object Name -Descending | Select-Object -First 1).Name
        }

        # Reads the ClientNetworkProtocol rows of that namespace over CIM directly.
        function Get-NativeClientProtocolRow($computer) {
            $splatProtocolRead = @{
                ComputerName = $computer
                Namespace    = "root\Microsoft\SQLServer\" + (Get-NativeClientNamespace $computer)
                ClassName    = "ClientNetworkProtocol"
                ErrorAction  = "Stop"
            }
            @(Get-CimInstance @splatProtocolRead)
        }

        function Get-NativeEnabledOrder($rows) {
            @($rows | Where-Object ProtocolOrder -gt 0 | Sort-Object ProtocolOrder | ForEach-Object { $PSItem.ProtocolName })
        }

        $nativeExpectedRows = @(Get-NativeClientProtocolRow $nativeClientComputer)
    }

    Context "Protocols of the leg's SQL Server computer" {
        It "returns some protocols, or on SQL Server 2022 no protocols" {
            $nativeProtocolWarnings = @()
            $results = @(Get-DbaClientProtocol -ComputerName $nativeClientComputer -WarningAction SilentlyContinue -WarningVariable nativeProtocolWarnings)
            if ($nativeClientMajor -eq 16) {
                Get-NativeClientNamespace $nativeClientComputer | Should -Be "ComputerManagement16"
                @(Get-NativeClientProtocolRow $nativeClientComputer).Count | Should -Be 0
                $results.Count | Should -Be 0
                $nativeClientName = (Resolve-DbaNetworkName -ComputerName $nativeClientComputer).FullComputerName
                $nativeProtocolWarnings.Count | Should -Be 1
                $nativeProtocolWarnings[0].Message | Should -Match ([regex]::Escape("[Get-DbaClientProtocol] No Sql ClientNetworkProtocol found on $nativeClientName") + '$')
            } else {
                $results.Status.Count | Should -BeGreaterThan 1
                $results | Where-Object ProtocolDisplayName -eq "TCP/IP" | Should -Not -BeNullOrEmpty
                @($results.ProtocolName | Sort-Object) | Should -Be @($nativeExpectedRows.ProtocolName | Sort-Object)
            }
        }

        It "shows the pinned default view and aliases, with IsEnabled following ProtocolOrder" {
            $results = @(Get-DbaClientProtocol -ComputerName $nativeClientComputer)
            $results.Count | Should -Be $nativeExpectedRows.Count
            foreach ($protocol in $results) {
                $protocol.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @("ComputerName", "DisplayName", "DLL", "Order", "IsEnabled")
                $protocol.ComputerName | Should -Be $protocol.PSComputerName
                $protocol.DisplayName | Should -Be $protocol.ProtocolDisplayName
                $protocol.DLL | Should -Be $protocol.ProtocolDll
                $protocol.Order | Should -Be $protocol.ProtocolOrder
                $protocol.IsEnabled | Should -Be ($protocol.ProtocolOrder -ne 0)
                $expected = $nativeExpectedRows | Where-Object ProtocolName -eq $protocol.ProtocolName
                $protocol.ProtocolOrder | Should -Be $expected.ProtocolOrder
                @($protocol.PSObject.TypeNames) | Should -Be @($expected.PSObject.TypeNames)
            }
        }

        It "returns the protocols of every piped computer" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($nativeClientComputer, $nativeClientFqdn | Get-DbaClientProtocol)
            $results.Count | Should -Be (2 * $nativeExpectedRows.Count)
            @($results | Where-Object ProtocolDisplayName -eq "TCP/IP").Count | Should -Be (2 * @($nativeExpectedRows | Where-Object ProtocolDisplayName -eq "TCP/IP").Count)
        }

        It "warns for a computer DNS cannot resolve and goes on to the next one" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            $nativeClientWarnings = @()
            $results = @(Get-DbaClientProtocol -ComputerName $nativeMissingComputer, $nativeClientComputer -EnableException:$false -WarningAction SilentlyContinue -WarningVariable nativeClientWarnings)
            $results.Count | Should -Be $nativeExpectedRows.Count
            $nativeMissingWarnings = @($nativeClientWarnings | Where-Object { $PSItem.Message.Contains($nativeMissingComputer) })
            $nativeMissingWarnings.Count | Should -Be 2
            $nativeMissingWarnings[0].Message | Should -Match ([regex]::Escape("[Resolve-DbaNetworkName] DNS name $nativeMissingComputer not found | "))
            $nativeMissingWarnings[1].Message | Should -Match ([regex]::Escape("[Get-DbaClientProtocol] Failed to connect to $nativeMissingComputer") + '$')
        }

        It "only warns under EnableException, as the pinned nested calls never throw" -Tag "NativeChecklist:enable-exception" {
            $nativeClientWarnings = @()
            $nativeClientErrors = @()
            $results = @(Get-DbaClientProtocol -ComputerName $nativeMissingComputer, $nativeClientComputer -EnableException -WarningAction SilentlyContinue -WarningVariable nativeClientWarnings -ErrorVariable nativeClientErrors)
            $results.Count | Should -Be $nativeExpectedRows.Count
            @($nativeClientWarnings | Where-Object { $PSItem.Message.Contains($nativeMissingComputer) }).Count | Should -Be 2
            # The nested Resolve-DbaNetworkName's Stop-Function record reaches -ErrorVariable, nothing else (pin 236550ae, case S1:
            # its record is there in every mode; correction nested-error-variable).
            $nativeClientErrors.Count | Should -Be 1
            $nativeClientErrors[0].FullyQualifiedErrorId | Should -BeLike "dbatools_Resolve-DbaNetworkName*"
            $nativeClientErrors[0].Exception.Message | Should -Not -BeNullOrEmpty
        }

        It "defaults ComputerName to the local computer" {
            $nativeDefaultWarnings = @()
            $nativeExplicitWarnings = @()
            $default = @(Get-DbaClientProtocol -WarningAction SilentlyContinue -WarningVariable nativeDefaultWarnings)
            $explicit = @(Get-DbaClientProtocol -ComputerName $env:COMPUTERNAME -WarningAction SilentlyContinue -WarningVariable nativeExplicitWarnings)
            ($default.Count + $nativeDefaultWarnings.Count) | Should -BeGreaterThan 0
            @($default.ProtocolName) | Should -Be @($explicit.ProtocolName)
            $ownDefault = @($nativeDefaultWarnings | Where-Object { $PSItem.Message.Contains("[Get-DbaClientProtocol]") } | ForEach-Object { $PSItem.Message -replace '^\[\d\d:\d\d:\d\d\]', '' })
            $ownExplicit = @($nativeExplicitWarnings | Where-Object { $PSItem.Message.Contains("[Get-DbaClientProtocol]") } | ForEach-Object { $PSItem.Message -replace '^\[\d\d:\d\d:\d\d\]', '' })
            $ownDefault | Should -Be $ownExplicit
        }
    }

    Context "A SQL Server 2022 computer, which ships no SQL Native Client" {
        BeforeAll {
            $nativeNoClientComputer = (New-Object Dataplat.Dbatools.Parameter.DbaInstanceParameter -ArgumentList $TestConfig.InstanceSqlLogin).ComputerName
        }

        It "warns that it found no client protocol when the newest namespace holds none" {
            Get-NativeClientNamespace $nativeNoClientComputer | Should -Be "ComputerManagement16"
            @(Get-NativeClientProtocolRow $nativeNoClientComputer).Count | Should -Be 0

            $nativeNoClientName = (Resolve-DbaNetworkName -ComputerName $nativeNoClientComputer).FullComputerName
            $nativeNoClientWarnings = @()
            $results = @(Get-DbaClientProtocol -ComputerName $nativeNoClientComputer -WarningAction SilentlyContinue -WarningVariable nativeNoClientWarnings)
            $results.Count | Should -Be 0
            $nativeNoClientWarnings.Count | Should -Be 1
            $nativeNoClientWarnings[0].Message | Should -Match ([regex]::Escape("[Get-DbaClientProtocol] No Sql ClientNetworkProtocol found on $nativeNoClientName") + '$')
        }
    }

    Context "Enable and Disable methods" {
        BeforeAll {
            $nativeOriginalOrder = @(Get-NativeEnabledOrder (Get-NativeClientProtocolRow $nativeClientComputer))
            $nativeToggleName = if ($nativeOriginalOrder) { $nativeOriginalOrder[-1] }

            # A host that records what it is asked and shown, and answers a confirmation with the label in Answer.
            if (-not ([System.Management.Automation.PSTypeName]"NativeClientProtocolTests.ConfirmationHost").Type) {
                Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
namespace NativeClientProtocolTests {
    public sealed class ConfirmationUI : PSHostUserInterface {
        private readonly PSHostRawUserInterface raw;
        public string Answer = "No";
        public readonly List<string> Captions = new List<string>();
        public readonly List<string> Prompts = new List<string>();
        public readonly List<string> Choices = new List<string>();
        public readonly List<int> Defaults = new List<int>();
        public readonly List<string> Writes = new List<string>();
        public ConfirmationUI(PSHostRawUserInterface raw) { this.raw = raw; }
        public override PSHostRawUserInterface RawUI { get { return raw; } }
        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice) {
            Captions.Add(caption);
            Prompts.Add(message);
            Defaults.Add(defaultChoice);
            List<string> labels = new List<string>();
            foreach (ChoiceDescription choice in choices) { labels.Add(choice.Label); }
            Choices.Add(String.Join("|", labels.ToArray()));
            for (int i = 0; i < choices.Count; i++)
                if (String.Equals(choices[i].Label.Replace("&", ""), Answer, StringComparison.OrdinalIgnoreCase)) return i;
            throw new InvalidOperationException("Confirmation did not offer " + Answer);
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
        public override string Name { get { return "NativeClientProtocolConfirmation"; } }
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

            # The preferences are set globally in a runspace of its own, with that host: the pinned ScriptMethods'
            # Invoke-CimMethod reads them through the module's scope, which reaches the global scope only.
            $nativeShouldHost = New-Object NativeClientProtocolTests.ConfirmationHost -ArgumentList $Host.UI.RawUI
            $nativeShouldRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($nativeShouldHost, [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault())
            $nativeShouldRunspace.Open()
            $nativeShouldShell = [System.Management.Automation.PowerShell]::Create()
            $nativeShouldShell.Runspace = $nativeShouldRunspace
            $nativeShouldModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $nativeShouldShell.AddCommand("Import-Module").AddParameter("Name", $nativeShouldModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            # Calls Method on the protocol Name of Computer with $WhatIfPreference ($true) or $ConfirmPreference (Medium) set
            # globally, the host answering Answer. Returns the method result and what the host recorded.
            function Invoke-NativeShouldCase {
                param([string]$Case, [string]$Method, [string]$Answer = "No")
                $ui = $nativeShouldHost.TestUI
                $ui.Answer = $Answer
                $ui.Captions.Clear(); $ui.Prompts.Clear(); $ui.Choices.Clear(); $ui.Defaults.Clear(); $ui.Writes.Clear()
                $nativeShouldShell.Commands.Clear()
                $nativeShouldShell.Streams.Error.Clear()
                $caseScript = {
                    param($Computer, $Name, $Case, $Method)
                    $protocol = Get-DbaClientProtocol -ComputerName $Computer -WarningAction SilentlyContinue | Where-Object ProtocolName -eq $Name
                    try {
                        if ($Case -eq "WhatIf") { $global:WhatIfPreference = $true } else { $global:ConfirmPreference = "Medium" }
                        $result = if ($Method -eq "Disable") { $protocol.Disable() } else { $protocol.Enable() }
                    } finally {
                        $global:WhatIfPreference = $false
                        $global:ConfirmPreference = "High"
                    }
                    [pscustomobject]@{ Found = $null -ne $protocol; IsNull = $null -eq $result; ReturnValue = $(if ($null -ne $result) { $result.ReturnValue }) }
                }
                $null = $nativeShouldShell.AddScript($caseScript.ToString()).AddArgument($nativeClientComputer).AddArgument($nativeToggleName).AddArgument($Case).AddArgument($Method)
                $output = @($nativeShouldShell.Invoke())
                if ($nativeShouldShell.HadErrors) { throw $nativeShouldShell.Streams.Error[0] }
                [pscustomobject]@{
                    Found       = $output[0].Found
                    IsNull      = $output[0].IsNull
                    ReturnValue = $output[0].ReturnValue
                    Captions    = @($ui.Captions.ToArray())
                    Prompts     = @($ui.Prompts.ToArray())
                    Choices     = @($ui.Choices.ToArray())
                    Defaults    = @($ui.Defaults.ToArray())
                    Writes      = @($ui.Writes.ToArray())
                }
            }

            # A script that sets $WhatIfPreference at its top, in its own script scope, then calls Method on the protocol it is given.
            $nativeScriptScopeFile = Join-Path ([System.IO.Path]::GetTempPath()) ("native-clientprotocol-" + [guid]::NewGuid().ToString("N") + ".ps1")
            $nativeScriptScopeText = @(
                'param($Protocol, $Method)'
                '$WhatIfPreference = $true'
                'if ($Method -eq "Disable") { $Protocol.Disable() } else { $Protocol.Enable() }'
            )
            Set-Content -Path $nativeScriptScopeFile -Value $nativeScriptScopeText -Encoding UTF8

            # Calls Method on a PSObject.Copy() of the protocol Name of Computer, in the runspace above, with $WhatIfPreference
            # set globally (Scope Global) or at the top of the script above (Scope Script). Returns the method result, whether
            # the copy holds the same CIM instance, and what the host recorded.
            function Invoke-NativeCopyCase {
                param([string]$Scope, [string]$Method)
                $ui = $nativeShouldHost.TestUI
                $ui.Answer = "No"
                $ui.Captions.Clear(); $ui.Prompts.Clear(); $ui.Choices.Clear(); $ui.Defaults.Clear(); $ui.Writes.Clear()
                $nativeShouldShell.Commands.Clear()
                $nativeShouldShell.Streams.Error.Clear()
                $copyScript = {
                    param($Computer, $Name, $Scope, $Method, $ScriptFile)
                    $protocol = Get-DbaClientProtocol -ComputerName $Computer -WarningAction SilentlyContinue | Where-Object ProtocolName -eq $Name
                    $copy = $protocol.PSObject.Copy()
                    try {
                        if ($Scope -eq "Global") {
                            $global:WhatIfPreference = $true
                            $result = if ($Method -eq "Disable") { $copy.Disable() } else { $copy.Enable() }
                        } else {
                            $result = & $ScriptFile -Protocol $copy -Method $Method
                        }
                    } finally {
                        $global:WhatIfPreference = $false
                    }
                    [pscustomobject]@{
                        Found      = $null -ne $protocol
                        HasMethod  = $null -ne $copy.PSObject.Methods[$Method]
                        SameObject = [object]::ReferenceEquals($copy.PSObject.BaseObject, $protocol.PSObject.BaseObject)
                        IsNull     = $null -eq $result
                    }
                }
                $null = $nativeShouldShell.AddScript($copyScript.ToString()).AddArgument($nativeClientComputer).AddArgument($nativeToggleName).AddArgument($Scope).AddArgument($Method).AddArgument($nativeScriptScopeFile)
                $output = @($nativeShouldShell.Invoke())
                if ($nativeShouldShell.HadErrors) { throw $nativeShouldShell.Streams.Error[0] }
                [pscustomobject]@{
                    Found      = $output[0].Found
                    HasMethod  = $output[0].HasMethod
                    SameObject = $output[0].SameObject
                    IsNull     = $output[0].IsNull
                    Prompts    = @($ui.Prompts.ToArray())
                    Writes     = @($ui.Writes.ToArray())
                }
            }
        }

        AfterAll {
            if ($nativeShouldShell) { $nativeShouldShell.Dispose() }
            if ($nativeShouldRunspace) { $nativeShouldRunspace.Dispose() }
            if ($nativeScriptScopeFile -and (Test-Path -Path $nativeScriptScopeFile)) { Remove-Item -Path $nativeScriptScopeFile }
            # Put the computer's client protocols back as they were: re-enable any that were
            # enabled, then restore their order.
            try {
                $nativeNowRows = @(Get-NativeClientProtocolRow $nativeClientComputer)
                if (((Get-NativeEnabledOrder $nativeNowRows) -join ",") -ne ($nativeOriginalOrder -join ",")) {
                    foreach ($row in $nativeNowRows) {
                        if ($row.ProtocolOrder -eq 0 -and $row.ProtocolName -in $nativeOriginalOrder) {
                            $null = Invoke-CimMethod -InputObject $row -MethodName SetEnable
                        }
                    }
                    $nativeAnyRow = @(Get-NativeClientProtocolRow $nativeClientComputer)[0]
                    $null = Invoke-CimMethod -InputObject $nativeAnyRow -MethodName SetProtocolsOrder -Arguments @{ ProtocolOrderList = [string[]]$nativeOriginalOrder }
                }
            } catch {
                Write-Warning ("Could not restore the client protocol order on " + $nativeClientComputer + ": " + $PSItem.Exception.Message)
            }
        }

        It "Disable() and Enable() switch the protocol over WMI and return the method result" {
            # The methods live on returned objects. On a SQL Server 2022 computer a successful read of no rows leaves
            # nothing to call them on; a failed read fails this test and any row runs them.
            $nativeToggleRows = @(Get-NativeClientProtocolRow $nativeClientComputer)
            if ($nativeClientMajor -eq 16 -and $nativeToggleRows.Count -eq 0) {
                Get-NativeClientNamespace $nativeClientComputer | Should -Be "ComputerManagement16"
                @(Get-DbaClientProtocol -ComputerName $nativeClientComputer -WarningAction SilentlyContinue).Count | Should -Be 0
            } else {
                $nativeOriginalOrder.Count | Should -BeGreaterThan 1
                $protocol = Get-DbaClientProtocol -ComputerName $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName
                $disabled = $protocol.Disable()
                $disabled.ReturnValue | Should -Be 0
                $disabled.PSComputerName | Should -Be $protocol.PSComputerName
                $disabled.PSObject.TypeNames[0] | Should -Be "Microsoft.Management.Infrastructure.CimMethodResult#ClientNetworkProtocol#SetDisable"
                $disabled.PSObject.TypeNames[1] | Should -Be "Microsoft.Management.Infrastructure.CimMethodResult"

                $afterDisable = Get-DbaClientProtocol -ComputerName $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName
                $afterDisable.Order | Should -Be 0
                $afterDisable.IsEnabled | Should -BeFalse
                (Get-NativeClientProtocolRow $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName).ProtocolOrder | Should -Be 0

                $enabled = $afterDisable.Enable()
                $enabled.ReturnValue | Should -Be 0
                $enabled.PSObject.TypeNames[0] | Should -Be "Microsoft.Management.Infrastructure.CimMethodResult#ClientNetworkProtocol#SetEnable"

                $afterEnable = Get-DbaClientProtocol -ComputerName $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName
                $afterEnable.Order | Should -BeGreaterThan 0
                $afterEnable.IsEnabled | Should -BeTrue
            }
        }

        # The pinned methods call Invoke-CimMethod, which asks ShouldProcess (ConfirmImpact Medium) before the WMI call:
        # its target is the CIM instance's ToString() and its action "Invoke-CimMethod: <method>". A method call takes no
        # -WhatIf or -Confirm, so only $WhatIfPreference and $ConfirmPreference count; each case runs in the runspace above.
        It "Disable() and Enable() under WhatIfPreference write the What if line and change nothing" {
            $nativeShouldRows = @(Get-NativeClientProtocolRow $nativeClientComputer)
            if ($nativeClientMajor -eq 16 -and $nativeShouldRows.Count -eq 0) {
                Get-NativeClientNamespace $nativeClientComputer | Should -Be "ComputerManagement16"
                @(Get-DbaClientProtocol -ComputerName $nativeClientComputer -WarningAction SilentlyContinue).Count | Should -Be 0
            } else {
                $nativeShouldRow = $nativeShouldRows | Where-Object ProtocolName -eq $nativeToggleName
                $nativeShouldRow.ProtocolOrder | Should -BeGreaterThan 0
                $nativeShouldTarget = $nativeShouldRow.ToString()

                $disable = Invoke-NativeShouldCase -Case WhatIf -Method Disable
                $disable.Found | Should -BeTrue
                $disable.IsNull | Should -BeTrue
                $disable.Prompts.Count | Should -Be 0
                $disable.Writes | Should -Be @('What if: Performing the operation "Invoke-CimMethod: SetDisable" on target "' + $nativeShouldTarget + '".')
                (Get-NativeClientProtocolRow $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName).ProtocolOrder | Should -Be $nativeShouldRow.ProtocolOrder

                $enable = Invoke-NativeShouldCase -Case WhatIf -Method Enable
                $enable.IsNull | Should -BeTrue
                $enable.Prompts.Count | Should -Be 0
                $enable.Writes | Should -Be @('What if: Performing the operation "Invoke-CimMethod: SetEnable" on target "' + $nativeShouldTarget + '".')
                (Get-NativeEnabledOrder (Get-NativeClientProtocolRow $nativeClientComputer)) | Should -Be $nativeOriginalOrder
            }
        }

        It "Disable() and Enable() under ConfirmPreference Medium ask first, change nothing on No and go on with Yes" {
            $nativeShouldRows = @(Get-NativeClientProtocolRow $nativeClientComputer)
            if ($nativeClientMajor -eq 16 -and $nativeShouldRows.Count -eq 0) {
                Get-NativeClientNamespace $nativeClientComputer | Should -Be "ComputerManagement16"
                @(Get-DbaClientProtocol -ComputerName $nativeClientComputer -WarningAction SilentlyContinue).Count | Should -Be 0
            } else {
                $nativeShouldRow = $nativeShouldRows | Where-Object ProtocolName -eq $nativeToggleName
                $nativeShouldRow.ProtocolOrder | Should -BeGreaterThan 0
                $nativeShouldTarget = $nativeShouldRow.ToString()
                $nativeShouldChoices = "&Yes|Yes to &All|&No|No to A&ll|&Suspend"

                $declined = Invoke-NativeShouldCase -Case Confirm -Method Disable -Answer No
                $declined.Found | Should -BeTrue
                $declined.IsNull | Should -BeTrue
                $declined.Writes.Count | Should -Be 0
                $declined.Captions | Should -Be @("Confirm")
                $declined.Prompts | Should -Be @("Are you sure you want to perform this action?`r`nPerforming the operation ""Invoke-CimMethod: SetDisable"" on target ""$nativeShouldTarget"".")
                $declined.Choices | Should -Be @($nativeShouldChoices)
                $declined.Defaults | Should -Be @(0)
                (Get-NativeClientProtocolRow $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName).ProtocolOrder | Should -Be $nativeShouldRow.ProtocolOrder

                $accepted = Invoke-NativeShouldCase -Case Confirm -Method Disable -Answer Yes
                $accepted.IsNull | Should -BeFalse
                $accepted.ReturnValue | Should -Be 0
                $accepted.Prompts.Count | Should -Be 1
                (Get-NativeClientProtocolRow $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName).ProtocolOrder | Should -Be 0

                $enableDeclined = Invoke-NativeShouldCase -Case Confirm -Method Enable -Answer No
                $enableDeclined.IsNull | Should -BeTrue
                $enableDeclined.Prompts | Should -Be @("Are you sure you want to perform this action?`r`nPerforming the operation ""Invoke-CimMethod: SetEnable"" on target ""$nativeShouldTarget"".")
                (Get-NativeClientProtocolRow $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName).ProtocolOrder | Should -Be 0

                $enableAccepted = Invoke-NativeShouldCase -Case Confirm -Method Enable -Answer Yes
                $enableAccepted.ReturnValue | Should -Be 0
                $enableAccepted.Prompts.Count | Should -Be 1
                (Get-NativeClientProtocolRow $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName).ProtocolOrder | Should -BeGreaterThan 0
            }
        }

        # A copy carries the methods: PSObject.Copy() copies the instance members, and on Windows PowerShell it also clones the
        # CIM instance, so the copy holds an instance Get-DbaClientProtocol never returned; on PowerShell 7 the CIM instance is
        # not cloneable and the copy holds the same one. Select-Object, Export/Import-Clixml and a new CimInstance carry no
        # methods. The copy's methods read the preferences where they are called, globally or at a script's top alike (the
        # script-scope value is the accepted difference method-preferences-caller-scope: the pin reads the global one only).
        It "a copy's Disable() and Enable() under a global or script-scope WhatIfPreference write the What if line and change nothing" {
            $nativeCopyRows = @(Get-NativeClientProtocolRow $nativeClientComputer)
            if ($nativeClientMajor -eq 16 -and $nativeCopyRows.Count -eq 0) {
                Get-NativeClientNamespace $nativeClientComputer | Should -Be "ComputerManagement16"
                @(Get-DbaClientProtocol -ComputerName $nativeClientComputer -WarningAction SilentlyContinue).Count | Should -Be 0
            } else {
                $nativeCopyRow = $nativeCopyRows | Where-Object ProtocolName -eq $nativeToggleName
                $nativeCopyRow.ProtocolOrder | Should -BeGreaterThan 0
                $nativeCopyTarget = $nativeCopyRow.ToString()

                foreach ($scope in "Global", "Script") {
                    foreach ($method in "Disable", "Enable") {
                        $case = Invoke-NativeCopyCase -Scope $scope -Method $method
                        $case.Found | Should -BeTrue -Because "$scope $method"
                        $case.HasMethod | Should -BeTrue -Because "$scope $method"
                        $case.SameObject | Should -Be ($PSVersionTable.PSEdition -eq "Core") -Because "$scope $method"
                        $case.IsNull | Should -BeTrue -Because "$scope $method"
                        $case.Prompts.Count | Should -Be 0 -Because "$scope $method"
                        $case.Writes | Should -Be @('What if: Performing the operation "Invoke-CimMethod: Set' + $method + '" on target "' + $nativeCopyTarget + '".') -Because "$scope $method"
                        (Get-NativeClientProtocolRow $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName).ProtocolOrder | Should -Be $nativeCopyRow.ProtocolOrder -Because "$scope $method"
                    }
                }
                (Get-NativeEnabledOrder (Get-NativeClientProtocolRow $nativeClientComputer)) | Should -Be $nativeOriginalOrder
            }
        }

        # Where the caller's preferences cannot be read, the methods refuse rather than act as if the defaults applied: in a
        # runspace Get-DbaClientProtocol never ran in, for the returned object and its copy alike.
        It "Disable() and Enable() called in a runspace Get-DbaClientProtocol never ran in refuse and change nothing" {
            $nativeRefuseRows = @(Get-NativeClientProtocolRow $nativeClientComputer)
            if ($nativeClientMajor -eq 16 -and $nativeRefuseRows.Count -eq 0) {
                Get-NativeClientNamespace $nativeClientComputer | Should -Be "ComputerManagement16"
                @(Get-DbaClientProtocol -ComputerName $nativeClientComputer -WarningAction SilentlyContinue).Count | Should -Be 0
            } else {
                $nativeRefuseRow = $nativeRefuseRows | Where-Object ProtocolName -eq $nativeToggleName
                $nativeRefuseRow.ProtocolOrder | Should -BeGreaterThan 0
                $protocol = Get-DbaClientProtocol -ComputerName $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName
                $copy = $protocol.PSObject.Copy()
                $nativeRefuseItems = @(
                    [pscustomobject]@{ Name = "returned"; Object = $protocol; Method = "Disable" }
                    [pscustomobject]@{ Name = "copy"; Object = $copy; Method = "Disable" }
                    [pscustomobject]@{ Name = "copy"; Object = $copy; Method = "Enable" }
                )
                $refuseScript = {
                    param($Items)
                    foreach ($item in $Items) {
                        try {
                            $null = if ($item.Method -eq "Disable") { $item.Object.Disable() } else { $item.Object.Enable() }
                            [pscustomobject]@{ Name = $item.Name; Method = $item.Method; Returned = $true; Outer = $null; Inner = $null; Message = $null }
                        } catch {
                            $inner = $PSItem.Exception
                            while ($inner -and $inner -isnot [System.Management.Automation.PSInvalidOperationException]) { $inner = $inner.InnerException }
                            [pscustomobject]@{ Name = $item.Name; Method = $item.Method; Returned = $false; Outer = $PSItem.Exception.GetType().FullName; Inner = $(if ($inner) { $inner.GetType().FullName }); Message = $(if ($inner) { $inner.Message }) }
                        }
                    }
                }
                $refuseRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
                $refuseRunspace.Open()
                $refuseShell = [System.Management.Automation.PowerShell]::Create()
                $refuseShell.Runspace = $refuseRunspace
                try {
                    $null = $refuseShell.AddScript($refuseScript.ToString()).AddArgument($nativeRefuseItems)
                    $refused = @($refuseShell.Invoke())
                } finally {
                    $refuseShell.Dispose()
                    $refuseRunspace.Dispose()
                }

                $refused.Count | Should -Be 3
                foreach ($outcome in $refused) {
                    $because = $outcome.Name + " " + $outcome.Method
                    $outcome.Returned | Should -BeFalse -Because $because
                    $outcome.Outer | Should -Be "System.Management.Automation.MethodInvocationException" -Because $because
                    $outcome.Inner | Should -Be "System.Management.Automation.PSInvalidOperationException" -Because $because
                    $outcome.Message | Should -Be ($outcome.Method + "() changed nothing: the caller's WhatIf and Confirm preferences cannot be read here, because Get-DbaClientProtocol has not run in this runspace. Call " + $outcome.Method + "() on a protocol Get-DbaClientProtocol returned in the runspace that calls it.") -Because $because
                }
                (Get-NativeClientProtocolRow $nativeClientComputer | Where-Object ProtocolName -eq $nativeToggleName).ProtocolOrder | Should -Be $nativeRefuseRow.ProtocolOrder
                (Get-NativeEnabledOrder (Get-NativeClientProtocolRow $nativeClientComputer)) | Should -Be $nativeOriginalOrder
            }
        }
    }

    # The nested Resolve-DbaNetworkName and Get-DbaCmObject calls get no -EnableException, so a failure in either is their own
    # Stop-Function -Continue: its warning under the nested name and its record in $error, then the command goes on; nothing throws
    # under a caller's try, -EnableException or -ErrorAction Stop. Measured on the pin, both editions, every case alike in all four
    # call modes: S1 and S2 in evidence/pin-nestedsites-236550ae-20261105.txt (sha256 2bf3a0d5), S3 in
    # evidence/pin-nestedsites4-86cfbcd7-20261105.txt (sha256 d7f081cb). The pin's $error also holds the record of the method call
    # its nested function caught (GetHostEntry, GetConnectionType), a call the port does not make, and its Stop-Function records
    # carry ",Stop-Function" and the activity Write-Error: the accepted differences omitted-consequential-records and
    # stop-record-id-stem-and-activity, so only the Stop-Function record and its id stem are asserted. The caller's -ErrorVariable
    # holds that record too (correction nested-error-variable); the pin's also holds the blank and caught-call entries.
    Context "Nested call failures, in each call mode" {
        BeforeAll {
            $nativeNestedSwitches = "DisableConnectionCimRM", "DisableConnectionCimDCOM", "DisableConnectionWMI", "DisableConnectionPowerShellRemoting"
            $nativeNestedText = "Multiple protocol connections were attempted, but no successful connections could be established with the specified computer."
            $nativeNestedCall = 'Exception calling "GetConnectionType" with "2" argument(s): "' + $nativeNestedText + '"'
            $nativeNestedFullName = (Resolve-DbaNetworkName -ComputerName $nativeClientComputer).FullComputerName
            try {
                $null = [System.Net.Dns]::GetHostEntry($nativeMissingComputer)
            } catch {
                $nativeDnsText = $PSItem.Exception.InnerException.Message
            }

            function Clear-NativeNestedConnection {
                foreach ($key in @([Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Keys)) {
                    $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($key)
                }
            }

            function Set-NativeNestedProtocol($Off) {
                foreach ($switch in $nativeNestedSwitches) {
                    if ($Off) {
                        [Dataplat.Dbatools.Connection.ConnectionHost]::$switch = $true
                    } else {
                        [Dataplat.Dbatools.Connection.ConnectionHost]::$switch = $nativeNestedSaved[$switch]
                    }
                }
            }

            # Runs one case as the pin probes did: -Verbose, warnings and verbose lines merged into the output, which a
            # ForEach-Object reads as they are written. With -FlipAtClassRead the dbatools protocols are switched off and the
            # cached connections dropped when the command announces its ClientNetworkProtocol read, after the namespace query.
            # Returns the objects, the merged warnings, -WarningVariable, -ErrorVariable, the new $error records (newest first),
            # what a caller's catch received and how many times the switch flipped.
            function Invoke-NativeNestedCase($Mode, $Target, [switch]$FlipAtClassRead) {
                $state = @{ Flips = 0 }
                $flip = {
                    if ($FlipAtClassRead -and $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message.Contains("Getting Cim class ClientNetworkProtocol in Namespace ")) {
                        Set-NativeNestedProtocol $true
                        Clear-NativeNestedConnection
                        $state.Flips++
                    }
                    $PSItem
                }
                $mark = $null
                if ($global:Error.Count -gt 0) {
                    $mark = $global:Error[0]
                }
                $w = @()
                $ev = @()
                $out = @()
                $caught = $null
                switch ($Mode) {
                    "plain" {
                        $out = @(Get-DbaClientProtocol -ComputerName $Target -Verbose -WarningVariable w -ErrorVariable ev 4>&1 3>&1 | ForEach-Object $flip)
                    }
                    "plaintry" {
                        try {
                            $out = @(Get-DbaClientProtocol -ComputerName $Target -Verbose -WarningVariable w -ErrorVariable ev 4>&1 3>&1 | ForEach-Object $flip)
                        } catch {
                            $caught = $PSItem
                        }
                    }
                    "ee" {
                        try {
                            $out = @(Get-DbaClientProtocol -ComputerName $Target -EnableException -Verbose -WarningVariable w -ErrorVariable ev 4>&1 3>&1 | ForEach-Object $flip)
                        } catch {
                            $caught = $PSItem
                        }
                    }
                    "stop" {
                        try {
                            $out = @(Get-DbaClientProtocol -ComputerName $Target -ErrorAction Stop -Verbose -WarningVariable w -ErrorVariable ev 4>&1 3>&1 | ForEach-Object $flip)
                        } catch {
                            $caught = $PSItem
                        }
                    }
                }
                $newErrors = @()
                foreach ($record in @($global:Error)) {
                    if ($null -ne $mark -and [object]::ReferenceEquals($record, $mark)) {
                        break
                    }
                    $newErrors += $record
                }
                [PSCustomObject]@{
                    Objects     = @($out | Where-Object { $PSItem -isnot [System.Management.Automation.WarningRecord] -and $PSItem -isnot [System.Management.Automation.VerboseRecord] -and $PSItem -isnot [System.Management.Automation.ErrorRecord] })
                    Streamed    = @($out | Where-Object { $PSItem -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $PSItem.Message })
                    Warnings    = @($w | ForEach-Object { $PSItem.Message })
                    ErrorStream = @($out | Where-Object { $PSItem -is [System.Management.Automation.ErrorRecord] })
                    Errors      = @($ev)
                    NewErrors   = $newErrors
                    Caught      = $caught
                    Flips       = $state.Flips
                }
            }

            # The nested Stop-Function record: id stem, category, target, and the exception chain the pin's record holds.
            function Assert-NativeNestedRecord($Record, $Function, $Category, $Target, $Message, $CallText, $CallInnerType) {
                $Record.FullyQualifiedErrorId | Should -BeLike "dbatools_$Function*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly $Category
                if ($null -eq $Target) {
                    $Record.TargetObject | Should -BeNullOrEmpty
                } else {
                    $Record.TargetObject | Should -BeOfType [string]
                    $Record.TargetObject | Should -BeExactly $Target
                }
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Exception"
                $Record.Exception.Message | Should -BeExactly $Message
                $Record.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
                $Record.Exception.InnerException.Message | Should -BeExactly $CallText
                $Record.Exception.InnerException.InnerException.GetType().FullName | Should -BeExactly $CallInnerType
            }
        }

        BeforeEach {
            $nativeNestedSaved = @{ }
            foreach ($switch in $nativeNestedSwitches) {
                $nativeNestedSaved[$switch] = [Dataplat.Dbatools.Connection.ConnectionHost]::$switch
            }
            Clear-NativeNestedConnection
        }

        AfterEach {
            Set-NativeNestedProtocol $false
            Clear-NativeNestedConnection
        }

        It "S1, a computer DNS cannot resolve: the Resolve-DbaNetworkName and Failed to connect lines, one record, nothing thrown (<Mode>)" -ForEach @(
            @{ Mode = "plain" }, @{ Mode = "plaintry" }, @{ Mode = "ee" }, @{ Mode = "stop" }
        ) {
            $nativeDnsText | Should -Not -BeNullOrEmpty
            $case = Invoke-NativeNestedCase $Mode $nativeMissingComputer
            $expected = @(
                ([regex]::Escape("[Resolve-DbaNetworkName] DNS name $nativeMissingComputer not found | $nativeDnsText") + '$'),
                ([regex]::Escape("[Get-DbaClientProtocol] Failed to connect to $nativeMissingComputer") + '$')
            )
            $case.Objects.Count | Should -Be 0
            $case.Caught | Should -BeNullOrEmpty
            $case.ErrorStream.Count | Should -Be 0
            foreach ($lines in $case.Streamed, $case.Warnings) {
                $lines.Count | Should -Be 2
                $lines[0] | Should -Match $expected[0]
                $lines[1] | Should -Match $expected[1]
            }
            $case.NewErrors.Count | Should -Be 1
            Assert-NativeNestedRecord $case.NewErrors[0] "Resolve-DbaNetworkName" "NotSpecified" $null $nativeDnsText ('Exception calling "GetHostEntry" with "1" argument(s): "' + $nativeDnsText + '"') "System.Net.Sockets.SocketException"
        }

        It "S2, the namespace query fails: the Get-DbaCmObject and namespace lines, one record, nothing thrown (<Mode>)" -ForEach @(
            @{ Mode = "plain" }, @{ Mode = "plaintry" }, @{ Mode = "ee" }, @{ Mode = "stop" }
        ) {
            Set-NativeNestedProtocol $true
            $case = Invoke-NativeNestedCase $Mode $nativeClientComputer
            Set-NativeNestedProtocol $false
            $tag = $nativeClientComputer.ToLowerInvariant()
            $expected = @(
                ([regex]::Escape("[Get-DbaCmObject] [$tag] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: None | $nativeNestedText") + '$'),
                ([regex]::Escape("[Get-DbaClientProtocol] No ComputerManagement Namespace on $nativeClientComputer. Please note that this function is available from SQL 2005 up.") + '$')
            )
            $case.Objects.Count | Should -Be 0
            $case.Caught | Should -BeNullOrEmpty
            $case.ErrorStream.Count | Should -Be 0
            foreach ($lines in $case.Streamed, $case.Warnings) {
                $lines.Count | Should -Be 2
                $lines[0] | Should -Match $expected[0]
                $lines[1] | Should -Match $expected[1]
            }
            $case.NewErrors.Count | Should -Be 1
            Assert-NativeNestedRecord $case.NewErrors[0] "Get-DbaCmObject" "OpenError" $tag $nativeNestedText $nativeNestedCall "System.Management.Automation.PSInvalidOperationException"
        }

        It "S3, the ClientNetworkProtocol read fails after the namespace query: the Get-DbaCmObject line alone, one record, nothing thrown (<Mode>)" -ForEach @(
            @{ Mode = "plain" }, @{ Mode = "plaintry" }, @{ Mode = "ee" }, @{ Mode = "stop" }
        ) {
            $case = Invoke-NativeNestedCase $Mode $nativeClientComputer -FlipAtClassRead
            Set-NativeNestedProtocol $false
            $tag = $nativeNestedFullName.ToLowerInvariant()
            $expected = [regex]::Escape("[Get-DbaCmObject] [$tag] Unable to find a connection to the target system. Ensure the name is typed correctly, and the server allows any of the following protocols: None | $nativeNestedText") + '$'
            $case.Flips | Should -Be 1
            $case.Objects.Count | Should -Be 0
            $case.Caught | Should -BeNullOrEmpty
            $case.ErrorStream.Count | Should -Be 0
            foreach ($lines in $case.Streamed, $case.Warnings) {
                $lines.Count | Should -Be 1
                $lines[0] | Should -Match $expected
            }
            $case.NewErrors.Count | Should -Be 1
            Assert-NativeNestedRecord $case.NewErrors[0] "Get-DbaCmObject" "OpenError" $tag $nativeNestedText $nativeNestedCall "System.Management.Automation.PSInvalidOperationException"
            # The caller's -ErrorVariable holds that same Stop-Function record, as the pin's does in every mode on both editions
            # (86cfbcd7; correction nested-error-variable). Asserted last, so it is the only assertion that can fail before the fix.
            $case.Errors.Count | Should -Be 1
            $case.Errors[0] | Should -BeOfType System.Management.Automation.ErrorRecord
            Assert-NativeNestedRecord $case.Errors[0] "Get-DbaCmObject" "OpenError" $tag $nativeNestedText $nativeNestedCall "System.Management.Automation.PSInvalidOperationException"
        }
    }

    Context "Credential" {
        AfterAll {
            # Drop the cached connection the unknown account touched, so later tests start clean.
            foreach ($key in @([Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Keys)) {
                if ($key -eq $nativeClientComputer.ToLowerInvariant() -or $key -eq $nativeClientFqdn.ToLowerInvariant()) {
                    $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($key)
                }
            }
        }

        It "reads the computer's SQL WMI as the Credential account" {
            $nativeUnknownUser = $env:USERDOMAIN + "\nativenx" + [guid]::NewGuid().ToString("N").Substring(0, 8)
            $nativeUnknownPassword = ConvertTo-SecureString ([guid]::NewGuid().ToString("N")) -AsPlainText -Force
            $nativeUnknownCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $nativeUnknownUser, $nativeUnknownPassword
            $nativeClientWarnings = @()
            $results = @(Get-DbaClientProtocol -ComputerName $nativeClientComputer -Credential $nativeUnknownCredential -WarningAction SilentlyContinue -WarningVariable nativeClientWarnings)
            $results.Count | Should -Be 0
            (@($nativeClientWarnings | ForEach-Object { $PSItem.Message }) -join " ") | Should -Match ([regex]::Escape("[Get-DbaClientProtocol] No ComputerManagement Namespace on "))
        }
    }
}
