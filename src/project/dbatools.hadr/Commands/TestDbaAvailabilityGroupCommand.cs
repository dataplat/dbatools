#nullable enable

using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Tests whether an availability group is in a healthy, failover-ready state.
/// Port of public/Test-DbaAvailabilityGroup.ps1; surface pinned by
/// migration/baselines/Test-DbaAvailabilityGroup.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaAvailabilityGroup")]
public sealed class TestDbaAvailabilityGroupCommand : DbaBaseCmdlet
{
    /// <summary>The SQL Server instance hosting the primary replica.</summary>
    [Parameter(Mandatory = true, Position = 0)]
    public DbaInstanceParameter? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The availability group to test.</summary>
    [Parameter(Mandatory = true)]
    [PsStringCast]
    public string? AvailabilityGroup { get; set; }

    /// <summary>The secondary replica instance(s).</summary>
    [Parameter]
    public DbaInstanceParameter[]? Secondary { get; set; }

    /// <summary>Alternative credentials for the secondary replica(s).</summary>
    [Parameter]
    public PSCredential? SecondarySqlCredential { get; set; }

    /// <summary>Databases to test for add-readiness to the availability group.</summary>
    [Parameter]
    [PsStringArrayCast]
    public string[]? AddDatabase { get; set; }

    /// <summary>The seeding mode to validate against.</summary>
    [Parameter]
    [ValidateSet("Automatic", "Manual")]
    [PsStringCast]
    public string? SeedingMode { get; set; }

    /// <summary>The shared path used for the seeding/restore readiness checks.</summary>
    [Parameter]
    public string? SharedPath { get; set; }

    /// <summary>Validate using the last backup rather than a shared path.</summary>
    [Parameter]
    public SwitchParameter UseLastBackup { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // The SIMPLEST hop in the wave. [CmdletBinding()] with NO ShouldProcess (no transplant, no
        // gate), NO Test-Bound anywhere (so NO bound flags), NO ValueFromPipeline (SqlInstance is a
        // single Mandatory Position-0 DbaInstanceParameter, not a pipeline array), NO cross-record
        // state (detector clean, 0 parameter-target assignments), single-shot. The hop just passes
        // the parameters through and runs the verbatim body.
        //
        // UseLastBackup is passed UNTYPED and as .ToBool() - a typed [switch] in a hop param block
        // is excluded from positional binding (class #7/#8 switch-shift). $EnableException is
        // passed for the 22 Stop-Function calls' dynamic scope read.
        //
        // T8/DEF-002 EXPOSURE (shared-runtime, blocked on A, escalated): AvailabilityGroup [string]
        // and AddDatabase [string[]] flow to called cmdlets. DEF-001 is weaker (read-only) though
        // it emits per replica/database.
        // DEF-001 closed via InvokeScopedStreaming (ab7492c); read-only so no WhatIf interaction.
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
            SqlInstance, SqlCredential, AvailabilityGroup, Secondary, SecondarySqlCredential,
            AddDatabase, SeedingMode, SharedPath, UseLastBackup.ToBool(),
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the source process block VERBATIM, CRLF-preserved and byte-proven against source
    // lines 116-334 (extracted programmatically) after stripping the 22 Stop-Function -FunctionName
    // appends and reversing the 10 direct-Write-Message DEF-006 rewrites (each carries its own
    // # SOURCE: marker; -FunctionName + -ModuleName "dbatools" so the anonymous hop stamps the
    // command name and module the same way the function world does - measured, not assumed). The
    // source has NO Test-Bound (asserted at generation). All of the source's development notes ride
    // untouched. No gate, no sentinel; the source's own `return`s after each Stop-Function are
    // preserved by the dot-block.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $AvailabilityGroup, $Secondary, $SecondarySqlCredential, $AddDatabase, $SeedingMode, $SharedPath, $UseLastBackup, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, [PSCredential]$SqlCredential, [string]$AvailabilityGroup, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$Secondary, [PSCredential]$SecondarySqlCredential, [string[]]$AddDatabase, [string]$SeedingMode, [string]$SharedPath, $UseLastBackup, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        try {
            $server = Connect-DbaInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -FunctionName Test-DbaAvailabilityGroup
            return
        }

        try {
            $ag = Get-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $AvailabilityGroup -EnableException
        } catch {
            Stop-Function -Message "Availability Group $AvailabilityGroup not found on $server." -ErrorRecord $_ -FunctionName Test-DbaAvailabilityGroup
            return
        }

        if (-not $ag) {
            Stop-Function -Message "Availability Group $AvailabilityGroup not found on $server." -FunctionName Test-DbaAvailabilityGroup
            return
        }

        if ($ag.LocalReplicaRole -ne 'Primary') {
            Stop-Function -Message "LocalReplicaRole of replica $server is not Primary, but $($ag.LocalReplicaRole). Please connect to the current primary replica $($ag.PrimaryReplica)." -FunctionName Test-DbaAvailabilityGroup
            return
        }

