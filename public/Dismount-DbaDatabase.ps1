function Dismount-DbaDatabase {
    <#
    .SYNOPSIS
        Detaches one or more databases from a SQL Server instance with built-in safety checks and validation.

    .DESCRIPTION
        Safely detaches databases from SQL Server instances while performing comprehensive validation checks before detachment. This function automatically validates that databases aren't system databases, replicated, or have active snapshots, preventing common detachment failures. When databases are part of mirroring or Availability Groups, the -Force parameter allows automatic cleanup by breaking mirrors and removing databases from AGs before detaching. Active user connections can also be forcibly terminated when needed. This command is essential for database migration scenarios, decommissioning databases, or moving databases between instances without using backup/restore methods.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the name(s) of databases to detach from the SQL Server instance. Accepts wildcards for pattern matching.
        Use this when you need to detach specific databases by name rather than passing database objects through the pipeline.

    .PARAMETER InputObject
        Accepts database objects from the pipeline for detachment operations. Typically used with Get-DbaDatabase output.
        This allows you to filter and select databases using Get-DbaDatabase before detaching them, providing more control over the selection process.

    .PARAMETER UpdateStatistics
        Updates database statistics before detaching the database to ensure optimal performance if the database is later reattached.
        Use this when you plan to reattach the database later and want to maintain current statistics for query optimization.

    .PARAMETER Force
        Bypasses safety checks and handles blocking conditions that prevent database detachment. Automatically breaks database mirroring, removes databases from Availability Groups, and terminates active user connections.
        Use this when you need to detach databases that are part of high availability configurations or have active connections that cannot be closed gracefully.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Detach, Database
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Dismount-DbaDatabase

    .EXAMPLE
        PS C:\> Detach-DbaDatabase -SqlInstance sql2016b -Database SharePoint_Config, WSS_Logging

        Detaches SharePoint_Config and WSS_Logging from sql2016b

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016b -Database 'PerformancePoint Service Application_10032db0fa0041df8f913f558a5dc0d4' | Detach-DbaDatabase -Force

        Detaches 'PerformancePoint Service Application_10032db0fa0041df8f913f558a5dc0d4' from sql2016b. Since Force was specified, if the database is part of mirror, the mirror will be broken prior to detaching.

        If the database is part of an Availability Group, it will first be dropped prior to detachment.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sql2016b -Database WSS_Logging | Detach-DbaDatabase -Force -WhatIf

        Shows what would happen if the command were to execute (without actually executing the detach/break/remove commands).

    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = "Default", ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ParameterSetName = 'SqlInstance')]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ParameterSetName = 'SqlInstance')]
        [string[]]$Database,
        [parameter(Mandatory, ParameterSetName = 'Pipeline', ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [Switch]$UpdateStatistics,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $InputObject += $server.Databases | Where-Object Name -in $Database
            } else {
                $InputObject += $server.Databases
            }

            if ($ExcludeDatabase) {
                $InputObject = $InputObject | Where-Object Name -NotIn $ExcludeDatabase
            }
        }

        foreach ($db in $InputObject) {
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
            $snapshots = (Get-DbaDbSnapshot -SqlInstance $server).SnapshotOf
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
                        } catch {
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
                        } catch {
                            if ($_.Exception.InnerException) {
                                $exception = $_.Exception.InnerException.ToString() -Split "Microsoft.Data.SqlClient.SqlException: "
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
                    $dbID = $db.ID
                    $server.DetachDatabase($db.Name, $UpdateStatistics)

                    [PSCustomObject]@{
                        ComputerName = $server.ComputerName
                        InstanceName = $server.ServiceName
                        SqlInstance  = $server.DomainInstanceName
                        Database     = $db.name
                        DatabaseID   = $dbID
                        DetachResult = "Success"
                    }
                } catch {
                    Stop-Function -Message "Failure" -Target $db -ErrorRecord $_ -Continue
                }
            }
        }
    }
}