#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Generates randomized data into database tables from a data-generation config file. Port of
/// public/Invoke-DbaDbDataGenerator.ps1; the workflow remains a module-scoped PowerShell compatibility hop. Mutating,
/// with real SupportsShouldProcess (ConfirmImpact High).
///
/// A begin+process port (FilePath is Mandatory ValueFromPipeline pos3, alias Path/FullName). Three mechanisms:
/// (1) BEGIN-STATE CARRY: begin builds supportedDataTypes/supportedFakerMaskingTypes/supportedFakerSubTypes (the
/// module-scope script:faker persists on its own) - carried begin to process via a sentinel; begin body wrapped in a
/// continue-guard foreach for the Faker-load Stop-Function -Continue (which does NOT set the interrupt).
/// (2) CROSS-RECORD PROCESS INTERRUPT: process opens with if (Test-FunctionInterrupt) return and several no-Continue
/// Stop-Function+return guards set the interrupt; because FilePath is pipeline, the body is DOT-SOURCED, the module
/// interrupt var captured (Get-Variable Scope 0) and emitted, and C# _processInterrupted persists across ProcessRecord.
/// All process Stop-Function -Continue are loop-bound (no process continue-guard).
/// (3) SHOULDPROCESS: Pscmdlet.ShouldProcess to realCmdlet; PSBoundParameters.MaxValue to MaxValue (not reassigned).
/// ExactLength is surface-only unused; Locale/CharacterString/ModulusFactor defaults via property initializers; the
/// undefined Force reference (dead branch) is preserved. Surface pinned by migration/baselines/Invoke-DbaDbDataGenerator.json.
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbDataGenerator", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class InvokeDbaDbDataGeneratorCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to generate data into.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>The data-generation config file (path or URL).</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 3)]
    [Alias("Path", "FullName")]
    public object? FilePath { get; set; }

    /// <summary>The locale used for value generation (default 'en').</summary>
    [Parameter(Position = 4)]
    public string Locale { get; set; } = "en";

    /// <summary>The character set to draw string values from.</summary>
    [Parameter(Position = 5)]
    public string CharacterString { get; set; } = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

    /// <summary>Only generate data for the specified table(s).</summary>
    [Parameter(Position = 6)]
    public string[]? Table { get; set; }

    /// <summary>Only generate data for the specified column(s).</summary>
    [Parameter(Position = 7)]
    public string[]? Column { get; set; }

    /// <summary>Exclude the specified table(s).</summary>
    [Parameter(Position = 8)]
    public string[]? ExcludeTable { get; set; }

    /// <summary>Exclude the specified column(s).</summary>
    [Parameter(Position = 9)]
    public string[]? ExcludeColumn { get; set; }

    /// <summary>The maximum length/value for generated string values.</summary>
    [Parameter(Position = 10)]
    public int MaxValue { get; set; }

    /// <summary>Use the exact length for generated values (surface parity; unused by the body).</summary>
    [Parameter]
    public SwitchParameter ExactLength { get; set; }

    /// <summary>How often nullable columns get a null value (1 in N; default 10).</summary>
    [Parameter(Position = 11)]
    public int ModulusFactor { get; set; } = 10;

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private object? _supportedDataTypes, _supportedFakerMaskingTypes, _supportedFakerSubTypes;
    private bool _processInterrupted;
    // DEF-011/012: prior-record process-scope state carried between hops via the sentinel.
    private object? _uniqueValueColumns;
    private object? _transaction;
    private object? _elapsed;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__dgBegin"))
            {
                if (sentinel["__dgBegin"] is Hashtable state)
                {
                    _supportedDataTypes = state["SupportedDataTypes"];
                    _supportedFakerMaskingTypes = state["SupportedFakerMaskingTypes"];
                    _supportedFakerSubTypes = state["SupportedFakerSubTypes"];
                }
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
            Locale, EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted || _processInterrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__dgProcess"))
            {
                if (sentinel["__dgProcess"] is Hashtable state)
                {
                    _processInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
                    _uniqueValueColumns = state["UniqueValueColumns"];
                    _transaction = state["Transaction"];
                    _elapsed = state["Elapsed"];
                }
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
            SqlInstance, SqlCredential, Database, FilePath, Locale, CharacterString, Table, Column, ExcludeTable,
            ExcludeColumn, MaxValue, ModulusFactor, EnableException.ToBool(),
            _supportedDataTypes, _supportedFakerMaskingTypes, _supportedFakerSubTypes, this,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"),
            _uniqueValueColumns, _transaction, _elapsed);
    }
    private const string BeginScript = """
param($Locale, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string]$Locale, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    foreach ($__continueGuard in @(1)) {
        if ($Force) { $ConfirmPreference = 'none' }

        # Create the faker objects
        try {
            $script:faker = New-Object Bogus.Faker($Locale)
        } catch {
            Stop-Function -Message "Could not load randomizer class" -FunctionName Invoke-DbaDbDataGenerator -Continue
        }

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'
        $supportedFakerMaskingTypes = ($script:faker | Get-Member -MemberType Property | Select-Object Name -ExpandProperty Name)
        # The value of the property DateTimeReference is currently $null, which causes the next line to throw an exception.
        # We have to contact the developer of Bogus to solve the issue.
        $supportedFakerSubTypes = ($script:faker | Get-Member -MemberType Property | Where-Object Name -ne DateTimeReference) | ForEach-Object { ($script:faker.$($_.Name)) | Get-Member -MemberType Method | Where-Object { $_.Name -notlike 'To*' -and $_.Name -notlike 'Get*' -and $_.Name -notlike 'Trim*' -and $_.Name -notin 'Add', 'Equals', 'CompareTo', 'Clone', 'Contains', 'CopyTo', 'EndsWith', 'IndexOf', 'IndexOfAny', 'Insert', 'IsNormalized', 'LastIndexOf', 'LastIndexOfAny', 'Normalize', 'PadLeft', 'PadRight', 'Remove', 'Replace', 'Split', 'StartsWith', 'Substring', 'Letter', 'Lines', 'Paragraph', 'Paragraphs', 'Sentence', 'Sentences' } | Select-Object name -ExpandProperty Name }
        $supportedFakerSubTypes += "Date"
        #$foreignKeyQuery = Get-Content -Path "$script:PSModuleRoot\bin\datageneration\ForeignKeyHierarchy.sql"
    }
    @{ __dgBegin = @{ SupportedDataTypes = $supportedDataTypes; SupportedFakerMaskingTypes = $supportedFakerMaskingTypes; SupportedFakerSubTypes = $supportedFakerSubTypes } }
} $Locale $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $FilePath, $Locale, $CharacterString, $Table, $Column, $ExcludeTable, $ExcludeColumn, $MaxValue, $ModulusFactor, $EnableException, $supportedDataTypes, $supportedFakerMaskingTypes, $supportedFakerSubTypes, $__realCmdlet, $__boundVerbose, $__boundDebug, $__carriedUniqueValueColumns, $__carriedTransaction, $__carriedElapsed)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [object]$FilePath, [string]$Locale, [string]$CharacterString, [string[]]$Table, [string[]]$Column, [string[]]$ExcludeTable, [string[]]$ExcludeColumn, [int]$MaxValue, [int]$ModulusFactor, $EnableException, $supportedDataTypes, $supportedFakerMaskingTypes, $supportedFakerSubTypes, $__realCmdlet, $__boundVerbose, $__boundDebug, $__carriedUniqueValueColumns, $__carriedTransaction, $__carriedElapsed)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    # DEF-011/012 cross-record carries (codex r2): the function world's process scope persists
    # $uniqueValueColumns / $transaction / $elapsed across pipeline records; each hop is a fresh
    # scope, so they are seeded from the sentinel-carried prior-record values here and emitted
    # back below. The verbatim body is untouched.
    if ($null -ne $__carriedUniqueValueColumns) { $uniqueValueColumns = $__carriedUniqueValueColumns }
    if ($null -ne $__carriedTransaction) { $transaction = $__carriedTransaction }
    if ($null -ne $__carriedElapsed) { $elapsed = $__carriedElapsed }
    . {
        if (Test-FunctionInterrupt) { return }

        if ($FilePath.ToString().StartsWith('http')) {
            $tables = Invoke-RestMethod -Uri $FilePath
        } else {
            # Check if the destination is accessible
            if (-not (Test-Path -Path $FilePath)) {
                Stop-Function -Message "Could not find data generation config file $FilePath" -Target $FilePath -FunctionName Invoke-DbaDbDataGenerator
                return
            }

            # Test the configuration
            try {
                Test-DbaDbDataGeneratorConfig -FilePath $FilePath -EnableException
            } catch {
                Stop-Function -Message "Errors found testing the configuration file. `n$_" -ErrorRecord $_ -Target $FilePath -FunctionName Invoke-DbaDbDataGenerator
                return
            }

            # Get all the items that should be processed
            try {
                $tables = Get-Content -Path $FilePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            } catch {
                Stop-Function -Message "Could not parse masking config file" -ErrorRecord $_ -Target $FilePath -FunctionName Invoke-DbaDbDataGenerator
                return
            }
        }

        foreach ($tabletest in $tables.Tables) {
            if ($Table -and $tabletest.Name -notin $Table) {
                continue
            }
            foreach ($columntest in $tabletest.Columns) {
                if ($columntest.ColumnType -in 'hierarchyid', 'geography', 'xml', 'geometry' -and $columntest.Name -notin $Column) {
                    Stop-Function -Message "$($columntest.ColumnType) is not supported, please remove the column $($columntest.Name) from the $($tabletest.Name) table" -Target $tables -FunctionName Invoke-DbaDbDataGenerator
                }
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -FunctionName Invoke-DbaDbDataGenerator -Continue
            }

            if ($Database) {
                $dbs = Get-DbaDatabase -SqlInstance $server -Database $Database
            } else {
                $dbs = Get-DbaDatabase -SqlInstance $server -Database $tables.Name
            }

            $sqlconn = $server.ConnectionContext.SqlConnectionObject.PsObject.Copy()
            $sqlconn.Open()

            foreach ($db in $dbs) {
                $stepcounter = $nullmod = 0

                #$foreignKeys = Invoke-DbaQuery -SqlInstance $instance -SqlCredential $SqlCredential -Database $db -Query $foreignKeyQuery

                foreach ($tableobject in $tables.Tables) {

                    if ($tableobject.Name -in $ExcludeTable -or ($Table -and $tableobject.Name -notin $Table)) {
                        Write-Message -Level Verbose -Message "Skipping $($tableobject.Name) because it is explicitly excluded" -FunctionName Invoke-DbaDbDataGenerator -ModuleName "dbatools"
                        continue
                    }

                    if ($tableobject.Name -notin $db.Tables.Name) {
                        Stop-Function -Message "Table $($tableobject.Name) is not present in $db" -Target $db -FunctionName Invoke-DbaDbDataGenerator -Continue
                    }

                    $uniqueValues = @()

                    # Check if the table contains unique indexes
                    if ($tableobject.HasUniqueIndex) {
                        # Loop through the rows and generate a unique value for each row
                        Write-Message -Level Verbose -Message "Generating unique values for $($tableobject.Name)" -FunctionName Invoke-DbaDbDataGenerator -ModuleName "dbatools"

                        for ($i = 0; $i -lt $tableobject.Rows; $i++) {
                            $rowValue = New-Object PSCustomObject

                            # Loop through each of the unique indexes
                            foreach ($index in ($db.Tables[$($tableobject.Name)].Indexes | Where-Object IsUnique -eq $true )) {

                                # Loop through the index columns
                                foreach ($indexColumn in $index.IndexedColumns) {
                                    # Get the column mask info
                                    $columnMaskInfo = $tableobject.Columns | Where-Object Name -eq $indexColumn.Name

                                    if ($columnMaskInfo) {
                                        # Generate a new value
                                        try {
                                            if ($MaxValue -and $columnMaskInfo.SubType -eq 'String' -and $columnMaskInfo.MaxValue -gt $MaxValue) {
                                                $columnMaskInfo.MaxValue = $MaxValue
                                            }
                                            if ($columnMaskInfo.ColumnType -in $supportedDataTypes -and $columnMaskInfo.MaskingType -eq 'Random' -and $columnMaskInfo.SubType -in 'Bool', 'Number', 'Float', 'Byte', 'String') {
                                                $newValue = Get-DbaRandomizedValue -DataType $columnMaskInfo.ColumnType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                            } else {
                                                $newValue = Get-DbaRandomizedValue -RandomizerType $columnMaskInfo.MaskingType -RandomizerSubtype $columnMaskInfo.SubType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                            }
                                        } catch {
                                            Stop-Function -Message "Failure" -Target $columnMaskInfo -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataGenerator
                                        }

                                        # Check if the value is already present as a property
                                        if (($rowValue | Get-Member -MemberType NoteProperty).Name -notcontains $indexColumn.Name) {
                                            $rowValue | Add-Member -Name $indexColumn.Name -Type NoteProperty -Value $newValue
                                        }
                                    }

                                }

                                # To be sure the values are unique, loop as long as long as needed to generate a unique value
                                while (($uniqueValues | Select-Object -Property ($rowValue | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name)) -match $rowValue) {

                                    $rowValue = New-Object PSCustomObject

                                    # Loop through the index columns
                                    foreach ($indexColumn in $index.IndexedColumns) {
                                        # Get the column mask info
                                        $columnMaskInfo = $tableobject.Columns | Where-Object Name -eq $indexColumn.Name

                                        # Generate a new value
                                        try {
                                            if ($MaxValue -and $columnMaskInfo.SubType -eq 'String' -and $columnMaskInfo.MaxValue -gt $MaxValue) {
                                                $columnMaskInfo.MaxValue = $MaxValue
                                            }
                                            if ($columnMaskInfo.ColumnType -in $supportedDataTypes -and $columnMaskInfo.MaskingType -eq 'Random' -and $columnMaskInfo.SubType -in 'Bool', 'Number', 'Float', 'Byte', 'String') {
                                                $newValue = Get-DbaRandomizedValue -DataType $columnMaskInfo.ColumnType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                            } else {
                                                $newValue = Get-DbaRandomizedValue -RandomizerType $columnMaskInfo.MaskingType -RandomizerSubtype $columnMaskInfo.SubType -Locale $Locale -Min $columnMaskInfo.MinValue -Max $columnMaskInfo.MaxValue
                                            }

                                        } catch {
                                            Stop-Function -Message "Failure" -Target $script:faker -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataGenerator
                                        }

                                        # Check if the value is already present as a property
                                        if (($rowValue | Get-Member -MemberType NoteProperty).Name -notcontains $indexColumn.Name) {
                                            $rowValue | Add-Member -Name $indexColumn.Name -Type NoteProperty -Value $newValue
                                            $uniqueValueColumns += $indexColumn.Name
                                        }
                                    }
                                }
                            }
                            # Add the row value to the array
                            $uniqueValues += $rowValue
                        }
                    }

                    $uniqueValueColumns = $uniqueValueColumns | Select-Object -Unique

                    if (-not $server.IsAzure) {
                        $sqlconn.ChangeDatabase($db.Name)
                    }
                    $tablecolumns = $tableobject.Columns

                    if ($Column) {
                        $tablecolumns = $tablecolumns | Where-Object Name -in $Column
                    }

                    if ($ExcludeColumn) {
                        $tablecolumns = $tablecolumns | Where-Object Name -notin $ExcludeColumn
                    }

                    if (-not $tablecolumns) {
                        Write-Message -Level Verbose "No columns to process in $($db.Name).$($tableobject.Schema).$($tableobject.Name), moving on" -FunctionName Invoke-DbaDbDataGenerator -ModuleName "dbatools"
                        continue
                    }

                    $insertQuery = ""

                    if ($__realCmdlet.ShouldProcess($instance, "Generating data for columns $($tablecolumns.Name -join ', ') in $($tableobject.Rows) rows in $($db.Name).$($tableobject.Schema).$($tableobject.Name)")) {
                        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()

                        Write-ProgressHelper -StepNumber ($stepcounter++) -TotalSteps $tables.Tables.Count -Activity "Generating data" -Message "Inserting $($tableobject.Rows) rows in $($tableobject.Schema).$($tableobject.Name) in $($db.Name) on $instance"

                        if ($tableobject.TruncateTable) {
                            $query = "TRUNCATE TABLE [$($tableobject.Schema)].[$($tableobject.Name)];"

                            try {
                                $null = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query
                            } catch {
                                Write-Message -Level VeryVerbose -Message "$query" -FunctionName Invoke-DbaDbDataGenerator -ModuleName "dbatools"
                                $errormessage = $_.Exception.Message.ToString()
                                Stop-Function -Message "Error truncating $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $query -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataGenerator
                            }
                        }

                        if ($tableobject.Columns.Identity -contains $true) {
                            $query = "SELECT IDENT_CURRENT('[$($tableobject.Schema)].[$($tableobject.Name)]') AS CurrentIdentity,
                            IDENT_INCR('[$($tableobject.Schema)].[$($tableobject.Name)]') AS IdentityIncrement,
                            IDENT_SEED('[$($tableobject.Schema)].[$($tableobject.Name)]') AS IdentitySeed;"

                            try {
                                $identityValues = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query
                                # https://docs.microsoft.com/en-us/sql/t-sql/public/ident-current-transact-sql says:
                                # When the IDENT_CURRENT value is NULL (because the table has never contained rows or has been truncated), the IDENT_CURRENT function returns the seed value.
                                # So if we get a 1 back, we count the rows so that the first row added to an empty table gets the number 1.
                                if ($identityValues.CurrentIdentity -eq 1) {
                                    $query = "SELECT COUNT(*) FROM [$($tableobject.Schema)].[$($tableobject.Name)];"
                                    $rowcount = Invoke-DbaQuery -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $db.Name -Query $query -As SingleValue
                                    if ($rowcount -eq 0) {
                                        $identityValues.CurrentIdentity = 0
                                    }
                                }
                            } catch {
                                Write-Message -Level VeryVerbose -Message "$query" -FunctionName Invoke-DbaDbDataGenerator -ModuleName "dbatools"
                                $errormessage = $_.Exception.Message.ToString()
                                Stop-Function -Message "Error getting identity values from $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $query -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataGenerator
                            }

                            $insertQuery += "SET IDENTITY_INSERT [$($tableobject.Schema)].[$($tableobject.Name)] ON;`n"
                        }

                        $insertQuery += "INSERT INTO [$($tableobject.Schema)].[$($tableobject.Name)] ([$($tablecolumns.Name -join '],[')])`nVALUES`n"

                        [int]$nextIdentity = $null

                        for ($i = 1; $i -le $tableobject.Rows; $i++) {
                            $columnValues = @()

                            foreach ($columnobject in $tablecolumns) {

                                if ($columnobject.ColumnType -notin $supportedDataTypes) {
                                    Stop-Function -Message "Unsupported data type '$($columnobject.ColumnType)' for column $($columnobject.Name)" -Target $columnobject -FunctionName Invoke-DbaDbDataGenerator -Continue
                                }

                                if ($columnobject.MaskingType -notin $supportedFakerMaskingTypes) {
                                    Stop-Function -Message "Unsupported masking type '$($columnobject.MaskingType)' for column $($columnobject.Name)" -Target $columnobject -FunctionName Invoke-DbaDbDataGenerator -Continue
                                }

                                if ($columnobject.SubType -notin $supportedFakerSubTypes) {
                                    Stop-Function -Message "Unsupported masking sub type '$($columnobject.SubType)' for column $($columnobject.Name)" -Target $columnobject -FunctionName Invoke-DbaDbDataGenerator -Continue
                                }

                                # make sure max is good
                                if ($columnobject.Nullable -and (($nullmod++) % $ModulusFactor -eq 0)) {
                                    $columnValue = $null
                                } elseif ($tableobject.HasUniqueIndex -and $columnobject.Name -in $uniqueValueColumns) {

                                    if ($uniqueValues.Count -lt 1) {
                                        Stop-Function -Message "Could not find any unique values in dictionary" -Target $tableobject -FunctionName Invoke-DbaDbDataGenerator
                                        return
                                    }

                                    $columnValue = $uniqueValues[$rowNumber].$($columnobject.Name)

                                } elseif ($columnobject.Identity) {
                                    if ($nextIdentity -or (-not $nextIdentity -and $tableobject.TruncateTable)) {
                                        $nextIdentity += $identityValues.IdentityIncrement
                                    } else {
                                        $nextIdentity = $identityValues.CurrentIdentity + $identityValues.IdentityIncrement
                                    }
                                    $columnValue = $nextIdentity
                                } else {

                                    if ($columnobject.CharacterString) {
                                        $charstring = $columnobject.CharacterString
                                    } else {
                                        $charstring = $CharacterString
                                    }

                                    if (($columnobject.MinValue -or $columnobject.MaxValue) -and ($columnobject.ColumnType -match 'date')) {
                                        if (-not $columnobject.MinValue) {
                                            $columnobject.MinValue = (Get-Date -Date $columnobject.MaxValue).AddDays(-365)
                                        }
                                        if (-not $columnobject.MaxValue) {
                                            $columnobject.MaxValue = (Get-Date -Date $columnobject.MinValue).AddDays(365)
                                        }
                                    }

                                    try {
                                        if ($MaxValue -and $columnobject.SubType -eq 'String' -and $columnobject.MaxValue -gt $MaxValue) {
                                            $columnobject.MaxValue = $MaxValue
                                        }
                                        if ($columnobject.ColumnType -in $supportedDataTypes -and $columnobject.MaskingType -eq 'Random' -and $columnobject.SubType -in 'Bool', 'Number', 'Float', 'Byte', 'String') {
                                            $randomParams = @{
                                                DataType        = $columnobject.ColumnType
                                                CharacterString = $charstring
                                                Locale          = $Locale
                                                Min             = $columnobject.MinValue
                                                Max             = $columnobject.MaxValue
                                            }
                                            $columnValue = Get-DbaRandomizedValue @randomParams
                                        } else {
                                            $randomParams = @{
                                                RandomizerType    = $columnobject.MaskingType
                                                RandomizerSubtype = $columnobject.SubType
                                                CharacterString   = $charstring
                                                Locale            = $Locale
                                                Min               = $columnobject.MinValue
                                                Max               = $columnobject.MaxValue
                                            }
                                            $columnValue = Get-DbaRandomizedValue @randomParams
                                        }

                                    } catch {
                                        Stop-Function -Message "Failure" -Target $script:faker -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataGenerator
                                    }

                                }

                                if ($null -eq $columnValue -and $columnobject.Nullable -eq $true) {
                                    $columnValues += 'NULL'
                                } elseif ($columnobject.ColumnType -eq 'xml') {
                                    # nothing, unsure how i'll handle this
                                } elseif ($columnobject.ColumnType -in 'uniqueidentifier') {
                                    $columnValues += "'$columnValue'"
                                } elseif ($columnobject.ColumnType -match 'int') {
                                    $columnValues += "$columnValue"
                                } elseif ($columnobject.ColumnType -in 'bit', 'bool') {
                                    if ($columnValue) {
                                        $columnValues += "1"
                                    } else {
                                        $columnValues += "0"
                                    }
                                } else {
                                    $columnValue = ($columnValue).Tostring().Replace("'", "''")
                                    $columnValues += "'$columnValue'"
                                }
                            }

                            if ($i -lt $tableobject.Rows) {
                                $insertQuery += "( $($columnValues -join ',') ),`n"
                            } else {
                                $insertQuery += "( $($columnValues -join ',') );`n"
                            }
                        }

                        if ($tableobject.Columns.Identity -contains $true) {
                            $insertQuery += "SET IDENTITY_INSERT [$($tableobject.Schema)].[$($tableobject.Name)] OFF;"
                        }

                        try {
                            $transaction = $sqlconn.BeginTransaction()
                            $sqlcmd = New-Object Microsoft.Data.SqlClient.SqlCommand($insertQuery, $sqlconn, $transaction)
                            $null = $sqlcmd.ExecuteNonQuery()
                        } catch {
                            Write-Message -Level VeryVerbose -Message "$insertQuery" -FunctionName Invoke-DbaDbDataGenerator -ModuleName "dbatools"
                            $errormessage = $_.Exception.Message.ToString()
                            Stop-Function -Message "Error inserting $($tableobject.Schema).$($tableobject.Name): $errormessage" -Target $insertQuery -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataGenerator
                        }


                    }

                    try {
                        $null = $transaction.Commit()
                        [PSCustomObject]@{
                            ComputerName = $db.Parent.ComputerName
                            InstanceName = $db.Parent.ServiceName
                            SqlInstance  = $db.Parent.DomainInstanceName
                            Database     = $db.Name
                            Schema       = $tableobject.Schema
                            Table        = $tableobject.Name
                            Columns      = $tableobject.Columns.Name
                            Rows         = $tableobject.Rows
                            Elapsed      = [prettytimespan]$elapsed.Elapsed
                            Status       = "Done"
                        }
                    } catch {
                        Stop-Function -Message "Error inserting into $($tableobject.Schema).$($tableobject.Name)" -Target $insertQuery -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataGenerator
                    }
                }
            }

            try {
                $sqlconn.Close()
            } catch {
                Stop-Function -Message "Failure" -Continue -ErrorRecord $_ -FunctionName Invoke-DbaDbDataGenerator
            }
        }
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __dgProcess = @{ Interrupted = [bool]($__iv -and $__iv.Value); UniqueValueColumns = $uniqueValueColumns; Transaction = $transaction; Elapsed = $elapsed } }
} $SqlInstance $SqlCredential $Database $FilePath $Locale $CharacterString $Table $Column $ExcludeTable $ExcludeColumn $MaxValue $ModulusFactor $EnableException $supportedDataTypes $supportedFakerMaskingTypes $supportedFakerSubTypes $__realCmdlet $__boundVerbose $__boundDebug $__carriedUniqueValueColumns $__carriedTransaction $__carriedElapsed @__commonParameters 3>&1 2>&1
""";
}
