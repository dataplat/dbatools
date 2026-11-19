#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Exports table DATA (INSERT statements) as T-SQL. Port of public/Export-DbaDbTableData.ps1; the
/// workflow remains a module-scoped PowerShell compatibility hop.
///
/// A thin wrapper: the source begin block builds one scripting-options object (ScriptSchema off,
/// ScriptData on, IncludeDatabaseContext on) and the process block, per piped table, does
/// `if ($Pscmdlet.ShouldProcess(...)) { Export-DbaScript @PSBoundParameters -ScriptingOptionsObject
/// $ScriptingOptionsObject }`. InputObject is ValueFromPipeline so process fires per record; the
/// options object is built ONCE in begin and carried begin->process by a sentinel Hashtable (_state)
/// - carrying the single instance (rather than rebuilding per record) is faithful in case
/// Export-DbaScript mutates it across records.
///
/// NOVEL MECHANISM - the whole-$PSBoundParameters splat-forward. No prior campaign hop forwards
/// @PSBoundParameters (they only read individual $PSBoundParameters.X). Inside a hop $PSBoundParameters
/// is the INNER scriptblock's own bound set, not the real cmdlet's, so it cannot be used directly.
/// Instead the bound set is RECONSTRUCTED deterministically from explicit boundness flags (C# TestBound
/// per parameter): InputObject is always present (Mandatory, the current record), each data parameter
/// is added ONLY when the user bound it, and bound Verbose/Debug/Confirm ride along, plus bound
/// ErrorAction/WarningAction forwarded as their raw ActionPreference values so -ErrorAction Stop /
/// -WarningAction Stop can halt Export-DbaScript mid-artifact as the source does (WhatIf is moot -
/// the outer ShouldProcess gate blocks the call before the forward). This reproduces the source's
/// $PSBoundParameters exactly for the forward, with no reliance on C# MyInvocation.BoundParameters
/// per-record or common-parameter quirks. Export-DbaScript is already a compiled cmdlet with a superset
/// surface (it adds ScriptingOptionsObject), so the reconstructed splat forwards legally.
///
/// Distinction from Export-DbaDbRole: Path here is FORWARD-ONLY - Export-DbaDbTableData never uses
/// $Path itself, so the config default is deliberately NOT reproduced (forwarding Path when unbound
/// would be wrong; the source does not forward it, and Export-DbaScript supplies its own identical
/// default). The only body edits are $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess and
/// @PSBoundParameters -> the reconstructed @__splat. Surface pinned by
/// migration/baselines/Export-DbaDbTableData.json (implicit positions 0-4, FilePath OutFile/FileName
/// aliases, Encoding ValidateSet).
/// </summary>
[Cmdlet(VerbsData.Export, "DbaDbTableData", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class ExportDbaDbTableDataCommand : DbaBaseCmdlet
{
    /// <summary>The table object(s) whose data to export.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public Microsoft.SqlServer.Management.Smo.Table[] InputObject { get; set; } = null!;

    /// <summary>The output directory; defaults to the DbatoolsExport config path (forward-only).</summary>
    [Parameter(Position = 1)]
    [PsStringCast]
    public string? Path { get; set; }

    /// <summary>The output file path.</summary>
    [Parameter(Position = 2)]
    [Alias("OutFile", "FileName")]
    [PsStringCast]
    public string? FilePath { get; set; }

    /// <summary>The output file encoding.</summary>
    [Parameter(Position = 3)]
    [ValidateSet("ASCII", "BigEndianUnicode", "Byte", "String", "Unicode", "UTF7", "UTF8", "Unknown")]
    [PsStringCast]
    public string Encoding { get; set; } = "UTF8";

    /// <summary>The batch separator; defaults to empty.</summary>
    [Parameter(Position = 4)]
    [PsStringCast]
    public string BatchSeparator { get; set; } = "";

    /// <summary>Omit the prefix header from the generated script.</summary>
    [Parameter]
    public SwitchParameter NoPrefix { get; set; }

    /// <summary>Return the generated script instead of writing it to a file.</summary>
    [Parameter]
    public SwitchParameter Passthru { get; set; }

    /// <summary>Do not overwrite an existing file.</summary>
    [Parameter]
    public SwitchParameter NoClobber { get; set; }

    /// <summary>Append to an existing file.</summary>
    [Parameter]
    public SwitchParameter Append { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The scripting-options object built once in begin, carried begin->process via the sentinel.
    private Hashtable? _state;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__exportDbaDbTableDataBegin"))
            {
                _state = sentinel["__exportDbaDbTableDataBegin"] as Hashtable;
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
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            InputObject, Path, FilePath, Encoding, BatchSeparator,
            NoPrefix.ToBool(), Passthru.ToBool(), NoClobber.ToBool(), Append.ToBool(), EnableException.ToBool(),
            TestBound(nameof(Path)), TestBound(nameof(FilePath)), TestBound(nameof(Encoding)),
            TestBound(nameof(BatchSeparator)), TestBound(nameof(NoPrefix)), TestBound(nameof(Passthru)),
            TestBound(nameof(NoClobber)), TestBound(nameof(Append)), TestBound(nameof(EnableException)),
            _state, this,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            BoundCommonParameterValue("ErrorAction"), BoundCommonParameterValue("WarningAction")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // ErrorAction/WarningAction must forward their raw ActionPreference value (not a bool): a bound
    // -ErrorAction Stop / -WarningAction Stop makes Export-DbaScript halt immediately on the error/
    // warning path, which can change the produced artifact.
    private object? BoundCommonParameterValue(string name)
    {
        if (MyInvocation.BoundParameters.TryGetValue(name, out object? value))
            return value;
        return null;
    }

    // PS: the begin block VERBATIM (builds the one scripting-options object) plus a sentinel that
    // hands the object to the process hop.
    private const string BeginScript = """
param($EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        $ScriptingOptionsObject = New-DbaScriptingOption
        $ScriptingOptionsObject.ScriptSchema = $false
        $ScriptingOptionsObject.ScriptData = $true
        $ScriptingOptionsObject.IncludeDatabaseContext = $true

    @{ __exportDbaDbTableDataBegin = @{ ScriptingOptionsObject = $ScriptingOptionsObject } }
} $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block. Edits: $Pscmdlet.ShouldProcess -> $__realCmdlet.ShouldProcess, and
    // @PSBoundParameters -> the reconstructed @__splat (bound-only, built from the carried boundness
    // flags). The scripting-options object is restored from the carried sentinel state.
    private const string ProcessScript = """
param($InputObject, $Path, $FilePath, $Encoding, $BatchSeparator, $NoPrefix, $Passthru, $NoClobber, $Append, $EnableException, $__boundPath, $__boundFilePath, $__boundEncoding, $__boundBatchSeparator, $__boundNoPrefix, $__boundPassthru, $__boundNoClobber, $__boundAppend, $__boundEnableException, $__state, $__realCmdlet, $__boundVerbose, $__boundDebug, $__boundConfirm, $__boundErrorAction, $__boundWarningAction)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Microsoft.SqlServer.Management.Smo.Table[]]$InputObject, [string]$Path, [string]$FilePath, [string]$Encoding, [string]$BatchSeparator, $NoPrefix, $Passthru, $NoClobber, $Append, $EnableException, $__boundPath, $__boundFilePath, $__boundEncoding, $__boundBatchSeparator, $__boundNoPrefix, $__boundPassthru, $__boundNoClobber, $__boundAppend, $__boundEnableException, $__state, $__realCmdlet, $__boundVerbose, $__boundDebug, $__boundConfirm, $__boundErrorAction, $__boundWarningAction)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    $ScriptingOptionsObject = $__state.ScriptingOptionsObject

    # Reconstruct the source's $PSBoundParameters (bound-only) for the @PSBoundParameters splat-forward.
    $__splat = @{ InputObject = $InputObject }
    if ($__boundPath) { $__splat.Path = $Path }
    if ($__boundFilePath) { $__splat.FilePath = $FilePath }
    if ($__boundEncoding) { $__splat.Encoding = $Encoding }
    if ($__boundBatchSeparator) { $__splat.BatchSeparator = $BatchSeparator }
    if ($__boundNoPrefix) { $__splat.NoPrefix = [bool]$NoPrefix }
    if ($__boundPassthru) { $__splat.Passthru = [bool]$Passthru }
    if ($__boundNoClobber) { $__splat.NoClobber = [bool]$NoClobber }
    if ($__boundAppend) { $__splat.Append = [bool]$Append }
    if ($__boundEnableException) { $__splat.EnableException = [bool]$EnableException }
    if ($null -ne $__boundVerbose) { $__splat.Verbose = [bool]$__boundVerbose }
    if ($null -ne $__boundDebug) { $__splat.Debug = [bool]$__boundDebug }
    if ($null -ne $__boundConfirm) { $__splat.Confirm = [bool]$__boundConfirm }
    if ($null -ne $__boundErrorAction) { $__splat.ErrorAction = $__boundErrorAction }
    if ($null -ne $__boundWarningAction) { $__splat.WarningAction = $__boundWarningAction }

    if ($__realCmdlet.ShouldProcess($env:computername, "Exporting $InputObject")) {
        Export-DbaScript @__splat -ScriptingOptionsObject $ScriptingOptionsObject
    }
} $InputObject $Path $FilePath $Encoding $BatchSeparator $NoPrefix $Passthru $NoClobber $Append $EnableException $__boundPath $__boundFilePath $__boundEncoding $__boundBatchSeparator $__boundNoPrefix $__boundPassthru $__boundNoClobber $__boundAppend $__boundEnableException $__state $__realCmdlet $__boundVerbose $__boundDebug $__boundConfirm $__boundErrorAction $__boundWarningAction @__commonParameters 3>&1 2>&1
""";
}
