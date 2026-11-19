#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Compares the logins on a source SQL Server instance against one or more destination instances.
/// </summary>
/// <remarks>
/// The workflow remains a module-scoped PowerShell compatibility hop so that login discovery, the
/// comparison, output shape, and dbatools stream and error handling stay observable-identical to the
/// script implementation. The command is shipped as TWO hops to preserve the script's lifecycle: the
/// begin hop connects to the source and gathers its logins EXACTLY ONCE - so it still runs when the
/// upstream pipeline is empty, matching the function - and the process hop compares against each
/// destination. The source server and its logins are carried between the hops as fields.
/// </remarks>
[Cmdlet(VerbsData.Compare, "DbaLogin")]
public sealed class CompareDbaLoginCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for the destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>The login or logins to compare; all logins are compared when omitted.</summary>
    [Parameter(Position = 4)]
    public string[]? Login { get; set; }

    /// <summary>Logins to exclude from the comparison.</summary>
    [Parameter(Position = 5)]
    public string[]? ExcludeLogin { get; set; }

    /// <summary>Excludes system logins from the comparison.</summary>
    [Parameter]
    public SwitchParameter ExcludeSystemLogin { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Set when the begin block stopped the command (source connection failure).</summary>
    private bool _beginInterrupted;

    /// <summary>The source server and its logins, gathered once in begin and read by each record.</summary>
    private object? _sourceServer;
    private object? _sourceLogins;

    /// <summary>Connects to the source and gathers its logins once, before any record.</summary>
    protected override void BeginProcessing()
    {
        bool completed = false;
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Source, SourceSqlCredential, Login, ExcludeLogin, ExcludeSystemLogin.ToBool(),
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__CompareDbaLoginBeginComplete"]?.Value))
            {
                completed = true;
                _sourceServer = UnwrapHopValue(item.Properties["SourceServer"]?.Value);
                _sourceLogins = UnwrapHopValue(item.Properties["SourceLogins"]?.Value);
            }
            else if (item is not null)
            {
                WriteObject(item);
            }
        }

        // The sentinel is the last statement of the begin body, so it is absent exactly when that
        // body returned early - which it does only after a source connection failure stopped the command.
        _beginInterrupted = !completed;
    }

    /// <summary>Compares the source logins against each destination for one pipeline record.</summary>
    protected override void ProcessRecord()
    {
        if (_beginInterrupted || Interrupted)
            return;

        // [DEF-001] streamed via InvokeScopedStreaming: the hop body loops emitting per-item and
        // carries reachable terminating throws (-Continue Stop-Function under -EnableException), so a
        // buffered InvokeScoped would lose an earlier item's emit when a later item throws. Streaming
        // yields each record as produced; no state carry on this row.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            if (item is not null)
                WriteObject(item);
        }, ProcessScript,
            Destination, DestinationSqlCredential, Login, ExcludeLogin, ExcludeSystemLogin.ToBool(),
            _sourceServer, _sourceLogins, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    /// <summary>
    /// Unwraps a value the begin hop carried out through its sentinel.
    /// </summary>
    /// <remarks>
    /// A command that produced NO output leaves the script variable holding AutomationNull, which
    /// behaves as $null in PowerShell but unwraps to a truthy, property-less object - so it comes
    /// back as null instead. Otherwise the value is unwrapped ONLY when the wrapper adds nothing:
    /// note properties (whether Add-Member decoration on an SMO object or the members of a
    /// [PSCustomObject]) live on the PSObject wrapper, not the BaseObject, so unwrapping such a
    /// value silently discards them. Cardinality is settled at the sentinel, where the carried
    /// collection is normalized with @(), never inferred here - a genuinely empty
    /// [pscustomobject]@{} and a no-output result are indistinguishable by shape, and only the
    /// sentinel knows which it holds.
    /// </remarks>
    private static object? UnwrapHopValue(object? value)
    {
        if (value is null || ReferenceEquals(value, System.Management.Automation.Internal.AutomationNull.Value))
            return null;
        if (value is not PSObject wrapper)
            return value;
        foreach (PSMemberInfo member in wrapper.Members)
        {
            if (member is PSNoteProperty)
                return wrapper;
        }
        return wrapper.BaseObject;
    }

    // PS: the begin body VERBATIM. Substitution only: -FunctionName on the direct Stop-Function call.
    // The begin catch keeps its explicit return, which skips the trailing sentinel - that absence is
    // how BeginProcessing learns the source connection failed. The source server and its logins are
    // emitted through the sentinel so the process hop can read them (a hop scope dies between hops).
    private const string BeginScript = """
param($Source, $SourceSqlCredential, $Login, $ExcludeLogin, $ExcludeSystemLogin, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [PSCredential]$SourceSqlCredential, [string[]]$Login, [string[]]$ExcludeLogin, $ExcludeSystemLogin, $EnableException, $__boundVerbose, $__boundDebug)

    try {
        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
    } catch {
        Stop-Function -Message "Failure connecting to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Compare-DbaLogin
        return
    }

    $splatGetSource = @{
        SqlInstance        = $sourceServer
        ExcludeSystemLogin = $ExcludeSystemLogin
    }
    if ($Login) {
        $splatGetSource["Login"] = $Login
    }
    if ($ExcludeLogin) {
        $splatGetSource["ExcludeLogin"] = $ExcludeLogin
    }
    $sourceLogins = Get-DbaLogin @splatGetSource

    # SourceLogins is normalized to an array so the seam carries cardinality unambiguously: a
    # no-output result becomes an empty array rather than AutomationNull, which the process replay
    # would otherwise receive as a truthy, property-less object and iterate over.
    [pscustomobject]@{ __CompareDbaLoginBeginComplete = $true; SourceServer = $sourceServer; SourceLogins = @($sourceLogins) }
} $Source $SourceSqlCredential $Login $ExcludeLogin $ExcludeSystemLogin $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process body VERBATIM. Substitution only: -FunctionName on the direct Stop-Function call.
    // $sourceServer and $sourceLogins are received from the begin hop rather than a shared function
    // scope. The Test-FunctionInterrupt guard is preserved verbatim; the begin stop is carried by
    // _beginInterrupted, so this record only runs when begin completed.
    private const string ProcessScript = """
