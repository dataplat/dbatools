#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# Engine check for the shared StatementFault helper (harness-edits.md, "Operator decision: StatementFault.Surface required
# at caller-try sites (2026-11-02)", point 9(b)). Surface reads one engine-internal flag to tell a caller's try from a plain
# call; these tests prove that read in the shell that runs them, against the loaded dbatools assembly, through a probe
# cmdlet that calls the shared helper by reflection. No SQL Server is needed.

Describe "Native StatementFault engine check" {
    BeforeAll {
        $engineHelper = [Dataplat.Dbatools.Connection.NativeExecutionGuard].Assembly.GetType("Dataplat.Dbatools.Commands.StatementFault", $true)
        $engineProbeName = "NativeStatementFaultEngine.TestNativeStatementFaultProbe"
        if (-not ([System.Management.Automation.PSTypeName]$engineProbeName).Type) {
            $engineProbeSource = @"
using System;
using System.Management.Automation;
using System.Reflection;
namespace NativeStatementFaultEngine {
    [Cmdlet(VerbsDiagnostic.Test, "NativeStatementFaultProbe")]
    public sealed class TestNativeStatementFaultProbe : PSCmdlet {
        private static Action<PSCmdlet, ErrorRecord> surface;
        public static void Bind(Type helper) {
            MethodInfo method = helper.GetMethod("Surface", BindingFlags.NonPublic | BindingFlags.Static, null, new Type[] { typeof(PSCmdlet), typeof(ErrorRecord) }, null);
            surface = (Action<PSCmdlet, ErrorRecord>)Delegate.CreateDelegate(typeof(Action<PSCmdlet, ErrorRecord>), method);
        }
        protected override void ProcessRecord() {
            ErrorRecord record = new ErrorRecord(new InvalidOperationException("StatementFault engine probe"), "NativeStatementFaultProbe", ErrorCategory.InvalidOperation, "probe-target");
            SessionState.PSVariable.Set(new PSVariable("NativeStatementFaultProbeRecord", record, ScopedItemOptions.None));
            surface(this, record);
        }
    }
}
"@
            $splatEngineProbe = @{
                TypeDefinition       = $engineProbeSource
                ReferencedAssemblies = @([psobject].Assembly.Location)
                IgnoreWarnings       = $true
            }
            Add-Type @splatEngineProbe
        }
        $engineProbe = ([System.Management.Automation.PSTypeName]$engineProbeName).Type
        $engineProbe::Bind($engineHelper)
        Import-Module -Assembly $engineProbe.Assembly
    }

    It "resolves the engine flag the shared helper reads" {
        $engineAvailable = $engineHelper.GetMethod("EngineFlagAvailable", [System.Reflection.BindingFlags]"NonPublic, Static")
        $engineAvailable.Invoke($null, @()) | Should -BeTrue
    }

    It "lets a caller's try catch the record and go no further" {
        $NativeStatementFaultProbeRecord = $null
        $engineOutput = @(try { Test-NativeStatementFaultProbe; "after" } catch { $_ })
        $engineSurfaced = $NativeStatementFaultProbeRecord

        $engineSurfaced | Should -Not -BeNullOrEmpty
        $engineOutput.Count | Should -Be 1
        $engineOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
        [object]::ReferenceEquals($engineOutput[0].Exception, $engineSurfaced.Exception) | Should -BeTrue
        $engineOutput[0].FullyQualifiedErrorId | Should -BeLike "NativeStatementFaultProbe*"
        $engineOutput[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
        $engineOutput[0].TargetObject | Should -Be "probe-target"
    }

    It "writes the record and goes on in a plain call" {
        # A Pester It runs its body inside a try, so the plain call needs a runspace of its own.
        $engineState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $engineEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Test-NativeStatementFaultProbe", $engineProbe, $null
        $engineState.Commands.Add($engineEntry)
        $engineRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($engineState)
        $engineShell = [System.Management.Automation.PowerShell]::Create()
        try {
            $engineRunspace.Open()
            $engineShell.Runspace = $engineRunspace
            $null = $engineShell.AddScript("Test-NativeStatementFaultProbe; 'after'")
            $engineOutput = @($engineShell.Invoke())
            $engineWritten = @($engineShell.Streams.Error.ReadAll())
            $engineSurfaced = $engineRunspace.SessionStateProxy.GetVariable("NativeStatementFaultProbeRecord")
        } finally {
            $engineShell.Dispose()
            $engineRunspace.Dispose()
        }

        $engineSurfaced | Should -Not -BeNullOrEmpty
        $engineOutput.Count | Should -Be 1
        $engineOutput[0] | Should -Be "after"
        $engineWritten.Count | Should -Be 1
        [object]::ReferenceEquals($engineWritten[0].Exception, $engineSurfaced.Exception) | Should -BeTrue
        $engineWritten[0].FullyQualifiedErrorId | Should -BeLike "NativeStatementFaultProbe*"
        $engineWritten[0].CategoryInfo.Category | Should -Be ([System.Management.Automation.ErrorCategory]::InvalidOperation)
        $engineWritten[0].TargetObject | Should -Be "probe-target"
    }
}
