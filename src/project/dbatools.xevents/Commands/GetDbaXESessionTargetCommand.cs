#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using XeSession = Microsoft.SqlServer.Management.XEvent.Session;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the target(s) of Extended Events sessions from SQL Server instances (or from piped
/// Get-DbaXESession output).
/// </summary>
/// <remarks>
/// The session resolution, the per-session/per-target walk, the target-file path resolution, the
/// Add-Member decoration, and the Select-DefaultView projection all run the original dbatools PowerShell
/// body VERBATIM inside the dbatools module scope rather than being reimplemented in C#, so the engine
/// decides the observable details.
///
/// The source begin block ONLY defines the pure nested helper function Get-Target (used by process), so
/// per the begin-defined-nested-function rule this is ported PROCESS-ONLY with the Get-Target definition
/// PREPENDED into the process hop (redefined per record - identical, harmless). There is no Stop-Function
/// or Write-Message anywhere in this function, so the body is fully VERBATIM (no -FunctionName edits). The
/// process block's "if (Test-FunctionInterrupt) { return }" is preserved verbatim but INERT - nothing in
/// this function sets the interrupt (Get-DbaXESession's own interrupt lives in its own scope), so there is
/// no interrupt to carry and no Interrupted guard.
///
/// Two parameter sets: -SqlInstance (set "instance") or piped -InputObject sessions (set "piped"), default
/// "Default". $InputObject is carried across records: in the "instance" set it is UNBOUND and the body's
/// "$InputObject += Get-DbaXESession ..." accumulates across piped SqlInstance records (function scope), so
/// the C# seeds each record's $InputObject from the fresh VFP binding when present (piped set) else from the
/// carried accumulation (instance set), and captures the re-emitted value from the process sentinel.
/// Each target is emitted before a later instance may fail under -EnableException (a nested
/// Get-DbaXESession connect failure throws terminating under EE) (DEF-001), so the process hop uses
/// InvokeScopedStreaming. Surface pinned by migration/baselines/Get-DbaXESessionTarget.json.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaXESessionTarget", DefaultParameterSetName = "Default")]
public sealed class GetDbaXESessionTargetCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "instance")]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Filters results to specific Extended Events sessions by name.</summary>
    [Parameter]
    public string[]? Session { get; set; }

    /// <summary>Filters results to specific target names.</summary>
    [Parameter]
    public string[]? Target { get; set; }

    /// <summary>Extended Events Session objects piped in (e.g. from Get-DbaXESession).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "piped")]
    public XeSession[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (no set named), which
    // reflects as __AllParameterSets and matches the inherited [Parameter]; no per-set override needed.

    // $InputObject is a function-scope parameter variable. In the "piped" set it is VFP (rebound each
    // record); in the "instance" set it is UNBOUND and the body's "$InputObject += Get-DbaXESession ..."
    // ACCUMULATES across records (function scope persists across ProcessRecord). So it is carried record
    // to record: seeded from the fresh VFP binding when present (piped set), else from the carried value
    // (instance-set accumulation), and re-emitted from each record's sentinel.
    private object? _inputObject;

    protected override void ProcessRecord()
    {
        // piped set: InputObject is bound (non-null) -> use the fresh VFP value (overwrites the carry).
        // instance set: InputObject is null -> use the carried accumulation.
        object? inputSeed = (object?)InputObject ?? _inputObject;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaXESessionTargetProcess"))
            {
                if (sentinel["__getDbaXESessionTargetProcess"] is Hashtable state)
                {
                    _inputObject = state["InputObject"];
                }
                return;
            }
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
            SqlInstance, SqlCredential, Session, Target, inputSeed, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block's nested Get-Target function definition prepended VERBATIM, then the process
    // block VERBATIM (no direct Stop-Function/Write-Message, so no -FunctionName edits). Get-Target is
    // redefined per record - identical and harmless.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Session, $Target, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Session, [string[]]$Target, [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject, $EnableException)
    function Get-Target {
        [CmdletBinding()]
        param (
            $Sessions,
            $Session,
            $Server,
            $Target
        )

        foreach ($xsession in $Sessions) {

            if ($null -eq $server) {
                $server = $xsession.Parent
            }

            if ($Session -and $xsession.Name -notin $Session) { continue }
            $status = switch ($xsession.IsRunning) { $true { "Running" } $false { "Stopped" } }
            $sessionname = $xsession.Name

            foreach ($xtarget in $xsession.Targets) {
                if ($Target -and $xtarget.Name -notin $Target) { continue }

                $files = $xtarget.TargetFields | Where-Object Name -eq Filename | Select-Object -ExpandProperty Value

                $filecollection = $remotefile = @()

                if ($files) {
                    foreach ($file in $files) {
                        if ($file -notmatch ':\\' -and $file -notmatch '\\\\') {
                            $directory = $server.ErrorLogPath.TrimEnd("\")
                            $file = "$directory\$file"
                        }
                        $filecollection += $file
                        $remotefile += Join-AdminUnc -servername $server.ComputerName -filepath $file
                    }
                }

                Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name Session -Value $sessionname
                Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name SessionStatus -Value $status
                Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name TargetFile -Value $filecollection
                Add-Member -Force -InputObject $xtarget -MemberType NoteProperty -Name RemoteTargetFile -Value $remotefile

                Select-DefaultView -InputObject $xtarget -Property ComputerName, InstanceName, SqlInstance, Session, SessionStatus, Name, ID, 'TargetFields as Field', PackageName, 'TargetFile as File', Description, ScriptName
            }
        }
    }

    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        $InputObject += Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential -Session $Session
    }
    Get-Target -Sessions $InputObject -Session $Session -Target $Target
    @{ __getDbaXESessionTargetProcess = @{ InputObject = $InputObject } }
} $SqlInstance $SqlCredential $Session $Target $InputObject $EnableException @__commonParameters 3>&1 2>&1
""";
}
