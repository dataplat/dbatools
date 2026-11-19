#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates a data-masking configuration file describing the columns to mask. Port of
/// public/New-DbaDbMaskingConfig.ps1 (667 lines); the workflow remains a module-scoped PowerShell
/// compatibility hop.
///
/// BEGIN+PROCESS, two hops. $InputObject is ValueFromPipeline, so process fires per record.
///
/// INTERRUPT CARRY IS LIVE. Begin's eight Stop-Function calls (:175,:186,:197,:201,:210,:214,:223,
/// :227) all lack -Continue, so they set the module interrupt latch, and process opens with
/// "if (Test-FunctionInterrupt) { return }" at :249 - a begin failure must silence EVERY record. The
/// latch does not survive between hop invocations, so the begin hop reads it at
/// Get-Variable -Scope 0 after its dot-sourced body and carries it to C#, which skips process.
/// Mechanism measured in migration/logs/probe-20260718-latch-sentinel (latch lands at Scope 0;
/// does NOT survive to the next hop). Contrast W2-144, which deliberately does NOT bridge because
/// its source has no Test-FunctionInterrupt to read the latch back.
///
/// FOUR BEGIN-TO-PROCESS CARRIES. $knownNames, $patterns and $supportedDataTypes are built in begin
/// and read-only in process. $maskingconfig is the one that matters:
///
/// FOUR CROSS-RECORD CARRIES, ALL RIDING BUG-FOR-BUG.
///
/// 1. $maskingconfig. Initialized to @() ONCE in begin (:246), appended per database (:629), and
///    NEVER reset - and :658 writes the ENTIRE accumulation to each database's file, so the second
///    database's file also contains the first database's config, and the accumulation continues
///    across pipeline records too. A plain local, never the pipeline-bound parameter, so the carry
///    is unconditional. Dropping it would make each record write only its own entries - arguably
///    more correct, which is precisely why it would be a divergence.
///
/// 2. $databases. The SECOND never-reset accumulator: "$databases += Get-DbaDatabase ..." at :257,
///    iterated whole at :260, never reset, and not a parameter (the parameter is the singular
///    $Database). From the second record onward the source therefore REPROCESSES every database an
///    earlier record already handled - re-running its sampling queries and re-appending to
///    $maskingconfig. Same shape as New-DbaDacProfile's $ConnectionString (W2-142).
///
/// 3. $searchArray. Assigned ONLY inside "if ($InputObject)" (:251-254) but read unconditionally at
///    :419, so after a truthy record a later FALSEY piped value (@($false), 0, '') leaves the
///    source still holding the previous record's array. It therefore carries with an Assigned flag
///    rather than a plain restore, so that a first record with a falsey $InputObject leaves it
///    genuinely undefined, exactly as the source does.
///
/// 4. $tableobject. The foreach variable at :276, read again at :635 AFTER that loop has closed. A
///    stale cross-record read is UNREACHABLE, and this is MEASURED rather than argued: :635 sits in
///    the else of "if ($tables)", and reaching it requires $tablecollection.Count -ge 1 at :271,
///    because otherwise the Stop-Function -Continue at :272 skips the database - so :276 has just
///    assigned $tableobject in the same record. codex r3 challenged exactly this, asserting that
///    "Stop-Function -Continue is a command invocation, not the PowerShell continue statement", so
///    an empty collection would fall through to :635. That is wrong: Stop-Function's -Continue path
///    executes a bare "continue" (Stop-Function.ps1:268-273), and PowerShell's continue is
///    DYNAMICALLY scoped - it propagates up the call stack to the caller's enclosing loop. Measured
///    on BOTH editions with a fall-through control in
///    migration/logs/probe-20260718-continue-propagation.
///
///    It is carried anyway, with an Assigned flag. The restore is therefore a deliberate no-op
///    safeguard, kept because it costs three lines and matches the source's persistent function
///    scope in every case. This is NOT a licence to add carries speculatively: an unnecessary carry
///    is only free when it restores a value the source would ALSO still be holding, which is exactly
///    what the Assigned flag guarantees here - a first record leaves it undefined, as the source does.
///
/// HOW 2 AND 3 WERE FOUND, recorded because the process failed before it worked: codex r1 found
/// them, not me. My claim analysis enumerated $maskingconfig and stopped, which is the SAME
/// parameter-anchored enumeration that produced the Move-DbaDbFile P1 - I had written "every
/// process-block local was enumerated" on the previous row while, here, doing exactly the thing
/// that phrase is supposed to prevent. $databases is a bare undeclared local created by "+=" on
/// first use, so it appears in no param block and survives any reading that starts from the
/// parameters. The durable lesson: enumerate assignments, not declarations - a variable that is
/// never declared anywhere is precisely the one this class hides behind.
///
/// A SOURCE BUG IS PRESERVED VERBATIM - recorded here so no reviewer reads it as port drift. Line
/// :172 assigns $knownNameFilePath while :154 declares the PARAMETER $KnownNameFilePath, and
/// PowerShell variables are CASE-INSENSITIVE, so begin silently overwrites the caller's parameter
/// with the resolved default path. The guard at :192 is therefore always truthy whenever
/// -ExcludeDefaultKnownName was not passed, and the default known-names file is loaded a SECOND
/// time, duplicating entries. Identical shape at :183 versus :155 for $PatternFilePath. The hop
/// rides the body verbatim, so this reproduces for free; process never reads either parameter, so
/// the collision stays confined to begin and needs no carry.
///
/// SWITCHES CROSS AS SwitchParameter OBJECTS, NOT .ToBool(), per B's combined rule (2026-07-18):
/// a typed [switch] hop param shifts positional binding, while marshaling as .ToBool() silently
/// breaks any $Switch.IsPresent in the body. Untyped param + SwitchParameter object is safe on both
/// axes. This body has no .IsPresent sites today, but the object form costs nothing and removes the
/// need to re-audit if one is ever added. -Force is consumed as "-Force:$Force" at :221, which the
/// object form keeps correct.
///
/// NO ShouldProcess GATE EXISTS. SupportsShouldProcess is declared at :142 but $Pscmdlet is never
/// called anywhere in the 667 lines, so there is no gate to route and no $__realCmdlet parameter.
/// The attribute is still declared here to keep the surface identical.
///
/// STREAMING, NOT BUFFERED (DEF-001): the command writes config files and emits Get-ChildItem per
/// database, so a buffered hop would discard the record of files already written when a later
/// database's failure terminated the hop under -EnableException.
///
/// In-hop Stop-Function/Write-Message calls carry -FunctionName (25 sites). Implicit positions 0-11
/// are made explicit per the W2-071 law; the four switches carry none. Surface pinned by
/// migration/baselines/New-DbaDbMaskingConfig.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaDbMaskingConfig", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
public sealed class NewDbaDbMaskingConfigCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to profile for masking.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Limit the configuration to these tables.</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    /// <summary>Limit the configuration to these columns.</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Column { get; set; }

    /// <summary>Directory the configuration file is written to.</summary>
    [Parameter(Mandatory = true, Position = 5)]
    [PsStringCast]
    public string Path { get; set; } = null!;

    /// <summary>Locale used when generating masked values.</summary>
    [Parameter(Position = 6)]
    [PsStringCast]
    public string Locale { get; set; } = "en";

    /// <summary>Character set used for random string generation.</summary>
    [Parameter(Position = 7)]
    [PsStringCast]
    public string CharacterString { get; set; } = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    /// <summary>Rows sampled per column when detecting PII.</summary>
    [Parameter(Position = 8)]
    public int SampleCount { get; set; } = 100;

    /// <summary>Path to a custom known-names JSON file.</summary>
    [Parameter(Position = 9)]
    [PsStringCast]
    public string? KnownNameFilePath { get; set; }

    /// <summary>Path to a custom patterns JSON file.</summary>
    [Parameter(Position = 10)]
    [PsStringCast]
    public string? PatternFilePath { get; set; }

    /// <summary>Skip the built-in known-names catalogue.</summary>
    [Parameter]
    public SwitchParameter ExcludeDefaultKnownName { get; set; }

    /// <summary>Skip the built-in patterns catalogue.</summary>
    [Parameter]
    public SwitchParameter ExcludeDefaultPattern { get; set; }

    /// <summary>Create the output directory if it does not exist.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    /// <summary>Databases piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 11)]
    public object[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The catalogues and the seed $maskingconfig built in begin; opaque to C#.
    private Hashtable? _beginState;
    // The $maskingconfig accumulator carried across records; opaque to C#.
    private Hashtable? _state;
    // A failed begin guard silences every record.
    private bool _interrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            ExcludeDefaultKnownName, ExcludeDefaultPattern, KnownNameFilePath, PatternFilePath,
            Path, Force, EnableException,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbMaskingConfigBegin"))
            {
                if (sentinel["__newDbaDbMaskingConfigBegin"] is Hashtable state)
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

        // Streaming, not buffered (DEF-001): config files are written and emitted per database, so
        // a buffered hop would drop the audit trail of files already written.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__newDbaDbMaskingConfigProcess"))
            {
                _state = sentinel["__newDbaDbMaskingConfigProcess"] as Hashtable;
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
            SqlInstance, SqlCredential, Database, Table, Column, Path, Locale, CharacterString,
            SampleCount, InputObject, EnableException, _beginState, _state,
            NestedCommand.BoundCommonParameter(this, "WhatIf"), NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the begin block VERBATIM, dot-sourced so its four early returns exit only the body. The
    // only edit is -FunctionName on the message calls. The sentinel carries the two catalogues, the
    // supported-type list, the seed $maskingconfig, and the interrupt latch read at Scope 0.
    // Note the $knownNameFilePath / $KnownNameFilePath case collision at :172 rides verbatim.
    private const string BeginScript = """
param($ExcludeDefaultKnownName, $ExcludeDefaultPattern, $KnownNameFilePath, $PatternFilePath, $Path, $Force, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($ExcludeDefaultKnownName, $ExcludeDefaultPattern, [string]$KnownNameFilePath, [string]$PatternFilePath, [string]$Path, $Force, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {

        # Initialize the arrays
        $knownNames = @()
        $patterns = @()

        # Get the known names
        if (-not $ExcludeDefaultKnownName) {
            try {
                $knownNameFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-knownnames.json"
                $knownNames += Get-Content -Path $knownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse known names file" -ErrorRecord $_ -FunctionName New-DbaDbMaskingConfig
                return
            }
        }

        # Get the patterns
        if (-not $ExcludeDefaultPattern) {
            try {
                $patternFilePath = Resolve-Path -Path "$script:PSModuleRoot\bin\datamasking\pii-patterns.json"
                $patterns = Get-Content -Path $patternFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Couldn't parse pattern file" -ErrorRecord $_ -FunctionName New-DbaDbMaskingConfig
                return
            }
        }

        # Get custom known names and patterns
        if ($KnownNameFilePath) {
            if (Test-Path -Path $KnownNameFilePath) {
                try {
                    $knownNames += Get-Content -Path $KnownNameFilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse known types file" -ErrorRecord $_ -Target $KnownNameFilePath -FunctionName New-DbaDbMaskingConfig
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find known names file" -Target $KnownNameFilePath -FunctionName New-DbaDbMaskingConfig
            }
        }

        if ($PatternFilePath ) {
            if (Test-Path -Path $PatternFilePath ) {
                try {
                    $patterns += Get-Content -Path $PatternFilePath  -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
                } catch {
                    Stop-Function -Message "Couldn't parse patterns file" -ErrorRecord $_ -Target $PatternFilePath -FunctionName New-DbaDbMaskingConfig
                    return
                }
            } else {
                Stop-Function -Message "Couldn't not find patterns file" -Target $PatternFilePath -FunctionName New-DbaDbMaskingConfig
            }
        }

        # Check if the Path is accessible
        if (-not (Test-Path -Path $Path)) {
            try {
                $null = New-Item -Path $Path -ItemType Directory -Force:$Force
            } catch {
                Stop-Function -Message "Could not create Path directory" -ErrorRecord $_ -Target $Path -FunctionName New-DbaDbMaskingConfig
            }
        } else {
            if ((Get-Item $path) -isnot [System.IO.DirectoryInfo]) {
                Stop-Function -Message "$Path is not a directory" -FunctionName New-DbaDbMaskingConfig
            }
        }

        $supportedDataTypes = @(
            'bit', 'bigint', 'bool',
            'char', 'date',
            'datetime', 'datetime2',
            'decimal', 'numeric',
            'float',
            'int',
            'money',
            'nchar', 'ntext', 'nvarchar',
            'smalldatetime', 'smallint',
            'text', 'time', 'tinyint',
            'uniqueidentifier', 'userdefineddatatype',
            'varchar'
        )

        $maskingconfig = @()
    }

    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    $__kn = Get-Variable -Name knownNames -Scope 0 -ErrorAction Ignore
    $__pa = Get-Variable -Name patterns -Scope 0 -ErrorAction Ignore
    $__sd = Get-Variable -Name supportedDataTypes -Scope 0 -ErrorAction Ignore
    $__mc = Get-Variable -Name maskingconfig -Scope 0 -ErrorAction Ignore
    @{ __newDbaDbMaskingConfigBegin = @{
        Interrupted        = [bool]($__iv -and $__iv.Value)
        KnownNames         = $(if ($__kn) { , @($__kn.Value) } else { , @() })
        Patterns           = $(if ($__pa) { , @($__pa.Value) } else { , @() })
        SupportedDataTypes = $(if ($__sd) { , @($__sd.Value) } else { , @() })
        MaskingConfig      = $(if ($__mc) { , @($__mc.Value) } else { , @() })
    } }
} $ExcludeDefaultKnownName $ExcludeDefaultPattern $KnownNameFilePath $PatternFilePath $Path $Force $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced. The only edit is -FunctionName on the message
    // calls. The begin catalogues are restored first; $maskingconfig restores from the PROCESS
    // carry when one exists and from the begin seed on the first record, which is what makes the
    // never-reset accumulator behave across records exactly as the source's function scope does.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $Table, $Column, $Path, $Locale, $CharacterString, $SampleCount, $InputObject, $EnableException, $__beginState, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Low")]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$Table, [string[]]$Column, [string]$Path, [string]$Locale, [string]$CharacterString, [int]$SampleCount, [object[]]$InputObject, $EnableException, $__beginState, $__state, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # begin's catalogues, read-only in the body
    $knownNames         = @($__beginState.KnownNames)
    $patterns           = @($__beginState.Patterns)
    $supportedDataTypes = @($__beginState.SupportedDataTypes)
    # the never-reset accumulator: previous records' value if we have one, else begin's seed
    $maskingconfig      = $(if ($null -ne $__state) { @($__state.MaskingConfig) } else { @($__beginState.MaskingConfig) })
    # $databases: the SECOND never-reset accumulator (+= at :257, read at :260, never a parameter).
    # On the first record the source has it UNDEFINED and "+=" creates it, which @() matches exactly.
    $databases          = $(if ($null -ne $__state) { @($__state.Databases) } else { @() })
    # $searchArray is assigned ONLY under "if ($InputObject)" (:251-254) yet read unconditionally at
    # :419, so on a falsy piped record the source still sees the PREVIOUS record's value. It must
    # therefore restore only when some earlier record actually assigned it - hence the Assigned flag
    # rather than a plain restore, which would wrongly define it on the very first falsy record.
    if ($null -ne $__state -and $__state.SearchArrayAssigned) { $searchArray = @($__state.SearchArray) }
    # $tableobject is the foreach variable at :276, but :635 reads it AFTER that loop has closed.
    # I judge a stale cross-record read UNREACHABLE: :635 sits in the else of "if ($tables)", and
    # getting there requires $tablecollection.Count -ge 1 at :271 (otherwise Stop-Function -Continue
    # skips the database), which means :276 just assigned it in this same record. It is carried
    # anyway, with an Assigned flag: the restore is a NO-OP wherever my reachability reading holds,
    # and a fix wherever it does not, and it matches the source's persistent function scope in both
    # cases - the flag keeps a first record from defining it where the source would not.
    if ($null -ne $__state -and $__state.TableObjectAssigned) { $tableobject = $__state.TableObject }

    . {
        if (Test-FunctionInterrupt) { return }

        if ($InputObject) {
            $searchArray = @()
            $searchArray += $InputObject | Select-Object ComputerName, InstanceName, SqlInstance, Database, Schema, Table, Column
        }

        if ($SqlInstance) {
            $databases += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $databases) {
            $server = $db.Parent
            $tables = @()

            # Get the tables
            if ($Table) {
                $tablecollection = $db.Tables | Where-Object Name -in $Table
            } else {
                $tablecollection = $db.Tables
            }

            if ($tablecollection.Count -lt 1) {
                Stop-Function -Message "The database does not contain any tables" -Target $db -Continue -FunctionName New-DbaDbMaskingConfig
            }

            # Loop through the tables
            foreach ($tableobject in $tablecollection) {
                Write-Message -Message "Processing table [$($tableobject.Schema)].[$($tableobject.Name)]" -Level Verbose -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"

                $hasUniqueIndex = $false

                if ($tableobject.Indexes.IsUnique) {
                    $hasUniqueIndex = $true
                }

                $columns = @()

                # Get the columns
                if ($Column) {
                    [array]$columncollection = $tableobject.Columns | Where-Object Name -in $Column
                } else {
                    [array]$columncollection = $tableobject.Columns
                }

                foreach ($columnobject in $columncollection) {
                    $result = $minValue = $maxValue = $null

                    # Skip incompatible columns
                    if ($columnobject.Identity) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is an identity column" -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                        continue
                    }

                    if ($columnobject.IsForeignKey) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a foreign key" -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                        continue
                    }

                    if ($columnobject.Computed) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a computed column" -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                        continue
                    }

                    if ($server.VersionMajor -ge 13 -and $columnobject.GeneratedAlwaysType -ne 'None') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a computed column for temporal tables" -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                        continue
                    }

                    if ($columnobject.DataType.Name -notin $supportedDataTypes) {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is not a supported data type" -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                        continue
                    }

                    if ($columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -eq 'xml') {
                        Write-Message -Level Verbose -Message "Skipping $columnobject because it is a xml column" -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                        continue
                    }

                    $searchObject = [PSCustomObject]@{
                        ComputerName = $db.Parent.ComputerName
                        InstanceName = $db.Parent.ServiceName
                        SqlInstance  = $db.Parent.DomainInstanceName
                        Database     = $db.Name
                        Schema       = $tableobject.Schema
                        Table        = $tableobject.Name
                        Column       = $columnobject.Name
                    }

                    if ($columnobject.Datatype.Name -in 'date', 'datetime', 'datetime2', 'smalldatetime', 'time') {
                        $columnLength = $columnobject.Datatype.NumericScale
                    } else {
                        $columnLength = $columnobject.Datatype.MaximumLength
                    }

                    $columnType = $columnobject.DataType.Name

                    switch ($columnType) {
                        "bigint" {
                            $minValue = 1
                            $maxValue = 9223372036854775807
                        }
                        { $_ -in "char", "nchar", "nvarchar", "varchar" } {
                            if ($columnLength -eq -1) {
                                if ($_ -in "char", "varchar") {
                                    $minValue = 1
                                    $maxValue = 8000
                                } elseif ($_ -in "nchar", "nvarchar") {
                                    $minValue = 1
                                    $maxValue = 4000
                                }
                            } else {
                                $minValue = [int]($columnLength / 2)
                                $maxValue = $columnLength
                            }
                        }
                        "date" { $maxValue = $null }
                        "datetime" { $maxValue = $null }
                        "datetime2" { $maxValue = $null }
                        "decimal" {
                            $minValue = 1.1
                            $maxValue = $null
                        }
                        "float" {
                            $minValue = 1.1
                            $maxValue = $null
                        }
                        "int" {
                            $minValue = 1
                            $maxValue = 2147483647
                        }
                        "money" {
                            $minValue = 1.0
                            $maxValue = 922337203685477.5807
                        }
                        "smallint" {
                            $minValue = 1
                            $maxValue = 32767
                        }
                        "smalldatetime" {
                            $maxValue = $null
                        }
                        "text" {
                            $minValue = 10
                            $maxValue = 2147483647
                        }
                        "time" {
                            $maxValue = $null
                        }
                        "tinyint" {
                            $minValue = 1
                            $maxValue = 255
                        }
                        "varbinary" {
                            $maxValue = $columnLength
                        }
                        "userdefineddatatype" {
                            if ($columnLength -eq 1) {
                                $maxValue = $columnLength
                            } else {
                                $minValue = [int]($columnLength / 2)
                                $maxValue = $columnLength
                            }
                        }
                        default {
                            $minValue = [int]($columnLength / 2)
                            $maxValue = $columnLength
                        }
                    }

                    if ($searchArray -contains $searchObject) {
                        $result = $InputObject | Where-Object { $_.Database -eq $searchObject.Name -and $_.Schema -eq $searchObject.Schema -and $_.Table -eq $searchObject.Name -and $_.Column -eq $searchObject.Name }
                    } else {

                        if ($columnobject.InPrimaryKey -and $columnobject.DataType.SqlDataType.ToString().ToLowerInvariant() -notmatch 'date') {
                            $minValue = 2
                        }

                        if ($columnobject.DataType.Name -eq "geography") {
                            # Add the results
                            $result = [PSCustomObject]@{
                                ComputerName   = $db.Parent.ComputerName
                                InstanceName   = $db.Parent.ServiceName
                                SqlInstance    = $db.Parent.DomainInstanceName
                                Database       = $db.Name
                                Schema         = $tableobject.Schema
                                Table          = $tableobject.Name
                                Column         = $columnobject.Name
                                "PII-Category" = "Location"
                                "PII-Name"     = "Geography"
                                FoundWith      = "DataType"
                                MaskingType    = "Random"
                                MaskingSubType = "Decimal"
                            }
                        } else {
                            if ($knownNames.Count -ge 1) {
                                # Go through the first check to see if any column is found with a known name
                                foreach ($knownName in $knownNames) {
                                    foreach ($pattern in $knownName.Pattern) {
                                        if ($null -eq $result -and $columnobject.Name -match $pattern ) {
                                            # Add the results
                                            $result = [PSCustomObject]@{
                                                ComputerName   = $db.Parent.ComputerName
                                                InstanceName   = $db.Parent.ServiceName
                                                SqlInstance    = $db.Parent.DomainInstanceName
                                                Database       = $db.Name
                                                Schema         = $tableobject.Schema
                                                Table          = $tableobject.Name
                                                Column         = $columnobject.Name
                                                "PII-Category" = $knownName.Category
                                                "PII-Name"     = $knownName.Name
                                                FoundWith      = "KnownName"
                                                MaskingType    = $knownName.MaskingType
                                                MaskingSubType = $knownName.MaskingSubType
                                            }
                                        }
                                    }
                                }
                                $knownName = $null
                            } else {
                                Write-Message -Level Verbose -Message "No known names found to perform check on" -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                            }

                            # Go through the second check to see if any column is found with a known type
                            if ($patterns.Count -ge 1) {
                                if ($null -eq $result) {
                                    # Setup the query
                                    $query = "SELECT TOP($SampleCount) [$($columnobject.Name)] FROM [$($tableobject.Schema)].[$($tableobject.Name)]"

                                    # Get the data
                                    $dataset = @()

                                    try {
                                        $dataset += Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query -EnableException
                                    } catch {
                                        $errormessage = $_.Exception.Message.ToString()
                                        Stop-Function -Message "Error executing query [$($tableobject.Schema)].[$($tableobject.Name)]: $errormessage" -Target $updatequery -Continue -ErrorRecord $_ -FunctionName New-DbaDbMaskingConfig
                                    }

                                    # Check if there is any data
                                    if ($dataset.Count -ge 1) {

                                        # Loop through the patterns
                                        foreach ($patternobject in $patterns) {

                                            # If there is a result from the match
                                            if ($null -eq $result -and $dataset.$($columnobject.Name) -match $patternobject.Pattern) {
                                                # Add the results
                                                $result = [PSCustomObject]@{
                                                    ComputerName   = $db.Parent.ComputerName
                                                    InstanceName   = $db.Parent.ServiceName
                                                    SqlInstance    = $db.Parent.DomainInstanceName
                                                    Database       = $db.Name
                                                    Schema         = $tableobject.Schema
                                                    Table          = $tableobject.Name
                                                    Column         = $columnobject.Name
                                                    "PII-Category" = $patternobject.Category
                                                    "PII-Name"     = $patternobject.Name
                                                    FoundWith      = "Pattern"
                                                    MaskingType    = $patternobject.MaskingType
                                                    MaskingSubType = $patternobject.MaskingSubType
                                                }
                                            }
                                            $patternobject = $null
                                        }
                                    } else {
                                        Write-Message -Message "Table $($tableobject.Name) does not contain any rows" -Level Verbose -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                                    }
                                }
                            } else {
                                Write-Message -Level Verbose -Message "No patterns found to perform check on" -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                            }
                        }
                    }

                    if ($result) {
                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $( if ($result.MaskingType -in "String", "String2") { $CharacterString } else { $null } )
                            MinValue        = $minValue
                            MaxValue        = $maxValue
                            MaskingType     = $result.MaskingType
                            SubType         = $result.MaskingSubType
                            Format          = $null
                            Separator       = $null
                            Deterministic   = $false
                            Nullable        = $columnobject.Nullable
                            KeepNull        = $true
                            Composite       = $null
                            Action          = $null
                            StaticValue     = $null
                        }
                    } else {
                        $type = "Random"

                        switch ($columnType) {
                            { $_ -in "bit", "bool" } { $subType = "Bool" }
                            "bigint" { $subType = "Number" }
                            { $_ -in "char", "nchar", "nvarchar", "varchar" } { $subType = "String2" }
                            "date" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "datetime" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "datetime2" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "decimal" { $subType = "Decimal" }
                            "numeric" { $subType = "Decimal" }
                            "float" { $subType = "Float" }
                            "int" { $subType = "Number" }
                            "money" {
                                $type = "Commerce"
                                $subType = "Price"
                            }
                            "smallint" { $subType = "Number" }
                            "smalldatetime" { $subType = "Date" }
                            "text" { $subType = "String" }
                            "time" {
                                $type = "Date"
                                $subType = "Past"
                            }
                            "tinyint" { $subType = "Number" }
                            "varbinary" { $subType = "Byte" }
                            "userdefineddatatype" {
                                if ($columnLength -eq 1) {
                                    $subType = "Bool"
                                } else {
                                    $subType = "String2"
                                }
                            }
                            "uniqueidentifier" {
                                $subType = "Guid"
                            }
                            default {
                                $subType = "String2"
                            }
                        }

                        $columns += [PSCustomObject]@{
                            Name            = $columnobject.Name
                            ColumnType      = $columnType
                            CharacterString = $( if ($subType -in "String", "String2") { $CharacterString } else { $null } )
                            MinValue        = $minValue
                            MaxValue        = $maxValue
                            MaskingType     = $type
                            SubType         = $subType
                            Format          = $null
                            Separator       = $null
                            Deterministic   = $false
                            Nullable        = $columnobject.Nullable
                            KeepNull        = $true
                            Composite       = $null
                            Action          = $null
                            StaticValue     = $null
                        }
                    }
                }

                # Check if something needs to be generated
                if ($columns) {
                    $tables += [PSCustomObject]@{
                        Name           = $tableobject.Name
                        Schema         = $tableobject.Schema
                        Columns        = $columns
                        HasUniqueIndex = $hasUniqueIndex
                        FilterQuery    = $null
                    }
                } else {
                    Write-Message -Message "No columns match for masking in table $($tableobject.Name)" -Level Verbose -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                }
            }

            # Check if something needs to be generated
            if ($tables) {
                $maskingconfig += [PSCustomObject]@{
                    Name   = $db.Name
                    Type   = "DataMaskingConfiguration"
                    Tables = $tables
                }
            } else {
                Write-Message -Message "No columns match for masking in table $($tableobject.Name)" -Level Verbose -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
            }

            # Write the data to the Path
            if ($maskingconfig) {
                Write-Message -Message "Writing masking config" -Level Verbose -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
                try {
                    $filenamepart = $server.Name.Replace('\', '$').Replace('TCP:', '').Replace(',', '.')

                    if ($Table) {
                        if ($Table.Count -ge 5) {
                            $temppath = Join-Path -Path $Path -ChildPath "$($filenamepart).$($db.Name).Tables_$(Get-Date -f 'yyyyMMddHHmmss').DataMaskingConfig.json"
                        } else {
                            $temppath = Join-Path -Path $Path -ChildPath "$($filenamepart).$($db.Name).$($Table -join '-').DataMaskingConfig.json"
                        }
                    } else {
                        $temppath = Join-Path -Path $Path -ChildPath "$($filenamepart).$($db.Name).DataMaskingConfig.json"
                    }

                    if (-not $script:isWindows) {
                        $temppath = $temppath.Replace("\", "/")
                    }

                    Set-Content -Path $temppath -Value ($maskingconfig | ConvertTo-Json -Depth 5)
                    Get-ChildItem -Path $temppath
                } catch {
                    Stop-Function -Message "Something went wrong writing the results to the '$Path'" -Target $Path -Continue -ErrorRecord $_ -FunctionName New-DbaDbMaskingConfig
                }
            } else {
                Write-Message -Message "No tables to save for database $($db.Name) on $($server.Name)" -Level Verbose -FunctionName New-DbaDbMaskingConfig -ModuleName "dbatools"
            }
        }
    }

    $__mc = Get-Variable -Name maskingconfig -Scope 0 -ErrorAction Ignore
    $__db = Get-Variable -Name databases -Scope 0 -ErrorAction Ignore
    $__sa = Get-Variable -Name searchArray -Scope 0 -ErrorAction Ignore
    $__to = Get-Variable -Name tableobject -Scope 0 -ErrorAction Ignore
    @{ __newDbaDbMaskingConfigProcess = @{
        MaskingConfig       = $(if ($__mc) { , @($__mc.Value) } else { , @() })
        Databases           = $(if ($__db) { , @($__db.Value) } else { , @() })
        SearchArrayAssigned = [bool]$__sa
        SearchArray         = $(if ($__sa) { , @($__sa.Value) } else { , @() })
        TableObjectAssigned = [bool]$__to
        TableObject         = $(if ($__to) { $__to.Value } else { $null })
    } }
} $SqlInstance $SqlCredential $Database $Table $Column $Path $Locale $CharacterString $SampleCount $InputObject $EnableException $__beginState $__state $__boundWhatIf $__boundConfirm $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
