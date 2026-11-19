#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using XeSession = Microsoft.SqlServer.Management.XEvent.Session;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Watches a running Extended Events session and streams its events as structured PowerShell objects.
/// </summary>
/// <remarks>
/// The session resolution, the running-state guard, the column/action projection, the Read-XEvent live
/// read, and the per-event object shaping all run the original dbatools PowerShell body VERBATIM inside the
/// dbatools module scope rather than being reimplemented in C#, so the engine decides the observable
/// details.
///
/// Process-only, non-mutating (no ShouldProcess). $InputObject is reassigned from Get-DbaXESession only when
/// -SqlInstance is supplied, which is the single non-piped process invocation (SqlInstance is not
/// pipeline-bound); when piped, $InputObject is bound per record. So the reassignment never leaks across
/// records and no cross-record carry is needed. The no-Continue Stop-Functions in the read catch arm an
/// interrupt nothing reads (there is no Test-FunctionInterrupt guard), so no interrupt is carried.
///
/// -Raw is passed as a bool via .ToBool() and the inner hop param is UNTYPED (a [switch] inner param skips
/// positional binding and would shift -Raw onto the next argument - the switch-shift class). Each shaped
/// event, and the -Raw Read-XEvent output, emit before a later session may fail under -EnableException, so
/// the process hop uses InvokeScopedStreaming. Surface pinned by migration/baselines/Watch-DbaXESession.json.
/// </remarks>
[Cmdlet(VerbsCommon.Watch, "DbaXESession")]
public sealed class WatchDbaXESessionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The name of the Extended Events session to watch.</summary>
    [Parameter(Position = 2)]
    [Alias("Name")]
    public string? Session { get; set; }

    /// <summary>Extended Events session objects piped in (e.g. from Get-DbaXESession).</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public XeSession[]? InputObject { get; set; }

    /// <summary>Returns the native XEvent objects instead of structured PowerShell objects.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the inherited
    // [Parameter] already matches; no override needed.

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
            SqlInstance, SqlCredential, Session, InputObject, Raw.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from -FunctionName Watch-DbaXESession on the direct
    // Stop-Function/Write-Message sites. $Raw arrives as a bool (the inner param is untyped so the positional
    // bool binds; "if ($raw)" evaluates identically). EnableException is bound so Stop-Function's
    // scope-walking default inherits the caller's value.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Session, $InputObject, $Raw, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, $SqlCredential, [string]$Session, [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject, $Raw, $EnableException)
    if ($SqlInstance) {
        $InputObject = Get-DbaXESession -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Session $Session
    }

    foreach ($xesession in $InputObject) {
        $server = $xesession.Parent
        $sessionname = $xesession.Name
        Write-Message -Level Verbose -Message "Watching $sessionname on $($server.Name)." -FunctionName Watch-DbaXESession -ModuleName "dbatools"

        if (-not $xesession.IsRunning) {
            Stop-Function -Message "$($xesession.Name) is not running on $($server.Name)" -Continue -FunctionName Watch-DbaXESession
        }

        # Setup all columns for csv but do it in an order
        $columns = @("name", "timestamp")
        $newcolumns = @()

        $fields = ($xesession.Events.EventFields.Name | Select-Object -Unique)
        foreach ($column in $fields) {
            $newcolumns += $column.TrimStart("collect_")
        }

        $actions = ($xesession.Events.Actions.Name | Select-Object -Unique)
        foreach ($action in $actions) {
            $newcolumns += ($action -Split '\.')[-1]
        }

        $newcolumns = $newcolumns | Sort-Object
        $columns = ($columns += $newcolumns) | Select-Object -Unique

        try {
            if ($raw) {
                return (Read-XEvent -ConnectionString $server.ConnectionContext.ConnectionString -SessionName $sessionname -ErrorAction Stop)
            }

            Read-XEvent -ConnectionString $server.ConnectionContext.ConnectionString -SessionName $sessionname -ErrorAction Stop | ForEach-Object -Process {

                $hash = [ordered]@{ }

                foreach ($column in $columns) {
                    $null = $hash.Add($column, $PSItem.$column) # this basically adds name and timestamp then nulls
                }

                foreach ($key in $PSItem.Actions.Keys) {
                    $hash[$key] = $PSItem.Actions[$key]
                }

                foreach ($key in $PSItem.Fields.Keys) {
                    $hash[$key] = $PSItem.Fields[$key]
                }

                [PSCustomObject]($hash)
            }
        } catch {
            Start-Sleep 1
            $status = Get-DbaXESession -SqlInstance $server -Session $sessionname
            if ($status.Status -ne "Running") {
                Stop-Function -Message "$($xesession.Name) was stopped." -FunctionName Watch-DbaXESession
            } else {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $sessionname -FunctionName Watch-DbaXESession
            }
        }
    }
} $SqlInstance $SqlCredential $Session $InputObject $Raw $EnableException @__commonParameters 3>&1 2>&1
""";
}
