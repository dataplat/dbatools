#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the on-disk target file(s) of Extended Events sessions (or of piped Get-DbaXESessionTarget
/// output) from SQL Server instances.
/// </summary>
/// <remarks>
/// The target resolution, the per-object type dispatch, the file-path glob expansion, and the
/// Get-ChildItem enumeration all run the original dbatools PowerShell body VERBATIM inside the dbatools
/// module scope rather than being reimplemented in C#, so the engine decides the observable details.
///
/// Three parameter sets: -SqlInstance (set "instance"), piped -InputObject (set "piped"), or the default
/// "Default". $InputObject is carried across records: in the "instance" set it is UNBOUND and the body's
/// "$InputObject += Get-DbaXESessionTarget ..." accumulates across piped SqlInstance records (function
/// scope), so the C# seeds each record's $InputObject from the fresh VFP binding when present (piped set)
/// else from the carried accumulation (instance set), and captures the re-emitted value.
///
/// INTERRUPT is carried process -> process (cross-record): the object loop's no-Continue Stop-Functions
/// (Get-ChildItem failure, unsupported type) set the function-scope interrupt, and the process block's own
/// "if (Test-FunctionInterrupt) { return }" reads it; in the source that interrupt persists across records,
/// so each record emits it in the sentinel and the C# OR-accumulates _interrupted, with ProcessRecord
/// guarding on it. Under -EnableException those Stop-Functions throw terminating instead (framework
/// re-throws). The source's Test-FunctionInterrupt line is verbatim but inert at record entry (nothing sets
/// the interrupt before it within a record; cross-record is the C# guard's job). The -Continue Stop-Function
/// (missing target file) never sets the interrupt.
///
/// Each file is emitted before a later object may fail under -EnableException (DEF-001), so the process hop
/// uses InvokeScopedStreaming. No ShouldProcess, no Test-Bound, no Interrupted (base-flag) guard. Surface
/// pinned by migration/baselines/Get-DbaXESessionTargetFile.json.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaXESessionTargetFile", DefaultParameterSetName = "Default")]
public sealed class GetDbaXESessionTargetFileCommand : DbaBaseCmdlet
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

    /// <summary>Session or Target objects piped in (e.g. from Get-DbaXESessionTarget).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, ParameterSetName = "piped")]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (no set named), which
    // reflects as __AllParameterSets and matches the inherited [Parameter]; no per-set override needed.

    // The function-scope interrupt, set by the object loop's no-Continue Stop-Functions and read by the
    // process block; carried record to record.
    private bool _interrupted;

    // $InputObject: VFP in the "piped" set (rebound per record); UNBOUND and accumulating in the "instance"
    // set. Carried record to record.
    private object? _inputObject;

    protected override void ProcessRecord()
    {
        if (_interrupted)
        {
            return;
        }

        // piped set: InputObject is bound (non-null) -> fresh VFP value (overwrites the carry).
        // instance set: InputObject is null -> carried accumulation.
        object? inputSeed = (object?)InputObject ?? _inputObject;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__getDbaXESessionTargetFileProcess"))
            {
                if (sentinel["__getDbaXESessionTargetFileProcess"] is Hashtable state)
                {
                    _inputObject = state["InputObject"];
                    _interrupted = _interrupted || LanguagePrimitives.IsTrue(state["Interrupted"]);
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

    // PS: the process block VERBATIM apart from -FunctionName Get-DbaXESessionTargetFile on the direct
    // Stop-Function/Write-Message sites, plus a trailing sentinel carrying $InputObject and the interrupt.
    // No dot-source wrap: the only return (Test-FunctionInterrupt) is inert at record entry, and the
    // no-Continue Stop-Functions do not return, so the sentinel is always reached.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Session, $Target, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [string[]]$Session, [string[]]$Target, [object[]]$InputObject, $EnableException)
    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        $splatTarget = @{
            SqlInstance   = $instance
            SqlCredential = $SqlCredential
            Session       = $Session
            Target        = $Target
        }
        $InputObject += Get-DbaXESessionTarget @splatTarget | Where-Object File -ne $null
    }

    foreach ($object in $InputObject) {
        if ($object -is [Microsoft.SqlServer.Management.XEvent.Session]) {
            if ($object.TargetFile.Length -eq 0) {
                Stop-Function -Message "The session [$object] does not have an associated Target File." -Continue -FunctionName Get-DbaXESessionTargetFile
            }

            $instance = [DbaInstance]$object.ComputerName
            if ($instance.IsLocalHost) {
                $targetFile = $object.TargetFile
            } else {
                $targetFile = $object.RemoteTargetFile
            }

            $targetFile = $targetFile.Replace(".xel", "*.xel").Replace(".xem", "*.xem")

            try {
                Write-Message -Level Verbose -Message "Getting $targetFile" -FunctionName Get-DbaXESessionTargetFile -ModuleName "dbatools"
                Get-ChildItem -Path $targetFile -File -Recurse -ErrorAction Stop | Sort-Object LastWriteTime
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $targetFile -FunctionName Get-DbaXESessionTargetFile
            }
        } elseif ($object -is [Microsoft.SqlServer.Management.XEvent.Target]) {
            $computer = [dbainstance]$object.ComputerName
            try {
                if ($computer.IsLocal) {
                    $file = $object.TargetFile
                    Write-Message -Level Verbose -Message "Getting $file" -FunctionName Get-DbaXESessionTargetFile -ModuleName "dbatools"
                    Get-ChildItem "$file*" -File -Recurse -ErrorAction Stop
                } else {
                    $file = $object.RemoteTargetFile
                    Write-Message -Level Verbose -Message "Getting $file" -FunctionName Get-DbaXESessionTargetFile -ModuleName "dbatools"
                    Get-ChildItem "$file*" -File -Recurse -ErrorAction Stop
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Get-DbaXESessionTargetFile
            }
        } else {
            Stop-Function -Message "The Path [$object] has an unsupported type of [$($object.GetType().FullName)]." -FunctionName Get-DbaXESessionTargetFile
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __getDbaXESessionTargetFileProcess = @{ InputObject = $InputObject; Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Session $Target $InputObject $EnableException @__commonParameters 3>&1 2>&1
""";
}
