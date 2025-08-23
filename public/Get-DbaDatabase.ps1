function Get-DbaDatabase {
    <#
    .SYNOPSIS
        Retrieves database objects and metadata from SQL Server instances with advanced filtering and usage analytics.

    .DESCRIPTION
        Retrieves detailed database information from one or more SQL Server instances, returning rich database objects instead of basic metadata queries.
        This command provides comprehensive filtering options for database status, access type, recovery model, backup history, and encryption status, making it essential for database inventory, compliance auditing, and maintenance planning.
        Unlike querying sys.databases directly, this returns full SMO database objects with calculated properties for backup status, usage statistics from DMVs, and consistent formatting across SQL Server versions.
        Supports both on-premises SQL Server (2000+) and Azure SQL Database with automatic compatibility handling.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies one or more database(s) to process. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies one or more database(s) to exclude from processing.

    .PARAMETER ExcludeUser
        If this switch is enabled, only databases which are not User databases will be processed.

        This parameter cannot be used with -ExcludeSystem.

    .PARAMETER ExcludeSystem
        If this switch is enabled, only databases which are not System databases will be processed.

        This parameter cannot be used with -ExcludeUser.

    .PARAMETER Status
        Specifies one or more database statuses to filter on. Only databases in the status(es) listed will be returned. Valid options for this parameter are 'EmergencyMode', 'Normal', 'Offline', 'Recovering', 'RecoveryPending', 'Restoring', 'Standby', and 'Suspect'.

    .PARAMETER Access
        Filters databases returned by their access type. Valid options for this parameter are 'ReadOnly' and 'ReadWrite'. If omitted, no filtering is performed.

    .PARAMETER Owner
        Specifies one or more database owners. Only databases owned by the listed owner(s) will be returned.

    .PARAMETER Encrypted
        If this switch is enabled, only databases which have Transparent Data Encryption (TDE) enabled will be returned.

    .PARAMETER RecoveryModel
        Filters databases returned by their recovery model. Valid options for this parameter are 'Full', 'Simple', and 'BulkLogged'.

    .PARAMETER NoFullBackup
        If this switch is enabled, only databases without a full backup recorded by SQL Server will be returned. This will also indicate which of these databases only have CopyOnly full backups.

    .PARAMETER NoFullBackupSince
        Only databases which haven't had a full backup since the specified DateTime will be returned.

    .PARAMETER NoLogBackup
        If this switch is enabled, only databases without a log backup recorded by SQL Server will be returned.

    .PARAMETER NoLogBackupSince
        Only databases which haven't had a log backup since the specified DateTime will be returned.

    .PARAMETER IncludeLastUsed
        If this switch is enabled, the last used read & write times for each database will be returned. This data is retrieved from sys.dm_db_index_usage_stats which is reset when SQL Server is restarted.

    .PARAMETER OnlyAccessible
        If this switch is enabled, only accessible databases are returned (huge speedup in SMO enumeration)

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
        Author: Garry Bargsley (@gbargsley), blog.garrybargsley.com | Klaas Vandenberghe (@PowerDbaKlaas) | Simone Bizzotto (@niphlod)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDatabase

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost

        Returns all databases on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -ExcludeUser

        Returns only the system databases on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance localhost -ExcludeSystem

        Returns only the user databases on the local default SQL Server instance.

    .EXAMPLE
        PS C:\> 'localhost','sql2016' | Get-DbaDatabase

        Returns databases on multiple instances piped into the function.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress -RecoveryModel full,Simple

        Returns only the user databases in Full or Simple recovery model from SQL Server instance SQL1\SQLExpress.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress -Status Normal

        Returns only the user databases with status 'normal' from SQL Server instance SQL1\SQLExpress.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress -IncludeLastUsed

        Returns the databases from SQL Server instance SQL1\SQLExpress and includes the last used information
        from the sys.dm_db_index_usage_stats DMV.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -ExcludeDatabase model,master

        Returns all databases except master and model from SQL Server instances SQL1\SQLExpress and SQL2.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -Encrypted

        Returns only databases using TDE from SQL Server instances SQL1\SQLExpress and SQL2.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -Access ReadOnly

        Returns only read only databases from SQL Server instances SQL1\SQLExpress and SQL2.

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL2,SQL3 -Database OneDB,OtherDB

        Returns databases 'OneDb' and 'OtherDB' from SQL Server instances SQL2 and SQL3 if databases by those names exist on those instances.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [Alias("SystemDbOnly", "NoUserDb", "ExcludeAllUserDb")]
        [switch]$ExcludeUser,
        [Alias("UserDbOnly", "NoSystemDb", "ExcludeAllSystemDb")]
        [switch]$ExcludeSystem,
        [string[]]$Owner,
        [switch]$Encrypted,
        [ValidateSet('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'RecoveryPending', 'Restoring', 'Standby', 'Suspect')]
        [string[]]$Status = @('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'RecoveryPending', 'Restoring', 'Standby', 'Suspect'),
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$Access,
        [ValidateSet('Full', 'Simple', 'BulkLogged')]
        [string[]]$RecoveryModel = @('Full', 'Simple', 'BulkLogged'),
        [switch]$NoFullBackup,
        [datetime]$NoFullBackupSince,
        [switch]$NoLogBackup,
        [datetime]$NoLogBackupSince,
        [switch]$EnableException,
        [switch]$IncludeLastUsed,
        [switch]$OnlyAccessible
    )

    begin {

        if ($ExcludeUser -and $ExcludeSystem) {
            Stop-Function -Message "You cannot specify both ExcludeUser and ExcludeSystem." -Continue -EnableException $EnableException
        }

    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (!$IncludeLastUsed) {
                $dblastused = $null
            } else {
                ## Get last used information from the DMV
                $querylastused = "WITH agg AS
                (
                  SELECT
                       max(last_user_seek) last_user_seek,
                       max(last_user_scan) last_user_scan,
                       max(last_user_lookup) last_user_lookup,
                       max(last_user_update) last_user_update,
                       sd.name dbname
                   FROM
                       sys.dm_db_index_usage_stats, master..sysdatabases sd
                   WHERE
                     database_id = sd.dbid AND database_id > 4
                      group by sd.name
                )
                SELECT
                   dbname,
                   last_read = MAX(last_read),
                   last_write = MAX(last_write)
                FROM
                (
                   SELECT dbname, last_user_seek, NULL FROM agg
                   UNION ALL
                   SELECT dbname, last_user_scan, NULL FROM agg
                   UNION ALL
                   SELECT dbname, last_user_lookup, NULL FROM agg
                   UNION ALL
                   SELECT dbname, NULL, last_user_update FROM agg
                ) AS x (dbname, last_read, last_write)
                GROUP BY
                   dbname
                ORDER BY 1;"
                # put a function around this to enable Pester Testing and also to ease any future changes
                function Invoke-QueryDBlastUsed {
                    $server.Query($querylastused)
                }
                $dblastused = Invoke-QueryDBlastUsed
            }

            if ($ExcludeUser) {
                $DBType = @($true)
            } elseif ($ExcludeSystem) {
                $DBType = @($false)
            } else {
                $DBType = @($false, $true)
            }

            $AccessibleFilter = switch ($OnlyAccessible) {
                $true { @($true) }
                default { @($true, $false) }
            }

            $Readonly = switch ($Access) {
                'Readonly' { @($true) }
                'ReadWrite' { @($false) }
                default { @($true, $false) }
            }
            $Encrypt = switch (Test-Bound -Parameter 'Encrypted') {
                $true { @($true) }
                default { @($true, $false, $null) }
            }
            function Invoke-QueryRawDatabases {
                try {
                    if ($server.isAzure) {
                        $dbquery = "SELECT db.name, db.state, dp.name AS [Owner] FROM sys.databases AS db LEFT JOIN sys.database_principals AS dp ON dp.sid = db.owner_sid"
                        $server.ConnectionContext.ExecuteWithResults($dbquery).Tables
                    } elseif ($server.VersionMajor -eq 8) {
                        $server.Query("
                            SELECT name,
                                CASE DATABASEPROPERTYEX(name,'status')
                                    WHEN 'ONLINE'     THEN 0
                                    WHEN 'RESTORING'  THEN 1
                                    WHEN 'RECOVERING' THEN 2
                                    WHEN 'SUSPECT'    THEN 4
                                    WHEN 'EMERGENCY'  THEN 5
                                    WHEN 'OFFLINE'    THEN 6
                                END AS state,
                                SUSER_SNAME(sid) AS [Owner]
                            FROM master.dbo.sysdatabases
                        ")
                    } elseif ($server.VersionMajor -eq 9) {
                        # CDC did not exist in version 9, but did afterwards.
                        $server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner]")
                    } else {
                        $server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases")
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }

            $backed_info = Invoke-QueryRawDatabases
            $backed_info = $backed_info | Where-Object {
                ($_.name -in $Database -or !$Database) -and
                ($_.name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                ($_.Owner -in $Owner -or !$Owner) -and
                ($_.state -ne 6 -or !$OnlyAccessible)
            }


            $inputObject = @()
            foreach ($dt in $backed_info) {
                try {
                    $inputObject += $server.Databases | Where-Object Name -ceq $dt.name
                } catch {
                    # I've seen this only once and can not reproduce:
                    # The following exception occurred while trying to enumerate the collection: "Failed to connect to server XXXXX.database.windows.net.".
                    # So we implement the fallback that was used before #8333.
                    Write-Message -Level Verbose -Message "Failure: $_"
                    $inputObject += $server.Databases[$dt.name]
                }
            }
            if ($server.isAzure) {
                $inputObject = $inputObject |
                    Where-Object {
                        ($_.Name -in $Database -or !$Database) -and
                        ($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                        ($_.Owner -in $Owner -or !$Owner) -and
                        ($_.RecoveryModel -in $RecoveryModel -or !$_.RecoveryModel) -and
                        $_.EncryptionEnabled -in $Encrypt
                    }
            } else {
                $inputObject = $inputObject |
                    Where-Object {
                        ($_.Name -in $Database -or !$Database) -and
                        ($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                        ($_.Owner -in $Owner -or !$Owner) -and
                        $_.ReadOnly -in $Readonly -and
                        $_.IsAccessible -in $AccessibleFilter -and
                        $_.IsSystemObject -in $DBType -and
                        ((Compare-Object @($_.Status.tostring().split(',').trim()) $Status -ExcludeDifferent -IncludeEqual).inputobject.count -ge 1 -or !$status) -and
                        ($_.RecoveryModel -in $RecoveryModel -or !$_.RecoveryModel) -and
                        $_.EncryptionEnabled -in $Encrypt
                    }
            }
            if ($NoFullBackup -or $NoFullBackupSince) {
                $lastFullBackups = Get-DbaDbBackupHistory -SqlInstance $server -LastFull
                $lastCopyOnlyBackups = Get-DbaDbBackupHistory -SqlInstance $server -LastFull -IncludeCopyOnly | Where-Object IsCopyOnly
                if ($NoFullBackupSince) {
                    $lastFullBackups = $lastFullBackups | Where-Object End -gt $NoFullBackupSince
                    $lastCopyOnlyBackups = $lastCopyOnlyBackups | Where-Object End -gt $NoFullBackupSince
                }

                $hasCopyOnly = $inputObject | Compare-DbaCollationSensitiveObject -Property Name -In -Value $lastCopyOnlyBackups.Database -Collation $server.Collation
                $inputObject = $inputObject | Where-Object Name -cne 'tempdb'
                $inputObject = $inputObject | Compare-DbaCollationSensitiveObject -Property Name -NotIn -Value $lastFullBackups.Database -Collation $server.Collation
            }
            if ($NoLogBackup -or $NoLogBackupSince) {
                if (!$NoLogBackupSince) {
                    $NoLogBackupSince = New-Object -TypeName DateTime
                    $NoLogBackupSince = $NoLogBackupSince.AddMilliSeconds(1)
                }
                $inputObject = $inputObject | Where-Object { $_.LastLogBackupDate -lt $NoLogBackupSince -and $_.RecoveryModel -ne 'Simple' }
            }

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'IsAccessible', 'RecoveryModel',
            'LogReuseWaitStatus', 'Size as SizeMB', 'CompatibilityLevel as Compatibility', 'Collation', 'Owner', 'EncryptionEnabled as Encrypted',
            'LastBackupDate as LastFullBackup', 'LastDifferentialBackupDate as LastDiffBackup',
            'LastLogBackupDate as LastLogBackup'

            if ($NoFullBackup -or $NoFullBackupSince) {
                $defaults += ('BackupStatus')
            }
            if ($IncludeLastUsed) {
                # Add Last Used to the default view
                $defaults += ('LastRead as LastIndexRead', 'LastWrite as LastIndexWrite')
            }

            try {
                foreach ($db in $inputObject) {

                    $backupStatus = $null
                    if ($NoFullBackup -or $NoFullBackupSince) {
                        if ($db -cin $hasCopyOnly) {
                            $backupStatus = "Only CopyOnly backups"
                        }
                    }

                    $lastusedinfo = $dblastused | Where-Object { $_.dbname -eq $db.name }
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name BackupStatus -Value $backupStatus
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastRead -Value $lastusedinfo.last_read
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastWrite -Value $lastusedinfo.last_write
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name IsCdcEnabled -Value ($backed_info | Where-Object { $_.name -ceq $db.name }).is_cdc_enabled
                    Select-DefaultView -InputObject $db -Property $defaults
                }
            } catch {
                Stop-Function -ErrorRecord $_ -Target $instance -Message "Failure. Collection may have been modified. If so, please use parens (Get-DbaDatabase ....) | when working with commands that modify the collection such as Remove-DbaDatabase." -Continue
            }
        }
    }
}