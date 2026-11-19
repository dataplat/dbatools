#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies SQL Data Collector collection sets between instances. Port of
/// public/Copy-DbaDataCollector.ps1. The whole workflow rides one module-scoped PowerShell hop
/// because it leans on the Collector SMO config store, ScriptCreate/ScriptAlter, the private
/// Get-ErrorMessage helper and Select-DefaultView decoration, all of which keep the retired
/// function's engine semantics there. The compiled cmdlet supplies the real ShouldProcess
/// runtime. Surface pinned by migration/baselines/Copy-DbaDataCollector.json.
/// </summary>
[Cmdlet(VerbsCommon.Copy, "DbaDataCollector", DefaultParameterSetName = "Default",
    SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class CopyDbaDataCollectorCommand : DbaBaseCmdlet
{
    /// <summary>Source SQL Server instance. Requires sysadmin and SQL Server 2008 or higher.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter Source { get; set; } = null!;

    /// <summary>Alternative credential for the source instance.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SourceSqlCredential { get; set; }

    /// <summary>Destination SQL Server instances. Data Collector must already be enabled there.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    public DbaInstanceParameter[] Destination { get; set; } = null!;

    /// <summary>Alternative credential for destination instances.</summary>
    [Parameter(Position = 3)]
    public PSCredential? DestinationSqlCredential { get; set; }

    /// <summary>Only copy the collection sets with these names.</summary>
    [Parameter(Position = 4)]
    public object[]? CollectionSet { get; set; }

    /// <summary>Skip the collection sets with these names.</summary>
    [Parameter(Position = 5)]
    public object[]? ExcludeCollectionSet { get; set; }

    /// <summary>Reserved for future server-level configuration copying; suppresses the placeholder status object.</summary>
    [Parameter]
    public SwitchParameter NoServerReconfig { get; set; }

    /// <summary>Drop and recreate collection sets that already exist on the destination.</summary>
    [Parameter]
    public SwitchParameter Force { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
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
            Source, SourceSqlCredential, Destination, DestinationSqlCredential,
            CollectionSet, ExcludeCollectionSet, NoServerReconfig.ToBool(), Force.ToBool(),
            EnableException.ToBool(), this, NestedCommand.BoundCommonParameter(this, "Verbose"),
            NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    private const string BodyScript = """
param($Source, $SourceSqlCredential, $Destination, $DestinationSqlCredential, $CollectionSet, $ExcludeCollectionSet, $NoServerReconfig, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$Source, $SourceSqlCredential, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Destination, $DestinationSqlCredential, [object[]]$CollectionSet, [object[]]$ExcludeCollectionSet, $NoServerReconfig, $Force, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)

    if (-not $script:isWindows) {
        Stop-Function -Message "Copy-DbaDataCollector does not support Linux - we're still waiting for the Core SMOs from Microsoft" -FunctionName Copy-DbaDataCollector
        return
    }
    try {
        $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 10
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source -FunctionName Copy-DbaDataCollector
        return
    }
    $sourceSqlConn = $sourceServer.ConnectionContext.SqlConnectionObject
    $sourceSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $sourceSqlConn
    $sourceStore = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $sourceSqlStoreConnection
    $configDb = $sourceStore.ScriptAlter().GetScript() | Out-String
    $configDb = $configDb -replace [Regex]::Escape("'$source'"), "'$destReplace'"

    if ($Force) { $ConfirmPreference = "none" }

    if (Test-FunctionInterrupt) { return }
    foreach ($destinstance in $Destination) {

        try {
            $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 10
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue -FunctionName Copy-DbaDataCollector
        }
        if ($NoServerReconfig -eq $false) {
            if ($__realCmdlet.ShouldProcess($destinstance, "Server reconfiguration not yet supported. Only Collection Set migration will be migrated at this time.")) {
                Write-Message -Level Verbose -Message "Server reconfiguration not yet supported. Only Collection Set migration will be migrated at this time." -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                $NoServerReconfig = $true

                <# for future use when this support is added #>
                $copyServerConfigStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $userName
                    Type              = "Data Collection Server Config"
                    Status            = "Skipped"
                    Notes             = "Not supported at this time"
                    DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }
                $copyServerConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
            }
        }
        $destSqlConn = $destServer.ConnectionContext.SqlConnectionObject
        $destSqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $destSqlConn
        $destStore = New-Object Microsoft.SqlServer.Management.Collector.CollectorConfigStore $destSqlStoreConnection

        if (!$NoServerReconfig) {
            if ($__realCmdlet.ShouldProcess($destinstance, "Attempting to modify Data Collector configuration")) {
                try {
                    $sql = "Unknown at this time"
                    $destServer.Query($sql)
                    $destStore.Alter()
                } catch {
                    $copyServerConfigStatus.Status = "Failed"
                    $copyServerConfigStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Stop-Function -Message "Issue modifying Data Collector configuration" -Target $destServer -ErrorRecord $_ -FunctionName Copy-DbaDataCollector
                }
            }
        }

        if ($destStore.Enabled -eq $false) {
            Write-Message -Level Verbose -Message "The Data Collector must be setup initially for Collection Sets to be migrated. Setup the Data Collector and try again." -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
            continue
        }

        $storeCollectionSets = $sourceStore.CollectionSets | Where-Object { $_.IsSystem -eq $false }
        if ($CollectionSet) {
            $storeCollectionSets = $storeCollectionSets | Where-Object Name -In $CollectionSet
        }
        if ($ExcludeCollectionSet) {
            $storeCollectionSets = $storeCollectionSets | Where-Object Name -NotIn $ExcludeCollectionSet
        }

        Write-Message -Level Verbose -Message "Migrating collection sets" -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
        foreach ($set in $storeCollectionSets) {
            $collectionName = $set.Name

            $copyCollectionSetStatus = [PSCustomObject]@{
                SourceServer      = $sourceServer.Name
                DestinationServer = $destServer.Name
                Name              = $collectionName
                Type              = "Collection Set"
                Status            = $null
                Notes             = $null
                DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
            }

            if ($null -ne $destStore.CollectionSets[$collectionName]) {
                if ($force -eq $false) {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Collection Set '$collectionName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate")) {
                        Write-Message -Level Verbose -Message "Collection Set '$collectionName' was skipped because it already exists on $destinstance. Use -Force to drop and recreate" -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                        $copyCollectionSetStatus.Status = "Skipped"
                        $copyCollectionSetStatus.Notes = "Already exists on destination"
                        $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    }
                    continue
                } else {
                    if ($__realCmdlet.ShouldProcess($destinstance, "Attempting to drop $collectionName")) {
                        Write-Message -Level Verbose -Message "Collection Set '$collectionName' exists on $destinstance" -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                        Write-Message -Level Verbose -Message "Force specified. Dropping $collectionName." -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"

                        try {
                            $destStore.CollectionSets[$collectionName].Drop()
                        } catch {
                            $copyCollectionSetStatus.Status = "Failed to drop collection $collectionName on $destinstance"
                            $copyCollectionSetStatus.Notes = (Get-ErrorMessage -Record $_)
                            $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Failed to drop collection $collectionName on $destinstance | $PSItem" -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                            continue
                        }
                    }
                }
            }

            if ($__realCmdlet.ShouldProcess($destinstance, "Migrating collection set $collectionName")) {
                try {
                    $sql = $set.ScriptCreate().GetScript() | Out-String
                    $sql = $sql -replace [Regex]::Escape("'$source'"), "'$destinstance'"
                    Write-Message -Level Debug -Message $sql -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                    Write-Message -Level Verbose -Message "Migrating collection set $collectionName" -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                    $destServer.Query($sql)
                    $copyCollectionSetStatus.Status = "Successful"
                    $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $copyCollectionSetStatus.Status = "Failed to create collection"
                    $copyCollectionSetStatus.Notes = (Get-ErrorMessage -Record $_)
                    Write-Message -Level Verbose -Message "Issue creating collection $collectionName on $destinstance | $PSItem" -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                    continue
                }

                try {
                    if ($set.IsRunning) {
                        Write-Message -Level Verbose -Message "Starting collection set $collectionName" -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                        $destStore.CollectionSets.Refresh()
                        $destStore.CollectionSets[$collectionName].Start()
                    }

                    $copyCollectionSetStatus.Status = "Successful started Collection"
                    $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                } catch {
                    $copyCollectionSetStatus.Status = "Failed to start collection"
                    $copyCollectionSetStatus.Notes = (Get-ErrorMessage -Record $_)
                    $copyCollectionSetStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Issue starting collection $collectionName on $destinstance | $PSItem" -FunctionName Copy-DbaDataCollector -ModuleName "dbatools"
                }
            }
        }
    }
} $Source $SourceSqlCredential $Destination $DestinationSqlCredential $CollectionSet $ExcludeCollectionSet $NoServerReconfig $Force $EnableException $__realCmdlet $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
