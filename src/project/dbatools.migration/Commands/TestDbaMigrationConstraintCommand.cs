#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Validates that a database's edition-specific features survive a move to another instance. Port
/// of public/Test-DbaMigrationConstraint.ps1; the workflow stays a module-scoped PowerShell
/// compatibility hop because it leans on SMO Databases/FileGroups enumeration, Get-DbaSpConfigure
/// and Server.Query. Surface pinned by migration/baselines/Test-DbaMigrationConstraint.json.
///
/// BEGIN+PROCESS lifecycle split. Source is ValueFromPipeline, so process fires once per piped
/// instance while begin runs exactly once. There is no end block.
///
/// WHAT THE CARRIER IS ACTUALLY FOR. begin's three values - the edition weight table and the two
/// note strings - are immutable and would survive a per-record rebuild unchanged. $Database is the
/// reason the state has to exist. It is a PARAMETER variable that the process body REASSIGNS: when
/// the caller supplies no -Database, record one overwrites it with that server's user databases,
/// and because the parameter is not pipeline-bound the engine never rebinds it, so record two
/// evaluates the SECOND instance against the FIRST instance's database list. Each ProcessRecord is
/// a fresh scriptblock here, so without the carrier every record would re-resolve from its own
/// server and the divergence would be silent - the ported command would look more correct and
/// behave differently. DatabaseSeeded rather than a null check, because "record one legitimately
/// resolved nothing" and "no record has run yet" are different states and only the second may fall
/// back to the bound argument.
///
/// -ExcludeDatabase is not carried: the body assigns it nowhere. It does overwrite $Database with
/// an unfiltered server enumeration, which means -ExcludeDatabase discards any -Database filter and
/// re-admits system databases. Reproduced as written.
///
/// NO INTERRUPT CARRY. The process block never reads Test-FunctionInterrupt, so a Stop-Function on
/// one record does not silence later ones and there is no latch to carry.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaMigrationConstraint", DefaultParameterSetName = "DbMigration")]
public sealed class TestDbaMigrationConstraintCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance holding the databases to validate. Requires SQL Server 2008 or higher.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The destination SQL Server instance the databases would be migrated to.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter Destination { get; set; } = null!;

    /// <summary>Alternative credential for the destination instance.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only validate these databases. When omitted, every user database on the source is validated.</summary>
    [Parameter(Position = 4)]
    public object[]? Database { get; set; }

    /// <summary>Skip these databases.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeDatabase { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // begin's edition table and note strings, plus the $Database the process body rewrites.
    private Hashtable? _beginState;

    protected override void BeginProcessing()
    {
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, BeginScript,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is Hashtable sentinel && sentinel.ContainsKey("__testDbaMigrationConstraintBegin"))
            {
                if (sentinel["__testDbaMigrationConstraintBegin"] is Hashtable state)
                {
                    _beginState = state;
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
        // NO Interrupted PROLOGUE, and its absence is load-bearing. The nested hop reports a
        // Stop-Function back to the host, which latches Interrupted for the rest of the pipeline;
        // the source's process block reads Test-FunctionInterrupt nowhere, so a connect failure on
        // one piped record leaves the records after it untouched. Guarding here silences them.
        // Measured, not reasoned: with the guard in place the gate's "should still process the
        // record after the failure" leg went red against a pre-flip run of the same suite that was
        // green.
        //
        // The hop writes the carried $Database straight back into _beginState, which is the same
        // Hashtable instance the script sees, so there is no process sentinel to demux.
        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            Source, SourceSqlCredential, Destination, DestinationSqlCredential,
            Database, ExcludeDatabase, EnableException.ToBool(), _beginState,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
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

    // PS: the begin block VERBATIM. The sentinel hands its three values on, and seeds the slot the
    // process hop writes $Database back into.
    private const string BeginScript = """
param($__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($__boundVerbose, $__boundDebug)

    <#
        1804890536 = Enterprise
        1872460670 = Enterprise Edition: Core-based Licensing
        610778273 = Enterprise Evaluation
        284895786 = Business Intelligence
        -2117995310 = Developer
        -1592396055 = Express
        -133711905= Express with Advanced Services
        -1534726760 = Standard
        1293598313 = Web
        1674378470 = SQL Database
    #>

    $editions = @{
        "Enterprise" = 10;
        "Developer"  = 10;
        "Evaluation" = 10;
        "Standard"   = 5;
        "Express"    = 1
    }
    $notesCanMigrate = "Database can be migrated."
    $notesCannotMigrate = "Database cannot be migrated."

    @{ __testDbaMigrationConstraintBegin = @{ Editions = $editions; NotesCanMigrate = $notesCanMigrate; NotesCannotMigrate = $notesCannotMigrate; Database = $null; DatabaseSeeded = $false } }
} $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";

    // PS: the process block VERBATIM, preceded by begin's carried values. Only edit is
    // -FunctionName Test-DbaMigrationConstraint (plus -ModuleName "dbatools" on Write-Message) so
    // the messages carry the command's own name rather than the hop scriptblock's.
    // The body is dot-sourced so its four early returns leave the block, not the hop, and the
    // $Database write-back below still runs - which is what makes the carry match the function's
    // single function scope.
    private const string ProcessScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $Database, $ExcludeDatabase, $EnableException, $__beginState, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, [PSCredential]$SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Destination, [PSCredential]$DestinationSqlCredential, [object[]]$Database, [object[]]$ExcludeDatabase, $EnableException, $__beginState)

    $editions = $__beginState.Editions
    $notesCanMigrate = $__beginState.NotesCanMigrate
    $notesCannotMigrate = $__beginState.NotesCannotMigrate
    if ($__beginState.DatabaseSeeded) {
        $Database = $__beginState.Database
    }

    . {
        try {
            $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Test-DbaMigrationConstraint
        }

        try {
            $destServer = Connect-DbaInstance -SqlInstance $Destination -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Destination -FunctionName Test-DbaMigrationConstraint
        }

        if (-Not $Database) {
            $Database = $sourceServer.Databases | Where-Object IsSystemObject -eq 0 | Select-Object Name, Status
        }

        if ($ExcludeDatabase) {
            $Database = $sourceServer.Databases | Where-Object Name -NotIn $ExcludeDatabase
        }

        if ($Database.Count -gt 0) {
            if ($Database -in @("master", "msdb", "tempdb")) {
                Stop-Function -Message "Migrating system databases is not currently supported." -FunctionName Test-DbaMigrationConstraint
                return
            }

            if ($sourceServer.VersionMajor -lt 9 -and $destServer.VersionMajor -gt 10) {
                Stop-Function -Message "Sql Server 2000 databases cannot be migrated to SQL Server version 2012 and above. Quitting." -FunctionName Test-DbaMigrationConstraint
                return
            }

            if ($sourceServer.Collation -ne $destServer.Collation) {
                Write-Message -Level Warning -Message "Collation on $Source, $($sourceServer.collation) differs from the $Destination, $($destServer.collation)." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
            }

            if ($sourceServer.VersionMajor -gt $destServer.VersionMajor) {
                #indicate they must use 'Generate Scripts' and 'Export Data' options?
                Stop-Function -Message "You can't migrate databases from a higher version to a lower one. Quitting." -FunctionName Test-DbaMigrationConstraint
                return
            }

            if ($sourceServer.VersionMajor -lt 10) {
                Stop-Function -Message "This function does not support versions lower than SQL Server 2008 (v10)" -FunctionName Test-DbaMigrationConstraint
                return
            }

            #if editions differs, from higher to lower one, verify the sys.dm_db_persisted_sku_features - only available from SQL 2008 +
            if (($sourceServer.VersionMajor -ge 10 -and $destServer.VersionMajor -ge 10)) {
                foreach ($db in $Database) {
                    if ([string]::IsNullOrEmpty($db.Status)) {
                        $dbstatus = ($sourceServer.Databases | Where-Object Name -eq $db).Status.ToString()
                        $dbName = $db
                    } else {
                        $dbstatus = $db.Status.ToString()
                        $dbName = $db.Name
                    }

                    Write-Message -Level Verbose -Message "Checking database '$dbName'." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"

                    if ($dbstatus.Contains("Offline") -eq $false -or $db.IsAccessible -eq $true) {

                        [long]$destVersionNumber = $($destServer.VersionString).Replace(".", "")
                        [string]$sourceVersion = "$($sourceServer.Edition) $($sourceServer.ProductLevel) ($($sourceServer.Version))"
                        [string]$destVersion = "$($destServer.Edition) $($destServer.ProductLevel) ($($destServer.Version))"
                        [string]$dbFeatures = ""

                        #Check if database has any FILESTREAM filegroup
                        Write-Message -Level Verbose -Message "Checking if FileStream is in use for database '$dbName'." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
                        if ($sourceServer.Databases[$dbName].FileGroups | Where-Object FileGroupType -eq 'FileStreamDataFileGroup') {
                            Write-Message -Level Verbose -Message "Found FileStream filegroup and files." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
                            $fileStreamSource = Get-DbaSpConfigure -SqlInstance $sourceServer -ConfigName FilestreamAccessLevel
                            $fileStreamDestination = Get-DbaSpConfigure -SqlInstance $destServer -ConfigName FilestreamAccessLevel

                            if ($fileStreamSource.RunningValue -ne $fileStreamDestination.RunningValue) {
                                [PSCustomObject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate. Destination server dones not have the 'FilestreamAccessLevel' configuration (RunningValue: $($fileStreamDestination.RunningValue)) equal to source server (RunningValue: $($fileStreamSource.RunningValue))."
                                }
                                Continue
                            }
                        }

                        try {
                            $sql = "SELECT feature_name FROM sys.dm_db_persisted_sku_features"

                            $skuFeatures = $sourceServer.Query($sql, $dbName)

                            Write-Message -Level Verbose -Message "Checking features in use..." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"

                            if (@($skuFeatures).Count -gt 0) {
                                foreach ($row in $skuFeatures) {
                                    $dbFeatures += ",$($row["feature_name"])"
                                }

                                $dbFeatures = $dbFeatures.TrimStart(",")
                            }
                        } catch {
                            Stop-Function -Message "Issue collecting sku features." -ErrorRecord $_ -Target $sourceServer -Continue -FunctionName Test-DbaMigrationConstraint
                        }

                        #If SQL Server 2016 SP1 (13.0.4001.0) or higher
                        if ($destVersionNumber -ge 13040010) {
                            <#
                                Need to verify if Edition = EXPRESS and database uses 'Change Data Capture' (CDC)
                                This means that database cannot be migrated because Express edition doesn't have SQL Server Agent
                            #>
                            if ($editions.Item($destServer.Edition.ToString().Split(" ")[0]) -eq 1 -and $dbFeatures.Contains("ChangeCapture")) {
                                [PSCustomObject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate. Destination server edition is EXPRESS which does not support 'ChangeCapture' feature that is in use."
                                }
                            } else {
                                [PSCustomObject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $true
                                    Notes               = $notesCanMigrate
                                }
                            }
                        }
                        #Version is lower than SQL Server 2016 SP1
                        else {
                            Write-Message -Level Verbose -Message "Source Server Edition: $($sourceServer.Edition) (Weight: $($editions.Item($sourceServer.Edition.ToString().Split(" ")[0])))" -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
                            Write-Message -Level Verbose -Message "Destination Server Edition: $($destServer.Edition) (Weight: $($editions.Item($destServer.Edition.ToString().Split(" ")[0])))" -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"

                            #Check for editions. If destination edition is lower than source edition and exists features in use
                            if (($editions.Item($destServer.Edition.ToString().Split(" ")[0]) -lt $editions.Item($sourceServer.Edition.ToString().Split(" ")[0])) -and (!([string]::IsNullOrEmpty($dbFeatures)))) {
                                [PSCustomObject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $false
                                    Notes               = "$notesCannotMigrate There are features in use not available on destination instance."
                                }
                            }
                            #
                            else {
                                [PSCustomObject]@{
                                    SourceInstance      = $sourceServer.Name
                                    DestinationInstance = $destServer.Name
                                    SourceVersion       = $sourceVersion
                                    DestinationVersion  = $destVersion
                                    Database            = $dbName
                                    FeaturesInUse       = $dbFeatures
                                    IsMigratable        = $true
                                    Notes               = $notesCanMigrate
                                }
                            }
                        }
                    } else {
                        Write-Message -Level Warning -Message "Database '$dbName' is offline or not accessible. Bring database online and re-run the command." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
                    }
                }
            } else {
                #SQL Server 2005 or under
                Write-Message -Level Warning -Message "This validation will not be made on versions lower than SQL Server 2008 (v10)." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Source server version: $($sourceServer.VersionMajor)." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
                Write-Message -Level Verbose -Message "Destination server version: $($destServer.VersionMajor)." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
            }
        } else {
            Write-Message -Level Output -Message "There are no databases to validate." -FunctionName Test-DbaMigrationConstraint -ModuleName "dbatools"
        }
    }

    $__beginState.Database = $Database
    $__beginState.DatabaseSeeded = $true
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $Database $ExcludeDatabase $EnableException $__beginState @__commonParameters 3>&1 2>&1
""";
}
