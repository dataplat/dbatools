function Get-DbaAgBackupHistory {
    <#
    .SYNOPSIS
        Returns backup history details for databases on a SQL Server Availability Group.

    .DESCRIPTION
        Returns backup history details for some or all databases on a SQL Server Availability Group.

        You can even get detailed information (including file path) for latest full, differential and log files.
        For detailed examples of the various parameters see the documentation of Get-DbaDbBackupHistory.

        Reference: http://www.sqlhub.com/2011/07/find-your-backup-history-in-sql-server.html

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

        If you pass in one availability group listener, all replicas are automatically determined and queried.
        If you pass in a list of individual replicas, they will be queried. This enables you to use custom ports for the replicas.

    .PARAMETER SqlCredential
        Credential object used to connect to the SQL Server instance as a different user. This can be a Windows or SQL Server account. Windows users are determined by the existence of a backslash, so if you are intending to use an alternative Windows connection instead of a SQL login, ensure it contains a backslash.

    .PARAMETER AvailabilityGroup
        Specify the availability group to process.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases of the availability group will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER IncludeCopyOnly
        By default Get-DbaAgBackupHistory will ignore backups taken with the CopyOnly option. This switch will include them.

    .PARAMETER Force
        If this switch is enabled, a large amount of information is returned, similar to what SQL Server itself returns.

    .PARAMETER Since
        Specifies a DateTime object to use as the starting point for the search for backups.

    .PARAMETER RecoveryFork
        Specifies the Recovery Fork you want backup history for

    .PARAMETER Last
        If this switch is enabled, the most recent full chain of full, diff and log backup sets is returned.

    .PARAMETER LastFull
        If this switch is enabled, the most recent full backup set is returned.

    .PARAMETER LastDiff
        If this switch is enabled, the most recent differential backup set is returned.

    .PARAMETER LastLog
        If this switch is enabled, the most recent log backup is returned.

    .PARAMETER DeviceType
        Specifies a filter for backup sets based on DeviceType. Valid options are 'Disk','Permanent Disk Device', 'Tape', 'Permanent Tape Device','Pipe','Permanent Pipe Device','Virtual Device','URL', in addition to custom integers for your own DeviceType.

    .PARAMETER Raw
        If this switch is enabled, one object per backup file is returned. Otherwise, media sets (striped backups across multiple files) will be grouped into a single return object.

    .PARAMETER Type
        Specifies one or more types of backups to return. Valid options are 'Full', 'Log', 'Differential', 'File', 'Differential File', 'Partial Full', and 'Partial Differential'. Otherwise, all types of backups will be returned unless one of the -Last* switches is enabled.

    .PARAMETER LastLsn
        Specifies a minimum LSN to use in filtering backup history. Only backups with an LSN greater than this value will be returned, which helps speed the retrieval process.

    .PARAMETER IncludeMirror
        By default mirrors of backups are not returned, this switch will cause them to be returned

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DisasterRecovery, Backup
        Author: Chrissy LeMaire (@cl) | Stuart Moore (@napalmgram), Andreas Jordan

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaAgBackupHistory

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance AgListener -AvailabilityGroup AgTest1

        Returns information for all database backups still in msdb history on all replicas of availability group AgTest1 using the listener AgListener to determine all replicas.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance Replica1, Replica2, Replica3 -AvailabilityGroup AgTest1

        Returns information for all database backups still in msdb history on the given replicas of availability group AgTest1.

    .EXAMPLE
        PS C:\> Get-DbaAgBackupHistory -SqlInstance 'Replica1:14331', 'Replica2:14332', 'Replica3:14333' -AvailabilityGroup AgTest1

        Returns information for all database backups still in msdb history on the given replicas of availability group AgTest1 using custom ports.

    .EXAMPLE
        PS C:\> $ListOfReplicas | Get-DbaAgBackupHistory -AvailabilityGroup AgTest1

        Returns information for all database backups still in msdb history on the replicas in $ListOfReplicas of availability group AgTest1.

    .EXAMPLE
        PS C:\> $serverWithAllAgs = Connect-DbaInstance -SqlInstance MyServer
        PS C:\> $allAgResults = foreach ( $ag in $serverWithAllAgs.AvailabilityGroups ) {
        >>     Get-DbaAgBackupHistory -SqlInstance $ag.AvailabilityReplicas.Name -AvailabilityGroup $ag.Name
        >> }
        >>
        PS C:\> $allAgResults | Format-Table

        Returns information for all database backups on all replicas for all availability groups on SQL instance MyServer.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance,
        [PsCredential]$SqlCredential,
        [parameter(Mandatory)]
        [string]$AvailabilityGroup,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeCopyOnly,
        [Parameter(ParameterSetName = "NoLast")]
        [switch]$Force,
        [DateTime]$Since = (Get-Date '01/01/1970'),
        [ValidateScript( { ($_ -match '^(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}$') -or ('' -eq $_) })]
        [string]$RecoveryFork,
        [switch]$Last,
        [switch]$LastFull,
        [switch]$LastDiff,
        [switch]$LastLog,
        [string[]]$DeviceType,
        [switch]$Raw,
        [bigint]$LastLsn,
        [switch]$IncludeMirror,
        [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
        [string[]]$Type,
        [switch]$EnableException
    )

    begin {
        Write-Message -Level System -Message "Active Parameter set: $($PSCmdlet.ParameterSetName)."
        Write-Message -Level System -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"
        $serverList = @()
    }

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Only work on instances with availability groups
            if ($server.AvailabilityGroups.Count -eq 0) {
                Stop-Function -Message "Instance $instance has no availability groups, so skipping." -Target $instance -Continue
            }

            # Only work on instances with the specific availability group
            if ($AvailabilityGroup -notin $server.AvailabilityGroups.Name) {
                Stop-Function -Message "Instance $instance has no availability group named '$AvailabilityGroup', so skipping." -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Added $server to serverList"
            $serverList += $server
        }
    }

    end {
        if ($serverList.Count -eq 0) {
            Stop-Function -Message "No instances with availability group named '$AvailabilityGroup' found, so finishing without results."
        }

        if ($serverList.Count -eq 1) {
            Write-Message -Level Verbose -Message "We have one server, so it should be a listener"
            $server = $serverList[0]

            $replicaNames = $server.AvailabilityGroups.Where( { $_.Name -in $AvailabilityGroup }).AvailabilityReplicas.Name
            Write-Message -Level Verbose -Message "We have found these replicas: $replicaNames"

            $serverList = $replicaNames
        }

        Write-Message -Level Verbose -Message "We have more than one server, so query them all and aggregate"
        $null = $PSBoundParameters.Remove('SqlInstance')
        $null = $PSBoundParameters.Remove('AvailabilityGroup')
        $null = $PSBoundParameters.Remove('Last')
        $AgResults = Get-DbaDbBackupHistory -SqlInstance $serverList @PSBoundParameters
        Foreach ($agr in $AgResults) {
            $agr.AvailabilityGroupName = $AvailabilityGroup
        }

        if ($Last) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for Last"
            $AgResults | Select-DbaBackupInformation -ServerName $AvailabilityGroup
        } elseif ($LastFull) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastFull"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property FirstLsn | Select-Object -Last 1
            }
        } elseif ($LastDiff) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastDiff"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property FirstLsn | Select-Object -Last 1
            }
        } elseif ($LastLog) {
            Write-Message -Level Verbose -Message "Filtering Ag backups for LastLog"
            Foreach ($AgDb in ( $AgResults.Database | Select-Object -Unique)) {
                $AgResults | Where-Object { $_.Database -eq $AgDb } | Sort-Object -Property FirstLsn | Select-Object -Last 1
            }
        } else {
            Write-Message -Level Verbose -Message "Output Ag backups without filtering"
            $AgResults
        }
    }
}