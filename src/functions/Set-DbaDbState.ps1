function Set-DbaDbState {
    <#
    .SYNOPSIS
        Sets various options for databases, hereby called "states"

    .DESCRIPTION
        Sets some common "states" on databases:
        - "RW" options (ReadOnly, ReadWrite)
        - "Status" options (Online, Offline, Emergency, plus a special "Detached")
        - "Access" options (SingleUser, RestrictedUser, MultiUser)

        Returns an object with SqlInstance, Database, RW, Status, Access, Notes

        Notes gets filled when something went wrong setting the state

    .PARAMETER SqlInstance
        The target SQL Server instance or instances

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. if unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER AllDatabases
        This is a parameter that was included for safety, so you don't accidentally set options on all databases without specifying

    .PARAMETER ReadOnly
        RW Option : Sets the database as READ_ONLY

    .PARAMETER ReadWrite
        RW Option : Sets the database as READ_WRITE

    .PARAMETER Online
        Status Option : Sets the database as ONLINE

    .PARAMETER Offline
        Status Option : Sets the database as OFFLINE

    .PARAMETER Emergency
        Status Option : Sets the database as EMERGENCY

    .PARAMETER Detached
        Status Option : Detaches the database

    .PARAMETER SingleUser
        Access Option : Sets the database as SINGLE_USER

    .PARAMETER RestrictedUser
        Access Option : Sets the database as RESTRICTED_USER

    .PARAMETER MultiUser
        Access Option : Sets the database as MULTI_USER

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER Force
        For most options, this translates to instantly rolling back any open transactions
        that may be stopping the process.
        For -Detached it is required to break mirroring and Availability Groups

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER InputObject
        Accepts piped database objects

    .NOTES
        Tags: Database, State
        Author: Simone Bizzotto (@niphold)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaDbState

    .EXAMPLE
        PS C:\> Set-DbaDbState -SqlInstance sqlserver2014a -Database HR -Offline

        Sets the HR database as OFFLINE

    .EXAMPLE
        PS C:\> Set-DbaDbState -SqlInstance sqlserver2014a -AllDatabases -Exclude HR -ReadOnly -Force

        Sets all databases of the sqlserver2014a instance, except for HR, as READ_ONLY

    .EXAMPLE
        PS C:\> Get-DbaDbState -SqlInstance sql2016 | Where-Object Status -eq 'Offline' | Set-DbaDbState -Online

        Finds all offline databases and sets them to online

    .EXAMPLE
        PS C:\> Set-DbaDbState -SqlInstance sqlserver2014a -Database HR -SingleUser

        Sets the HR database as SINGLE_USER

    .EXAMPLE
        PS C:\> Set-DbaDbState -SqlInstance sqlserver2014a -Database HR -SingleUser -Force

        Sets the HR database as SINGLE_USER, dropping all other connections (and rolling back open transactions)

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance sqlserver2014a -Database HR | Set-DbaDbState -SingleUser -Force

        Gets the databases from Get-DbaDatabase, and sets them as SINGLE_USER, dropping all other connections (and rolling back open transactions)

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = "Server")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$AllDatabases,
        [switch]$ReadOnly,
        [switch]$ReadWrite,
        [switch]$Online,
        [switch]$Offline,
        [switch]$Emergency,
        [switch]$Detached,
        [switch]$SingleUser,
        [switch]$RestrictedUser,
        [switch]$MultiUser,
        [switch]$Force,
        [switch]$EnableException,
        [parameter(Mandatory, ValueFromPipeline, ParameterSetName = "Database")]
        [PsCustomObject[]]$InputObject
    )

    begin {
        if ($Force) { $ConfirmPreference = 'none' }

        function Get-WrongCombo($optset, $allParams) {
            $x = 0
            foreach ($opt in $optset) {
                if ($allParams.ContainsKey($opt)) { $x += 1 }
            }
            if ($x -gt 1) {
                $msg = $optset -Join ',-'
                $msg = "You can only specify one of: -" + $msg
                throw $msg
            }
        }

        function Edit-DatabaseState($SqlInstance, $dbName, $opt, $immediate = $false) {
            $warn = $null
            $sql = "ALTER DATABASE [$dbName] SET $opt"
            if ($immediate) {
                $sql += " WITH ROLLBACK IMMEDIATE"
            } else {
                $sql += " WITH NO_WAIT"
            }
            try {
                Write-Message -Level System -Message $sql
                if ($immediate) {
                    # this can be helpful only for SINGLE_USER databases
                    # but since $immediate is called, it does no more harm
                    # than the immediate rollback
                    $SqlInstance.KillAllProcesses($dbName)
                }
                $null = $SqlInstance.Query($sql)
            } catch {
                $warn = "Failed to set '$dbName' to $opt"
                Write-Message -Level Warning -Message $warn
            }
            return $warn
        }

        $statusHash = @{
            'Offline'       = 'OFFLINE'
            'Normal'        = 'ONLINE'
            'EmergencyMode' = 'EMERGENCY'
        }

        function Get-DbState($databaseName, $dbStatuses) {
            $base = $dbStatuses | Where-Object DatabaseName -ceq $databaseName
            foreach ($status in $statusHash.Keys) {
                if ($base.Status -match $status) {
                    $base.Status = $statusHash[$status]
                    break
                }
            }
            return $base
        }

        $RWExclusive = @('ReadOnly', 'ReadWrite')
        $statusExclusive = @('Online', 'Offline', 'Emergency', 'Detached')
        $accessExclusive = @('SingleUser', 'RestrictedUser', 'MultiUser')
        $allParams = $PSBoundParameters
        try {
            Get-WrongCombo -optset $RWExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_
            return
        }
        try {
            Get-WrongCombo -optset $statusExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_
            return
        }
        try {
            Get-WrongCombo -optset $accessExclusive -allparams $allParams
        } catch {
            Stop-Function -Message $_
            return
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        $dbs = @()
        if (!$Database -and !$AllDatabases -and !$InputObject -and !$ExcludeDatabase) {
            Stop-Function -Message "You must specify a -AllDatabases or -Database to continue"
            return
        }

        if ($InputObject) {
            if ($InputObject.Database) {
                # comes from Get-DbaDbState
                $dbs += $InputObject.Database
            } elseif ($InputObject.Name) {
                # comes from Get-DbaDatabase
                $dbs += $InputObject
            }
        } else {
            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }
                $all_dbs = $server.Databases
                $dbs += $all_dbs | Where-Object { @('master', 'model', 'msdb', 'tempdb', 'distribution') -notcontains $_.Name }

                if ($database) {
                    $dbs = $dbs | Where-Object { $database -contains $_.Name }
                }
                if ($ExcludeDatabase) {
                    $dbs = $dbs | Where-Object { $ExcludeDatabase -notcontains $_.Name }
                }
            }
        }

        # need to pick up here
        foreach ($db in $dbs) {
            if ($db.Name -in @('master', 'model', 'msdb', 'tempdb', 'distribution')) {
                Write-Message -Level Warning -Message "Database $db is a system one, skipping"
                Continue
            }
            $dbStatuses = @{ }
            $server = $db.Parent
            if ($server -notin $dbStatuses.Keys) {
                $dbStatuses[$server] = Get-DbaDbState -SqlInstance $server
            }

            # normalizing properties returned by SMO to something more "fixed"
            $db_status = Get-DbState -DatabaseName $db.Name -dbStatuses $dbStatuses[$server]


            $warn = @()

            if ($db.DatabaseSnapshotBaseName.Length -gt 0) {
                Write-Message -Level Warning -Message "Database $db is a snapshot, skipping"
                Continue
            }

            if ($ReadOnly -eq $true) {
                if ($db_status.RW -eq 'READ_ONLY') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already READ_ONLY"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to READ_ONLY")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to READ_ONLY"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "READ_ONLY" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.RW = 'READ_ONLY'
                        }
                    }
                }
            }

            if ($ReadWrite -eq $true) {
                if ($db_status.RW -eq 'READ_WRITE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already READ_WRITE"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to READ_WRITE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to READ_WRITE"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "READ_WRITE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.RW = 'READ_WRITE'
                        }
                    }
                }
            }

            if ($Online -eq $true) {
                if ($db_status.Status -eq 'ONLINE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already ONLINE"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to ONLINE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to ONLINE"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "ONLINE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.Status = 'ONLINE'
                        }
                    }
                }
            }

            if ($Offline -eq $true) {
                if ($db_status.Status -eq 'OFFLINE') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already OFFLINE"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to OFFLINE")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to OFFLINE"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "OFFLINE" -immediate $Force
                        $warn += $partial
                        if (!$partial) {
                            $db_status.Status = 'OFFLINE'
                        }
                    }
                }
            }

            if ($Emergency -eq $true) {
                if ($db_status.Status -eq 'EMERGENCY') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already EMERGENCY"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to EMERGENCY")) {
                        Write-Message -Level VeryVerbose -Message "Setting database $db to EMERGENCY"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "EMERGENCY" -immediate $Force
                        if (!$partial) {
                            $db_status.Status = 'EMERGENCY'
                        }
                    }
                }
            }

            if ($SingleUser -eq $true) {
                if ($db_status.Access -eq 'SINGLE_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already SINGLE_USER"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to SINGLE_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to SINGLE_USER"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "SINGLE_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'SINGLE_USER'
                        }
                    }
                }
            }

            if ($RestrictedUser -eq $true) {
                if ($db_status.Access -eq 'RESTRICTED_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already RESTRICTED_USER"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to RESTRICTED_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to RESTRICTED_USER"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "RESTRICTED_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'RESTRICTED_USER'
                        }
                    }
                }
            }

            if ($MultiUser -eq $true) {
                if ($db_status.Access -eq 'MULTI_USER') {
                    Write-Message -Level VeryVerbose -Message "Database $db is already MULTI_USER"
                } else {
                    if ($Pscmdlet.ShouldProcess($server, "Set $db to MULTI_USER")) {
                        Write-Message -Level VeryVerbose -Message "Setting $db to MULTI_USER"
                        $partial = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "MULTI_USER" -immediate $Force
                        if (!$partial) {
                            $db_status.Access = 'MULTI_USER'
                        }
                    }
                }
            }

            if ($Detached -eq $true) {
                # Refresh info about database state here (before detaching)
                $db.Refresh()
                # we need to see what snaps are on the server, as base databases cannot be dropped
                $snaps = $server.Databases | Where-Object { $_.DatabaseSnapshotBaseName.Length -gt 0 }
                $snaps = $snaps.DatabaseSnapshotBaseName | Get-Unique
                if ($db.Name -in $snaps) {
                    Write-Message -Level Warning -Message "Database $db has snapshots, you need to drop them before detaching, skipping..."
                    Continue
                }
                if ($db.IsMirroringEnabled -eq $true -or $db.AvailabilityGroupName.Length -gt 0) {
                    if ($Force -eq $false) {
                        Write-Message -Level Warning -Message "Needs -Force to detach $db, skipping"
                        Continue
                    }
                }

                if ($db.IsMirroringEnabled) {
                    if ($Pscmdlet.ShouldProcess($server, "Break mirroring for $db")) {
                        try {
                            $db.ChangeMirroringState([Microsoft.SqlServer.Management.Smo.MirroringOption]::Off)
                            $db.Alter()
                            $db.Refresh()
                            Write-Message -Level VeryVerbose -Message "Broke mirroring for $db"
                        } catch {
                            Stop-Function -Message "Could not break mirror for $db. Skipping." -ErrorRecord $_ -Target $server -Continue
                        }
                    }
                }

                if ($db.AvailabilityGroupName) {
                    $agname = $db.AvailabilityGroupName
                    if ($Pscmdlet.ShouldProcess($server, "Removing $db from AG [$agname]")) {
                        try {
                            $server.AvailabilityGroups[$db.AvailabilityGroupName].AvailabilityDatabases[$db.Name].Drop()
                            Write-Message -Level VeryVerbose -Message "Successfully removed $db from AG [$agname] on $server"
                        } catch {
                            Stop-Function -Message "Could not remove $db from AG [$agname] on $server" -ErrorRecord $_ -Target $server -Continue
                        }
                    }
                }

                # DBA 101 should encourage detaching just OFFLINE databases
                # we can do that here
                if ($Pscmdlet.ShouldProcess($server, "Detaching $db")) {
                    if ($db_status.Status -ne 'OFFLINE') {
                        $null = Edit-DatabaseState -sqlinstance $server -dbname $db.Name -opt "OFFLINE" -immediate $true
                    }
                    try {
                        $sql = "EXEC master.dbo.sp_detach_db N'$($db.Name)'"
                        Write-Message -Level System -Message $sql
                        $null = $server.Query($sql)
                        $db_status.Status = 'DETACHED'
                    } catch {
                        Stop-Function -Message "Failed to detach $db" -ErrorRecord $_ -Target $server -Continue
                        $warn += "Failed to detach"
                    }

                }

            }
            if ($warn) {
                $warn = $warn | Where-Object { $_ } | Get-Unique
                $warn = $warn -Join ';'
            } else {
                $warn = $null
            }
            if ($Detached -eq $true) {
                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    DatabaseName = $db.Name
                    RW           = $db_status.RW
                    Status       = $db_status.Status
                    Access       = $db_status.Access
                    Notes        = $warn
                    Database     = $db
                } | Select-DefaultView -ExcludeProperty Database
            } else {
                $db.Refresh()
                if ($null -eq $warn) {
                    # we avoid reenumerating properties
                    $newstate = $db_status
                } else {
                    $newstate = Get-DbState -databaseName $db.Name -dbStatuses $dbStatuses[$server]
                }

                [PSCustomObject]@{
                    ComputerName = $server.ComputerName
                    InstanceName = $server.ServiceName
                    SqlInstance  = $server.DomainInstanceName
                    DatabaseName = $db.Name
                    RW           = $newstate.RW
                    Status       = $newstate.Status
                    Access       = $newstate.Access
                    Notes        = $warn
                    Database     = $db
                } | Select-DefaultView -ExcludeProperty Database
            }
        }

    }
}