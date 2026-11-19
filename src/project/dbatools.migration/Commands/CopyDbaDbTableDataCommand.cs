#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Streams table or view data between SQL Server instances with SqlBulkCopy. Port of
/// public/Copy-DbaDbTableData.ps1. The whole workflow rides module-scoped PowerShell hops: the body
/// leans on Get-DbaDbTable/Get-DbaDbView, the private Get-ObjectNameParts, Export-DbaScript,
/// Invoke-DbaQuery, the prettytimespan accelerator and a SqlRowsCopied event closure, all of which
/// keep the retired function's engine semantics there. The compiled cmdlet supplies the real
/// ShouldProcess runtime. Surface pinned by migration/baselines/Copy-DbaDbTableData.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaDbTableData", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaDbTableDataCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Destination SQL Server instances.</summary>
    [Parameter(Position = 2)]
    public DbaInstanceParameter[]? Destination { get; set; }

    /// <summary>Alternative credential for the destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Source database holding the table or view to copy from.</summary>
    [Parameter(Position = 4)]
    public string? Database { get; set; }

    /// <summary>Target database the copied data is written to.</summary>
    [Parameter(Position = 5)]
    public string? DestinationDatabase { get; set; }

    /// <summary>Source table names, 2-part or 3-part.</summary>
    [Parameter(Position = 6)]
    public string[]? Table { get; set; }

    /// <summary>Source view names, 2-part or 3-part.</summary>
    [Parameter(Position = 7)]
    public string[]? View { get; set; }

    /// <summary>Custom SELECT used as the data source instead of the whole object.</summary>
    [Parameter(Position = 8)]
    public string? Query { get; set; }

    /// <summary>Keep name-based column mapping when -Query is used.</summary>
    [Parameter]
    public SwitchParameter ForceExplicitMapping { get; set; }

    /// <summary>Create the destination table from the source structure when it is missing.</summary>
    [Parameter]
    public SwitchParameter AutoCreateTable { get; set; }

    /// <summary>Rows per bulk copy batch.</summary>
    [Parameter(Position = 9)]
    public int BatchSize { get; set; } = 50000;

    /// <summary>Rows between progress notifications.</summary>
    [Parameter(Position = 10)]
    public int NotifyAfter { get; set; } = 5000;

    /// <summary>Target table name.</summary>
    [Parameter(Position = 11)]
    public string? DestinationTable { get; set; }

    /// <summary>Drop the default TABLOCK on the destination table.</summary>
    [Parameter]
    public SwitchParameter NoTableLock { get; set; }

    /// <summary>Check constraints during the bulk copy.</summary>
    [Parameter]
    public SwitchParameter CheckConstraints { get; set; }

    /// <summary>Fire INSERT triggers during the bulk copy.</summary>
    [Parameter]
    public SwitchParameter FireTriggers { get; set; }

    /// <summary>Preserve source identity values.</summary>
    [Parameter]
    public SwitchParameter KeepIdentity { get; set; }

    /// <summary>Preserve source NULLs instead of destination defaults.</summary>
    [Parameter]
    public SwitchParameter KeepNulls { get; set; }

    /// <summary>Truncate the destination table before copying.</summary>
    [Parameter]
    public SwitchParameter Truncate { get; set; }

    /// <summary>Seconds the bulk copy may run before timing out.</summary>
    [Parameter(Position = 12)]
    public int BulkCopyTimeout { get; set; } = 5000;

    /// <summary>Seconds the source query may run before timing out.</summary>
    [Parameter(Position = 13)]
    public int CommandTimeout { get; set; }

    /// <summary>Script new tables onto the destination's default filegroup.</summary>
    [Parameter]
    public SwitchParameter UseDefaultFileGroup { get; set; }

    /// <summary>Scripting options governing an auto-created destination table.</summary>
    [Parameter(Position = 14)]
    public Microsoft.SqlServer.Management.Smo.ScriptingOptions? ScriptingOptionsObject { get; set; }

    /// <summary>Table or view objects from Get-DbaDbTable or Get-DbaDbView.</summary>
    [Parameter(Position = 15, ValueFromPipeline = true)]
    public Microsoft.SqlServer.Management.Smo.TableViewBase[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The begin block's two products. They depend only on parameters that cannot arrive by
    // pipeline, so they are computed once: recreating the ScriptingOptions per record would hand
    // Export-DbaScript a different object than the single one the function built.
    private object? _bulkCopyOptions;
    private object? _defaultFGScriptingOption;

    // Cross-record carriers (DEF-008). The source's process-block locals are FUNCTION-scoped and
    // survive between piped records; each hop record runs in a fresh scope, so every local that is
    // READ on a path no same-record assignment dominates has to ride back and forth.
    //
    // $Destination: "if (-not $Destination) { $Destination = $server }" only assigns when the
    // caller left it unbound, so record 2 of a pipe reads the instance record 1 latched - even
    // when the two tables come from different servers.
    //
    // $Database: reassigned from the piped object inside the loop, then read by the -SqlInstance
    // branch at the top of the NEXT record.
    //
    // $cmd/$bulkCopy/$elapsed/$destColumns: assigned under the "Copy data from" ShouldProcess gate
    // and read under the separate "Writing rows to" gate. Two gates means an interactive caller can
    // decline the first and accept the second, which reaches the previous record's objects.
    //
    // Not carried, with the dominance proof: $server, $SourceObject, $newTableParts, $connstring,
    // $fqtnfrom, $fqtndest, $desttable, $sourceLabel and $orderByClause are assigned
    // unconditionally before every read; $destServer's only failure path is a Stop-Function
    // -Continue that binds to the destination loop guarding the read; $DestinationTable,
    // $DestinationDatabase and $Query are reassigned whenever their bound-flag branch is taken and
    // hold the caller's constant otherwise; $orderColumns is read only inside the branch that
    // assigns it; $script:prevRowsCopied/$script:totalRowsCopied are module-scoped in both worlds
    // and carry themselves. $InputObject is rebound per record by the engine in both worlds, so
    // the "+=" accumulation resets identically.
    private object? _database;
    private object? _destination;
    private object? _cmd;
    private object? _bulkCopy;
    private object? _elapsed;
    private object? _destColumns;

    protected override void BeginProcessing()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__CopyDbaDbTableDataBeginComplete"]?.Value))
            {
                _bulkCopyOptions = UnwrapHopValue(item.Properties["bulkCopyOptions"]?.Value);
                _defaultFGScriptingOption = UnwrapHopValue(item.Properties["defaultFGScriptingOption"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, BeginScript,
            NoTableLock.ToBool(), CheckConstraints.ToBool(), FireTriggers.ToBool(),
            KeepIdentity.ToBool(), KeepNulls.ToBool(), UseDefaultFileGroup.ToBool(),
            ScriptingOptionsObject, EnableException.ToBool(),
            TestBound(nameof(ScriptingOptionsObject)),
            NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // No Interrupted guard: the source has no Test-FunctionInterrupt, so a Stop-Function that ends
    // one record still lets the next piped record run, and gating here would swallow it.
    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__CopyDbaDbTableDataProcessComplete"]?.Value))
            {
                _database = UnwrapHopValue(item.Properties["Database"]?.Value);
                _destination = UnwrapHopValue(item.Properties["Destination"]?.Value);
                _cmd = UnwrapHopValue(item.Properties["cmd"]?.Value);
                _bulkCopy = UnwrapHopValue(item.Properties["bulkCopy"]?.Value);
                _elapsed = UnwrapHopValue(item.Properties["elapsed"]?.Value);
                _destColumns = UnwrapHopValue(item.Properties["destColumns"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            SqlInstance, SqlCredential, _destination ?? Destination, DestinationSqlCredential,
            _database ?? Database, DestinationDatabase, Table, View, Query,
            ForceExplicitMapping.ToBool(), AutoCreateTable.ToBool(), BatchSize, NotifyAfter,
            DestinationTable, NoTableLock.ToBool(), CheckConstraints.ToBool(),
            FireTriggers.ToBool(), KeepIdentity.ToBool(), KeepNulls.ToBool(), Truncate.ToBool(),
            BulkCopyTimeout, CommandTimeout, UseDefaultFileGroup.ToBool(), ScriptingOptionsObject,
            InputObject, EnableException.ToBool(), _bulkCopyOptions, _defaultFGScriptingOption,
            _cmd, _bulkCopy, _elapsed, _destColumns,
            TestBound(nameof(InputObject)), TestBound(nameof(SqlInstance)),
            TestBound(nameof(Database)), TestBound(nameof(Table)), TestBound(nameof(View)),
            TestBound(nameof(Destination)), TestBound(nameof(DestinationDatabase)),
            TestBound(nameof(DestinationTable)), TestBound(nameof(Query)), this,
            NestedCommand.BoundCommonParameter(this, "WhatIf"),
            NestedCommand.BoundCommonParameter(this, "Confirm"),
            NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // Carried hop state arrives PSObject-wrapped. A PSCustomObject carries its content on the
    // wrapper rather than the BaseObject, so unwrapping one would discard it - keep it wrapped.
    private static object? UnwrapHopValue(object? value)
    {
        if (value is null || ReferenceEquals(value, System.Management.Automation.Internal.AutomationNull.Value))
            return null;
        if (value is not PSObject wrapper)
            return value;
        return wrapper.BaseObject is PSCustomObject ? wrapper : wrapper.BaseObject;
    }

    // PS: the begin block. Get-Variable reads the option switches out of this scope by NAME, so
    // every one of them has to be a parameter here even though the block never names them.
    private const string BeginScript = """
param($NoTableLock, $CheckConstraints, $FireTriggers, $KeepIdentity, $KeepNulls, $UseDefaultFileGroup, $ScriptingOptionsObject, $EnableException, $__boundScriptingOptionsObject, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    # The flag parameters are deliberately untyped: PowerShell excludes [switch] parameters from
    # positional binding, so one typed flag would shift every argument after it. They arrive as
    # real booleans, which Get-Variable and the -eq $true test read the same way a switch reads.
    param($NoTableLock, $CheckConstraints, $FireTriggers, $KeepIdentity, $KeepNulls, $UseDefaultFileGroup, [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject, $EnableException, $__boundScriptingOptionsObject)

    $bulkCopyOptions = 0
    $options = "TableLock", "CheckConstraints", "FireTriggers", "KeepIdentity", "KeepNulls", "Default"

    foreach ($option in $options) {
        $optionValue = Get-Variable $option -ValueOnly -ErrorAction SilentlyContinue
        if ($option -eq "TableLock" -and (!$NoTableLock)) {
            $optionValue = $true
        }
        if ($optionValue -eq $true) {
            $bulkCopyOptions += $([Microsoft.Data.SqlClient.SqlBulkCopyOptions]::$option).value__
        }
    }

    if ($__boundScriptingOptionsObject) {
        $defaultFGScriptingOption = @{
            ScriptingOptionsObject = $ScriptingOptionsObject
        }
    } else {
        $defaultFGScriptingOption = @{
            ScriptingOptionsObject = $(
                $so = New-DbaScriptingOption
                $so.NoFileGroup = $UseDefaultFileGroup
                $so
            )
        }
    }

    [PSCustomObject]@{
        __CopyDbaDbTableDataBeginComplete = $true
        bulkCopyOptions                   = $bulkCopyOptions
        defaultFGScriptingOption          = $defaultFGScriptingOption
    }
} $NoTableLock $CheckConstraints $FireTriggers $KeepIdentity $KeepNulls $UseDefaultFileGroup $ScriptingOptionsObject $EnableException $__boundScriptingOptionsObject @__commonParameters 3>&1 2>&1
""";

    // PS: the process block, verbatim apart from the Test-Bound reads becoming carried bound flags,
    // $Pscmdlet.ShouldProcess becoming $__realCmdlet.ShouldProcess, and the -FunctionName/-ModuleName
    // attribution. The body is dot-sourced so its seven early returns end the record without
    // skipping the cross-record sentinel that follows them.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Destination, $DestinationSqlCredential, $Database, $DestinationDatabase, $Table, $View, $Query, $ForceExplicitMapping, $AutoCreateTable, $BatchSize, $NotifyAfter, $DestinationTable, $NoTableLock, $CheckConstraints, $FireTriggers, $KeepIdentity, $KeepNulls, $Truncate, $BulkCopyTimeout, $CommandTimeout, $UseDefaultFileGroup, $ScriptingOptionsObject, $InputObject, $EnableException, $bulkCopyOptions, $defaultFGScriptingOption, $cmd, $bulkCopy, $elapsed, $destColumns, $__boundInputObject, $__boundSqlInstance, $__boundDatabase, $__boundTable, $__boundView, $__boundDestination, $__boundDestinationDatabase, $__boundDestinationTable, $__boundQuery, $__realCmdlet, $__boundWhatIf, $__boundConfirm, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundWhatIf) { $__commonParameters.WhatIf = [bool]$__boundWhatIf }
if ($null -ne $__boundConfirm) { $__commonParameters.Confirm = [bool]$__boundConfirm }
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    # The flag parameters are deliberately untyped, for the positional-binding reason above. The
    # carried locals ($cmd, $bulkCopy, $elapsed, $destColumns) are untyped because they are $null
    # on the first record, exactly as the function's own locals are.
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, [PSCredential]$DestinationSqlCredential, [string]$Database, [string]$DestinationDatabase, [string[]]$Table, [string[]]$View, [string]$Query, $ForceExplicitMapping, $AutoCreateTable, [int]$BatchSize, [int]$NotifyAfter, [string]$DestinationTable, $NoTableLock, $CheckConstraints, $FireTriggers, $KeepIdentity, $KeepNulls, $Truncate, [int]$BulkCopyTimeout, [int]$CommandTimeout, $UseDefaultFileGroup, [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject, [Microsoft.SqlServer.Management.Smo.TableViewBase[]]$InputObject, $EnableException, $bulkCopyOptions, $defaultFGScriptingOption, $cmd, $bulkCopy, $elapsed, $destColumns, $__boundInputObject, $__boundSqlInstance, $__boundDatabase, $__boundTable, $__boundView, $__boundDestination, $__boundDestinationDatabase, $__boundDestinationTable, $__boundQuery, $__realCmdlet)

    . {
        if ((-not $__boundInputObject) -and ((-not ($__boundSqlInstance -and $__boundDatabase)) -or (-not ($__boundTable -or $__boundView)))) {
            Stop-Function -Message "You must pipe in a table or specify SqlInstance, Database and [View|Table]." -FunctionName Copy-DbaDbTableData
            return
        }

        # determine if -Table or -View was used
        $SourceObject = $Table
        if ($__boundView -and $__boundTable) {
            Stop-Function -Message "Only one of [View|Table] may be specified." -FunctionName Copy-DbaDbTableData
            return
        } elseif ( $__boundView ) {
            $SourceObject = $View
        }

        if ($SqlInstance) {
            if ((-not ($__boundDestination -or $__boundDestinationDatabase -or $__boundDestinationTable))) {
                Stop-Function -Message "Cannot copy $SourceObject into itself. One of the parameters Destination (Server), DestinationDatabase, or DestinationTable must be specified " -Target $SourceObject -FunctionName Copy-DbaDbTableData
                return
            }

            try {
                # Ensuring that the default db connection is to the passed in $Database instead of the master db. This way callers don't have to remember to do 3 part queries.
                $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Copy-DbaDbTableData
                return
            }

            try {
                foreach ($sourceDataObject in $SourceObject) {
                    $dbObject = $null

                    if ( $__boundView ) {
                        $dbObject = Get-DbaDbView -SqlInstance $server -View $sourceDataObject -Database $Database -EnableException -Verbose:$false
                    } else {
                        $dbObject = Get-DbaDbTable -SqlInstance $server -Table $sourceDataObject -Database $Database -EnableException -Verbose:$false
                    }

                    if ($dbObject.Count -eq 1) {
                        $InputObject += $dbObject
                    } else {
                        Stop-Function -Message "The object $sourceDataObject matches $($dbObject.Count) objects. Unable to determine which object to copy" -Continue -FunctionName Copy-DbaDbTableData
                    }
                }
            } catch {
                Stop-Function -Message "Unable to determine source : $SourceObject" -FunctionName Copy-DbaDbTableData
                return
            }
        }

        foreach ($sqlObject in $InputObject) {
            $Database = $sqlObject.Parent.Name
            $server = $sqlObject.Parent.Parent

            if ((-not $__boundDestinationTable)) {
                $DestinationTable = '[' + $sqlObject.Schema + '].[' + $sqlObject.Name + ']'
            }

            $newTableParts = Get-ObjectNameParts -ObjectName $DestinationTable
            #using FQTN to determine database name
            if ($newTableParts.Database) {
                $DestinationDatabase = $newTableParts.Database
            } elseif ((-not $__boundDestinationDatabase)) {
                $DestinationDatabase = $Database
            }

            if (-not $Destination) {
                $Destination = $server
            }

            foreach ($destinstance in $Destination) {
                try {
                    $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -Database $DestinationDatabase
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaDbTableData
                }

                if ($DestinationDatabase -notin $destServer.Databases.Name) {
                    Stop-Function -Message "Database $DestinationDatabase doesn't exist on $destServer" -FunctionName Copy-DbaDbTableData
                    return
                }

                $desttable = Get-DbaDbTable -SqlInstance $destServer -Table $DestinationTable -Database $DestinationDatabase -Verbose:$false | Select-Object -First 1
                if (-not $desttable -and $AutoCreateTable) {
                    try {
                        $tablescript = $null
                        $schemaNameToReplace = $null
                        $tableNameToReplace = $null
                        if ( $__boundView ) {
                            #select view into tempdb to generate script
                            $tempTableName = "$($sqlObject.Name)_table"
                            $createquery = "SELECT * INTO tempdb..$tempTableName FROM [$($sqlObject.Schema)].[$($sqlObject.Name)] WHERE 1=2"
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -Query $createquery -EnableException
                            #refreshing table list to make sure get-dbadbtable will find the new table
                            $server.Databases['tempdb'].Tables.Refresh($true)
                            $tempTable = Get-DbaDbTable -SqlInstance $server -Database tempdb -Table $tempTableName
                            # need these for generating the script of the table and then replacing the schema and name
                            $schemaNameToReplace = $tempTable.Schema
                            $tableNameToReplace = $tempTable.Name
                            $tablescript = $tempTable |
                                Export-DbaScript @defaultFGScriptingOption -Passthru |
                                Out-String
                            # cleanup
                            Invoke-DbaQuery -SqlInstance $server -Database $Database -Query "DROP TABLE tempdb..$tempTableName" -EnableException
                        } else {
                            $tablescript = $sqlObject |
                                Export-DbaScript @defaultFGScriptingOption -Passthru |
                                Out-String
                            $schemaNameToReplace = $sqlObject.Schema
                            $tableNameToReplace = $sqlObject.Name
                        }

                        #replacing table name
                        if ($newTableParts.Name) {
                            $rX = "(CREATE|ALTER)( TABLE \[$([regex]::Escape($schemaNameToReplace))\]\.\[)$([regex]::Escape($tableNameToReplace))(\])"
                            $tablescript = $tablescript -replace $rX, "`${1}`${2}$($newTableParts.Name)`${3}"
                        }
                        #replacing table schema
                        if ($newTableParts.Schema) {
                            $rX = "(CREATE|ALTER)( TABLE \[)$([regex]::Escape($schemaNameToReplace))(\]\.\[$([regex]::Escape($newTableParts.Name))\])"
                            $tablescript = $tablescript -replace $rX, "`${1}`${2}$($newTableParts.Schema)`${3}"
                        }

                        if ($__realCmdlet.ShouldProcess($destServer, "Creating new table: $DestinationTable")) {
                            Write-Message -Message "New table script: $tablescript" -Level VeryVerbose -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"
                            Invoke-DbaQuery -SqlInstance $destServer -Database $DestinationDatabase -Query "$tablescript" -EnableException # add some string assurance there
                            #table list was updated, let's grab a fresh one
                            $destServer.Databases[$DestinationDatabase].Tables.Refresh()
                            $desttable = Get-DbaDbTable -SqlInstance $destServer -Table $DestinationTable -Database $DestinationDatabase -Verbose:$false
                            Write-Message -Message "New table created: $desttable" -Level Verbose -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"
                        }
                    } catch {
                        Stop-Function -Message "Unable to determine destination table: $DestinationTable" -ErrorRecord $_ -FunctionName Copy-DbaDbTableData
                        return
                    }
                }
                if (-not $desttable) {
                    Stop-Function -Message "Table $DestinationTable cannot be found in $DestinationDatabase. Use -AutoCreateTable to automatically create the table on the destination." -Continue -FunctionName Copy-DbaDbTableData
                }

                $connstring = $destServer.ConnectionContext.ConnectionString

                if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                    $fqtnfrom = "$sqlObject"
                } else {
                    $fqtnfrom = "$($server.Databases[$Database]).$sqlObject"
                }

                if ($destServer.DatabaseEngineType -eq "SqlAzureDatabase") {
                    $fqtndest = "$desttable"
                } else {
                    $fqtndest = "$($destServer.Databases[$DestinationDatabase]).$desttable"
                }

                if ($fqtndest -eq $fqtnfrom -and $server.Name -eq $destServer.Name -and (-not $__boundQuery)) {
                    Stop-Function -Message "Cannot copy $fqtnfrom on $($server.Name) into $fqtndest on ($destServer.Name). Source and Destination must be different " -Target $Table -FunctionName Copy-DbaDbTableData
                    return
                }


                if (-not $__boundQuery) {
                    # Build ORDER BY clause to ensure consistent row order
                    # This prevents data misalignment when copying tables without explicit ordering
                    $orderByClause = ""

                    # Refresh indexes to ensure we have current metadata
                    $sqlObject.Indexes.Refresh()

                    # Option 1: Use clustered index columns for ordering (most common and performant)
                    $clusteredIndex = $sqlObject.Indexes | Where-Object IsClustered -eq $true | Select-Object -First 1
                    if ($clusteredIndex) {
                        $orderColumns = $clusteredIndex.IndexedColumns | Sort-Object IndexKeyPosition | ForEach-Object {
                            $colName = $_.Name
                            $descending = if ($_.Descending) { " DESC" } else { "" }
                            "[$colName]$descending"
                        }
                        if ($orderColumns) {
                            $orderByClause = " ORDER BY " + ($orderColumns -join ", ")
                            Write-Message -Level Verbose -Message "Using clustered index for ordering: $orderByClause" -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"
                        }
                    }

                    # Option 2: If no clustered index, try primary key
                    if (-not $orderByClause) {
                        $primaryKey = $sqlObject.Indexes | Where-Object IndexKeyType -eq "DriPrimaryKey" | Select-Object -First 1
                        if ($primaryKey) {
                            $orderColumns = $primaryKey.IndexedColumns | Sort-Object IndexKeyPosition | ForEach-Object {
                                $colName = $_.Name
                                $descending = if ($_.Descending) { " DESC" } else { "" }
                                "[$colName]$descending"
                            }
                            if ($orderColumns) {
                                $orderByClause = " ORDER BY " + ($orderColumns -join ", ")
                                Write-Message -Level Verbose -Message "Using primary key for ordering: $orderByClause" -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"
                            }
                        }
                    }

                    # Option 3: If using KeepIdentity and an identity column exists, order by it
                    if (-not $orderByClause -and $KeepIdentity) {
                        $identityColumn = $sqlObject.Columns | Where-Object Identity -eq $true | Select-Object -First 1
                        if ($identityColumn) {
                            $orderByClause = " ORDER BY [$($identityColumn.Name)]"
                            Write-Message -Level Verbose -Message "Using identity column for ordering: $orderByClause" -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"
                        }
                    }

                    # If no ordering found, log a warning for tables without proper keys
                    if (-not $orderByClause) {
                        Write-Message -Level Verbose -Message "No clustered index, primary key, or identity column found for ordering. Row order is not guaranteed." -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"
                    }

                    $Query = "SELECT * FROM $fqtnfrom$orderByClause"
                    $sourceLabel = $fqtnfrom
                } else {
                    $sourceLabel = "Query"
                }
                try {
                    if ($Truncate -eq $true) {
                        if ($__realCmdlet.ShouldProcess($destServer, "Truncating table $fqtndest")) {
                            Invoke-DbaQuery -SqlInstance $destServer -Database $DestinationDatabase -Query "TRUNCATE TABLE $fqtndest" -EnableException
                        }
                    }
                    if ($__realCmdlet.ShouldProcess($server, "Copy data from $sourceLabel")) {
                        $cmd = $server.ConnectionContext.SqlConnectionObject.CreateCommand()
                        $cmd.CommandTimeout = $CommandTimeout
                        $cmd.CommandText = $Query
                        if ($server.ConnectionContext.IsOpen -eq $false) {
                            $server.ConnectionContext.SqlConnectionObject.Open()
                        }
                        $bulkCopy = New-Object Microsoft.Data.SqlClient.SqlBulkCopy("$connstring;Database=$DestinationDatabase", $bulkCopyOptions)
                        $bulkCopy.DestinationTableName = $fqtndest
                        $bulkCopy.EnableStreaming = $true
                        $bulkCopy.BatchSize = $BatchSize
                        $bulkCopy.NotifyAfter = $NotifyAfter
                        $bulkCopy.BulkCopyTimeout = $BulkCopyTimeout

                        # Get list of non-computed columns from destination table to avoid insert failures
                        # Refresh the columns collection to ensure it's populated
                        $desttable.Columns.Refresh()
                        $destColumns = $desttable.Columns | Where-Object Computed -eq $false | Select-Object -ExpandProperty Name
                        Write-Message -Level Verbose -Message "Destination table has $($destColumns.Count) non-computed columns" -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"

                        # The legacy bulk copy library uses a 4 byte integer to track the RowsCopied, so the only option is to use
                        # integer wrap so that copy operations of row counts greater than [int32]::MaxValue will report accurate numbers.
                        # See https://github.com/dataplat/dbatools/issues/6927 for more details
                        $script:prevRowsCopied = [int64]0
                        $script:totalRowsCopied = [int64]0

                        $elapsed = [System.Diagnostics.Stopwatch]::StartNew()
                        # Add RowCount output
                        $bulkCopy.Add_SqlRowsCopied( {

                                $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $args[1].RowsCopied -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                                $tstamp = $(Get-Date -format 'yyyyMMddHHmmss')
                                Write-Message -Level Verbose -Message "[$tstamp] The bulk copy library reported RowsCopied = $($args[1].RowsCopied). The previous RowsCopied = $($script:prevRowsCopied). The adjusted total rows copied = $($script:totalRowsCopied)" -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"

                                $RowsPerSec = [math]::Round($script:totalRowsCopied / $elapsed.ElapsedMilliseconds * 1000.0, 1)
                                Write-Progress -Id 1 -Activity "Inserting rows" -Status ([System.String]::Format("{0} rows ({1} rows/sec)", $script:totalRowsCopied, $RowsPerSec))

                                # save the previous count of rows copied to be used on the next event notification
                                $script:prevRowsCopied = $args[1].RowsCopied
                            })
                    }

                    if ($__realCmdlet.ShouldProcess($destServer, "Writing rows to $fqtndest")) {
                        $reader = $cmd.ExecuteReader()

                        # Only apply explicit column mapping for straight table copies (not custom queries)
                        # Custom queries may have different column names/aliases, so let SqlBulkCopy use ordinal mapping
                        # Appending -ForceExplicitMapping will override this behaviour and keep explicit column mapping
                        if (-not $__boundQuery -or $ForceExplicitMapping) {
                            # Map only columns that exist in both source and destination (excluding computed columns)
                            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                                $sourceColumn = $reader.GetName($i)
                                if ($destColumns -contains $sourceColumn) {
                                    $null = $bulkCopy.ColumnMappings.Add($sourceColumn, $sourceColumn)
                                } else {
                                    Write-Message -Level Verbose -Message "Skipping column '$sourceColumn' (not in destination or is computed)" -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"
                                }
                            }
                        }

                        $bulkCopy.WriteToServer($reader)
                        $finalRowCountReported = Get-BulkRowsCopiedCount $bulkCopy

                        $script:totalRowsCopied += (Get-AdjustedTotalRowsCopied -ReportedRowsCopied $finalRowCountReported -PreviousRowsCopied $script:prevRowsCopied).NewRowCountAdded

                        $RowsTotal = $script:totalRowsCopied
                        $TotalTime = [math]::Round($elapsed.Elapsed.TotalSeconds, 1)
                        Write-Message -Level Verbose -Message "$RowsTotal rows inserted in $TotalTime sec" -FunctionName Copy-DbaDbTableData -ModuleName "dbatools"
                        if ($RowsTotal -gt 0) {
                            Write-Progress -Id 1 -Activity "Inserting rows" -Status "Complete" -Completed
                        }

                        $server.ConnectionContext.SqlConnectionObject.Close()
                        $bulkCopy.Close()
                        $bulkCopy.Dispose()
                        $reader.Close()

                        [PSCustomObject]@{
                            SourceInstance        = $server.Name
                            SourceDatabase        = $Database
                            SourceDatabaseID      = $sqlObject.Parent.ID
                            SourceSchema          = $sqlObject.Schema
                            SourceTable           = $sqlObject.Name
                            DestinationInstance   = $destServer.Name
                            DestinationDatabase   = $DestinationDatabase
                            DestinationDatabaseID = $desttable.Parent.ID
                            DestinationSchema     = $desttable.Schema
                            DestinationTable      = $desttable.Name
                            RowsCopied            = $RowsTotal
                            Elapsed               = [prettytimespan]$elapsed.Elapsed
                        }
                    }
                } catch {
                    Stop-Function -Message "Something went wrong" -ErrorRecord $_ -Target $server -continue -FunctionName Copy-DbaDbTableData
                }
            }
        }
    }

    [PSCustomObject]@{
        __CopyDbaDbTableDataProcessComplete = $true
        Database                            = $Database
        Destination                         = $Destination
        cmd                                 = $cmd
        bulkCopy                            = $bulkCopy
        elapsed                             = $elapsed
        destColumns                         = $destColumns
    }
} $SqlInstance $SqlCredential $Destination $DestinationSqlCredential $Database $DestinationDatabase $Table $View $Query $ForceExplicitMapping $AutoCreateTable $BatchSize $NotifyAfter $DestinationTable $NoTableLock $CheckConstraints $FireTriggers $KeepIdentity $KeepNulls $Truncate $BulkCopyTimeout $CommandTimeout $UseDefaultFileGroup $ScriptingOptionsObject $InputObject $EnableException $bulkCopyOptions $defaultFGScriptingOption $cmd $bulkCopy $elapsed $destColumns $__boundInputObject $__boundSqlInstance $__boundDatabase $__boundTable $__boundView $__boundDestination $__boundDestinationDatabase $__boundDestinationTable $__boundQuery $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
