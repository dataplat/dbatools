#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the instance max server memory. Port of public/Set-DbaMaxMemory.ps1 (W3-094).
/// WHOLE-RECORD verbatim hop. VFP-LOCAL CLASSIFICATION TABLE: InputObject is the ONLY
/// VFP param, so the `$InputObject += Test-DbaMaxMemory` mutation has NO cross-record
/// axis - a piped record rebinds InputObject and the engine restores it afterwards,
/// and SqlInstance (not VFP) makes multi-record arrival impossible on the accumulating
/// path; $server/$maxMem are per-iteration; $UseRecommended is the begin block (pure
/// function of the bound Max - unbound int reads 0, the SAME value the `$Max -eq 0`
/// test keys on, so bind-time equivalence holds) riding at hop top. No sentinel.
/// Gates route to the REAL cmdlet ($PSCmdlet -> $__realCmdlet; no Force convention -
/// no transplant, no hold exposure). QUIRKS verbatim: the OUTPUT emission sits INSIDE
/// the ShouldProcess gate here (the INVERSE of Set-DbaMaxDop - -WhatIf emits NO rows;
/// smoke pins it); the RecommendedValue-eq-0-or-null branch whose both arms assign the
/// same value; Add-Member -Force mutates the PIPED object caller-visibly, twice (the
/// second re-adds MaxValue as a NoteProperty AFTER $result.MaxValue was already set);
/// Test-DbaMaxMemory is invoked WITHOUT -EnableException regardless of the caller's
/// EE. [PsIntCast] on Max (W1-043 null->0 bind cast; 0 = use recommended). NO
/// WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Set-DbaMaxMemory.json (implicit positions 0-3, InputObject
/// PSObject[] pos3 sole VFP, no sets, ConfirmImpact Medium).
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaMaxMemory", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class SetDbaMaxMemoryCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Max server memory in MB; 0 (default) applies the recommended value.</summary>
    [Parameter(Position = 2)]
    [PsIntCast]
    public int Max { get; set; }

    /// <summary>Test-DbaMaxMemory output to act on.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public PSObject[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
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
            SqlInstance, SqlCredential, Max, InputObject, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin line + ENTIRE process body VERBATIM per record. Substitutions only:
    // $PSCmdlet -> $__realCmdlet on the gate and explicit -FunctionName Set-DbaMaxMemory
    // on Stop-Function/Write-Message (W1-090). The += over the sole-VFP InputObject,
    // the both-arms-identical RecommendedValue branch and the double Add-Member ride
    // as-is.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Max, $InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [int]$Max, [PSCustomObject[]]$InputObject, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if ($Max -eq 0) {
        $UseRecommended = $true
    }

    if ($SqlInstance) {
        $InputObject += Test-DbaMaxMemory -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    }

    foreach ($result in $InputObject) {
        $server = $result.Server
        Add-Member -Force -InputObject $result -NotePropertyName PreviousMaxValue -NotePropertyValue $result.MaxValue

        try {
            if ($UseRecommended) {
                Write-Message -Level Verbose -Message "Change $server SQL Server Max Memory from $($result.MaxValue) to $($result.RecommendedValue) " -FunctionName Set-DbaMaxMemory -ModuleName "dbatools"

                if ($result.RecommendedValue -eq 0 -or $null -eq $result.RecommendedValue) {
                    $maxMem = $result.RecommendedValue
                    Write-Message -Level VeryVerbose -Message "Max memory recommended: $maxMem" -FunctionName Set-DbaMaxMemory -ModuleName "dbatools"
                    $server.Configuration.MaxServerMemory.ConfigValue = $maxMem
                } else {
                    $server.Configuration.MaxServerMemory.ConfigValue = $result.RecommendedValue
                }
            } else {
                Write-Message -Level Verbose -Message "Change $server SQL Server Max Memory from $($result.MaxValue) to $Max " -FunctionName Set-DbaMaxMemory -ModuleName "dbatools"
                $server.Configuration.MaxServerMemory.ConfigValue = $Max
            }

            if ($__realCmdlet.ShouldProcess($server.Name, "Change Max Memory from $($result.PreviousMaxValue) to $($server.Configuration.MaxServerMemory.ConfigValue)")) {
                try {
                    $server.Configuration.Alter()
                    $result.MaxValue = $server.Configuration.MaxServerMemory.ConfigValue
                } catch {
                    Stop-Function -Message "Failed to apply configuration change for $server" -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaMaxMemory
                }

                Add-Member -InputObject $result -Force -MemberType NoteProperty -Name MaxValue -Value $result.MaxValue
                Select-DefaultView -InputObject $result -Property ComputerName, InstanceName, SqlInstance, Total, MaxValue, PreviousMaxValue
            }
        } catch {
            Stop-Function -Message "Could not modify Max Server Memory for $server" -ErrorRecord $_ -Target $server -Continue -FunctionName Set-DbaMaxMemory
        }
    }
} $SqlInstance $SqlCredential $Max $InputObject $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
