#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Sets the SQL Server network configuration (protocols, ports, IP bindings) via remote
/// WMI. Port of public/Set-DbaNetworkConfiguration.ps1 (W3-095). WHOLE-RECORD verbatim
/// hop. VFP-LOCAL CLASSIFICATION TABLE (InputObject is the sole VFP): the
/// `$InputObject += $netConf` accumulation has NO cross-record axis - the SqlInstance
/// loop that feeds it is NonPipeline-set-only (sets are exclusive, so piped records
/// arrive with $SqlInstance null and the loop never spins), and piped records rebind
/// InputObject; $netConf/$output/$computerName/$ipAll/$port/$address/$ipTarget are
/// per-iteration; $listenPort's stale-across-ip-iterations read is a WITHIN-record
/// quirk the whole-record hop preserves; **$result IS cross-record** - it is assigned
/// inside the ShouldProcess gate (line: Invoke-Command2) and read OUTSIDE it
/// ($result.Changes.Count), so a piped record whose gate is declined reads the
/// PREVIOUS record's result in the source - the __w3095State sentinel carries it.
/// Engine state: gates route to the REAL cmdlet ($Pscmdlet -> $__realCmdlet,
/// ConfirmImpact HIGH mirrored; no Force/ConfirmPreference convention = no transplant,
/// no hold exposure). The TWO Test-Bound calls (both -Not variants over the five
/// action params; the second with -Max 1) are substituted with carried flags
/// reproducing the exact counting semantics (originals commented in place).
/// ATTRIBUTION SHIM (the W3-084/W3-092 Get-PSCallStack class, third instance):
/// Test-ElevationRequirement stamps Stop-Function with the caller frame - a named
/// wrapper "Set-DbaNetworkConfiguration" restores the source frame (here it runs with
/// -EnableException $true, so the THROW identity is what the shim fixes). The begin
/// block's $wmiScriptBlock is a pure constant and rides at process-hop top verbatim
/// (W3-083 definition class). PARAM SETS mirrored exactly: NonPipeline (default,
/// SqlInstance Mandatory EXPLICIT pos0 + the five action params) / Pipeline
/// (InputObject object[] Mandatory VFP); Credential/RestartService/EnableException
/// carry BOTH set attributes like the source (not __AllParameterSets).
/// [PsStringCast]+ValidateSet on Enable/DisableProtocol (W1-032). All mutating paths
/// are ENV-BLOCKED on the lane topology (PS remoting/WMI guest->partition, the
/// W3-084/W3-092 class) - the smoke pins the deterministic failure/validation/WhatIf
/// paths; the remote WMI scriptblock rides verbatim OUT of smoke scope. NO
/// WarningAction carrier (codex W3-005 r3). Surface pinned by
/// migration/baselines/Set-DbaNetworkConfiguration.json.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaNetworkConfiguration", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High, DefaultParameterSetName = "NonPipeline")]
public sealed partial class SetDbaNetworkConfigurationCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ParameterSetName = "NonPipeline", Mandatory = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Windows credential for the remote WMI/remoting work.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public PSCredential? Credential { get; set; }

    /// <summary>Protocol to enable (SharedMemory, NamedPipes or TcpIp).</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [PsStringCast]
    [ValidateSet("SharedMemory", "NamedPipes", "TcpIp")]
    public string? EnableProtocol { get; set; }

    /// <summary>Protocol to disable (SharedMemory, NamedPipes or TcpIp).</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [PsStringCast]
    [ValidateSet("SharedMemory", "NamedPipes", "TcpIp")]
    public string? DisableProtocol { get; set; }

    /// <summary>Configures IPAll for dynamic ports.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public SwitchParameter DynamicPortForIPAll { get; set; }

    /// <summary>Configures IPAll for the given static port(s).</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public int[]? StaticPortForIPAll { get; set; }

    /// <summary>Configures listening on the given individual IP address(es).</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    public string[]? IpAddress { get; set; }

    /// <summary>Restarts the engine service when changes require it.</summary>
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public SwitchParameter RestartService { get; set; }

    /// <summary>Network configuration object(s) from Get-DbaNetworkConfiguration.</summary>
    [Parameter(ValueFromPipeline = true, ParameterSetName = "Pipeline", Mandatory = true)]
    public object[]? InputObject { get; set; }

    /// <summary>Raises exceptions instead of friendly warnings.</summary>
    // W3-072 precedent: the source declares EnableException as a MEMBER of both named
    // sets (not __AllParameterSets); the virtual base override carries the per-set
    // attributes so the compiled surface matches the baseline exactly.
    [Parameter(ParameterSetName = "NonPipeline")]
    [Parameter(ParameterSetName = "Pipeline")]
    public override SwitchParameter EnableException { get; set; }

    // Cross-record carry: the gate/try-assigned $result read outside the gate.
    private Hashtable? _state;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, Credential, EnableProtocol, DisableProtocol,
            DynamicPortForIPAll.ToBool(), StaticPortForIPAll, IpAddress,
            RestartService.ToBool(), InputObject, EnableException.ToBool(),
            TestBound(nameof(EnableProtocol)), TestBound(nameof(DisableProtocol)),
            TestBound(nameof(DynamicPortForIPAll)), TestBound(nameof(StaticPortForIPAll)),
            TestBound(nameof(IpAddress)), _state, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            Hashtable? sentinel = item?.BaseObject as Hashtable;
            if (sentinel is not null && sentinel.ContainsKey("__w3095State"))
            {
                _state = sentinel["__w3095State"] as Hashtable;
                continue;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    private const string ProcessScript = ProcessScriptHead + "\n" + ProcessScriptTail;
}
