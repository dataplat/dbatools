#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Clears SQL Server memory caches via DBCC FREEPROCCACHE / FREESESSIONCACHE / FREESYSTEMCACHE. The
/// begin-block query construction (operation-specific WITH clauses keyed off which switches the caller
/// bound), the per-instance connect, the two ShouldProcess gates, and the per-instance result object
/// remain a module-scoped PowerShell compatibility hop; the compiled cmdlet supplies the begin/process
/// lifetime, routes both ShouldProcess gates through its real runtime (ConfirmImpact High), carries the
/// begin-scoped query and the uppercased operation into the process hop, and carries the function-scoped
/// $results the source leaks across pipeline records. Surface pinned by
/// migration/baselines/Invoke-DbaDbccFreeCache.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbccFreeCache", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class InvokeDbaDbccFreeCacheCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0, ParameterSetName = "Default")]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1, ParameterSetName = "Default")]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Which cache-clearing operation to perform: FreeProcCache, FreeSessionCache, or FreeSystemCache.</summary>
    [Parameter(Position = 2, ParameterSetName = "Default")]
    [ValidateSet("FreeProcCache", "FreeSessionCache", "FreeSystemCache")]
    public string Operation { get; set; } = "FreeProcCache";

    /// <summary>A target value (plan_handle/sql_handle 0x..., or a Resource Governor pool name) limiting the operation.</summary>
    [Parameter(Position = 3, ParameterSetName = "Default")]
    public string? InputValue { get; set; }

    /// <summary>Suppresses informational messages returned by the DBCC commands.</summary>
    [Parameter(ParameterSetName = "Default")]
    public SwitchParameter NoInformationalMessages { get; set; }

    /// <summary>Marks active FreeSystemCache entries for removal once they become unused, rather than waiting.</summary>
    [Parameter(ParameterSetName = "Default")]
    public SwitchParameter MarkInUseForRemoval { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // $stringBuilder is built once in the source begin block and read every process record; carry it
    // forward so the process hop reads the same query the begin scope produced.
    private object? _stringBuilder;

    // $Operation is uppercased in the source begin block and read again in the process output object;
    // begin and process share the source function scope but are SEPARATE module-scope invocations here,
    // so carry the resolved (uppercased) operation forward to reproduce the output-object value.
    private object? _operation;

    // Set when the source begin block "aborts" on an unbound -Operation (it warns and `continue`s,
    // which skips both the query build AND the process block). The compiled cmdlet reproduces the
    // observable behavior - warning fires, no query, process does not run, no error - via this flag,
    // keeping the flow-control contained in the hop instead of leaking `continue` to the caller.
    private bool _beginAborted;

    // $results is function-scoped in the source: it is assigned only inside the execute-ShouldProcess
    // gate but read inside the SEPARATE output-ShouldProcess gate. When the execute gate returns false
    // yet the output gate returns true (mixed interactive -Confirm across piped instances), the source
    // reads the PRIOR record's $results; a per-record hop resets it, so we carry it forward to reproduce
    // that leak bug-for-bug. Starts null (never assigned on record 1).
    private object? _resultsState;

    // Per-invocation token so the process carrier sentinel is distinguishable from real output.
    private readonly string _processToken = Guid.NewGuid().ToString("N");

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            TestBound(nameof(Operation)), Operation,
            TestBound(nameof(InputValue)), InputValue,
            TestBound(nameof(NoInformationalMessages)), TestBound(nameof(MarkInUseForRemoval)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item?.BaseObject is WarningRecord nestedWarning)
            {
                // The begin hop's Write-Message -Level Warning is merged back via 3>&1; re-emit it
                // on the real warning stream so the source's "You must specify an operation" warning
                // surfaces for the caller (Write-Message already stamped its [time][command] prefix).
                WriteWarning(nestedWarning.Message);
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InvokeDbaDbccFreeCacheBeginComplete"]?.Value))
            {
                _stringBuilder = UnwrapHopValue(item.Properties["StringBuilder"]?.Value);
                _operation = UnwrapHopValue(item.Properties["Operation"]?.Value);
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__InvokeDbaDbccFreeCacheBeginAborted"]?.Value))
            {
                _beginAborted = true;
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _beginAborted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && string.Equals(
                item.Properties["__InvokeDbaDbccFreeCacheProcessComplete"]?.Value as string, _processToken, StringComparison.Ordinal))
            {
                _resultsState = UnwrapHopValue(item.Properties["Results"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            _stringBuilder, _operation, SqlInstance, SqlCredential, EnableException.ToBool(), _resultsState, this, _processToken,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // Carried hop state arrives PSObject-wrapped. A PSCustomObject carries its content on the
    // wrapper rather than the BaseObject, so unwrapping one would discard it - keep it wrapped.
    private static object? UnwrapHopValue(object? value)
    {
        if (value is PSObject wrapper && wrapper.BaseObject is not PSCustomObject)
            return wrapper.BaseObject;
        return value;
    }

    private const string BeginScript = """
param($__boundOperation, $Operation, $__boundInputValue, $InputValue, $__boundNoInformationalMessages, $__boundMarkInUseForRemoval, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundOperation, $Operation, $__boundInputValue, $InputValue, $__boundNoInformationalMessages, $__boundMarkInUseForRemoval)

    # Test-Bound replacement: the source keyed every WITH clause and the operation itself off whether
    # the caller EXPLICITLY bound each parameter (a boundness check, not its value); module scope cannot
    # see the caller's bound set, so boundness is carried in as a flag per parameter.
    # The source's `else { Write-Message ...; continue }` skips the query build and (via the bare
    # `continue` in a loop-less begin block) the whole process block. `return` here exits ONLY this
    # module-scope hop (early-return law, HOP-PATTERN section 2), keeping the flow-control contained;
    # the emitted BeginAborted sentinel tells the compiled cmdlet to skip ProcessRecord, so the
    # observable behavior matches (warning fires, no query, process does not run, no error).
    if (-not $__boundOperation) {
        Write-Message -Level Warning -Message "You must specify an operation " -FunctionName Invoke-DbaDbccFreeCache -ModuleName "dbatools"
        [pscustomobject]@{ __InvokeDbaDbccFreeCacheBeginAborted = $true }
        return
    }
    $Operation = $Operation.ToUpper()

    $stringBuilder = New-Object System.Text.StringBuilder
    if ($Operation -eq 'FREESESSIONCACHE') {
        $null = $stringBuilder.Append("DBCC $Operation")
        if ($__boundNoInformationalMessages) {
            $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
        }
    }
    if ($Operation -eq 'FREEPROCCACHE') {
        if ($__boundInputValue) {
            if ($InputValue.StartsWith('0x')) {
                $null = $stringBuilder.Append("DBCC $Operation($InputValue)")
            } else {
                $null = $stringBuilder.Append("DBCC $Operation('$InputValue')")
            }
            if ($__boundNoInformationalMessages) {
                $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
            }
        } else {
            $null = $stringBuilder.Append("DBCC $Operation")
            if ($__boundNoInformationalMessages) {
                $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
            }
        }
    }
    if ($Operation -eq 'FREESYSTEMCACHE') {
        if ($__boundInputValue) {
            $null = $stringBuilder.Append("DBCC FREESYSTEMCACHE('ALL', $InputValue)")
        } else {
            $null = $stringBuilder.Append("DBCC FREESYSTEMCACHE('ALL')")
        }
        if ($__boundNoInformationalMessages) {
            if ($__boundMarkInUseForRemoval) {
                $null = $stringBuilder.Append(" WITH NO_INFOMSGS, MARK_IN_USE_FOR_REMOVAL")
            } else {
                $null = $stringBuilder.Append(" WITH NO_INFOMSGS")
            }
        } elseif ($__boundMarkInUseForRemoval) {
            $null = $stringBuilder.Append(" WITH MARK_IN_USE_FOR_REMOVAL")
        }
    }

    [pscustomobject]@{ __InvokeDbaDbccFreeCacheBeginComplete = $true; StringBuilder = $stringBuilder; Operation = $Operation }
} $__boundOperation $Operation $__boundInputValue $InputValue $__boundNoInformationalMessages $__boundMarkInUseForRemoval @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($StringBuilder, $Operation, $SqlInstance, $SqlCredential, $EnableException, $results, $__realCmdlet, $__processToken, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param($StringBuilder, $Operation, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $EnableException, $results, $__realCmdlet, $__processToken)

    $query = $StringBuilder.ToString()

    foreach ($instance in $SqlInstance) {
        Write-Message -Message "Attempting Connection to $instance" -Level Verbose -FunctionName Invoke-DbaDbccFreeCache -ModuleName "dbatools"
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaDbccFreeCache
        }

        try {
            if ($__realCmdlet.ShouldProcess($server.Name, "Execute the command $query against $instance")) {
                Write-Message -Message "Query to run: $query" -Level Verbose -FunctionName Invoke-DbaDbccFreeCache -ModuleName "dbatools"
                $results = $server | Invoke-DbaQuery  -Query $query -MessagesToOutput
            }
        } catch {
            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue -FunctionName Invoke-DbaDbccFreeCache
        }
        if ($__realCmdlet.ShouldProcess("console", "Outputting object")) {
            [PSCustomObject]@{
                ComputerName = $server.ComputerName
                InstanceName = $server.ServiceName
                SqlInstance  = $server.DomainInstanceName
                Operation    = $Operation
                Cmd          = $query.ToString()
                Output       = $results
            }
        }
    }

    [pscustomobject]@{ __InvokeDbaDbccFreeCacheProcessComplete = $__processToken; Results = $results }
} $StringBuilder $Operation $SqlInstance $SqlCredential $EnableException $results $__realCmdlet $__processToken @__commonParameters 3>&1 2>&1
""";
}
