#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Gets registered servers from Central Management Servers and local stores. Port of
/// public/Get-DbaRegServer.ps1; the workflow remains a module-scoped
/// PowerShell compatibility hop. READ-ONLY (no mutating verbs, no SupportsShouldProcess).
///
/// BEGIN+PROCESS. -SqlInstance is ValueFromPipeline, so process fires per piped instance.
///
/// $defaults BEGIN -> PROCESS CARRY, bug-for-bug. begin :175-180 sets $defaults, and a SOURCE BUG
/// rides verbatim: :175 sets an 8-column set under "if ($ResolveNetworkName)", but :180
/// UNCONDITIONALLY overwrites it with the 5-column set - so -ResolveNetworkName never actually
/// widens the default view. Process reads $defaults at :383/:403 for Select-DefaultView. It is
/// carried from begin, not recomputed.
///
/// TWO begin HELPERS RECREATED IN THE PROCESS HOP. begin defines Unprotect-String (a function,
/// :182) and $matchesPattern (a scriptblock, :186) but CALLS neither; process calls them at :335 and
/// :294. Begin's scope dies before process, so both are recreated verbatim at the top of the process
/// hop - the same treatment New-DbaDacProfile's begin-defined helpers needed. Neither
/// closes over carried state (both are pure over their arguments), so recreation is faithful.
///
/// TWO CONFIG DEFAULTS resolved in the process hop:
///   -SqlInstance defaults to Get-DbatoolsConfigValue 'commands.get-dbaregserver.defaultcms'. Because
///     it is ValueFromPipeline, the piped/passed value wins per record and the CMS default applies
///     only when nothing was supplied - reproduced by "if (-not $PSBoundParameters.ContainsKey('SqlInstance')) { $SqlInstance = ... }".
///   -IncludeLocal (a switch) defaults to Get-DbatoolsConfigValue
///     'commands.get-dbaregserver.includelocal'; resolved when the caller did not pass it.
///
/// $PSBoundParameters PROJECTION (VALUE reads). The body reads $PSBoundParameters.SqlInstance
/// (:197/:232), .IncludeLocal (:232), .Group (:378) and .ExcludeGroup (:379) as VALUES - these
/// distinguish an EXPLICIT caller pass from a default and drive the local-store and group-filter
/// logic. Inside a hop $PSBoundParameters is the hop's own bindings, so the caller's real
/// BoundParameters dictionary is passed in and substituted for $PSBoundParameters before the body,
/// which keeps every value read faithful. It is only ever indexed by key,
/// never iterated.
///
/// NO INTERRUPT BRIDGE: no Test-FunctionInterrupt in the source; its Stop-Function calls carry
/// -Continue (:210) or terminate a single object.
///
/// ONE CROSS-RECORD STATE CARRY - $azureids (DO NOT REMOVE). It is initialized to @() ONLY
/// inside the local-store path (:244, gated by :232 "-not $PSBoundParameters.SqlInstance -or
/// $PSBoundParameters.IncludeLocal"), but READ at :308 in the UNCONDITIONAL "foreach ($server in
/// $servers)" loop. On a record that does not take the local-store path, the source's persistent
/// process scope reads a PREVIOUS record's $azureids, so a later server can be matched to a stale
/// Azure id/group; a fresh hop scope would see $null and diverge. It rides a process sentinel with an
/// AzureidsAssigned flag, restored before the body so the :244 re-init still overwrites it on a
/// record that does take the path, and a first record leaves it undefined exactly as the source does.
/// The remaining process locals genuinely do NOT carry: $servers, $serverstores and
/// $serverToServerStore reset to empty at :201-203 on every record, and every other local is
/// assigned before use within its own loop.
///
/// -ExcludeServerName carries Alias("ExcludeServer"). The three switches (IncludeSelf,
/// ResolveNetworkName, IncludeLocal) and inherited EnableException cross as SwitchParameter OBJECTS
/// received untyped. In-hop Stop-Function/Write-Message calls carry -FunctionName. Implicit positions
/// 0-8 are made explicit and confirmed against the exported baseline; SqlInstance
/// is position 0 and ValueFromPipeline. Streaming: emits per registered server via
/// Select-DefaultView. Surface pinned by the captured surface baseline.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaRegServer")]
public sealed partial class GetDbaRegServerCommand : DbaBaseCmdlet
{
    /// <summary>The CMS instance(s); defaults to the configured default CMS.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Filter to these registered-server names.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Name { get; set; }

    /// <summary>Filter to these server names.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? ServerName { get; set; }

    /// <summary>Regex patterns to match names or server names against.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Pattern { get; set; }

    /// <summary>Exclude these server names.</summary>
    [Parameter(Position = 5)]
    [Alias("ExcludeServer")]
    [PsStringArrayCast]
    public string[]? ExcludeServerName { get; set; }

    /// <summary>Limit to these groups.</summary>
    [Parameter(Position = 6)]
    [PsStringArrayCast]
    public string[]? Group { get; set; }

    /// <summary>Exclude these groups.</summary>
    [Parameter(Position = 7)]
    [PsStringArrayCast]
    public string[]? ExcludeGroup { get; set; }

    /// <summary>Limit to these registered-server ids.</summary>
    [Parameter(Position = 8)]
    public int[]? Id { get; set; }

    /// <summary>Include the CMS server itself in the results.</summary>
    [Parameter]
    public SwitchParameter IncludeSelf { get; set; }

    /// <summary>Resolve network names (widens the default view - though a source bug suppresses that).</summary>
    [Parameter]
    public SwitchParameter ResolveNetworkName { get; set; }

    /// <summary>Include local server stores; defaults to the configured value.</summary>
    [Parameter]
    public SwitchParameter IncludeLocal { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin's $defaults column set; opaque to C#.
    private Hashtable? _beginState;
    // $azureids carried record-to-record; opaque to C#.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            ResolveNetworkName, EnableException,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaRegServerBegin"))
            {
                _beginState = sentinel["__getDbaRegServerBegin"] as Hashtable;
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
        if (Interrupted)
            return;

        // Streaming, not buffered: each registered server is emitted as it is found, so a
        // buffered hop would discard results already produced when a later instance's failure
        // terminated the hop under -EnableException.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaRegServerProcess"))
            {
                _state = sentinel["__getDbaRegServerProcess"] as Hashtable;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlInstance, SqlCredential, Name, ServerName, Pattern, ExcludeServerName, Group,
            ExcludeGroup, Id, IncludeSelf, ResolveNetworkName, IncludeLocal, EnableException,
            _beginState, _state, GetBoundParametersCopy(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private Hashtable GetBoundParametersCopy()
    {
        Hashtable copy = new Hashtable(StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.Generic.KeyValuePair<string, object> kv in MyInvocation.BoundParameters)
            copy[kv.Key] = kv.Value;
        return copy;
    }
}