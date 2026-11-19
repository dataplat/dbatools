#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Replays Extended Events (from Read-DbaXEFile) against SQL Server instances by writing the captured
/// statements to a temp .sql file and running it through sqlcmd.
/// </summary>
/// <remarks>
/// The temp-file assembly, the event filtering, the sqlcmd invocation, and the output trimming all run the
/// original dbatools PowerShell body VERBATIM inside the dbatools module scope rather than being
/// reimplemented in C#, so the engine decides the observable details.
///
/// The script has begin (create the temp .sql; require sqlcmd), process (append each matching event's
/// statement to the temp file), and end (run sqlcmd per instance, emit the trimmed output, delete the temp
/// file) blocks - the temp $filename spans all three on the function scope. The port collects each piped
/// InputObject event into _batches across ProcessRecord and, in EndProcessing, runs ONE hop that executes
/// the begin body, the process body once per batch (dot-sourced), and the end body in a SINGLE scope, so
/// $filename and every other local persist exactly as the function scope does. An empty pipeline collects
/// no batches so the process body never runs (begin still creates the temp file), matching the script.
///
/// DEF-010 SANCTIONED KEEP-DIVERGENCE (ruled 2026-07-19, operator quality-review directive §3d): the
/// divergence below is DELIBERATE and APPROVED - do not "fix" it back to faithful reproduction. Same
/// class as W2-046: a bare continue that drops all subsequent events is a catastrophic SILENT bug, so
/// diverging toward the filter's evident intent (process all matching events) is the TB-092-spirit
/// call and is consistent with the DEF-010 canonical ruling. The underlying SOURCE bug is tracked
/// upstream as U-5; when it is fixed there, this divergence should disappear rather than be preserved.
///
/// The measurement, retained: the process body's event filter is a BARE "continue"
/// ("if (`$InputObject.Name -notin `$Event) { continue }"). In the script world that bare continue in a
/// process block has NO enclosing loop, so it propagates up the call stack and ABORTS the entire piped
/// invocation on the FIRST non-matching event (a latent source bug, the bare-continue sibling of W2-046's
/// dangling -ContinueLabel main - probe-confirmed 2026-07-18). Here the process body is dot-sourced inside
/// "foreach (`$__batch in `$__batches)", so the bare continue continues that foreach and SKIPS just that one
/// event, then processes the rest - which is the source author's evident intent (drop events not in
/// -Event). This is the DEF-010 "diverge toward intent where faithful reproduction is a bug" disposition;
/// the divergence is error/filter-path only. The end block's two "continue" statements (lines 142/145,
/// -Raw path) sit inside a real "foreach (`$instance in `$SqlInstance)" and continue THAT loop normally, so
/// they are unaffected.
///
/// -Raw is passed as a bool and the inner hop param is UNTYPED (a [switch] inner param skips positional
/// binding - the switch-shift class). -Database is declared for the surface but is unused by the body, so
/// it is not passed to the hop. Test-Bound -ParameterName SqlCredential -> the carried $__sqlCredentialBound
/// flag. The sqlcmd output emits before a later instance may fail under -EnableException, so the hop uses
/// InvokeScopedStreaming. Surface pinned by migration/baselines/Invoke-DbaXEReplay.json.
/// </remarks>
[Cmdlet(VerbsLifecycle.Invoke, "DbaXEReplay")]
public sealed class InvokeDbaXEReplayCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database context (declared by the source but unused by the body).</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The event names to replay; others are skipped.</summary>
    [Parameter(Position = 3)]
    public string[] Event { get; set; } = new[] { "sql_batch_completed", "rcp_completed" };

    /// <summary>Extended Events records piped in (e.g. from Read-DbaXEFile).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 4)]
    public object InputObject { get; set; } = null!;

    /// <summary>Return the raw sqlcmd output instead of trimmed lines.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // One batch per ProcessRecord: the piped event record. The begin body, every process record, and the end
    // body then run in a single EndProcessing hop so the temp $filename and other locals persist.
    private readonly List<object?> _batches = new List<object?>();

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        _batches.Add(InputObject);
    }

    protected override void EndProcessing()
    {
        if (Interrupted)
        {
            return;
        }

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
            _batches.ToArray(), SqlInstance, SqlCredential, Event, Raw.ToBool(), EnableException.ToBool(),
            TestBound(nameof(SqlCredential)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin body, the process body (dot-sourced, once per collected batch), and the end body VERBATIM
    // in ONE scope. Substitutions: -FunctionName on the direct Stop-Function; Test-Bound SqlCredential -> the
    // carried $__sqlCredentialBound flag. The bare-continue DEF-010 divergence is described in the class
    // remarks. EnableException is bound so Stop-Function's scope-walking default inherits it.
    private const string ProcessScript = """
param($__batches, $SqlInstance, $SqlCredential, $Event, $Raw, $EnableException, $__sqlCredentialBound, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__batches, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Event, $Raw, $EnableException, $__sqlCredentialBound)
    $timestamp = (Get-Date -Format yyyyMMddHHmm)
    $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
    $filename = "$temp\dbatools-replay-$timestamp.sql"
    Set-Content $filename -Value $null

    if (-not (Get-Command sqlcmd -ErrorAction Ignore)) {
        Stop-Function -Message "sqlcmd is not installed. Please install the SQL Server Command Line Utilities." -FunctionName Invoke-DbaXEReplay
        return
    }

    foreach ($__batch in $__batches) {
        $InputObject = $__batch
        . {
        if (Test-FunctionInterrupt) { return }
        if ($InputObject.Name -notin $Event) {
            continue
        }

        if ($InputObject.statement) {
            if ($InputObject.statement -notmatch "ALTER EVENT SESSION") {
                Add-Content -Path $filename -Value $InputObject.statement
                Add-Content -Path $filename -Value "GO"
            }
        } else {
            if ($InputObject.batch_text -notmatch "ALTER EVENT SESSION") {
                Add-Content -Path $filename -Value $InputObject.batch_text
                Add-Content -Path $filename -Value "GO"
            }
        }
        }
    }

    if (Test-FunctionInterrupt) { return }
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Invoke-DbaXEReplay
        }


        if ($Raw) {
            Write-Message -Message "Invoking XEReplay against $instance running on $($server.name) with raw output" -Level Verbose -FunctionName Invoke-DbaXEReplay -ModuleName "dbatools"
            if ($__sqlCredentialBound) {
                . sqlcmd -S $instance -i $filename -U $SqlCredential.Username -P $SqlCredential.GetNetworkCredential().Password
                continue
            } else {
                . sqlcmd -S $instance -i $filename
                continue
            }
        }

        Write-Message -Message "Invoking XEReplay against $instance running on $($server.name)" -Level Verbose -FunctionName Invoke-DbaXEReplay -ModuleName "dbatools"
        if ($__sqlCredentialBound) {
            $output = . sqlcmd -S $instance -i $filename -U $SqlCredential.Username -P $SqlCredential.GetNetworkCredential().Password
        } else {
            $output = . sqlcmd -S $instance -i $filename
        }

        foreach ($line in $output) {
            $newline = $line.Trim()
            if ($newline -and $newline -notmatch "------------------------------------------------------------------------------------") {
                "$newline"
            }
        }
    }
    Remove-Item -Path $filename -ErrorAction Ignore
} $__batches $SqlInstance $SqlCredential $Event $Raw $EnableException $__sqlCredentialBound @__commonParameters 3>&1 2>&1
""";
}
