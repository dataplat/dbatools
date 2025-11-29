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
        Specifies one or more databases to include in the results using exact name matching.
        Use this when you need to retrieve specific databases instead of all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies one or more databases to exclude from the results using exact name matching.
        Use this to filter out specific databases like test or staging environments from your inventory.

    .PARAMETER Pattern
        Specifies a pattern for filtering databases using regular expressions.
        Use this when you need to match databases by pattern, such as "^dbatools_" or ".*_prod$".
        This parameter supports standard .NET regular expression syntax.

    .PARAMETER ExcludeUser
        Returns only system databases (master, model, msdb, tempdb).
        Use this when you need to focus on system database maintenance tasks or validation.
        This parameter cannot be used with -ExcludeSystem.

    .PARAMETER ExcludeSystem
        Returns only user databases, excluding system databases (master, model, msdb, tempdb).
        Use this when you need to focus on application databases for maintenance, backup, or compliance reporting.
        This parameter cannot be used with -ExcludeUser.

    .PARAMETER Status
        Filters databases by their current operational status. Returns only databases matching the specified status values.
        Use this to identify databases requiring attention (Suspect, Offline) or in specific states for maintenance planning.
        Valid options: EmergencyMode, Normal, Offline, Recovering, RecoveryPending, Restoring, Standby, Suspect.

    .PARAMETER Access
        Filters databases by their read/write access mode. Returns only databases set to the specified access type.
        Use ReadOnly to find reporting databases or those temporarily set to read-only for maintenance.
        Valid options: ReadOnly, ReadWrite.

    .PARAMETER Owner
        Filters databases by their database owner (the principal listed as the database owner).
        Use this to find databases owned by specific accounts for security auditing or ownership cleanup.
        Accepts login names like 'sa', 'DOMAIN\user', or service account names.

    .PARAMETER Encrypted
        Returns only databases with Transparent Data Encryption (TDE) enabled.
        Use this for compliance reporting or to verify which databases have encryption configured for data protection.

    .PARAMETER RecoveryModel
        Filters databases by their recovery model setting, which controls transaction log behavior and backup capabilities.
        Use this to verify recovery model consistency or find databases needing model changes for backup strategy compliance.
        Valid options: Full (point-in-time recovery), Simple (no log backups), BulkLogged (minimal logging for bulk operations).

    .PARAMETER NoFullBackup
        Returns only databases that have never had a full backup or only have CopyOnly full backups recorded in msdb.
        Use this to identify databases at risk due to missing backup coverage for disaster recovery planning.

    .PARAMETER NoFullBackupSince
        Returns databases that haven't had a full backup since the specified date and time.
        Use this to identify databases with stale backups that may violate your backup policy or RTO requirements.

    .PARAMETER NoLogBackup
        Returns databases in Full or BulkLogged recovery model that have never had a transaction log backup.
        Use this to identify databases where transaction logs may be growing unchecked due to missing log backup strategy.

    .PARAMETER NoLogBackupSince
        Returns databases that haven't had a transaction log backup since the specified date and time.
        Use this to find databases with overdue log backups that may cause transaction log growth or RPO violations.

    .PARAMETER IncludeLastUsed
        Adds LastRead and LastWrite columns showing when databases were last accessed based on index usage statistics.
        Use this to identify unused or rarely accessed databases for decommissioning or archival decisions.
        Data is retrieved from sys.dm_db_index_usage_stats and resets when SQL Server restarts.

    .PARAMETER OnlyAccessible
        Returns only databases that are currently accessible, excluding offline or inaccessible databases.
        Use this to improve performance when you only need databases that can be queried, providing significant speedup for SMO enumeration.

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

    .EXAMPLE
        PS C:\> Get-DbaDatabase -SqlInstance SQL2,SQL3 -Pattern "^dbatools_"

        Returns all databases that match the regex pattern "^dbatools_" (e.g., dbatools_example1, dbatools_example2) from SQL Server instances SQL2 and SQL3.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseSingularNouns", "", Justification = "Internal functions are ignored")]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [string[]]$Pattern,
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
                       MAX(last_user_seek) last_user_seek,
                       MAX(last_user_scan) last_user_scan,
                       MAX(last_user_lookup) last_user_lookup,
                       MAX(last_user_update) last_user_update,
                       sd.name dbname
                   FROM
                       sys.dm_db_index_usage_stats, master..sysdatabases sd
                   WHERE
                     database_id = sd.dbid AND database_id > 4
                      GROUP BY sd.name
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
                        $server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner] FROM sys.databases")
                    } else {
                        $server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases")
                    }
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_
                }
            }

            $backed_info = Invoke-QueryRawDatabases

            # Helper function to test if a name matches any of the provided regex patterns
            $matchesPattern = {
                param($name, $patterns)
                if (!$patterns) { return $true }
                foreach ($pattern in $patterns) {
                    if ($name -match $pattern) { return $true }
                }
                return $false
            }

            $backed_info = $backed_info | Where-Object {
                ($_.name -in $Database -or !$Database) -and
                ($_.name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                (& $matchesPattern $_.name $Pattern) -and
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
                        (& $matchesPattern $_.Name $Pattern) -and
                        ($_.Owner -in $Owner -or !$Owner) -and
                        ($_.RecoveryModel -in $RecoveryModel -or !$_.RecoveryModel) -and
                        $_.EncryptionEnabled -in $Encrypt
                    }
            } else {
                $inputObject = $inputObject |
                    Where-Object {
                        ($_.Name -in $Database -or !$Database) -and
                        ($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                        (& $matchesPattern $_.Name $Pattern) -and
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

            # Get database sizes via T-SQL for fallback when SMO Size is null/0
            # This query works for SQL Server 2000+ and calculates size from sys.master_files or sysaltfiles
            # Azure SQL Database doesn't have sys.master_files, so we use sys.database_files instead
            $querySizes = if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                # Azure SQL Database doesn't have sys.master_files
                # Use sys.database_files which is database-scoped
                "SELECT DB_NAME() AS name,
                    CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB
                FROM sys.database_files"
            } elseif ($server.VersionMajor -ge 9) {
                "SELECT DB_NAME(database_id) AS name,
                    CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(18,2)) AS SizeMB
                FROM sys.master_files
                GROUP BY database_id"
            } else {
                "SELECT dbname = DB_NAME(dbid),
                    SizeMB = CAST(SUM(size) * 8.0 / 1024 AS DECIMAL(18,2))
                FROM master.dbo.sysaltfiles
                GROUP BY dbid"
            }

            function Invoke-QueryDatabaseSizes {
                try {
                    if ($server.DatabaseEngineType -eq "SqlAzureDatabase") {
                        # For Azure, we need to query each database individually
                        # since sys.database_files is database-scoped
                        $results = @()
                        foreach ($db in $inputObject) {
                            try {
                                $splatQuery = @{
                                    SqlInstance     = $server
                                    Database        = $db.Name
                                    Query           = $querySizes
                                    EnableException = $true
                                }
                                $result = Invoke-DbaQuery @splatQuery
                                if ($result) {
                                    $results += $result
                                }
                            } catch {
                                # Skip databases that can't be queried (offline, etc.)
                            }
                        }
                        $results
                    } else {
                        $server.Query($querySizes)
                    }
                } catch {
                    Write-Message -Level Warning -Message "Could not retrieve database sizes via T-SQL: $_"
                    $null
                }
            }

            $dbSizes = Invoke-QueryDatabaseSizes

            try {
                foreach ($db in $inputObject) {

                    $backupStatus = $null
                    if ($NoFullBackup -or $NoFullBackupSince) {
                        if ($db -cin $hasCopyOnly) {
                            $backupStatus = "Only CopyOnly backups"
                        }
                    }

                    # Use T-SQL size if SMO Size is null or 0
                    $sizeValue = $db.Size
                    if ($null -eq $sizeValue -or $sizeValue -eq 0) {
                        $dbSizeInfo = $dbSizes | Where-Object { $_.name -eq $db.Name }
                        if ($dbSizeInfo) {
                            $sizeValue = $dbSizeInfo.SizeMB
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
                    # Override Size property with calculated value if SMO returned null/0
                    if ($null -ne $sizeValue) {
                        Add-Member -Force -InputObject $db -MemberType NoteProperty -Name Size -Value $sizeValue
                    }
                    Select-DefaultView -InputObject $db -Property $defaults
                }
            } catch {
                Stop-Function -ErrorRecord $_ -Target $instance -Message "Failure. Collection may have been modified. If so, please use parens (Get-DbaDatabase ....) | when working with commands that modify the collection such as Remove-DbaDatabase." -Continue
            }
        }
    }
}