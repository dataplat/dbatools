#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the Extended Events objects (events, actions, targets, etc.) available on one or more
/// SQL Server instances.
/// </summary>
/// <remarks>
/// The query construction, the connection, the DMV query, and the Select-DefaultView projection all
/// run the original dbatools PowerShell body VERBATIM inside the dbatools module scope rather than
/// being reimplemented in C#, so the engine decides the observable details.
///
/// The function has a begin block and a process block. The begin block builds $sql from $Type; it is
/// kept as a SEPARATE once-only hop rather than folded, because it has an OBSERVABLE side effect: the
/// source's two "$where.Replace(...)" statements do NOT assign back, so their return values are emitted
/// to the SUCCESS stream. In the source those two strings are emitted exactly once (begin runs once);
/// folding the begin into the process hop would re-emit them per pipeline record. So the begin hop runs
/// once in BeginProcessing (its leaked strings are WriteObject'd once, before any process output,
/// matching the source), and $sql is carried to the process hop via the begin sentinel.
///
/// The process block's second Stop-Function (query failure) has NO -Continue, so it SETS the
/// function-scope interrupt, but nothing in the function reads Test-FunctionInterrupt, so the interrupt
/// is inert and needs no carry (under -EnableException that Stop-Function throws terminating instead,
/// which the framework re-throws). The connect Stop-Function is -Continue. There is no ShouldProcess
/// and no Test-Bound.
///
/// Each instance's rows are emitted before a later instance may fail under -EnableException (DEF-001),
/// so the process hop uses InvokeScopedStreaming. Surface pinned by
/// migration/baselines/Get-DbaXEObject.json.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaXEObject")]
public sealed class GetDbaXEObjectCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Filters the Extended Events objects by component type.</summary>
    [Parameter(Position = 2)]
    [ValidateSet("Type", "Event", "Target", "Action", "Map", "Message", "PredicateComparator", "PredicateSource")]
    public string[]? Type { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which
    // the inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    // $sql is built once in the begin hop (a computation with a leaked-string side effect) and carried
    // to every process record.
    private object? _sql;

    protected override void BeginProcessing()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Type, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaXEObjectBegin"))
            {
                if (sentinel["__getDbaXEObjectBegin"] is Hashtable state)
                {
                    _sql = state["Sql"];
                }
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

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, _sql, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM (including the two $where.Replace(...) statements whose results leak to
    // output - preserved exactly), plus a trailing sentinel carrying $sql. Runs once in BeginProcessing.
    private const string BeginScript = """
param($Type, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$Type)
    if ($Type) {
        $join = $Type -join "','"
        $where = "AND o.object_type in ('$join')"
        $where.Replace("PredicateComparator", "pred_compare")
        $where.Replace("PredicateSource", "pred_source")
    }
    $sql = "SELECT  SERVERPROPERTY('MachineName') AS ComputerName,
            ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
            SERVERPROPERTY('ServerName') AS SqlInstance,
            p.name AS PackageName,
            ObjectType =
                  CASE o.object_type
                     WHEN 'type' THEN 'Type'
                     WHEN 'event' THEN 'Event'
                     WHEN 'target' THEN 'Target'
                     WHEN 'pred_compare' THEN 'PredicateComparator'
                     WHEN 'pred_source' THEN 'PredicateSource'
                     WHEN 'action' THEN 'Action'
                     WHEN 'map' THEN 'Map'
                     WHEN 'message' THEN 'Message'
                     ELSE o.object_type
                  END,
            o.object_type AS ObjectTypeRaw,
            o.name AS TargetName,
            o.description AS Description
            FROM sys.dm_xe_packages AS p
            JOIN sys.dm_xe_objects AS o ON p.guid = o.package_guid
            WHERE (p.capabilities IS NULL OR p.capabilities & 1 = 0)
            $where
            AND (o.capabilities IS NULL OR o.capabilities & 1 = 0)
            ORDER BY o.object_type
            "
    @{ __getDbaXEObjectBegin = @{ Sql = $sql } }
} $Type @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from -FunctionName Get-DbaXEObject on the two direct
    // Stop-Function sites. $sql is received from the begin carry.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $sql, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $sql, $EnableException)
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaXEObject
        }

        try {
            $server.Query($sql) | Select-DefaultView -ExcludeProperty ComputerName, InstanceName, ObjectTypeRaw
        } catch {
            Stop-Function -Message "Issue collecting trace data on $server." -Target $server -ErrorRecord $_ -FunctionName Get-DbaXEObject
        }
    }
} $SqlInstance $SqlCredential $sql $EnableException @__commonParameters 3>&1 2>&1
""";
}