        # Test for health of Availability Group

        # Later: Get replica and database states like in SSMS dashboard
        # Now: Just test for ConnectionState -eq 'Connected'

        # Note on further development:
        # As long as there are no databases in the Availability Group, test for RollupSynchronizationState is not useful

        # The primary replica always has the best information about all the replicas.
        # We can maybe also connect to the secondary replicas and test their view of the situation, but then only test the local replica.

        $failure = $false
        foreach ($replica in $ag.AvailabilityReplicas) {
            if ($replica.ConnectionState -ne 'Connected') {
                $failure = $true
                Stop-Function -Message "ConnectionState of replica $replica is not Connected, but $($replica.ConnectionState)." -Continue -FunctionName Test-DbaAvailabilityGroup
            }
        }
        if ($failure) {
            Stop-Function -Message "ConnectionState of one or more replicas is not Connected." -FunctionName Test-DbaAvailabilityGroup
            return
        }


        # For now, just output the base information.

        if (-not $AddDatabase) {
            [PSCustomObject]@{
                ComputerName      = $ag.ComputerName
                InstanceName      = $ag.InstanceName
                SqlInstance       = $ag.SqlInstance
                AvailabilityGroup = $ag.AvailabilityGroup
            }
        }


        # Test for Add-DbaAgDatabase

        foreach ($dbName in $AddDatabase) {
            $db = $server.Databases[$dbName]

            if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
                Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above" -Target $server -FunctionName Test-DbaAvailabilityGroup
                return
            }

            if (-not $db) {
                Stop-Function -Message "Database [$dbName] is not found on $server." -Continue -FunctionName Test-DbaAvailabilityGroup
            }

            $null = $db.Refresh()

            if ($db.RecoveryModel -ne 'Full') {
                Stop-Function -Message "RecoveryModel of database $db is not Full, but $($db.RecoveryModel)." -Continue -FunctionName Test-DbaAvailabilityGroup
            }

            if ($db.Status -ne 'Normal') {
                Stop-Function -Message "Status of database $db is not Normal, but $($db.Status)." -Continue -FunctionName Test-DbaAvailabilityGroup
            }

            $backups = @( )
            if ($UseLastBackup) {
                try {
                    $backups = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.Name -IncludeCopyOnly -Last -EnableException
                } catch {
                    Stop-Function -Message "Failed to get backup history for database $db." -ErrorRecord $_ -Continue -FunctionName Test-DbaAvailabilityGroup
                }
                if ($backups.Type -notcontains 'Log') {
                    Stop-Function -Message "Cannot use last backup for database $db. A log backup must be the last backup taken." -Continue -FunctionName Test-DbaAvailabilityGroup
                }
            }

            if ($SeedingMode -eq 'Automatic' -and $server.VersionMajor -lt 13) {
                Stop-Function -Message "Automatic seeding mode only supported in SQL Server 2016 and above." -Continue -FunctionName Test-DbaAvailabilityGroup
            }

            # Try to connect to secondary replicas as soon as possible to fail the command before making any changes to the Availability Group.
            # Also test if these are really secondary replicas for that availability group. Only needed if -Secondary is used, but will do it anyway to simplify code.
            # Also test if database is already at the secondary and if so if Status is Restoring.
            # We store the server SMO in a hashtable based on the DomainInstanceName of the server as this is equal to the name of the replica in $ag.AvailabilityReplicas.
            if ($Secondary) {
                $secondaryReplicas = $Secondary
            } else {
                $secondaryReplicas = ($ag.AvailabilityReplicas | Where-Object { $_.Role -eq 'Secondary' }).Name
            }

