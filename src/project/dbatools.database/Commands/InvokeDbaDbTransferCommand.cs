#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Transfers database objects and data between instances via an SMO Transfer. Port of
/// public/Invoke-DbaDbTransfer.ps1; the workflow remains a module-scoped PowerShell compatibility hop.
///
/// BEGIN+PROCESS, two hops. InputObject (an SMO Transfer) is ValueFromPipeline, so process fires per
/// record. Begin runs once to resolve New-DbaDbTransfer's parameter names and carries that list to
/// process, which uses it to decide which of the caller's bound parameters to forward.
///
/// $PSBoundParameters CANNOT RIDE A HOP. The body iterates the CALLER's bound parameters
/// ("foreach ($key in $PSBoundParameters.Keys) { if ($key -in $newTransferParams) { ... } }") to
/// build the New-DbaDbTransfer splat, but inside a hop $PSBoundParameters is the inner
/// scriptblock's own positional binding, which would forward nothing. The compiled cmdlet's real
/// MyInvocation.BoundParameters is therefore carried in and substituted (the Export-DbaBinaryFile
/// boundness-carry class, extended here from single flags to the whole table). Only parameters the
/// caller actually bound are forwarded, exactly as the source does - a defaulted parameter is
/// absent from the table and is not passed on.
///
/// -DestinationDatabase's source default is "= $Database", a bind-time default derived from ANOTHER
/// parameter that a C# property initializer cannot express (the DEF-007 class, as with
/// Compare-DbaDbSchema's config-derived OutputPath). The hop reproduces the binding instead: when
/// -DestinationDatabase was not bound it takes -Database's value. Note this deliberately does NOT
/// add it to the carried bound-parameter table - the source's $PSBoundParameters would not contain
/// an unbound parameter either, so New-DbaDbTransfer keeps receiving only what the caller supplied.
///
/// INTERRUPT CARRY. The transfer-failure Stop-Function has no -Continue, so it sets the module
/// interrupt flag; across separate hop invocations the flag does not survive, so each hop reads it
/// at Get-Variable -Scope 0 after its dot-sourced body and carries it, and C# skips process when a
/// prior record set it. The body's "return" after that Stop-Function, and the "return
/// $transfer.ScriptTransfer()" on the -ScriptOnly path (which EMITS the script then exits), both
/// exit only the dot-sourced body while the sentinel still emits.
///
/// The single $PSCmdlet.ShouldProcess gate routes to the real cmdlet via $__realCmdlet
/// (SupportsShouldProcess mirrored; the -Force/ConfirmPreference axis was probe-proven safe for
/// this pattern - see migration/logs/probe-20260718-force-confirmpref). The Register-ObjectEvent
/// subscription and its $events.Output read ride verbatim inside the hop, so the event action
/// scriptblock and the captured output stay in one scope. Surface pinned by
/// migration/baselines/Invoke-DbaDbTransfer.json (DefaultParameterSetName "Default", no named sets).
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbTransfer", SupportsShouldProcess = true, DefaultParameterSetName = "Default")]
public sealed class InvokeDbaDbTransferCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The destination SQL Server instance.</summary>
    [Parameter(Position = 2)]
    public DbaInstanceParameter? DestinationSqlInstance { get; set; }

    /// <summary>Alternative credential for the destination instance.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>The source database.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string? Database { get; set; }

    /// <summary>The destination database; defaults to -Database when not supplied.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    public string? DestinationDatabase { get; set; }

    /// <summary>Rows per bulk-copy batch.</summary>
    [Parameter(Position = 6)]
    public int BatchSize { get; set; } = 50000;

    /// <summary>Bulk-copy timeout in seconds.</summary>
    [Parameter(Position = 7)]
    public int BulkCopyTimeOut { get; set; } = 5000;

    /// <summary>SMO scripting options applied to the transfer.</summary>
    [Parameter(Position = 8)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOption { get; set; }

    /// <summary>An existing SMO Transfer object, typically from New-DbaDbTransfer.</summary>
    [Parameter(ValueFromPipeline = true, Position = 9)]
    public Microsoft.SqlServer.Management.Smo.Transfer? InputObject { get; set; }

    /// <summary>Transfer every supported object type.</summary>
    [Parameter]
    public SwitchParameter CopyAllObjects { get; set; }

    /// <summary>Transfer only these object types.</summary>
    [Parameter(Position = 10)]
    [ValidateSet("FullTextCatalogs", "FullTextStopLists", "SearchPropertyLists",
        "Tables", "Views", "StoredProcedures", "UserDefinedFunctions", "UserDefinedDataTypes",
        "UserDefinedTableTypes", "PlanGuides", "Rules", "Defaults", "Users", "Roles", "PartitionSchemes",
        "PartitionFunctions", "XmlSchemaCollections", "SqlAssemblies", "UserDefinedAggregates",
        "UserDefinedTypes", "Schemas", "Synonyms", "Sequences", "DatabaseTriggers", "DatabaseScopedCredentials",
        "ExternalFileFormats", "ExternalDataSources", "Logins", "ExternalLibraries")]
    [PsStringArrayCast]
    public string[]? CopyAll { get; set; }

    /// <summary>Transfer schema without data.</summary>
    [Parameter]
    public SwitchParameter SchemaOnly { get; set; }

    /// <summary>Transfer data without schema.</summary>
    [Parameter]
    public SwitchParameter DataOnly { get; set; }

    /// <summary>Emit the transfer script instead of executing it.</summary>
    [Parameter]
    public SwitchParameter ScriptOnly { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // New-DbaDbTransfer's parameter names, resolved once in begin and carried (opaque).
    private Hashtable? _beginState;
    // A transfer-failure Stop-Function on an earlier record halts the rest.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbTransferBegin"))
            {
                _beginState = sentinel["__invokeDbaDbTransferBegin"] as Hashtable;
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
        if (Interrupted || _interrupted)
            return;

        // The caller's real bound parameters, which the body iterates to build the
        // New-DbaDbTransfer splat. Copied per record so the hop never mutates the live table.
        Hashtable bound = new Hashtable(MyInvocation.BoundParameters);

        // -DestinationDatabase's "= $Database" bind-time default. Applied to the variable the hop
        // sees, NOT to the carried bound-parameter table: the source's $PSBoundParameters would not
        // contain an unbound parameter, so it must not be forwarded to New-DbaDbTransfer either.
        string? destinationDatabase = MyInvocation.BoundParameters.ContainsKey("DestinationDatabase")
            ? DestinationDatabase
            : Database;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            InputObject, ScriptOnly.ToBool(), destinationDatabase, EnableException.ToBool(),
            _beginState, bound, this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__invokeDbaDbTransferProcess"))
            {
                if (sentinel["__invokeDbaDbTransferProcess"] is Hashtable result)
                    _interrupted = LanguagePrimitives.IsTrue(result["Interrupted"]);
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

    // PS: the begin block VERBATIM, dot-sourced. It only resolves New-DbaDbTransfer's parameter
    // names; the sentinel carries that list to process.
    private const string BeginScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        $newTransferParams = (Get-Command New-DbaDbTransfer).Parameters.Keys | Where-Object { $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters }
    }

    @{ __invokeDbaDbTransferBegin = @{ NewTransferParams = $newTransferParams } }
} $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM per record, dot-sourced so its returns (including the
    // -ScriptOnly "return $transfer.ScriptTransfer()", which emits then exits) leave only the body
    // while the sentinel still emits. Edits: $PSCmdlet -> $__realCmdlet on the one gate,
    // $PSBoundParameters -> the carried $__boundParameters (the caller's real table - the inner
    // scriptblock's own binding would forward nothing), and -FunctionName on the two calls.
    private const string ProcessScript = """
param($InputObject, $ScriptOnly, $DestinationDatabase, $EnableException, $__beginState, $__boundParameters, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess)]
    param([Microsoft.SqlServer.Management.Smo.Transfer]$InputObject, $ScriptOnly, [string]$DestinationDatabase, $EnableException, $__beginState, $__boundParameters, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin-resolved New-DbaDbTransfer parameter names
    $newTransferParams = $__beginState.NewTransferParams

    . {
        if ($InputObject) {
            $transfer = $InputObject
        } else {
            $paramSet = @{ }
            # generate transfer object by adding all applicable parameters to the New-DbaDbTransfer call
            foreach ($key in $__boundParameters.Keys) {
                if ($key -in $newTransferParams) {
                    $paramSet[$key] = $__boundParameters[$key]
                }
            }
            Write-Message -Message "Generating a transfer object based on current parameters" -Level Verbose -FunctionName Invoke-DbaDbTransfer -ModuleName "dbatools"
            $transfer = New-DbaDbTransfer @paramSet
        }
        # add event handling
        $events = Register-ObjectEvent -InputObject $transfer -EventName DataTransferEvent -Action {
            "[$(Get-Date)] [$($args[1].DataTransferEventType)] $($args[1].Message)"
        }
        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
        if ($__realCmdlet.ShouldProcess("Begin transfer")) {
            try {
                if ($ScriptOnly) {
                    return $transfer.ScriptTransfer()
                } else {
                    $transfer.TransferData()
                }
            } catch {
                Stop-Function -ErrorRecord $_ -Message "Transfer failed" -FunctionName Invoke-DbaDbTransfer
                return
            }

            return [PSCustomObject]@{
                SourceInstance      = $transfer.Database.Parent.Name
                SourceDatabase      = $transfer.Database.Name
                DestinationInstance = $transfer.DestinationServer
                DestinationDatabase = $transfer.DestinationDatabase
                Status              = 'Success'
                Elapsed             = [prettytimespan]$elapsed.Elapsed
                Log                 = $events.Output
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __invokeDbaDbTransferProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $InputObject $ScriptOnly $DestinationDatabase $EnableException $__beginState $__boundParameters $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
