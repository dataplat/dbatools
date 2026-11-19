#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies the Query Store configuration of one source database onto databases on destination
/// instances. Port of public/Copy-DbaDbQueryStoreOption.ps1. The whole workflow rides module-scoped
/// PowerShell hops because it leans on Get-DbaDbQueryStoreOption, Get-DbaDatabase, the
/// version-branched Set-DbaDbQueryStoreOption splat and Select-DefaultView decoration, all of which
/// keep the retired function's engine semantics there. The compiled cmdlet supplies the real
/// ShouldProcess runtime. Surface pinned by migration/baselines/Copy-DbaDbQueryStoreOption.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaDbQueryStoreOption",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaDbQueryStoreOptionCommand : DbaBaseCmdlet
{
    /// <summary>The source SQL Server instance holding the database to copy settings from.</summary>
    [Parameter(Mandatory = true, Position = 0, ValueFromPipeline = true)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>The database whose Query Store configuration is replicated.</summary>
    [Parameter(Mandatory = true, Position = 2, ValueFromPipeline = true)]
    public object SourceDatabase { get; set; } = null!;

    /// <summary>The destination SQL Server instances.</summary>
    [Parameter(Mandatory = true, Position = 3, ValueFromPipeline = true)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 4)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only apply the configuration to these destination databases.</summary>
    [Parameter(Position = 5)]
    public object[]? DestinationDatabase { get; set; }

    /// <summary>Destination databases to skip.</summary>
    [Parameter(Position = 6)]
    public object[]? Exclude { get; set; }

    /// <summary>Apply the configuration to every user database on the destination.</summary>
    [Parameter]
    public SwitchParameter AllDatabases { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    // The source connection is opened once in begin and read on every record, so it cannot be
    // rebuilt per record: reconnecting would use the record's -Source rather than the one begin
    // saw, and would open one connection per piped object.
    private object? _sourceServer;

    protected override void BeginProcessing()
    {
        // $Source is passed as it stands at begin time. Three parameters take pipeline input, so a
        // piped call leaves all of them unbound here - which is exactly what the function's begin
        // block saw, and it is why a piped call still needs -Source named.
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else if (item is not null && LanguagePrimitives.IsTrue(
                item.Properties["__CopyDbaDbQueryStoreOptionBeginComplete"]?.Value))
            {
                _sourceServer = UnwrapHopValue(item.Properties["sourceServer"]?.Value);
            }
            else
            {
                WriteObject(item);
            }
        }, BeginScript,
            Source, SourceSqlCredential, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    protected override void ProcessRecord()
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
            }
            else
            {
                WriteObject(item);
            }
        }, BodyScript,
            Source, SourceSqlCredential, SourceDatabase, Destination, DestinationSqlCredential,
            DestinationDatabase, Exclude, AllDatabases.ToBool(), EnableException.ToBool(),
            _sourceServer, this,
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

    // PS: the begin block. Its only product is $sourceServer, which every record reads, so it
    // rides back on a sentinel object rather than being emitted to the caller.
    private const string BeginScript = """
param($Source, $SourceSqlCredential, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    # $EnableException is unused here yet must be in scope: Stop-Function defaults its own
    # [bool]$EnableException from the caller's variable, so an undefined one binds $null and the
    # connection failure dies on a cast error instead of warning.
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, $EnableException)

    try {
        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaDbQueryStoreOption
        return
    }

    [PSCustomObject]@{
        __CopyDbaDbQueryStoreOptionBeginComplete = $true
        sourceServer                             = $sourceServer
    }
} $Source $SourceSqlCredential $EnableException @__commonParameters 3>&1 2>&1
""";

    // PS: the process block, verbatim apart from the -FunctionName/-ModuleName attribution, the
    // $sourceServer carry, and $PSCmdlet.ShouldProcess becoming $__realCmdlet.ShouldProcess - a
    // nested advanced function inside the hop would resolve $WhatIfPreference through the module
    // scope chain and never see the caller's bound -WhatIf. Test-FunctionInterrupt is not needed
    // here: the compiled cmdlet already returns before this hop when begin stopped.
    private const string BodyScript = """
param($Source, $SourceSqlCredential, $SourceDatabase, $Destination, $DestinationSqlCredential, $DestinationDatabase, $Exclude, $AllDatabases, $EnableException, $sourceServer, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    # Untyped flags: PowerShell excludes [switch] from positional binding, and one typed flag
    # would shift every argument after it.
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, [object]$SourceDatabase, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $DestinationSqlCredential, [object[]]$DestinationDatabase, [object[]]$Exclude, $AllDatabases, $EnableException, $sourceServer, $__realCmdlet)

    # Grab the Query Store configuration from the SourceDatabase through the Get-DbaQueryStoreConfig function
    $SourceQSConfig = Get-DbaDbQueryStoreOption -SqlInstance $sourceServer -Database $SourceDatabase

    $sourceDB = Get-DbaDatabase -SqlInstance $sourceServer -Database $SourceDatabase

    foreach ($destinstance in $Destination) {

        if (!$DestinationDatabase -and !$Exclude -and !$AllDatabases) {
            Stop-Function -Message "You must specify databases to execute against using either -DestinationDatabase, -Exclude or -AllDatabases." -Continue -FunctionName Copy-DbaDbQueryStoreOption
        }

        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaDbQueryStoreOption
        }

        # We have to exclude all the system databases since they cannot have the Query Store feature enabled
        $destDBs = Get-DbaDatabase -SqlInstance $destServer -ExcludeSystem

        if ($DestinationDatabase.count -gt 0) {
            $destDBs = $destDBs | Where-Object { $DestinationDatabase -contains $_.Name }
        }

        if ($Exclude.count -gt 0) {
            $destDBs = $destDBs | Where-Object { $exclude -notcontains $_.Name }
        }

        if ($destDBs.count -eq 0) {
            Stop-Function -Message "No matching databases found. Check the spelling and try again." -Continue -FunctionName Copy-DbaDbQueryStoreOption
        }

        foreach ($destDB in $destDBs) {
            # skipping the database if the source and destination are the same instance
            if (($sourceServer.Name -eq $destServer) -and ($SourceDatabase -eq $destDB.Name)) {
                continue
            }
            Write-Message -Message "Processing destination database: $destDB on $destServer." -Level Verbose -FunctionName Copy-DbaDbQueryStoreOption -ModuleName "dbatools"
            $copyQueryStoreStatus = [PSCustomObject]@{
                SourceServer          = $sourceServer.name
                SourceDatabase        = $SourceDatabase
                SourceDatabaseID      = $sourceDB.ID
                DestinationServer     = $destServer
                Name                  = $destDB.name
                DestinationDatabaseID = $destDB.ID
                Type                  = "QueryStore Configuration"
                Status                = $null
                Notes                 = $null
                DateTime              = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($destDB.IsAccessible -eq $false) {
                $copyQueryStoreStatus.Status = "Skipped"
                $copyQueryStoreStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                Write-Message -Level Verbose -Message "The database $destDB on server on $destinstance is not accessible, skipping" -FunctionName Copy-DbaDbQueryStoreOption -ModuleName "dbatools"
                continue
            }

            Write-Message -Message "Executing Set-DbaQueryStoreConfig." -Level Verbose -FunctionName Copy-DbaDbQueryStoreOption -ModuleName "dbatools"
            # Set the Query Store configuration through the Set-DbaQueryStoreConfig function
            if ($__realCmdlet.ShouldProcess($destServer, "Copying QueryStoreConfig for $destdb")) {
                try {
                    if ($sourceServer.VersionMajor -eq 13) {
                        $setDbaDbQueryStoreOptionParameters = @{
                            SqlInstance         = $destServer
                            SqlCredential       = $DestinationSqlCredential
                            Database            = $destDB.name
                            State               = $SourceQSConfig.ActualState
                            FlushInterval       = $SourceQSConfig.DataFlushIntervalInSeconds
                            CollectionInterval  = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                            MaxSize             = $SourceQSConfig.MaxStorageSizeInMB
                            CaptureMode         = $SourceQSConfig.QueryCaptureMode
                            CleanupMode         = $SourceQSConfig.SizeBasedCleanupMode
                            StaleQueryThreshold = $SourceQSConfig.StaleQueryThresholdInDays
                        }
                    } elseif ($sourceServer.VersionMajor -eq 14) {
                        $setDbaDbQueryStoreOptionParameters = @{
                            SqlInstance          = $destServer
                            SqlCredential        = $DestinationSqlCredential
                            Database             = $destDB.name
                            State                = $SourceQSConfig.ActualState
                            FlushInterval        = $SourceQSConfig.DataFlushIntervalInSeconds
                            CollectionInterval   = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                            MaxSize              = $SourceQSConfig.MaxStorageSizeInMB
                            CaptureMode          = $SourceQSConfig.QueryCaptureMode
                            CleanupMode          = $SourceQSConfig.SizeBasedCleanupMode
                            StaleQueryThreshold  = $SourceQSConfig.StaleQueryThresholdInDays
                            MaxPlansPerQuery     = $SourceQSConfig.MaxPlansPerQuery
                            WaitStatsCaptureMode = $SourceQSConfig.WaitStatsCaptureMode
                        }
                    } elseif ($sourceServer.VersionMajor -ge 15) {
                        $setDbaDbQueryStoreOptionParameters = @{
                            SqlInstance                                = $destServer
                            SqlCredential                              = $DestinationSqlCredential
                            Database                                   = $destDB.name
                            State                                      = $SourceQSConfig.ActualState
                            FlushInterval                              = $SourceQSConfig.DataFlushIntervalInSeconds
                            CollectionInterval                         = $SourceQSConfig.StatisticsCollectionIntervalInMinutes
                            MaxSize                                    = $SourceQSConfig.MaxStorageSizeInMB
                            CaptureMode                                = $SourceQSConfig.QueryCaptureMode
                            CleanupMode                                = $SourceQSConfig.SizeBasedCleanupMode
                            StaleQueryThreshold                        = $SourceQSConfig.StaleQueryThresholdInDays
                            MaxPlansPerQuery                           = $SourceQSConfig.MaxPlansPerQuery
                            WaitStatsCaptureMode                       = $SourceQSConfig.WaitStatsCaptureMode
                            CustomCapturePolicyExecutionCount          = $SourceQSConfig.CustomCapturePolicyExecutionCount
                            CustomCapturePolicyTotalCompileCPUTimeMS   = $SourceQSConfig.CustomCapturePolicyTotalCompileCPUTimeMS
                            CustomCapturePolicyTotalExecutionCPUTimeMS = $SourceQSConfig.CustomCapturePolicyTotalExecutionCPUTimeMS
                            CustomCapturePolicyStaleThresholdHours     = $SourceQSConfig.CustomCapturePolicyStaleThresholdHours
                        }
                    }

                    $null = Set-DbaDbQueryStoreOption @setDbaDbQueryStoreOptionParameters
                    $copyQueryStoreStatus.Status = "Successful"
                    $copyQueryStoreStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $copyQueryStoreStatus.Status = "Failed"
                    $copyQueryStoreStatus.Notes = "$PSItem"
                    Write-Message -Level Verbose -Message "Issue setting Query Store  for $destDB on server on $destinstance" -FunctionName Copy-DbaDbQueryStoreOption -ModuleName "dbatools"
                    continue
                }
            }
        }
    }
} $Source $SourceSqlCredential $SourceDatabase $Destination $DestinationSqlCredential $DestinationDatabase $Exclude $AllDatabases $EnableException $sourceServer $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
