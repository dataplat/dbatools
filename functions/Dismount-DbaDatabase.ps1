function Dismount-DbaDatabase {
    <#
        .SYNOPSIS
            Detach a SQL Server Database.

        .DESCRIPTION
            This command detaches one or more SQL Server databases. If necessary, -Force can be used to break mirrors and remove databases from availability groups prior to detaching.

        .PARAMETER SqlInstance
            The SQL Server instance.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            The database(s) to detach.

        .PARAMETER FileStructure
            A StringCollection object value that contains a list database files. If FileStructure is not specified, BackupHistory will be used to guess the structure.

        .PARAMETER DatabaseCollection
            A collection of databases (such as returned by Get-DbaDatabase), to be detached.

        .PARAMETER UpdateStatistics
            If this switch is enabled, statistics for the database will be updated prior to detaching it.

        .PARAMETER Force
            If this switch is enabled and the database is part of a mirror, the mirror will be broken. If the database is part of an Availability Group, it will be removed from the AG.

        .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Database
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Dismount-DbaDatabase

        .EXAMPLE
            Detach-DbaDatabase -SqlInstance sql2016b -Database SharePoint_Config, WSS_Logging

            Detaches SharePoint_Config and WSS_Logging from sql2016b

        .EXAMPLE
            Get-DbaDatabase -SqlInstance sql2016b -Database 'PerformancePoint Service Application_10032db0fa0041df8f913f558a5dc0d4' | Detach-DbaDatabase -Force

            Detaches 'PerformancePoint Service Application_10032db0fa0041df8f913f558a5dc0d4' from sql2016b. Since Force was specified, if the database is part of mirror, the mirror will be broken prior to detaching.

            If the database is part of an Availability Group, it will first be dropped prior to detachment.

            .EXAMPLE
            Get-DbaDatabase -SqlInstance sql2016b -Database WSS_Logging | Detach-DbaDatabase -Force -WhatIf

            Shows what would happen if the command were to execute (without actually executing the detach/break/remove commands).

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default")]
    Param (
        [parameter(Mandatory, ParameterSetName = 'SqlInstance')]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ParameterSetName = 'SqlInstance')]
        [string]$Database,
        [parameter(Mandatory, ParameterSetName = 'Pipeline', ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$DatabaseCollection,
        [Switch]$UpdateStatistics,
        [switch]$Force,
        [switch][Alias('Silent')]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $DatabaseCollection += $server.Databases | Where-Object Name -in $Database
            }
            else {
                $DatabaseCollection += $server.Databases
            }

            if ($ExcludeDatabase) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
            }
        }

        foreach ($db in $DatabaseCollection) {
            $db.Refresh()
            $server = $db.Parent

            if ($db.IsSystemObject) {
                Stop-Function -Message "$db is a system database and cannot be detached using this method." -Target $db -Continue
            }

            Write-Message -Level Verbose -Message "Checking replication status."
            if ($db.ReplicationOptions -ne "None") {
                Stop-Function -Message "Skipping $db  on $server because it is replicated." -Target $db -Continue
            }

            # repeat because different servers could be piped in
            $snapshots = (Get-DbaDatabaseSnapshot -SqlInstance $server).SnapshotOf
            Write-Message -Level Verbose -Message "Checking for snaps"
            if ($db.Name -in $snapshots) {
                Write-Message -Level Warning -Message "Database $db has snapshots, you need to drop them before detaching. Skipping $db on $server."
                Continue
            }

            Write-Message -Level Verbose -Message "Checking mirror status"
            if ($db.IsMirroringEnabled -and !$Force) {
                Stop-Function -Message "$db on $server is being mirrored. Use -Force to break mirror or use the safer backup/restore method." -Target $db -Continue
            }

            Write-Message -Level Verbose -Message "Checking Availability Group status"

            if ($db.AvailabilityGroupName -and !$Force) {
                $ag = $db.AvailabilityGroupName
                Stop-Function -Message "$db on $server is part of an Availability Group ($ag). Use -Force to drop from $ag availability group to detach. Alternatively, you can use the safer backup/restore method." -Target $db -Continue
            }

            $sessions = Get-DbaProcess -SqlInstance $db.Parent -Database $db.Name

            if ($sessions -and !$Force) {
                Stop-Function -Message "$db on $server currently has connected users and cannot be dropped. Use -Force to kill all connections and detach the database." -Target $db -Continue
            }

            if ($force) {

                if ($sessions) {
                    If ($Pscmdlet.ShouldProcess($server, "Killing $($sessions.count) sessions which are connected to $db")) {
                        $null = $sessions | Stop-DbaProcess -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                    }
                }

                if ($db.IsMirroringEnabled) {
                    If ($Pscmdlet.ShouldProcess($server, "Breaking mirror for $db on $server")) {
                        try {
                            Write-Message -Level Warning -Message "Breaking mirror for $db on $server."
                            $db.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                            $db.Alter()
                            $db.Refresh()
                        }
                        catch {
                            Stop-Function -Message "Could not break mirror for $db on $server - not detaching." -Target $db -ErrorRecord $_ -Continue
                        }
                    }
                }

                if ($db.AvailabilityGroupName) {
                    $ag = $db.AvailabilityGroupName
                    If ($Pscmdlet.ShouldProcess($server, "Attempting remove $db on $server from Availability Group $ag")) {
                        try {
                            $server.AvailabilityGroups[$ag].AvailabilityDatabases[$db.name].Drop()
                            Write-Message -Level Verbose -Message "Successfully removed $db from  detach from $ag on $server."
                        }
                        catch {
                            if ($_.Exception.InnerException) {
                                $exception = $_.Exception.InnerException.ToString() -Split "System.Data.SqlClient.SqlException: "
                                $exception = " | $(($exception[1] -Split "at Microsoft.SqlServer.Management.Common.ConnectionManager")[0])".TrimEnd()
                            }

                            Stop-Function -Message "Could not remove $db from $ag on $server $exception." -Target $db -ErrorRecord $_ -Continue
                        }
                    }
                }

                $sessions = Get-DbaProcess -SqlInstance $db.Parent -Database $db.Name

                if ($sessions) {
                    If ($Pscmdlet.ShouldProcess($server, "Killing $($sessions.count) sessions which are still connected to $db")) {
                        $null = $sessions | Stop-DbaProcess -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
                    }
                }
            }

            If ($Pscmdlet.ShouldProcess($server, "Detaching $db on $server")) {
                try {
                    $server.DetachDatabase($db.Name, $UpdateStatistics)

                    [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        DetachResult = "Success"
                    }
                }
                catch {
                    Stop-Function -Message "Failure" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}