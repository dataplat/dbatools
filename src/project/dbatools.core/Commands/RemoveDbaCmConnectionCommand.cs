#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes cached CIM/WMI management connections. Port of
/// public/Remove-DbaCmConnection.ps1 (W3-071), sibling of New-DbaCmConnection (W3-063)
/// and built on the same W3-001 lifecycle shape: begin/process/end bodies ride verbatim
/// module hops. Begin emits the InternalComment "Starting" plus the Verbose
/// "Bound parameters:" line (carried as this cmdlet's OWN bound-key list, which matches
/// the function's $PSBoundParameters keys for the same invocation); process wraps each
/// record in the source's per-record loop - Stop-Function -Continue on unparsed input,
/// then the $__realCmdlet.ShouldProcess gate (ConfirmImpact HIGH mirrored) around the
/// ConnectionHost.Connections cache removal; end emits the InternalComment "Ending".
/// No fn-scope state crosses records (no accumulation, no sentinel, no Test-Bound
/// reads - the W3-063 shape exactly). NO WarningAction carrier (codex W3-005 r3).
/// Surface pinned by migration/baselines/Remove-DbaCmConnection.json (ComputerName
/// DbaCmConnectionParameter[] Mandatory pos0 VFP, ConfirmImpact High).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaCmConnection", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaCmConnectionCommand : DbaBaseCmdlet
{
    /// <summary>The computer(s) whose cached connections should be removed.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaCmConnectionParameter[]? ComputerName { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            string.Join(", ", MyInvocation.BoundParameters.Keys), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Stream one hop PER COMPUTER: a whole-array hop batches every element's live
        // Debug/Verbose ahead of all buffered output, where the source's foreach
        // interleaves them per element (W2-010 P2A; coordinator 25a09f3 ruling - same
        // shape as the ruling's named W3-063 sibling). The source loop body has no
        // cross-element state.
        // Mandatory binding guarantees non-null, but the empty-array fallback replaces
        // the null-forgiving suppression with a runtime-safe no-op (codex sweep r1).
        foreach (DbaCmConnectionParameter computer in ComputerName ?? Array.Empty<DbaCmConnectionParameter>())
        {
            if (Interrupted)
                return;

            NestedCommand.InvokeScopedStreaming(this, item =>
            {
                if (item?.BaseObject is ErrorRecord nestedError)
                {
                    NestedCommand.RemoveDuplicateError(this, nestedError);
                    WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                    return;
                }
                WriteObject(item);
            }, ProcessScript,
            new[] { computer }, EnableException.ToBool(), this,
                NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
                NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
        }
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, EndScript,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the begin block verbatim. $PSBoundParameters.Keys -join ", " is carried as the
    // pre-joined key list from the cmdlet's own binding (identical keys for identical
    // invocations); explicit -FunctionName Remove-DbaCmConnection (W1-090).
    private const string BeginScript = """
param($__boundKeys, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundKeys, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    Write-Message -Level InternalComment -Message "Starting" -FunctionName Remove-DbaCmConnection -ModuleName "dbatools"
    Write-Message -Level Verbose -Message "Bound parameters: $__boundKeys" -FunctionName Remove-DbaCmConnection -ModuleName "dbatools"
} $__boundKeys $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM per record. Substitutions only: $Pscmdlet ->
    // $__realCmdlet and explicit -FunctionName Remove-DbaCmConnection on
    // Write-Message/Stop-Function (W1-090).
    private const string ProcessScript = """
param($ComputerName, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaCmConnectionParameter[]]$ComputerName, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    foreach ($connectionObject in $ComputerName) {
        if (-not $connectionObject.Success) { Stop-Function -Message "Failed to interpret computername input: $($connectionObject.InputObject)" -Category InvalidArgument -Target $connectionObject.InputObject -Continue -FunctionName Remove-DbaCmConnection }
        Write-Message -Level VeryVerbose -Message "Removing from connection cache: $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName -FunctionName Remove-DbaCmConnection -ModuleName "dbatools"
        if ($__realCmdlet.ShouldProcess($($connectionObject.Connection.ComputerName), "Removing Connection")) {
            if ([Dataplat.Dbatools.Connection.ConnectionHost]::Connections.ContainsKey($connectionObject.Connection.ComputerName)) {
                $null = [Dataplat.Dbatools.Connection.ConnectionHost]::Connections.Remove($connectionObject.Connection.ComputerName)
                Write-Message -Level Verbose -Message "Successfully removed $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName -FunctionName Remove-DbaCmConnection -ModuleName "dbatools"
            } else {
                Write-Message -Level Verbose -Message "Not found: $($connectionObject.Connection.ComputerName)" -Target $connectionObject.Connection.ComputerName -FunctionName Remove-DbaCmConnection -ModuleName "dbatools"
            }
        }
    }
} $ComputerName $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the end block verbatim.
    private const string EndScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    Write-Message -Level InternalComment -Message "Ending" -FunctionName Remove-DbaCmConnection -ModuleName "dbatools"
} $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
