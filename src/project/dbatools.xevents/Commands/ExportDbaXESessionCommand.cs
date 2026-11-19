#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using XeSession = Microsoft.SqlServer.Management.XEvent.Session;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports Extended Events sessions as T-SQL creation scripts (to files, or to the pipeline via -Passthru).
/// </summary>
/// <remarks>
/// The session resolution, the ScriptCreate().GetScript() generation, the prefix/batch-separator assembly,
/// the Get-ExportFilePath resolution, and the Out-File writes all run the original dbatools PowerShell body
/// VERBATIM inside the dbatools module scope rather than being reimplemented in C#, so the engine decides
/// the observable details.
///
/// The script has begin, process, and end blocks and produces ALL of its output from the end block, which
/// walks the $SessionCollection accumulator the process block fills. The port collects each pipeline
/// record's (SqlInstance, InputObject) pair into _batches across ProcessRecord, and then in EndProcessing
/// runs ONE hop that executes the begin body, the process body (dot-sourced, once per collected batch), and
/// the end body in a single scope - so the accumulators ($SessionCollection, $instanceArray) and the
/// function-scope interrupt persist naturally. The process body is only run when a record was actually
/// processed (an empty pipeline runs begin and end but not process, matching the script); it is dot-sourced
/// so its early "return" exits only that batch, like the script's per-record process return.
///
/// Substitutions only: -FunctionName on every direct Stop-Function/Write-Message; the two config-value
/// defaults (Path = Path.DbatoolsExport, BatchSeparator = Formatting.BatchSeparator) are applied inside the
/// hop when the parameter was not bound (a C# initializer cannot reach the module-scope config); the end
/// block's Get-ExportFilePath uses $PSBoundParameters.Path/.FilePath -> the carried immutable bound VALUES;
/// and $MyInvocation.MyCommand.Name -> the literal "Export-DbaXESession" (a hop scriptblock cannot resolve
/// the public command identity). The begin-block Test-ExportDirectory Stop-Function arms its interrupt in
/// the WRONG scope (a latent source bug), so it never short-circuits the process guard - preserved. There
/// is no ShouldProcess. Surface pinned by migration/baselines/Export-DbaXESession.json.
/// </remarks>
[Cmdlet(VerbsData.Export, "DbaXESession")]
public sealed class ExportDbaXESessionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Extended Events session objects piped in (e.g. from Get-DbaXESession).</summary>
    [Parameter(ValueFromPipeline = true, Position = 2)]
    public XeSession[]? InputObject { get; set; }

    /// <summary>Filters the sessions to export by name.</summary>
    [Parameter(Position = 3)]
    public string[]? Session { get; set; }

    /// <summary>The directory where the script files will be saved.</summary>
    [Parameter(Position = 4)]
    public string? Path { get; set; }

    /// <summary>The complete file path including filename for the exported script.</summary>
    [Parameter(Position = 5)]
    [Alias("OutFile", "FileName")]
    public string? FilePath { get; set; }

    /// <summary>The file encoding for the exported script.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>Return the script to the pipeline instead of writing files.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>The batch separator inserted between statements.</summary>
    [Parameter(Position = 7)]
    public string? BatchSeparator { get; set; }

    /// <summary>Omit the header comment prefix from the script.</summary>
    [Parameter]
    public SwitchParameter NoPrefix { get; set; }

    /// <summary>Do not overwrite an existing file.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Append to an existing file instead of overwriting.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // One batch per ProcessRecord: the (SqlInstance, InputObject) pair the process block saw for that record.
    private readonly List<object?[]> _batches = new List<object?[]>();

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        _batches.Add(new object?[] { SqlInstance, InputObject });
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
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            SqlCredential, _batches.ToArray(), Session, Path, FilePath, Encoding, BatchSeparator,
            Passthru.ToBool(), NoPrefix.ToBool(), NoClobber.ToBool(), Append.ToBool(), EnableException.ToBool(),
            TestBound(nameof(Path)), TestBound(nameof(BatchSeparator)),
            BoundValue("Path"), BoundValue("FilePath"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private object? BoundValue(string name)
    {
        return MyInvocation.BoundParameters.TryGetValue(name, out object? value) ? value : null;
    }

    // PS: the begin body, the process body (dot-sourced, run only for collected batches), and the end body
    // VERBATIM. See the class remarks for the (only) substitutions.
    private const string ProcessScript = """
param($SqlCredential, $__batches, $Session, $Path, $FilePath, $Encoding, $BatchSeparator, $Passthru, $NoPrefix, $NoClobber, $Append, $EnableException, $__pathBound, $__batchSepBound, $__boundPathValue, $__boundFilePathValue, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([System.Management.Automation.PSCredential]$SqlCredential, $__batches, [string[]]$Session, [string]$Path, [string]$FilePath, [string]$Encoding, [string]$BatchSeparator, $Passthru, $NoPrefix, $NoClobber, $Append, $EnableException, $__pathBound, $__batchSepBound, $__boundPathValue, $__boundFilePathValue, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $__pathBound) { $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }
    if (-not $__batchSepBound) { $BatchSeparator = Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator' }

    # Named-wrapper shim (mandatory per-row checklist item: grep Get-PSCallStack in every helper the source
    # calls). Get-ExportFilePath derives a FILENAME segment from (Get-PSCallStack)[1].Command - in the
    # function world that frame is Export-DbaXESession, giving "...-xesession.sql". Called directly from the
    # hop scriptblock the frame is "<ScriptBlock>", producing "...-<scriptblock>.sql", which contains
    # characters Windows rejects, so the export throws (the failure the gate found on Export-DbaUser).
    # Routing the call through a wrapper whose NAME is the real command restores the exact function-world
    # segment; the wrapper is local to this hop invocation and shadows nothing beyond it.
    function Export-DbaXESession {
        param($Path, $FilePath, $Type, $ServerName)
        Get-ExportFilePath -Path $Path -FilePath $FilePath -Type $Type -ServerName $ServerName
    }

    $null = Test-ExportDirectory -Path $Path
    $instanceArray = @()
    $SessionCollection = New-Object System.Collections.ArrayList
    if ($IsLinux -or $IsMacOs) {
        $executingUser = $env:USER
    } else {
        $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    $commandName = "Export-DbaXESession"

    foreach ($__batch in $__batches) {
        $SqlInstance = $__batch[0]
        $InputObject = $__batch[1]
        . {
        if (Test-FunctionInterrupt) { return }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a Credential or specify a SqlInstance" -FunctionName Export-DbaXESession
            return
        }

        if ($SqlInstance) {
            $InputObject = Get-DbaXESession -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Session $Session
        }

        foreach ($xe in $InputObject) {
            $server = $xe.Parent
            $serverName = $server.Name.Replace('\', '$')

            $outsql = $xe.ScriptCreate().GetScript()

            $SessionObject = [PSCustomObject]@{
                Name     = $xe.Name
                Instance = $serverName
                Sql      = $outsql[0]
            }
            $SessionCollection.Add($SessionObject) | Out-Null
        }
        }
    }

    $eol = [System.Environment]::NewLine

    foreach ($SessionObject in $SessionCollection) {

        if ($NoPrefix) {
            $prefix = $null
        } else {
            $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $($SessionObject.Instance) at $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
        }

        if ($BatchSeparator) {
            $sql = $SessionObject.SQL -join "$eol$BatchSeparator$eol"
            #add the final GO
            $sql += "$eol$BatchSeparator"
        } else {
            $sql = $SessionObject.SQL
        }

        if ($Passthru) {
            if ($null -ne $prefix) {
                $sql = "$prefix$eol$sql"
            }
            $sql
        } elseif ($Path -Or $FilePath) {
            if ($instanceArray -notcontains $($SessionObject.Instance)) {
                if ($null -ne $prefix) {
                    $sql = "$prefix$eol$sql"
                }
                $scriptPath = Export-DbaXESession -Path $__boundPathValue -FilePath $__boundFilePathValue -Type sql -ServerName $SessionObject.Instance
                if ((Test-Path -Path $scriptPath) -and $NoClobber) {
                    Stop-Function -Message "File already exists. If you want to overwrite it remove the -NoClobber parameter. If you want to append data, please Use -Append parameter." -Target $scriptPath -Continue -FunctionName Export-DbaXESession
                }
                $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append:$Append -NoClobber:$NoClobber
                $instanceArray += $SessionObject.Instance
                Get-ChildItem $scriptPath
            } else {
                $sql | Out-File -Encoding $Encoding -FilePath $scriptPath -Append
            }
        } else {
            $sql
        }
    }
} $SqlCredential $__batches $Session $Path $FilePath $Encoding $BatchSeparator $Passthru $NoPrefix $NoClobber $Append $EnableException $__pathBound $__batchSepBound $__boundPathValue $__boundFilePathValue $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
