#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using XeSession = Microsoft.SqlServer.Management.XEvent.Session;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports Extended Events sessions as reusable XML templates for SSMS.
/// </summary>
/// <remarks>
/// The session resolution (Get-DbaXESession), the file-name sanitisation, the SaveSessionToTemplate call,
/// and the Get-ChildItem output all run the original dbatools PowerShell body VERBATIM inside the dbatools
/// module scope rather than being reimplemented in C#, so the engine decides the observable details.
///
/// The begin block runs "Test-ExportDirectory -Path $Path" (creates the export directory, or warns), which
/// can only be evaluated after the module-scope -Path default is applied - the source default
/// "$home\...\XEventTemplates" resolves the $home automatic variable, so it is applied INSIDE the hop when
/// -Path was not bound (W1-087) and the resolved value is carried to the process records via a C# field.
/// Test-ExportDirectory's own Stop-Function arms the interrupt in the WRONG scope (a latent source bug:
/// Stop-Function's Scope-1 write lands in the helper's own frame, destroyed on return), so the begin path
/// NEVER fires the process guard - the warning re-emits and processing proceeds identically, no interrupt
/// carried from begin (the ExportDbaPfDataCollectorSetTemplate precedent documents this quirk).
///
/// The process block's own "if ($Path does not exist) Stop-Function" (no -Continue) DOES arm the
/// function-scope interrupt, and its opening "if (Test-FunctionInterrupt) { return }" short-circuits every
/// LATER record; that interrupt is carried process -> process via a Scope-0 sentinel that the C# OR-
/// accumulates, with ProcessRecord returning early once set (the Get-DbaXESessionTargetFile precedent). The
/// in-hop Test-FunctionInterrupt line is verbatim but inert at record entry (fresh scope; nothing sets the
/// interrupt before it within a record). $InputObject is not carried across records: SqlInstance is not
/// pipeline-bound, so only the InputObject-piped path produces multiple records and each is self-contained.
///
/// The source's "if (-not $PSBoundParameters.FilePath)" tests the ORIGINAL bound value's TRUTHINESS (not
/// mere presence) and re-reads it every $xes iteration - so an explicitly bound "" or $null recomputes, and
/// once $FilePath is reassigned the immutable $PSBoundParameters.FilePath keeps every later session
/// recomputing too. That is carried as the immutable $__boundFilePath = IsTrue(FilePath) flag (Test-Bound
/// never rides the hop; TestBound presence would wrongly retain a bound-empty FilePath). Each exported
/// FileInfo emits before a later session may fail under -EnableException (DEF-001),
/// so the process hop uses InvokeScopedStreaming. Surface pinned by
/// migration/baselines/Export-DbaXESessionTemplate.json.
/// </remarks>
[Cmdlet(VerbsData.Export, "DbaXESessionTemplate")]
public sealed class ExportDbaXESessionTemplateCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Which Extended Events sessions to export by name.</summary>
    [Parameter(Position = 2)]
    public object[]? Session { get; set; }

    /// <summary>The directory where XML template files will be saved.</summary>
    [Parameter(Position = 3)]
    public string? Path { get; set; }

    /// <summary>The complete file path including filename for the exported template.</summary>
    [Parameter(Position = 4)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    /// <summary>Extended Events session objects piped in (e.g. from Get-DbaXESession).</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public XeSession[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the inherited
    // [Parameter] already matches; no override needed.

    // The -Path default is resolved in the begin hop ($home is module-scope), then carried to every record.
    private string? _path;

    // The function-scope interrupt, armed only by the process block's own "$Path does not exist"
    // Stop-Function; carried record to record.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            Path, TestBound("Path"), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaXESessionTemplateBegin"))
            {
                if (sentinel["__exportDbaXESessionTemplateBegin"] is Hashtable state)
                {
                    _path = state["Path"] as string;
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
        if (_interrupted)
        {
            return;
        }

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaXESessionTemplateProcess"))
            {
                if (sentinel["__exportDbaXESessionTemplateProcess"] is Hashtable state)
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
            SqlInstance, SqlCredential, Session, _path, FilePath, InputObject,
            LanguagePrimitives.IsTrue(FilePath), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block "$null = Test-ExportDirectory -Path $Path" VERBATIM, preceded by the module-scope
    // -Path default (applied only when unbound), and returning the resolved $Path via a sentinel. Runs once
    // in BeginProcessing. EnableException is bound so Test-ExportDirectory's Stop-Function inherits it.
    private const string BeginScript = """
param($Path, $__boundPath, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Path, $__boundPath, $EnableException)
    if (-not $__boundPath) { $Path = "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates" }
    $null = Test-ExportDirectory -Path $Path
    @{ __exportDbaXESessionTemplateBegin = @{ Path = $Path } }
} $Path $__boundPath $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM apart from -FunctionName Export-DbaXESessionTemplate on the direct
    // Stop-Function/Write-Message sites, $PSBoundParameters.FilePath -> the carried $__boundFilePath flag,
    // and a trailing sentinel carrying the interrupt. EnableException is bound so Stop-Function's
    // scope-walking default inherits the caller's value.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Session, $Path, $FilePath, $InputObject, $__boundFilePath, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Session, [string]$Path, [string]$FilePath, [Microsoft.SqlServer.Management.XEvent.Session[]]$InputObject, $__boundFilePath, $EnableException)
    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        try {
            $InputObject += Get-DbaXESession -SqlInstance $instance -SqlCredential $SqlCredential -Session $Session -EnableException
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Export-DbaXESessionTemplate
        }
    }

    foreach ($xes in $InputObject) {
        $xesname = Remove-InvalidFileNameChars -Name $xes.Name

        if (-not (Test-Path -Path $Path)) {
            Stop-Function -Message "$Path does not exist." -Target $Path -FunctionName Export-DbaXESessionTemplate
        }

        if (-not $__boundFilePath) {
            $FilePath = Join-DbaPath $Path "$xesname.xml"
        }
        Write-Message -Level Verbose -Message "Wrote $xesname to $FilePath" -FunctionName Export-DbaXESessionTemplate -ModuleName "dbatools"
        [Microsoft.SqlServer.Management.XEvent.XEStore]::SaveSessionToTemplate($xes, $FilePath, $true)
        Get-ChildItem -Path $FilePath
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __exportDbaXESessionTemplateProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value) } }
} $SqlInstance $SqlCredential $Session $Path $FilePath $InputObject $__boundFilePath $EnableException @__commonParameters 3>&1 2>&1
""";
}
