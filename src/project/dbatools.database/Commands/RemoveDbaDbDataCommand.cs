#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Truncates all data in one or more databases, scripting out and recreating the foreign keys and
/// views that block truncation. Port of public/Remove-DbaDbData.ps1 (W2-158); the workflow remains a
/// module-scoped PowerShell compatibility hop.
///
/// THIS COMMAND DESTROYS DATA, and that fact drives the whole design of this port. It carries the
/// DEF-011 interrupt latch in BOTH halves, per the 2026-07-18 20:25 standing order ("every NEW port
/// with a hop Test-FunctionInterrupt + hard Stop-Function + VFP carries E's latch pattern"). This row
/// meets all three conditions: Test-FunctionInterrupt opens the process block, three Stop-Function
/// calls are hard (no -Continue), and -InputObject is ValueFromPipeline.
///
/// THE BEGIN HALF. The source's begin block is a single line -
/// `$null = Test-ExportDirectory -Path $Path` - and that helper can Stop-Function when the export
/// directory is unusable. That is why the process block opens with
/// `if (Test-FunctionInterrupt) { return }`. begin and process are separate scoped invocations in a
/// hop, so an uncarried begin interrupt would be LOST; the begin hop therefore reports
/// Test-FunctionInterrupt through its sentinel into _beginInterrupted, and ProcessRecord refuses to
/// run when it is set.
///
/// MEASURED CORRECTION, and it matters because this text is safety-critical: this comment first said
/// that a port without this carry "destroys data the source refuses to touch when -Path is bad". THE
/// SOURCE DOES NOT REFUSE. Probed with -Path pointing at a file (the input that actually makes
/// Test-ExportDirectory call Stop-Function), the legacy function truncated exactly as the port did -
/// before=3 after=0 with one warning in BOTH worlds.
///
/// The reason given for that was wrong, and the correct one is narrower. Stop-Function does NOT set
/// the interrupt variable only under -EnableException: its non-EnableException, non-Continue branch
/// sets the same variable at -Scope 1 and then returns. What makes the BEGIN half's guard unreachable
/// is where that scope points - the stop is raised inside Test-ExportDirectory, so -Scope 1 writes
/// into Test-ExportDirectory's caller frame, which is the helper's, not this command's, and the
/// command's own Test-FunctionInterrupt never sees it. The distinction matters because the wrong
/// reason implied the PROCESS half was unreachable too, and it is not: the direct Stop-Function calls
/// in the process body carry no -Continue, so each one does set this command's own interrupt flag.
///
/// The process half is therefore MEASURED, not merely constructed. Piping a non-database first and a
/// real database second stops on record 1 and the source refuses record 2; a port whose latch did not
/// carry would truncate it. Live A/B on both editions: 1 warning and the second database keeping all
/// its rows on BOTH sides, against a two-good-record control on the same trace that truncates both.
///
/// THE PROCESS HALF is the ordinary cross-record latch: an in-hop Stop-Function cannot set
/// DbaBaseCmdlet.Interrupted (private setter), so without a carry each record would start fresh and
/// keep truncating after a stop the source treated as fatal. The process hop reports its own
/// Test-FunctionInterrupt into _interruptLatched. Both fields plus the base flag are read by one
/// guard, mirroring AddDbaServerRoleMemberCommand (dbatools.security), the pattern's canonical
/// carrier:
///     if (_beginInterrupted || _interruptLatched || Interrupted) return;
///
/// Everything else is a plain process-only hop. THREE hard `return`s (the interrupt guard, the
/// no-input guard, and the switch's default arm) all reproduce as scriptblock returns, so NO
/// continue-guard wrapper is involved - there is no `continue` anywhere in this body. ZERO Test-Bound
/// calls: the no-input guard tests parameter VALUES.
///
/// $input SHADOWING is left verbatim, as on W2-164: `foreach ($input in $InputObject)` rebinds
/// PowerShell's automatic $input, and the foreach binds the name locally in both worlds.
///
/// -SqlInstance is declared `[DbaInstance[]]` in the source, which is the dbatools TYPE ACCELERATOR
/// for Dataplat.Dbatools.Parameter.DbaInstanceParameter - the same lesson W2-164 taught when the
/// compiler rejected the accelerator name. The baseline pins the resolved type and the C# declares it;
/// the body's type switch dispatches on that full name and still matches values bound through the
/// accelerator.
///
/// -Path defaults to `Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'`. The source evaluates
/// that default ONCE, at parameter binding, before begin. So the port resolves it ONCE in the begin
/// hop - and only when the parameter was not BOUND, since an explicitly bound $null or '' is the
/// caller's own value that the source keeps - then carries the resolved value on the begin sentinel
/// for every process record to reuse. Review caught the first version resolving it independently in
/// begin AND again per record, which on a command that truncates tables could validate one directory
/// and write to another. It is also never inlined at build time; a literal would freeze one machine's
/// export path into the assembly.
///
/// PRESERVED SOURCE BEHAVIOUR worth flagging for review, none of it tidied:
///   * the catch around truncation runs the _Create.Sql recovery script and does NOT rethrow, so a
///     failed truncation leaves the objects restored and execution continues;
///   * the recovery Invoke-DbaQuery in that catch is itself unguarded - if it throws, the error
///     escapes;
///   * `$objects` is tested for truthiness to decide whether drop/create scripts run, so a database
///     with no foreign keys or views truncates without scripting anything;
///   * the cleanup Remove-Item failure only warns.
///
/// Surface pinned by migration/baselines/Remove-DbaDbData.json
/// (sourceSha256 7e8f3c73c89168ae49ddd6c41a248088cf95ba09ce5dcbe6593a54ce4ede0dbf): supportsShouldProcess
/// true, confirmImpact High, no named parameter sets, outputType empty.
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaDbData", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaDbDataCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Server or database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public object[]? InputObject { get; set; }

    /// <summary>Directory for the scripted drop/create files. Defaults to the Path.DbatoolsExport
    /// config value, resolved at run time inside the hop rather than baked in at build time.</summary>
    [Parameter(Position = 5)]
    public string? Path { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // DEF-011 latch, both halves. _beginInterrupted carries a stop raised by the begin block's
    // Test-ExportDirectory; _interruptLatched carries a stop raised while handling an earlier record.
    // Without them a hop forgets the stop and keeps truncating - see the class remarks.
    private bool _beginInterrupted;

    // The -Path default, resolved ONCE in the begin hop exactly as the source's parameter default is
    // evaluated once at binding. Every process record reuses this, so begin validates and the
    // truncation writes to the SAME directory.
    private object? _resolvedPath;
    private bool _interruptLatched;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(item.Properties["__removeDbaDbDataBeginComplete"]?.Value))
            {
                _beginInterrupted = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
                _resolvedPath = item.Properties["ResolvedPath"]?.Value;
                return;
            }
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, BeginScript,
            Path, TestBound(nameof(Path)), EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        // The whole point of the latch: a stop raised in begin, or while handling an earlier record,
        // must prevent this record from truncating anything.
        if (_beginInterrupted || _interruptLatched || Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item is not null && LanguagePrimitives.IsTrue(item.Properties["__removeDbaDbDataProcessComplete"]?.Value))
            {
                _interruptLatched = LanguagePrimitives.IsTrue(item.Properties["Interrupted"]?.Value);
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, InputObject, _resolvedPath,
            EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block verbatim. The -Path default is resolved HERE, by calling the config system,
    // when the caller supplied none. Edit: the trailing completion sentinel, which reports whether
    // Test-ExportDirectory stopped the command so ProcessRecord can refuse to truncate.
    private const string BeginScript = """
param($Path, $__boundPath, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([string]$Path, $__boundPath, $EnableException, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    try {
        # The source evaluates the -Path default ONCE, at parameter binding, before begin runs. It is
        # resolved here and ONLY when the caller did not BIND the parameter: an explicitly bound $null
        # or '' is the caller's own value and the source keeps it, so testing the VALUE rather than the
        # bound flag would substitute a default the source never substitutes.
        if (-not $__boundPath) {
            $Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport')
        }

        $null = Test-ExportDirectory -Path $Path
    } finally {
        # Hop mechanism, not source: report the RESOLVED path, plus whether Test-ExportDirectory
        # stopped the command so the process hop can honour the source's begin-wide stop instead of
        # truncating anyway. Emitted from FINALLY so both survive a throw or return. Carrying the
        # resolved path is what keeps begin's validation and the truncation's writes on the SAME
        # directory - re-deriving it per record could validate one and write to another.
        [pscustomobject]@{ __removeDbaDbDataBeginComplete = $true; Interrupted = [bool](Test-FunctionInterrupt); ResolvedPath = $Path }
    }
} $Path $__boundPath $EnableException $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block verbatim. Edits: $Pscmdlet -> $__realCmdlet, -FunctionName
    // Remove-DbaDbData on the direct Stop-Function and Write-Message sites, and the trailing
    // completion sentinel carrying the interrupt latch. $Path arrives ALREADY RESOLVED from the begin
    // hop and is deliberately not re-derived here.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $InputObject, $Path, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [object[]]$InputObject, [string]$Path, $EnableException, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # NO -Path resolution here, deliberately: $Path arrives already resolved from the begin hop, so
    # every record writes to the exact directory begin validated. Re-resolving per record would let
    # begin check one path and the truncation write to another.

    # try/finally is HOP MECHANISM, not source. The body below has FOUR hard returns, three of them
    # immediately after a Stop-Function - which are exactly the paths that set the interrupt. A
    # sentinel emitted at the end of the body would be SKIPPED on precisely those returns, so the
    # latch would fail to carry on the only paths that need it and the next record would truncate.
    try {
    if (Test-FunctionInterrupt) { return }

    if (-not $InputObject -and -not $SqlInstance) {
        Stop-Function -Message "You must pipe in a database or a server, or specify a SqlInstance" -FunctionName Remove-DbaDbData
        return
    }

    if ($SqlInstance) {
        $InputObject = $SqlInstance
    }

    foreach ($input in $InputObject) {
        $inputType = $input.GetType().FullName
        switch ($inputType) {
            'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Remove-DbaDbData -ModuleName "dbatools"
                $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem
            }
            'Microsoft.SqlServer.Management.Smo.Server' {
                Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Remove-DbaDbData -ModuleName "dbatools"
                $dbDatabases = Get-DbaDatabase -SqlInstance $input -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase -ExcludeSystem
            }
            'Microsoft.SqlServer.Management.Smo.Database' {
                Write-Message -Level Verbose -Message "Processing Database through InputObject" -FunctionName Remove-DbaDbData -ModuleName "dbatools"
                $dbDatabases = $input | Where-Object { -not $_.IsSystemObject }
            }
            default {
                Stop-Function -Message "InputObject is not a server or database." -FunctionName Remove-DbaDbData
                return
            }
        }

        foreach ($db in $dbDatabases) {
            if ($__realCmdlet.ShouldProcess($db.Name, "Removing all data on $($db.Parent.Name)")) {
                $server = $db.Parent
                Write-Message -Level Verbose -Message "Truncating tables in $db on instance $server" -FunctionName Remove-DbaDbData -ModuleName "dbatools"
                try {

                    # Collect up the objects we need to drop and recreate
                    $objects = @()
                    $objects += Get-DbaDbForeignKey -SqlInstance $server -Database $db.Name
                    $objects += Get-DbaDbView -SqlInstance $server -Database $db.Name -ExcludeSystemView

                    # Script out the create statements for objects
                    $createOptions = New-DbaScriptingOption
                    $createOptions.Permissions = $true
                    $createOptions.ScriptBatchTerminator = $true
                    $createOptions.AnsiFile = $true
                    $null = $objects | Export-DbaScript -FilePath "$Path\$($db.Name)_Create.Sql" -ScriptingOptionsObject $createOptions

                    # Script out the drop statements for objects
                    $dropOptions = New-DbaScriptingOption
                    $dropOptions.ScriptDrops = $true
                    $null = $objects | Export-DbaScript -FilePath "$Path\$($db.Name)_Drop.Sql" -ScriptingOptionsObject $dropOptions
                } catch {
                    Stop-Function -Message "Issue scripting out the drop\create scripts for objects in $db on instance $server" -ErrorRecord $_ -FunctionName Remove-DbaDbData
                    return
                }

                try {
                    if ($objects) {
                        Invoke-DbaQuery -SqlInstance $server -Database $db.Name -File "$Path\$($db.Name)_Drop.Sql"
                    }

                    $db.Tables | ForEach-Object { $_.TruncateData() }

                    if ($objects) {
                        Invoke-DbaQuery -SqlInstance $server -Database $db.Name -File "$Path\$($db.Name)_Create.Sql"
                    }
                } catch {
                    Write-Message -Level warning -Message "Issue truncating tables in $db on instance $server" -FunctionName Remove-DbaDbData -ModuleName "dbatools"
                    Invoke-DbaQuery -SqlInstance $server -Database $db.Name -File "$Path\$($db.Name)_Create.Sql"
                }
                if ($objects) {
                    try {
                        Remove-Item "$Path\$($db.Name)_Drop.Sql", "$Path\$($db.Name)_Create.Sql" -ErrorAction Stop
                    } catch {
                        Write-Message -Level warning -Message "Unable to clear up output files for $db on $server" -FunctionName Remove-DbaDbData -ModuleName "dbatools"
                    }
                }
            }
        }
    }

    } finally {
        # Carry the interrupt latch to the next record, so a hard stop here prevents later records
        # from truncating - what the function's shared scope did for free.
        [pscustomobject]@{ __removeDbaDbDataProcessComplete = $true; Interrupted = [bool](Test-FunctionInterrupt) }
    }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $InputObject $Path $EnableException $__realCmdlet $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}