            $replicaServerSMO = @{ }
            $restoreNeeded = @{ }
            $backupNeeded = $false
            $failure = $false
            foreach ($replica in $secondaryReplicas) {
                try {
                    $replicaServer = Connect-DbaInstance -SqlInstance $replica -SqlCredential $SecondarySqlCredential
                } catch {
                    $failure = $true
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $replica -Continue -FunctionName Test-DbaAvailabilityGroup
                }

                try {
                    $replicaAg = Get-DbaAvailabilityGroup -SqlInstance $replicaServer -AvailabilityGroup $AvailabilityGroup -EnableException
                    $replicaName = $replicaAg.Parent.DomainInstanceName
                } catch {
                    $failure = $true
                    Stop-Function -Message "Availability Group $AvailabilityGroup not found on replica $replicaServer." -ErrorRecord $_ -Continue -FunctionName Test-DbaAvailabilityGroup
                }

                if (-not $replicaAg) {
                    $failure = $true
                    Stop-Function -Message "Availability Group $AvailabilityGroup not found on replica $replicaServer." -Continue -FunctionName Test-DbaAvailabilityGroup
                }

                if ($replicaAg.LocalReplicaRole -ne 'Secondary') {
                    $failure = $true
                    Stop-Function -Message "LocalReplicaRole of replica $replicaServer is not Secondary, but $($replicaAg.LocalReplicaRole)." -Continue -FunctionName Test-DbaAvailabilityGroup
                }

                $replicaDb = $replicaAg.Parent.Databases[$db.Name]

                if ($replicaDb) {
                    # Database already present on replica, so test if already joined or if we can use it.
                    if ($replicaDb.AvailabilityGroupName -eq $AvailabilityGroup) {
                        Write-Message -Level Verbose -Message "Database $db is already part of the Availability Group on replica $replicaName." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db is already part of the Availability Group on replica $replicaName."
                    } else {
                        if ($replicaDb.Status -ne 'Restoring') {
                            $failure = $true
                            Stop-Function -Message "Status of database $db on replica $replicaName is not Restoring, but $($replicaDb.Status)" -Continue -FunctionName Test-DbaAvailabilityGroup
                        }
                        if ($UseLastBackup) {
                            $failure = $true
                            Stop-Function -Message "Database $db is already present on $replicaName, so -UseLastBackup must not be used. Please remove database from replica to use -UseLastBackup." -Continue -FunctionName Test-DbaAvailabilityGroup
                        }
                        Write-Message -Level Verbose -Message "Database $db is already present in restoring status on replica $replicaName." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db is already present in restoring status on replica $replicaName."
                    }
                } else {
                    # No database on replica, so test if we need a backup.
                    # We need to restore a backup if the desired or the current seeding mode is manual.
                    # To have a detailed verbose message, we test in small steps.
                    if ($SeedingMode -eq 'Automatic') {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic') {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName. The replica is already configured accordingly." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName. The replica is already configured accordingly."
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName. The replica will be configured accordingly." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName. The replica will be configured accordingly."
                        }
                        if ($db.LastBackupDate.Year -eq 1) {
                            # Automatic seeding only works with databases that are really in RecoveryModel Full, so a full backup has been taken.
                            Write-Message -Level Verbose -Message "Database $db will need a backup first. This is ok if one of the other replicas uses manual seeding." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db will need a backup first. This is ok if one of the other replicas uses manual seeding."
                            $backupNeeded = $true
                        }
                    } elseif ($SeedingMode -eq 'Manual') {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Manual') {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName. The replica is already configured accordingly." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName. The replica is already configured accordingly."
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName. The replica will be configured accordingly." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName. The replica will be configured accordingly."
                        }
                        $restoreNeeded[$replicaName] = $true
                    } else {
                        if ($ag.AvailabilityReplicas[$replicaName].SeedingMode -eq 'Automatic') {
                            Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db will use automatic seeding on replica $replicaName."
                            if ($db.LastBackupDate.Year -eq 1) {
                                # Automatic seeding only works with databases that are really in RecoveryModel Full, so a full backup has been taken.
                                Write-Message -Level Verbose -Message "Database $db will need a backup first. This is ok if one of the other replicas uses manual seeding." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db will need a backup first. This is ok if one of the other replicas uses manual seeding."
                                $backupNeeded = $true
                            }
                        } else {
                            Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName." -FunctionName Test-DbaAvailabilityGroup -ModuleName "dbatools" # SOURCE: Write-Message -Level Verbose -Message "Database $db will need a restore on replica $replicaName."
                            $restoreNeeded[$replicaName] = $true
                        }
                    }
                }
                $replicaServerSMO[$replicaName] = $replicaAg.Parent
            }
            if ($failure) {
                Stop-Function -Message "Availability Group $AvailabilityGroup or database $db not found in suitable state on all secondary replicas." -Continue -FunctionName Test-DbaAvailabilityGroup
            }
            if ($restoreNeeded.Count -gt 0 -and -not $SharedPath -and -not $UseLastBackup) {
                Stop-Function -Message "A restore of database $db is needed on one or more replicas, but -SharedPath or -UseLastBackup are missing." -Continue -FunctionName Test-DbaAvailabilityGroup
            }
            if ($backupNeeded -and $restoreNeeded.Count -eq 0) {
                Stop-Function -Message "All replicas are configured to use automatic seeding, but the database $db was never backed up. Please backup the database or use manual seeding." -Continue -FunctionName Test-DbaAvailabilityGroup
            }

            [PSCustomObject]@{
                ComputerName          = $ag.ComputerName
                InstanceName          = $ag.InstanceName
                SqlInstance           = $ag.SqlInstance
                AvailabilityGroupName = $ag.Name
                DatabaseName          = $db.Name
                AvailabilityGroupSMO  = $ag
                DatabaseSMO           = $db
                PrimaryServerSMO      = $server
                ReplicaServerSMO      = $replicaServerSMO
                RestoreNeeded         = $restoreNeeded
                Backups               = $backups
            }
        }
    }
} $SqlInstance $SqlCredential $AvailabilityGroup $Secondary $SecondarySqlCredential $AddDatabase $SeedingMode $SharedPath $UseLastBackup $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}