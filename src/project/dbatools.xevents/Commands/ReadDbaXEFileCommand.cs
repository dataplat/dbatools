#nullable enable

using System;
using System.Collections;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Parses Extended Events trace files (.xel/.xem) into structured PowerShell objects for analysis.
/// </summary>
/// <remarks>
/// The per-object type dispatch, the target-file glob expansion, the running-session skip, the
/// Read-XEvent parsing, the column/action projection, and the per-event object shaping all run the
/// original dbatools PowerShell body VERBATIM inside the dbatools module scope rather than being
/// reimplemented in C#, so the engine decides the observable details.
///
/// Process-only, non-mutating (no ShouldProcess). INTERRUPT is carried process -> process (cross-record):
/// the source's process block opens with "if (Test-FunctionInterrupt) { return }", and the object loop's
/// no-Continue Stop-Function (unsupported path type) sets the function-scope interrupt without returning,
/// so in the source that interrupt persists and short-circuits every LATER record. A per-record hop scope
/// cannot hold it, so each record reads the interrupt variable at the end and emits it in a sentinel; the
/// C# OR-accumulates _interrupted and ProcessRecord returns early once it is set (reproducing the source's
/// entry return). The in-hop "if (Test-FunctionInterrupt) { return }" line is kept verbatim but is inert at
/// record entry (a fresh hop scope; the interrupt cannot already be set within one record before that
/// line). Under -EnableException the no-Continue Stop-Function throws terminating instead (framework
/// re-throws) and the sentinel is not reached, which matches the source terminating the pipeline. The
/// -Continue Stop-Functions never set the interrupt.
///
/// $Path is value-from-pipeline and only READ per record, so there is no data carry (only the interrupt).
/// Each parsed event, and the -Raw Read-XEvent output, emit before a later file in the same record may
/// fail under -EnableException, so the process hop uses InvokeScopedStreaming to avoid losing events that
/// were already produced (DEF-001). Surface pinned by migration/baselines/Read-DbaXEFile.json.
/// </remarks>
[Cmdlet(VerbsCommunications.Read, "DbaXEFile")]
public sealed class ReadDbaXEFileCommand : DbaBaseCmdlet
{
    /// <summary>The Extended Events file path (.xel or .xem), file objects, or XEvent session objects to read from.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [Alias("FullName")]
    public object[] Path { get; set; } = null!;

    /// <summary>Returns the native XEvent objects instead of structured PowerShell objects.</summary>
    [Parameter]
    public SwitchParameter Raw { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the inherited
    // [Parameter] already matches; no override needed.

    // The function-scope interrupt, set by the object loop's no-Continue Stop-Function and read by the
    // process block's entry "if (Test-FunctionInterrupt) { return }"; carried record to record.
    private bool _interrupted;

    protected override void ProcessRecord()
    {
        if (_interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__readDbaXEFileProcess"))
            {
                if (sentinel["__readDbaXEFileProcess"] is Hashtable state)
                {
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
            Path, Raw.ToBool(), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from -FunctionName Read-DbaXEFile on the Stop-Function/Write-Message
    // sites, plus a trailing sentinel carrying the interrupt. No dot-source wrap: the entry
    // Test-FunctionInterrupt return is inert (fresh scope), and the no-Continue Stop-Function does not return,
    // so the sentinel is always reached (except under -EnableException, where the throw terminates anyway).
    private const string ProcessScript = """
param($Path, $Raw, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([object[]]$Path, $Raw, $EnableException)
    if (Test-FunctionInterrupt) { return }
    foreach ($pathObject in $Path) {
        # in order to ensure CSV gets all fields, all columns will be
        # collected and output in the first (all all subsequent) object
        $columns = @("name", "timestamp")

        if ($pathObject -is [System.String]) {
            $files = $pathObject
        } elseif ($pathObject -is [System.IO.FileInfo]) {
            $files = $pathObject.FullName
        } elseif ($pathObject -is [Microsoft.SqlServer.Management.XEvent.Session]) {
            if ($pathObject.TargetFile.Length -eq 0) {
                Stop-Function -Message "The session [$pathObject] does not have an associated Target File." -Continue -FunctionName Read-DbaXEFile
            }

            $instance = [DbaInstance]$pathObject.ComputerName
            if ($instance.IsLocalHost) {
                $targetFile = $pathObject.TargetFile
            } else {
                $targetFile = $pathObject.RemoteTargetFile
            }

            $targetFile = $targetFile.Replace('.xel', '*.xel').Replace('.xem', '*.xem')
            $files = Get-ChildItem -Path $targetFile | Sort-Object LastWriteTime
            if ($pathObject.Status -eq 'Running') {
                $files = $files | Select-Object -SkipLast 1
            }
            Write-Message -Level Verbose -Message "Received $($files.Count) files based on [$targetFile]" -FunctionName Read-DbaXEFile -ModuleName "dbatools"
        } else {
            Stop-Function -Message "The Path [$pathObject] has an unsupported file type of [$($pathObject.GetType().FullName)]." -FunctionName Read-DbaXEFile
        }

        foreach ($file in $files) {
            if (-not (Test-Path -Path $file)) {
                Stop-Function -Message "$file cannot be accessed from $($env:COMPUTERNAME)." -Continue -FunctionName Read-DbaXEFile
            }

            if ($Raw) {
                try {
                    Read-XEvent -FileName $file
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue -FunctionName Read-DbaXEFile
                }
            } else {
                try {
                    $enum = Read-XEvent -FileName $file
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue -FunctionName Read-DbaXEFile
                }
                $newcolumns = ($enum.Fields.Name | Select-Object -Unique)

                $actions = ($enum.Actions.Name | Select-Object -Unique)
                foreach ($action in $actions) {
                    $newcolumns += ($action -Split '\.')[-1]
                }

                $newcolumns = $newcolumns | Sort-Object
                $columns = ($columns += $newcolumns) | Select-Object -Unique

                # Make it selectable, otherwise it's a weird enumeration
                foreach ($event in $enum) {
                    $hash = [ordered]@{ }

                    foreach ($column in $columns) {
                        $null = $hash.Add($column, $event.$column)
                    }

                    foreach ($key in $event.Actions.Keys) {
                        $hash[($key -Split '\.')[-1]] = $event.Actions[$key]
                    }

                    foreach ($key in $event.Fields.Keys) {
                        $hash[$key] = $event.Fields[$key]
                    }

                    [PSCustomObject]$hash
                }
            }
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __readDbaXEFileProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $Path $Raw $EnableException @__commonParameters 3>&1 2>&1
""";
}
