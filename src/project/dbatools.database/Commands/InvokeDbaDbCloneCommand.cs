#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Clones a database's schema and statistics via DBCC CLONEDATABASE. Port of public/Invoke-DbaDbClone.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop. This is a MUTATING command with real
/// SupportsShouldProcess.
///
/// A begin+process port (InputObject is ValueFromPipeline pos3). The begin block builds six state values that
/// process consumes - the UPDATE STATISTICS SQL ($sqlStats), the DBCC WITH clause ($sqlWith, dependent on
/// -ExcludeStatistics/-ExcludeQueryStore), and four minimum-version constants - and ALSO fires a Stop-Function (NO
/// -Continue) if -SqlInstance is given without -Database, which sets the interrupt that the process block's opening
/// if (Test-FunctionInterrupt) { return } gates on. So begin runs ONCE and carries both the state AND the interrupt
/// (the W2-112 pattern): the begin body is DOT-SOURCED, the six state values ride a sentinel, and the module
/// interrupt var is captured (Get-Variable -Scope 0) into _beginInterrupted which gates ProcessRecord. The two
/// $Pscmdlet.ShouldProcess calls (update-stats and DBCC clone) become $__realCmdlet.ShouldProcess with the compiled
/// cmdlet (this). Test-Bound checks (begin ExcludeStatistics/ExcludeQueryStore; process CloneDatabase/ExcludeStatistics/
/// ExcludeQueryStore/UpdateStatistics incl. a -Not) become carried $__bound flags; ExcludeStatistics/ExcludeQueryStore
/// are ALSO used as VALUES in begin (untyped inner params). All Stop-Function -Continue are inside foreach ($db) -
/// loop-bound, so no continue-guard. Surface pinned by migration/baselines/Invoke-DbaDbClone.json (positions 0-4,
/// InputObject VFP pos3, SupportsShouldProcess ConfirmImpact Medium).
/// </summary>
[Cmdlet(VerbsLifecycle.Invoke, "DbaDbClone", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class InvokeDbaDbCloneCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances (SQL 2012 SP4+).</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The source database(s) to clone.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    /// <summary>The name(s) for the cloned database(s) (defaults to &lt;db&gt;_clone).</summary>
    [Parameter(Position = 4)]
    public string[]? CloneDatabase { get; set; }

    /// <summary>Exclude statistics from the clone.</summary>
    [Parameter]
    public SwitchParameter ExcludeStatistics { get; set; }

    /// <summary>Exclude the query store from the clone.</summary>
    [Parameter]
    public SwitchParameter ExcludeQueryStore { get; set; }

    /// <summary>Update statistics on the source before cloning.</summary>
    [Parameter]
    public SwitchParameter UpdateStatistics { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // Carried begin->process: the six begin-built state values, and the begin interrupt.
    private object? _sqlStats, _sqlWith, _sql2012min, _sql2014min, _sql2014CuMin, _sql2016min;
    private bool _beginInterrupted;

    protected override void BeginProcessing()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__cloneBegin"))
            {
                if (sentinel["__cloneBegin"] is Hashtable state)
                {
                    _sqlStats = state["SqlStats"];
                    _sqlWith = state["SqlWith"];
                    _sql2012min = state["Sql2012min"];
                    _sql2014min = state["Sql2014min"];
                    _sql2014CuMin = state["Sql2014CuMin"];
                    _sql2016min = state["Sql2016min"];
                    _beginInterrupted = LanguagePrimitives.IsTrue(state["Interrupted"]);
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
            Database, SqlInstance, ExcludeStatistics.ToBool(), ExcludeQueryStore.ToBool(), EnableException.ToBool(),
            TestBound(nameof(ExcludeStatistics)), TestBound(nameof(ExcludeQueryStore)),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
    {
        // Replicates the source process block's opening if (Test-FunctionInterrupt) { return }:
        // a begin Stop-Function (no -Continue) sets the interrupt, carried here as _beginInterrupted.
        if (Interrupted || _beginInterrupted)
            return;

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
            SqlInstance, SqlCredential, Database, InputObject, CloneDatabase, EnableException.ToBool(),
            _sqlStats, _sqlWith, _sql2012min, _sql2014min, _sql2014CuMin, _sql2016min, this,
            TestBound(nameof(CloneDatabase)), TestBound(nameof(ExcludeStatistics)), TestBound(nameof(ExcludeQueryStore)),
            TestBound(nameof(UpdateStatistics)), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the begin block VERBATIM (DOT-SOURCED so the interrupt set by the no-Continue Stop-Function is captured).
    // Edits: -FunctionName Invoke-DbaDbClone on the Stop-Function; Test-Bound ExcludeStatistics/ExcludeQueryStore ->
    // carried flags. Emits the six state values + the interrupt. ExcludeStatistics/ExcludeQueryStore arrive as bools.
    private const string BeginScript = """
param($Database, $SqlInstance, $ExcludeStatistics, $ExcludeQueryStore, $EnableException, $__boundExcludeStatistics, $__boundExcludeQueryStore, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([string[]]$Database, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $ExcludeStatistics, $ExcludeQueryStore, $EnableException, $__boundExcludeStatistics, $__boundExcludeQueryStore, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }
    . {
        if (-not $Database -and $SqlInstance) {
            Stop-Function -Message "You must specify a database name if you did not pipe a database" -FunctionName Invoke-DbaDbClone
        }

        $sqlStats = "DECLARE @out TABLE(id INT IDENTITY(1,1), s SYSNAME, o SYSNAME, i SYSNAME, stats_stream VARBINARY(MAX), rows BIGINT, pages BIGINT)
            DECLARE @dbcc TABLE(stats_stream VARBINARY(MAX), rows BIGINT, pages BIGINT)
            DECLARE c CURSOR FOR
                    SELECT OBJECT_SCHEMA_NAME(object_id) s, OBJECT_NAME(object_id) o, name i
                    FROM sys.indexes
                    WHERE type_desc IN ('CLUSTERED COLUMNSTORE', 'NONCLUSTERED COLUMNSTORE')
            DECLARE @s SYSNAME, @o SYSNAME, @i SYSNAME
            OPEN c
            FETCH NEXT FROM c INTO @s, @o, @i
            WHILE @@FETCH_STATUS = 0
            BEGIN
                DECLARE @showStats NVARCHAR(MAX) = N'DBCC SHOW_STATISTICS(""' + QUOTENAME(@s) + '.' + QUOTENAME(@o) + '"", ' + QUOTENAME(@i) + ') WITH stats_stream'
                INSERT @dbcc EXEC sp_executesql @showStats
                INSERT @out SELECT @s, @o, @i, stats_stream, rows, pages FROM @dbcc
                DELETE @dbcc
                FETCH NEXT FROM c INTO @s, @o, @i
            END
            CLOSE c
            DEALLOCATE c

            DECLARE @sql NVARCHAR(MAX);
            DECLARE @id INT;
            SELECT TOP 1 @id=id,@sql=
            'UPDATE STATISTICS ' + QUOTENAME(s) + '.' + QUOTENAME(o)  + '(' + QUOTENAME(i)
            + ') WITH stats_stream = ' + CONVERT(NVARCHAR(MAX), stats_stream, 1)
            + ', rowcount = ' + CONVERT(NVARCHAR(MAX), rows) + ', pagecount = '  + CONVERT(NVARCHAR(MAX), pages)
            FROM @out

            WHILE (@@ROWCOUNT <> 0)
            BEGIN
                EXEC sp_executesql @sql
                DELETE @out WHERE id = @id
                SELECT TOP 1 @id=id,@sql=
                'UPDATE STATISTICS ' + QUOTENAME(s) + '.' + QUOTENAME(o)  + '(' + QUOTENAME(i)
                + ') WITH stats_stream = ' + CONVERT(NVARCHAR(MAX), stats_stream, 1)
                + ', rowcount = ' + CONVERT(NVARCHAR(MAX), rows) + ', pagecount = '  + CONVERT(NVARCHAR(MAX), pages)
                FROM @out
            END
        "

        $noStats = "NO_STATISTICS"
        $noQueryStore = "NO_QUERYSTORE"
        if ( ($__boundExcludeStatistics) -or ($__boundExcludeQueryStore) ) {
            $sqlWith = ""
            if ($ExcludeStatistics) {
                $sqlWith = "WITH $noStats"
            }
            if ($ExcludeQueryStore) {
                $sqlWith = "WITH $noQueryStore"
            }
            if ($ExcludeStatistics -and $ExcludeQueryStore) {
                $sqlWith = "WITH $noStats,$noQueryStore"
            }
        }

        $sql2012min = [version]"11.0.7001" # SQL 2012 SP4
        $sql2014min = [version]"12.0.5000" # SQL 2014 SP2
        $sql2014CuMin = [version]"12.0.5538" # SQL 2014 SP2 + CU3
        $sql2016min = [version]"13.0.4001" # SQL 2016 SP1
    }
    $__iv = Get-Variable -Name __dbatools_interrupt_function_78Q9VPrM6999g6zo24Qn83m09XF56InEn4hFrA8Fwhu5xJrs6r -Scope 0 -ErrorAction Ignore
    @{ __cloneBegin = @{ SqlStats = $sqlStats; SqlWith = $sqlWith; Sql2012min = $sql2012min; Sql2014min = $sql2014min; Sql2014CuMin = $sql2014CuMin; Sql2016min = $sql2016min; Interrupted = [bool]($__iv -and $__iv.Value) } }
} $Database $SqlInstance $ExcludeStatistics $ExcludeQueryStore $EnableException $__boundExcludeStatistics $__boundExcludeQueryStore $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM. Edits: -FunctionName on Stop-Function/Write-Message; $Pscmdlet.ShouldProcess ->
    // $__realCmdlet.ShouldProcess; Test-Bound (CloneDatabase/ExcludeStatistics/ExcludeQueryStore/UpdateStatistics incl.
    // -Not) -> carried flags. The six begin state values arrive as params. Continues are loop-bound in foreach ($db).
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $InputObject, $CloneDatabase, $EnableException, $sqlStats, $sqlWith, $sql2012min, $sql2014min, $sql2014CuMin, $sql2016min, $__realCmdlet, $__boundCloneDatabase, $__boundExcludeStatistics, $__boundExcludeQueryStore, $__boundUpdateStatistics, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Database, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, [string[]]$CloneDatabase, $EnableException, $sqlStats, $sqlWith, $sql2012min, $sql2014min, $sql2014CuMin, $sql2016min, $__realCmdlet, $__boundCloneDatabase, $__boundExcludeStatistics, $__boundExcludeQueryStore, $__boundUpdateStatistics, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if (Test-FunctionInterrupt) { return }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $instance = $server.Name

            if (-not ($__boundCloneDatabase)) {
                $CloneDatabase = "$($db.Name)_clone"
            }

            if ($server.VersionMajor -eq 11 -and $server.Version -lt $sql2012min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2012 SP4 and above required." -Target $server -FunctionName Invoke-DbaDbClone -Continue
            }

            if ($server.VersionMajor -eq 12 -and $server.Version -lt $sql2014min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2014 SP2 and above required." -Target $server -FunctionName Invoke-DbaDbClone -Continue
            }

            if ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -FunctionName Invoke-DbaDbClone -Continue
            }

            if ($__boundExcludeStatistics) {
                if ($server.VersionMajor -eq 12 -and $server.Version -lt $sql2014CuMin) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2014 SP1 + CU3 and above required." -Target $server -FunctionName Invoke-DbaDbClone -Continue
                }
                if ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -FunctionName Invoke-DbaDbClone -Continue
                }
            }

            if ($__boundExcludeQueryStore) {
                if ($server.VersionMajor -lt 13 - ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min)) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -FunctionName Invoke-DbaDbClone -Continue
                }
            }

            if ($db.IsSystemObject) {
                Stop-Function -Message "Only user databases are supported" -Target $instance -FunctionName Invoke-DbaDbClone -Continue
            }

            if ( ($__boundUpdateStatistics) -and (-not $__boundExcludeStatistics) ) {
                if ($__realCmdlet.ShouldProcess($instance, "Update statistics in $($db.Name)")) {
                    try {
                        Write-Message -Level Verbose -Message "Updating statistics" -FunctionName Invoke-DbaDbClone -ModuleName "dbatools"
                        $null = $db.Invoke($sqlStats)
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -FunctionName Invoke-DbaDbClone -Continue
                    }
                }
            }

            $dbName = $db.Name

            foreach ($clonedb in $CloneDatabase) {
                Write-Message -Level Verbose -Message "Cloning $clonedb from $db" -FunctionName Invoke-DbaDbClone -ModuleName "dbatools"
                if ($server.Databases[$clonedb]) {
                    Stop-Function -Message "Destination clone database $clonedb already exists" -Target $instance -FunctionName Invoke-DbaDbClone -Continue
                } else {
                    if ($__realCmdlet.ShouldProcess($instance, "Execute DBCC CloneDatabase($dbName, $clonedb)")) {
                        try {
                            $sql = "DBCC CLONEDATABASE('$dbName','$clonedb') $sqlWith"
                            Write-Message -Level Debug -Message "Sql Statement: $sql" -FunctionName Invoke-DbaDbClone -ModuleName "dbatools"
                            $null = $db.Invoke($sql)
                            $server.Databases.Refresh()
                            Get-DbaDatabase -SqlInstance $server -Database $clonedb
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -FunctionName Invoke-DbaDbClone -Continue
                        }
                    }
                }
            }
        }
} $SqlInstance $SqlCredential $Database $InputObject $CloneDatabase $EnableException $sqlStats $sqlWith $sql2012min $sql2014min $sql2014CuMin $sql2016min $__realCmdlet $__boundCloneDatabase $__boundExcludeStatistics $__boundExcludeQueryStore $__boundUpdateStatistics $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