param($Destination, $DestinationSqlCredential, $Login, $ExcludeLogin, $ExcludeSystemLogin, $sourceServer, $sourceLogins, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, [PSCredential]$DestinationSqlCredential, [string[]]$Login, [string[]]$ExcludeLogin, $ExcludeSystemLogin, $sourceServer, $sourceLogins, $EnableException, $__boundVerbose, $__boundDebug)

    if (Test-FunctionInterrupt) { return }

    foreach ($destInstance in $Destination) {
        $destServer = $null
        try {
            $destServer = Connect-DbaInstance -SqlInstance $destInstance -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure connecting to $destInstance" -Category ConnectionError -ErrorRecord $_ -Target $destInstance -Continue -FunctionName Compare-DbaLogin
        }
        if ($null -eq $destServer) { continue }

        $splatGetDest = @{
            SqlInstance        = $destServer
            ExcludeSystemLogin = $ExcludeSystemLogin
        }
        if ($Login) {
            $splatGetDest["Login"] = $Login
        }
        if ($ExcludeLogin) {
            $splatGetDest["ExcludeLogin"] = $ExcludeLogin
        }
        $destLogins = Get-DbaLogin @splatGetDest

        $allLoginNames = New-Object System.Collections.ArrayList
        foreach ($srcLogin in $sourceLogins) {
            if ($srcLogin.Name -notin $allLoginNames) {
                $null = $allLoginNames.Add($srcLogin.Name)
            }
        }
        foreach ($dstLogin in $destLogins) {
            if ($dstLogin.Name -notin $allLoginNames) {
                $null = $allLoginNames.Add($dstLogin.Name)
            }
        }

        foreach ($loginName in $allLoginNames) {
            $srcLogin = $sourceLogins | Where-Object Name -eq $loginName
            $dstLogin = $destLogins | Where-Object Name -eq $loginName

            if ($srcLogin -and $dstLogin) {
                $status = "Both"
            } elseif ($srcLogin) {
                $status = "SourceOnly"
            } else {
                $status = "DestinationOnly"
            }

            [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                LoginName         = $loginName
                LoginType         = if ($srcLogin) { $srcLogin.LoginType } else { $dstLogin.LoginType }
                Status            = $status
            }
        }
    }
} $Destination $DestinationSqlCredential $Login $ExcludeLogin $ExcludeSystemLogin $sourceServer $sourceLogins $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
