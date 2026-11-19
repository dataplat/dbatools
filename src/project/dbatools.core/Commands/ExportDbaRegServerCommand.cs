#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports registered servers and server groups to XML. Port of public/Export-DbaRegServer.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop.
///
/// BEGIN+PROCESS lifecycle-split. $InputObject is ValueFromPipeline, so process fires per piped
/// object. No SupportsShouldProcess (plain CmdletBinding), so no gate and no $__realCmdlet.
///
/// THE BEGIN BLOCK HAS A ONE-TIME SIDE EFFECT that must run exactly once, which is why this is a
/// lifecycle-split rather than a per-record hop: begin :132 does "" | Set-Content -Path $FilePath,
/// creating-or-truncating the export file. Running that per record would re-truncate the file on
/// every piped object. It stays in the BeginProcessing hop.
///
/// $timeNow BEGIN -> PROCESS CARRY. begin :120 computes $timeNow once (Get-Date with the configured
/// uformat) and process reads it at :181/:183 to name each export file. Begin's scope dies before
/// process runs, so it rides the begin sentinel; recomputing per record would stamp files from one
/// pipeline with different timestamps.
///
/// $Path BIND-TIME DEFAULT. The source default "(Get-DbatoolsConfigValue -FullName
/// 'Path.DbatoolsExport')" cannot be expressed by a C# initializer. It is resolved ONCE in the begin
/// hop when the caller omitted -Path (begin uses it at :119 for Test-ExportDirectory) and the
/// resolved value carries to process (used at Join-DbaPath). Bind-once, matching the source.
///
/// INTERRUPT CARRIES ON BOTH AXES.
///   begin -> process: the FilePath-extension guard (:126) and the no-Overwrite guard (:134) are
///     Stop-Function WITHOUT -Continue, so they set the module latch, and process opens with
///     "if (Test-FunctionInterrupt) { return }" at :140 - a bad begin silences every record.
///   process -> process: the catch at :202 is Stop-Function WITHOUT -Continue and WITHOUT a
///     following return, so a Failure sets the latch mid-record; the CURRENT record's object loop
///     runs on (the source's own behaviour), but the NEXT record's :140 Test-FunctionInterrupt must
///     then return. The hop scope dies per record, so the process hop reads the latch at
///     Get-Variable -Scope 0 after its body and carries it; the C# _interrupted field persists it
///     across ProcessRecord calls. Mechanism measured in a dedicated probe run.
///
/// $Overwrite CROSSES AS A SwitchParameter OBJECT received untyped. begin :133 reads
/// "$Overwrite.IsPresent"; marshaling as .ToBool() would make .IsPresent falsy and silently disable
/// the overwrite guard (B's combined rule). -EnableException crosses the same way.
///
/// $PSBoundParameters.ContainsKey() PROJECTION. The body tests caller-boundness eight times across
/// three parameters - FilePath (:124), Group (:143/:160), ExcludeGroup (:144/:149/:162/:164) - via
/// $PSBoundParameters.ContainsKey. Inside a hop $PSBoundParameters is the hop scriptblock's own
/// bindings, so each becomes a carried boundness flag ($__boundFilePath / $__boundGroup /
/// $__boundExcludeGroup) sourced from MyInvocation.BoundParameters.ContainsKey - the source tests
/// BOUNDNESS, so ContainsKey is the faithful carrier (the amended carrier rule), never a value test.
///
/// NO CROSS-RECORD STATE CARRY beyond the interrupt. Source :168's "$InputObject += ..." accumulates
/// into the pipeline-bound parameter, which the binder rewrites per record; every process local
/// ($instance, $object, $regname, $OutputFilePath, $ExportFileName, $serverName, $extension) is
/// assigned before use within its own object iteration.
///
/// FilePath carries Alias("FileName"/"OutFile"). In-hop Stop-Function/Write-Message calls carry
/// -FunctionName. The :199 "not a registered server" Stop-Function keeps -Continue. Implicit
/// positions 0-7 are made explicit and confirmed against the exported baseline;
/// InputObject is position 2 and ValueFromPipeline. Streaming: the command writes an XML
/// file and emits Get-ChildItem per object, so a buffered hop would discard the record of files
/// already written when a later object's failure terminated the hop under -EnableException. Surface
/// pinned by the captured surface baseline.
/// </summary>
[Cmdlet(VerbsData.Export, "DbaRegServer")]
public sealed class ExportDbaRegServerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Registered servers or groups piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public object[]? InputObject { get; set; }

    /// <summary>Directory the export files are written to; defaults to the configured export path.</summary>
    [Parameter(Position = 3)]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>A specific output file path (.xml or .regsrvr).</summary>
    [Parameter(Position = 4)]
    [Alias("FileName", "OutFile")]
    public System.IO.FileInfo? FilePath { get; set; }

    /// <summary>How credentials are persisted in the export.</summary>
    [Parameter(Position = 5)]
    [ValidateSet("None", "PersistLoginName", "PersistLoginNameAndPassword")]
    [PsStringCast]
    public string CredentialPersistenceType { get; set; } = "None";

    /// <summary>Limit the export to these groups.</summary>
    [Parameter(Position = 6)]
    public object[]? Group { get; set; }

    /// <summary>Exclude these groups from the export.</summary>
    [Parameter(Position = 7)]
    public object[]? ExcludeGroup { get; set; }

    /// <summary>Overwrite an existing -FilePath.</summary>
    [Parameter]
    public SwitchParameter Overwrite { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin's $timeNow and resolved $Path; opaque to C#.
    private Hashtable? _beginState;
    // a failed begin guard, or a process Failure on an earlier record, silences later records.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Path, FilePath, Overwrite, EnableException,
            MyInvocation.BoundParameters.ContainsKey("FilePath"),
            MyInvocation.BoundParameters.ContainsKey("Path"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaRegServerBegin"))
            {
                if (sentinel["__exportDbaRegServerBegin"] is Hashtable state)
                {
                    _beginState = state;
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
        if (Interrupted || _interrupted)
            return;

        // Streaming, not buffered: an XML file is written and emitted per object, so a
        // buffered hop would discard the record of files already written.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaRegServerProcess"))
            {
                if (sentinel["__exportDbaRegServerProcess"] is Hashtable state)
                    _interrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
            SqlInstance, SqlCredential, InputObject, FilePath, CredentialPersistenceType,
            Group, ExcludeGroup, EnableException, _beginState,
            MyInvocation.BoundParameters.ContainsKey("FilePath"),
            MyInvocation.BoundParameters.ContainsKey("Group"),
            MyInvocation.BoundParameters.ContainsKey("ExcludeGroup"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM, dot-sourced. Edits: the FilePath boundness probe becomes
    // $__boundFilePath, plus -FunctionName stamps. The $Path default is resolved first when
    // omitted; the sentinel carries $timeNow, the resolved $Path, and the interrupt latch. The
    // one-time Set-Content side-effect runs here, once.
    private const string BeginScript = """
param($Path, $FilePath, $Overwrite, $EnableException, $__boundFilePath, $__boundPath, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, [System.IO.FileInfo]$FilePath, $Overwrite, $EnableException, $__boundFilePath, $__boundPath, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # The source's "[string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport')"
    if (-not $__boundPath) { $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }

    . {
        $null = Test-ExportDirectory -Path $Path
        $timeNow = Get-Date -UFormat (Get-DbatoolsConfigValue -FullName formatting.uformat)

        # ValidateScript in the above param block relies on the order of the params specified by the user,
        # so the creation of the file path and $Overwrite are evaluated here
        if ($__boundFilePath) {
            if ($FilePath.FullName -notmatch "\.xml$|\.regsrvr$") {
                Stop-Function -Message "The FilePath specified must end with either .xml or .regsrvr" -FunctionName Export-DbaRegServer
                return
            }

            if (-not (Test-Path $FilePath) ) {
                $null = Test-ExportDirectory -Path (Split-Path -Path $FilePath)
                "" | Set-Content -Path $FilePath
            } elseif (-not $Overwrite.IsPresent) {
                Stop-Function -Message "Use the -Overwrite parameter if the file $FilePath should be overwritten." -FunctionName Export-DbaRegServer
                return
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    $__tn = Get-Variable -Name timeNow -Scope 0 -ErrorAction Ignore
    $__tnv = $null; if ($__tn) { $__tnv = $__tn.Value }
    @{ __exportDbaRegServerBegin = @{ Interrupted = [bool]($__iv -and $__iv.Value); TimeNow = $__tnv; ResolvedPath = $Path } }
} $Path $FilePath $Overwrite $EnableException $__boundFilePath $__boundPath $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced so the :140 early return exits only the body.
    // Edits: the Group/ExcludeGroup/FilePath boundness probes become carried flags, plus
    // -FunctionName stamps. $timeNow and $Path restore from the begin sentinel before the body; the
    // latch is read at Scope 0 after it so a Failure on this record silences later records.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $InputObject, $FilePath, $CredentialPersistenceType, $Group, $ExcludeGroup, $EnableException, $__beginState, $__boundFilePath, $__boundGroup, $__boundExcludeGroup, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [object[]]$InputObject, [System.IO.FileInfo]$FilePath, [string]$CredentialPersistenceType, [object[]]$Group, [object[]]$ExcludeGroup, $EnableException, $__beginState, $__boundFilePath, $__boundGroup, $__boundExcludeGroup, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin's once-computed values
    $timeNow = $__beginState.TimeNow
    $Path = $__beginState.ResolvedPath

    . {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if ($__boundGroup) {
                if ($__boundExcludeGroup) {
                    $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group -ExcludeGroup $ExcludeGroup
                } else {
                    $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                }
            } elseif ($__boundExcludeGroup) {
                $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -ExcludeGroup $ExcludeGroup
            } else {
                $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1 # legacy behavior to return -Id 1 which means return everything
            }
        }

        foreach ($object in $InputObject) {
            try {
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]) {
                    if ($__boundGroup) {
                        if ($__boundExcludeGroup) {
                            $object = Get-DbaRegServerGroup -SqlInstance $object.ParentServer -Group $Group -ExcludeGroup $ExcludeGroup
                        } else {
                            $object = Get-DbaRegServerGroup -SqlInstance $object.ParentServer -Group $Group
                        }
                    } elseif ($__boundExcludeGroup) {
                        $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -ExcludeGroup $ExcludeGroup
                    } else {
                        $object = Get-DbaRegServerGroup -SqlInstance $object.ParentServer -Id 1 # legacy behavior to return -Id 1 which means return everything
                    }
                }

                if (($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) -or ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup])) {
                    $regname = $object.Name.Replace('\', '$')
                    $OutputFilePath = $null

                    if (-not $__boundFilePath) {
                        $ExportFileName = $null
                        $serverName = $object.SqlInstance.Replace('\', '$')

                        if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                            $ExportFileName = "$serverName-regserver-$regname-$timeNow.xml"
                        } elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                            $ExportFileName = "$serverName-reggroup-$regname-$timeNow.xml"
                        }

                        $OutputFilePath = Join-DbaPath -Path $Path -Child $ExportFileName
                    } elseif ($InputObject.length -gt 1) {
                        # more than one group was passed in, so we need to add the group name to the FilePath because there will be multiple files generated.
                        $extension = [IO.Path]::GetExtension($FilePath.FullName)
                        $OutputFilePath = $FilePath.FullName.Replace($extension, "-" + $regname + $extension)
                    } else {
                        $OutputFilePath = $FilePath.FullName
                    }

                    $object.Export($OutputFilePath, $CredentialPersistenceType)

                    Get-ChildItem $OutputFilePath -ErrorAction Stop
                } else {
                    Stop-Function -Message "InputObject is not a registered server or server group" -Continue -FunctionName Export-DbaRegServer
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -FunctionName Export-DbaRegServer
            }
        }
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __exportDbaRegServerProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $InputObject $FilePath $CredentialPersistenceType $Group $ExcludeGroup $EnableException $__beginState $__boundFilePath $__boundGroup $__boundExcludeGroup $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}