#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Add-DbaAgDatabase {
    <#
    .SYNOPSIS
        Adds a database to an availability group on a SQL Server instance.

    .DESCRIPTION
        Adds a database to an availability group on a SQL Server instance.

        Before joining the replica databases to the availablity group, the databases will be initialized with automatic seeding or full/log backup.

   .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

        This should be the primary replica.

    .PARAMETER SqlCredential
        Login to the SqlInstance instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Database
        The database or databases to add.

    .PARAMETER AvailabilityGroup
        The availability group where the databases will be added.

    .PARAMETER Secondary
        Not required - the command will figure this out. But if you'd like to be explicit about replicas, this will help.

    .PARAMETER SecondarySqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER InputObject
        Enables piping from Get-DbaDatabase, Get-DbaDbSharePoint and more.

    .PARAMETER SeedingMode
        Specifies how the secondary replica will be initially seeded.

        Automatic enables direct seeding. This method will seed the secondary replica over the network. This method does not require you to backup and restore a copy of the primary database on the replica.

        Manual requires you to create a backup of the database on the primary replica and manually restore that backup on the secondary replica.

        If not specified, the setting from the availability group replica will be used. Otherwise the setting will be updated.

    .PARAMETER SharedPath
        The network share where the backups will be backed up and restored from.

        Each SQL Server service account must have access to this share.

        NOTE: If a backup / restore is performed, the backups will be left in tact on the network share.

    .PARAMETER UseLastBackup
        Use the last full backup of database.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AvailabilityGroup, HA, AG
        Author: Chrissy LeMaire (@cl), netnerds.net
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Add-DbaAgDatabase

    .EXAMPLE
        PS C:\> Add-DbaAgDatabase -SqlInstance sql2017a -AvailabilityGroup ag1 -Database db1, db2 -Confirm

        Adds db1 and db2 to ag1 on sql2017a. Prompts for confirmation.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2017a | Out-GridView -Passthru | Add-DbaAgDatabase -AvailabilityGroup ag1

        Adds selected databases from sql2017a to ag1

    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster | Add-DbaAgDatabase -AvailabilityGroup SharePoint

        Adds SharePoint databases as found in SharePoint_Config on sqlcluster to ag1 on sqlcluster

    .EXAMPLE
        PS C:\> Get-DbaDbSharePoint -SqlInstance sqlcluster -ConfigDatabase SharePoint_Config_2019 | Add-DbaAgDatabase -AvailabilityGroup SharePoint

        Adds SharePoint databases as found in SharePoint_Config_2019 on sqlcluster to ag1 on sqlcluster
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$AvailabilityGroup,
        [string[]]$Database,
        [DbaInstanceParameter[]]$Secondary,
        [PSCredential]$SecondarySqlCredential,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [ValidateSet('Automatic', 'Manual')]
        [string]$SeedingMode,
        [string]$SharedPath,
        [switch]$UseLastBackup,
        [switch]$EnableException
    )
    process {
        if ((Test-Bound -ParameterName SqlInstance)) {
            if ((Test-Bound -Not -ParameterName Database) -or (Test-Bound -Not -ParameterName AvailabilityGroup)) {
                Stop-Function -Message "You must specify one or more databases and one Availability Group when using the SqlInstance parameter."
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $allbackups = @{
            }

            $Primary = $db.Parent
            # check primary, should be run against primary
            $ag = Get-DbaAvailabilityGroup -SqlInstance $db.Parent -AvailabilityGroup $AvailabilityGroup

            if ($ag.AvailabilityDatabases.Name -contains $db.Name) {
                Stop-Function -Message "$($db.Name) is already joined to $($ag.Name)" -Continue
            }

            if (-not $Secondary) {
                $secondaryReplicas = $ag.AvailabilityReplicas | Where-Object Role -eq Secondary
            } else {
                $secondaryReplicas = Get-DbaAgReplica -SqlInstance $Secondary -SqlCredential $SecondarySqlCredential -AvailabilityGroup $ag.Name | Where-Object Role -eq Secondary
            }

            if ($SeedingMode -eq "Automatic") {
                # first check
                if ($Pscmdlet.ShouldProcess($Primary, "Backing up $db to NUL")) {
                    $null = Backup-DbaDatabase -BackupFileName NUL -SqlInstance $Primary -SqlCredential $SqlCredential -Database $db
                }
            }

            if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Adding availability group $db to $($db.Parent.Name)")) {
                try {
                    $agdb = New-Object Microsoft.SqlServer.Management.Smo.AvailabilityDatabase($ag, $db.Name)
                    # something is up with .net create(), force a stop
                    Invoke-Create -Object $agdb
                    Get-DbaAgDatabase -SqlInstance $ag.Parent -Database $db.Name
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }

            foreach ($replica in $secondaryReplicas) {

                $agreplica = Get-DbaAgReplica -SqlInstance $Primary -SqlCredential $SqlCredential -AvailabilityGroup $ag.name -Replica $replica.Name

                if ($SeedingMode) {
                    $agreplica.SeedingMode = $SeedingMode
                    $agreplica.alter()
                }
                $agreplica.refresh()
                $SeedingModeReplica = $agreplica.SeedingMode

                $primarydb = Get-DbaDatabase -SqlInstance $Primary -SqlCredential $SqlCredential -Database $db.name

                if ($SeedingModeReplica -ne 'Automatic') {
                    try {
                        if (-not $allbackups[$db]) {
                            if ($UseLastBackup) {
                                $allbackups[$db] = Get-DbaBackupHistory -SqlInstance $primarydb.Parent -Database $primarydb.Name -IncludeCopyOnly -Last -EnableException
                            } else {
                                $fullbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Full -EnableException
                                $logbackup = $primarydb | Backup-DbaDatabase -BackupDirectory $SharedPath -Type Log -EnableException
                                $allbackups[$db] = $fullbackup, $logbackup
                            }
                            Write-Message -Level Verbose -Message "Backups still exist on $SharedPath"
                        }
                        if ($Pscmdlet.ShouldProcess("$Secondary", "restoring full and log backups of $primarydb from $Primary")) {
                            # keep going to ensure output is shown even if dbs aren't added well.
                            $null = $allbackups[$db] | Restore-DbaDatabase -SqlInstance $replica.Parent.Parent -WithReplace -NoRecovery -TrustDbBackupHistory -EnableException
                        }
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                    }
                }

                $replicadb = Get-DbaAgDatabase -SqlInstance $replica.Parent.Parent -Database $db.Name -AvailabilityGroup $ag.Name   #credential of secondary !!

                if ($replicadb -and -not ($SeedingModeReplica -eq 'Automatic')) {
                    if ($Pscmdlet.ShouldProcess($ag.Parent.Name, "Joining availability group $db to $($db.Parent.Name)")) {
                        $timeout = 1
                        do {
                            try {
                                Write-Message -Level Verbose -Message "Trying to add $($replicadb.Name) to $($replica.Name)"
                                $timeout++
                                $replicadb.JoinAvailablityGroup()
                                $replicadb.Refresh()
                                Start-Sleep -Seconds 1
                            } catch {
                                Stop-Function -Message "Error joining database to availability group" -ErrorRecord $_ -Continue
                            }
                        } while (-not $replicadb.IsJoined -and $timeout -lt 10)

                        if ($replicadb.IsJoined) {
                            $replicadb
                        } else {
                            Stop-Function -Continue -Message "Could not join $($replicadb.Name) to $($replica.Name)"
                        }
                    }
                } else {
                    $replicadb
                }
            }
        }
    }
}