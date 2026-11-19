#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Applies row/page compression to tables, indexes and indexed views, either from Test-DbaDbCompression
/// recommendations or from an explicit -CompressionType. Port of public/Set-DbaDbCompression.ps1; the
/// workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port, and the largest body in this descent (~260 lines of process). It carries a
/// single Test-Bound - Test-Bound "InputObject" -> $__boundInputObject - which gates whether
/// compression suggestions come from the caller or from a live Test-DbaDbCompression call. That
/// distinction cannot be rewritten as "if ($InputObject)": the source deliberately asks whether the
/// parameter was SUPPLIED, so an explicitly-passed empty/null InputObject must still take the
/// passed-in branch rather than silently re-testing the database.
///
/// ShouldProcess is real (baseline: supportsShouldProcess true, confirmImpact Medium), so all THREE
/// $Pscmdlet.ShouldProcess(...) gates become $__realCmdlet.ShouldProcess(...) with target and action
/// strings byte-for-byte.
///
/// NO continue-guard wrapper is needed. The two bare `continue` statements (status-not-Normal and
/// compatibility-level-too-low) both sit inside the genuine `foreach ($db in $dbs)` loop, and every
/// Stop-Function -Continue site sits inside either that loop or the enclosing
/// `foreach ($instance in $SqlInstance)`. There are no `return` statements at all.
///
/// The body calls the module-private helper Get-ObjectNameParts. That resolves only because the hop
/// executes inside the dbatools module scope via `& $__dbatoolsModule` - it would be CommandNotFound
/// from a plain scriptblock, which is precisely what the module-scoped hop exists to provide.
///
/// PRESERVED SOURCE BUG - do not "fix" this in the port, and note it does NOT reproduce for free.
/// At source line 195 the online-rebuild capability scan iterates `$tables`, but `$tables` is not
/// assigned until line 265, inside the OTHER (explicit -CompressionType) branch. On the EXPLICIT
/// path that means the scan for each database reads the PREVIOUS iteration's table collection,
/// deciding this database's online-rebuild capability from another database's indexes; on the
/// "Recommended" path `$tables` is never assigned at all and the scan body simply never runs.
///
/// WITHIN one record the unmodified body reproduces that by itself. ACROSS records it does not, and
/// that is DEF-012: an advanced function's process-block locals persist across piped records, so the
/// source's record 2 still sees record 1's `$tables`, while a hop resets every body local per
/// record. Measured with a DBATOOLS_LEGACY_FUNCTIONS A/B (one disposable database, instance piped
/// twice, -CompressionType Row): the legacy function reported online rebuilds SUPPORTED on record 2
/// and the unfixed port reported NOT supported - the source issuing ONLINE index rebuilds where the
/// port issued OFFLINE ones, a real difference in locking behaviour on a destructive operation.
///
/// Fixed per the DEF-012 ruling with the established per-row sentinel carry: the affected locals ride
/// __setDbaDbCompressionProcess from each record's end-of-body back into the next record's seed, so
/// the bug is reproduced across records exactly as the source has it. Reproducing a bug faithfully
/// is the requirement; the underlying defect is logged upstream, not repaired here.
///
/// TWO locals are carried, and the second one is the subtler shape:
///   $tables                - read at line 195 before ANY assignment in the record.
///   $compressionSuggestion - assigned ONLY inside conditional branches (the passed-in-InputObject
///                            branch, or the first ShouldProcess gate), but READ at line 231 under a
///                            DIFFERENT gate. Decline the testing gate on record 2 while accepting
///                            the applying gate and the source reads record 1's suggestions, where an
///                            uncarried port would see nothing and silently apply nothing.
/// The second was found by review, not by my detector: a source-order walk sees an assignment textually
/// before the read and calls it safe. That gap is now closed in the detector as the CROSS-BRANCH rule
/// (an assignment dominates a read only if it is unconditional at some enclosing block level).
///
/// RESIDUAL, stated rather than hidden: the sentinel is emitted at the end of the body, so if the
/// body throws out of the hop entirely (an -EnableException path - every Stop-Function site here
/// uses -Continue, so this is narrow) that record's state is not carried, whereas the function's
/// scope would still have held it. Reproducing that too would need the carry to survive an
/// exception unwind, which the current InvokeScoped contract does not offer. Reviewed and accepted:
/// a terminating error that escapes the hop ends the command pipeline, so no subsequent record
/// survives to observe the lost state.
///
/// -InputObject is deliberately `object` and NOT an array: the source declares it untyped
/// (`$InputObject`, no type constraint) and the baseline records System.Object at position 8.
/// Narrowing it to a typed array would change binding for the Test-DbaDbCompression pipeline.
///
/// The two switches ForceOfflineRebuilds and SortInTempDB are passed as carried BOOL VALUES, not as
/// bound flags, because the body only ever reads their VALUE (`!$ForceOfflineRebuilds`,
/// `if ($SortInTempDB)`, and the SMO assignment `$underlyingObj.SortInTempdb = $SortInTempDB`) and
/// never asks whether they were bound.
///
/// Other body edits are -FunctionName Set-DbaDbCompression attribution stamping on the direct
/// Stop-Function and Write-Message sites.
///
/// Surface pinned by migration/baselines/Set-DbaDbCompression.json
/// (sourceSha256 ba6601c5bcf9fde9cce8d5cc4e876c8af0985ac60aee79d6490ab7ebdedc5a2c):
/// DefaultParameterSetName "Default"; SqlInstance 0 MANDATORY + ValueFromPipeline, SqlCredential 1,
/// Database 2, ExcludeDatabase 3, Table 4, CompressionType 5, MaxRunTime 6, PercentCompression 7,
/// InputObject 8; ForceOfflineRebuilds / SortInTempDB non-positional switches; outputType empty.
/// Positions are declared EXPLICITLY per the positional-binding-loss class ruling: an advanced
/// function gets implicit positional binding, a compiled cmdlet does not.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaDbCompression", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium, DefaultParameterSetName = "Default")]
public sealed class SetDbaDbCompressionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
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

    /// <summary>The table(s) to process.</summary>
    [Parameter(Position = 4)]
    public string[]? Table { get; set; }

    /// <summary>Compression type to apply, or Recommended to use Test-DbaDbCompression results.</summary>
    [Parameter(Position = 5)]
    [PsStringCast]
    [ValidateSet("Recommended", "Page", "Row", "None")]
    public string CompressionType { get; set; } = "Recommended";

    /// <summary>Maximum run time in minutes; 0 means no limit.</summary>
    [Parameter(Position = 6)]
    public int MaxRunTime { get; set; } = 0;

    /// <summary>Minimum percent compression required before an object is processed.</summary>
    [Parameter(Position = 7)]
    public int PercentCompression { get; set; } = 0;

    /// <summary>Compression suggestions piped in from Test-DbaDbCompression. Untyped, per the source.</summary>
    [Parameter(Position = 8)]
    public object? InputObject { get; set; }

    /// <summary>Force offline rebuilds even where online rebuilds are supported.</summary>
    [Parameter]
    public SwitchParameter ForceOfflineRebuilds { get; set; }

    /// <summary>Sort in tempdb during index rebuilds.</summary>
    [Parameter]
    public SwitchParameter SortInTempDB { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // DEF-012 cross-record carry. $tables is READ by the online-rebuild scan before anything assigns
    // it in this record, so in the source it holds whatever the PREVIOUS record left behind. A hop
    // resets body locals per record, which loses that. This field is the per-row sentinel carry
    // mandated by the DEF-012 ruling: seeded null for the first record, then refreshed from each
    // record's end-of-body sentinel so the next record sees exactly what the function would have.
    private object? _carriedTables;
    private object? _carriedCompressionSuggestion;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__setDbaDbCompressionProcess"))
            {
                if (sentinel["__setDbaDbCompressionProcess"] is Hashtable state)
                {
                    _carriedTables = state["Tables"];
                    _carriedCompressionSuggestion = state["CompressionSuggestion"];
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
            SqlInstance, SqlCredential, Database, ExcludeDatabase, Table,
            CompressionType, MaxRunTime, PercentCompression,
            ForceOfflineRebuilds.ToBool(), SortInTempDB.ToBool(),
            InputObject, EnableException.ToBool(),
            TestBound(nameof(InputObject)), _carriedTables, _carriedCompressionSuggestion,
            this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block verbatim. Edits: Test-Bound "InputObject" -> $__boundInputObject,
    // the three $Pscmdlet -> $__realCmdlet, and -FunctionName Set-DbaDbCompression on the direct
    // Stop-Function and Write-Message sites. The $tables-before-assignment bug at the online-rebuild
    // scan is PRESERVED deliberately (see the class remarks).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $Table, $CompressionType, $MaxRunTime, $PercentCompression, $ForceOfflineRebuilds, $SortInTempDB, $InputObject, $EnableException, $__boundInputObject, $__carriedTables, $__carriedCompressionSuggestion, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [string[]]$Table, [string]$CompressionType, [int]$MaxRunTime, [int]$PercentCompression, $ForceOfflineRebuilds, $SortInTempDB, $InputObject, $EnableException, $__boundInputObject, $__carriedTables, $__carriedCompressionSuggestion, $__realCmdlet, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # DEF-012 carry (hop mechanism, not source): re-seed the cross-record local the source would
    # still be holding from the previous record. Must precede the body so the line-195 scan reads it.
    $tables = $__carriedTables
    $compressionSuggestion = $__carriedCompressionSuggestion

    $starttime = Get-Date
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Set-DbaDbCompression
        }

        #The reason why we do this is because of SQL 2016 and they now allow for compression on standard edition.
        if ($server.EngineEdition -notmatch 'Enterprise' -and $server.VersionMajor -lt '13') {
            Stop-Function -Message "Only SQL Server Enterprise Edition supports compression on $server" -Target $server -Continue -FunctionName Set-DbaDbCompression
        }
        $dbs = $server.Databases | Where-Object { $_.IsAccessible -and $_.IsSystemObject -eq 0 }
        if ($Database) {
            $dbs = $dbs | Where-Object { $_.Name -in $Database }
        }
        if ($ExcludeDatabase) {
            $dbs = $dbs | Where-Object { $_.Name -NotIn $ExcludeDatabase }
        }
        foreach ($db in $dbs) {
            Write-Message -Level Verbose -Message "Querying $instance - $db" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
            if ($db.Status -ne 'Normal') {
                Write-Message -Level Warning -Message "$db has status $($db.Status) and will be skipped." -Target $db -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                continue
            }
            if ($db.CompatibilityLevel -lt 'Version100') {
                Write-Message -Level Warning -Message "$db has a compatibility level lower than Version100 and will be skipped." -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                continue
            }
            $isOnlineRebuildSupported = $false
            # Loop on indexes to see if Rebuild Online is supported
            $onlineRebuildScanCompleted = $false
            foreach ($obj in $tables | Where-Object { !$_.IsMemoryOptimized -and !$_.HasSparseColumn }) {
                if ($onlineRebuildScanCompleted) {
                    break
                }
                foreach ($index in $($obj.Indexes | Where-Object { !$_.IsMemoryOptimized -and $_.IndexType -notmatch 'Columnstore' })) {
                    if ($index.IsOnlineRebuildSupported -or $server.isAzure) {
                        $isOnlineRebuildSupported = $true
                        $onlineRebuildScanCompleted = $true
                        break
                    }
                }
            }
            Write-Message -Level Verbose -Message "Are Online Rebuilds supported ? $isOnlineRebuildSupported" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
            $CanDoOnlineOperation = $false
            if ($IsOnlineRebuildSupported -and !$ForceOfflineRebuilds) {
                $CanDoOnlineOperation = $true
                Write-Message -Level Verbose -Message "Using Online Rebuilds where possible" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
            }

            if ($CompressionType -eq "Recommended") {
                if ($__boundInputObject) {
                    Write-Message -Level Verbose -Message "Using passed in compression suggestions" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                    $compressionSuggestion = $InputObject | Where-Object { $_.Database -eq $db.Name }
                } else {
                    if ($__realCmdlet.ShouldProcess($db, "Testing database for compression suggestions on $instance")) {
                        try {
                            $compressionSuggestion = Test-DbaDbCompression -SqlInstance $server -Database $db.Name -Table $Table -EnableException
                        } catch {
                            Stop-Function -Message "Unable to test database compression suggestions for $instance - $db" -Target $db -ErrorRecord $_ -Continue -FunctionName Set-DbaDbCompression
                        }
                    }
                }

                if ($__realCmdlet.ShouldProcess($db, "Applying suggested compression using results from Test-DbaDbCompression")) {
                    $objects = $compressionSuggestion | Select-Object *, @{l = 'AlreadyProcessed'; e = { "False" } }
                    foreach ($obj in ($objects | Where-Object { $_.CompressionTypeRecommendation -notin @('NO_GAIN', '?') -and $_.PercentCompression -ge $PercentCompression } | Sort-Object PercentCompression -Descending)) {
                        if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                            Write-Message -Level Warning -Message "Reached max run time of $MaxRunTime" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                            break
                        }
                        if ($obj.indexId -le 1) {
                            ##heaps and clustered indexes
                            Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName)" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                            try {
                                ($server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $obj.Partition }).DataCompression = $obj.CompressionTypeRecommendation
                                $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].OnlineHeapOperation = $CanDoOnlineOperation
                                $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Rebuild()
                            } catch {
                                Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.TableName) - partition $($obj.Partition)" -Target $db -ErrorRecord $_ -Continue -FunctionName Set-DbaDbCompression
                            }
                        } else {
                            ##nonclustered indexes
                            Write-Message -Level Verbose -Message "Applying $($obj.CompressionTypeRecommendation) compression to $($obj.Database).$($obj.Schema).$($obj.TableName).$($obj.IndexName)" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                            try {
                                $underlyingObj = $server.Databases[$obj.Database].Tables[$obj.TableName, $obj.Schema].Indexes[$obj.IndexName]
                                ($underlyingObj.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $obj.Partition }).DataCompression = $obj.CompressionTypeRecommendation
                                $underlyingObj.OnlineIndexOperation = $CanDoOnlineOperation
                                $underlyingObj.SortInTempdb = $SortInTempDB
                                $underlyingObj.Rebuild()
                            } catch {
                                Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.TableName) - index $($obj.IndexName) - partition $($obj.Partition)" -Target $db -ErrorRecord $_ -Continue -FunctionName Set-DbaDbCompression
                            }
                        }
                        $obj.AlreadyProcessed = "True"
                        $obj
                    }
                }
            } else {
                if ($__realCmdlet.ShouldProcess($db, "Applying $CompressionType compression")) {
                    $tables = $server.Databases[$($db.name)].Tables
                    if ($Table) {
                        $tableParts = $Table | ForEach-Object { Get-ObjectNameParts -ObjectName $_ }
                        $tables = foreach ($tablePart in $tableParts) {
                            $server.Databases[$($db.name)].Tables | Where-Object {
                                $_.Name -eq $tablePart.Name -and
                                $tablePart.Schema -in ($_.Schema, $null) -and
                                $tablePart.Database -in ($db.Name, $null)
                            }
                        }
                    }

                    foreach ($obj in $tables | Where-Object { !$_.IsMemoryOptimized -and !$_.HasSparseColumn }) {
                        if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                            Write-Message -Level Warning -Message "Reached max run time of $MaxRunTime" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                            break
                        }
                        foreach ($p in $($obj.PhysicalPartitions | Where-Object { $_.DataCompression -notin ($CompressionType, 'ColumnStore', 'ColumnStoreArchive') })) {
                            Write-Message -Level Verbose -Message "Compressing table $($obj.Schema).$($obj.Name)" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                            try {
                                $($obj.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $p.PartitionNumber }).DataCompression = $CompressionType
                                $obj.OnlineHeapOperation = $CanDoOnlineOperation
                                $obj.Rebuild()
                            } catch {
                                Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.Name) - partition $($p.PartitionNumber)" -Target $db -ErrorRecord $_ -Continue -FunctionName Set-DbaDbCompression
                            }
                            [PSCustomObject]@{
                                ComputerName                  = $server.ComputerName
                                InstanceName                  = $server.ServiceName
                                SqlInstance                   = $server.DomainInstanceName
                                Database                      = $db.Name
                                Schema                        = $obj.Schema
                                TableName                     = $obj.Name
                                IndexName                     = $null
                                Partition                     = $p.PartitionNumber
                                IndexID                       = 0
                                IndexType                     = Switch ($obj.HasHeapIndex) { $false { "ClusteredIndex" } $true { "Heap" } }
                                PercentScan                   = $null
                                PercentUpdate                 = $null
                                RowEstimatePercentOriginal    = $null
                                PageEstimatePercentOriginal   = $null
                                CompressionTypeRecommendation = $CompressionType.ToUpper()
                                SizeCurrent                   = $null
                                SizeRequested                 = $null
                                PercentCompression            = $null
                                AlreadyProcessed              = "True"
                            }
                        }

                        foreach ($index in $($obj.Indexes | Where-Object { !$_.IsMemoryOptimized -and $_.IndexType -notmatch 'Columnstore' })) {
                            if ($MaxRunTime -ne 0 -and ($(Get-Date) - $starttime).TotalMinutes -ge $MaxRunTime) {
                                Write-Message -Level Warning -Message "Reached max run time of $MaxRunTime" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                                break
                            }
                            foreach ($p in $($index.PhysicalPartitions | Where-Object { $_.DataCompression -ne $CompressionType })) {
                                Write-Message -Level Verbose -Message "Compressing $($Index.IndexType) $($Index.Name) Partition $($p.PartitionNumber)" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                                try {
                                    ## There is a bug in SMO where setting compression to None at the index level doesn't work
                                    ## Once this UserVoice item is fixed the workaround can be removed
                                    ## https://feedback.azure.com/forums/908035-sql-server/suggestions/34080112-data-compression-smo-bug
                                    if ($CompressionType -eq "None") {
                                        $withOptions = @("DATA_COMPRESSION = $CompressionType")
                                        if ($CanDoOnlineOperation) {
                                            $withOptions += "ONLINE = ON"
                                        }
                                        if ($SortInTempDB) {
                                            $withOptions += "SORT_IN_TEMPDB = ON"
                                        }
                                        $query = "ALTER INDEX [$($index.Name)] ON $($index.Parent) REBUILD PARTITION = ALL WITH ($($withOptions -join ", "))"
                                        $Server.Query($query, $db.Name)
                                    } else {
                                        $($index.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                        $index.OnlineIndexOperation = $CanDoOnlineOperation
                                        $index.SortInTempdb = $SortInTempDB
                                        $index.Rebuild()
                                    }
                                } catch {
                                    Stop-Function -Message "Compression failed for $instance - $db - table $($obj.Schema).$($obj.Name) - index $($index.Name) - partition $($p.PartitionNumber)" -Target $db -ErrorRecord $_ -Continue -FunctionName Set-DbaDbCompression
                                }
                                [PSCustomObject]@{
                                    ComputerName                  = $server.ComputerName
                                    InstanceName                  = $server.ServiceName
                                    SqlInstance                   = $server.DomainInstanceName
                                    Database                      = $db.Name
                                    Schema                        = $obj.Schema
                                    TableName                     = $obj.Name
                                    IndexName                     = $index.Name
                                    Partition                     = $p.PartitionNumber
                                    IndexID                       = $index.Id
                                    IndexType                     = $index.IndexType
                                    PercentScan                   = $null
                                    PercentUpdate                 = $null
                                    RowEstimatePercentOriginal    = $null
                                    PageEstimatePercentOriginal   = $null
                                    CompressionTypeRecommendation = $CompressionType.ToUpper()
                                    SizeCurrent                   = $null
                                    SizeRequested                 = $null
                                    PercentCompression            = $null
                                    AlreadyProcessed              = "True"
                                }
                            }
                        }
                    }
                    foreach ($index in $($server.Databases[$($db.name)].Views | Where-Object { $_.Indexes }).Indexes) {
                        $parentView = $index.Parent
                        foreach ($p in $($index.PhysicalPartitions | Where-Object { $_.DataCompression -ne $CompressionType })) {
                            Write-Message -Level Verbose -Message "Compressing $($index.IndexType) $($index.Name) Partition $($p.PartitionNumber)" -FunctionName Set-DbaDbCompression -ModuleName "dbatools"
                            try {
                                ## There is a bug in SMO where setting compression to None at the index level doesn't work
                                ## Once this UserVoice item is fixed the workaround can be removed
                                ## https://feedback.azure.com/forums/908035-sql-server/suggestions/34080112-data-compression-smo-bug
                                if ($CompressionType -eq "None") {
                                    $withOptions = @("DATA_COMPRESSION = $CompressionType")
                                    if ($CanDoOnlineOperation) {
                                        $withOptions += "ONLINE = ON"
                                    }
                                    if ($SortInTempDB) {
                                        $withOptions += "SORT_IN_TEMPDB = ON"
                                    }
                                    $query = "ALTER INDEX [$($index.Name)] ON $($index.Parent) REBUILD PARTITION = ALL WITH ($($withOptions -join ", "))"
                                    $Server.Query($query, $db.Name)
                                } else {
                                    $($index.PhysicalPartitions | Where-Object { $_.PartitionNumber -eq $P.PartitionNumber }).DataCompression = $CompressionType
                                    $index.OnlineIndexOperation = $CanDoOnlineOperation
                                    $index.SortInTempdb = $SortInTempDB
                                    $index.Rebuild()
                                }
                            } catch {
                                Stop-Function -Message "Compression failed for $instance - $db - view $($parentView.Schema).$($parentView.Name) - index $($index.Name) - partition $($p.PartitionNumber)" -Target $db -ErrorRecord $_ -Continue -FunctionName Set-DbaDbCompression
                            }
                            [PSCustomObject]@{
                                ComputerName                  = $server.ComputerName
                                InstanceName                  = $server.ServiceName
                                SqlInstance                   = $server.DomainInstanceName
                                Database                      = $db.Name
                                Schema                        = $parentView.Schema
                                TableName                     = $parentView.Name
                                IndexName                     = $index.Name
                                Partition                     = $p.PartitionNumber
                                IndexID                       = $index.Id
                                IndexType                     = $index.IndexType
                                PercentScan                   = $null
                                PercentUpdate                 = $null
                                RowEstimatePercentOriginal    = $null
                                PageEstimatePercentOriginal   = $null
                                CompressionTypeRecommendation = $CompressionType.ToUpper()
                                SizeCurrent                   = $null
                                SizeRequested                 = $null
                                PercentCompression            = $null
                                AlreadyProcessed              = "True"
                            }
                        }
                    }
                }
            }
        }
    }

    # DEF-012 carry (hop mechanism, not source): hand this record's final $tables to the next one.
    @{ __setDbaDbCompressionProcess = @{ Tables = $tables; CompressionSuggestion = $compressionSuggestion } }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $Table $CompressionType $MaxRunTime $PercentCompression $ForceOfflineRebuilds $SortInTempDB $InputObject $EnableException $__boundInputObject $__carriedTables $__carriedCompressionSuggestion $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}

