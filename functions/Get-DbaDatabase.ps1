#ValidationTags#CodeStyle,Messaging,FlowControl,Pipeline#
function Get-DbaDatabase {
    <#
        .SYNOPSIS
            Gets SQL Database information for each database that is present on the target instance(s) of SQL Server.

        .DESCRIPTION
            The Get-DbaDatabase command gets SQL database information for each database that is present on the target instance(s) of
            SQL Server. If the name of the database is provided, the command will return only the specific database information.

         .PARAMETER SqlInstance
            The SQL Server instance to connect to.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Database
            Specifies one or more database(s) to process. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies one or more database(s) to exclude from processing.

        .PARAMETER ExcludeAllUserDb
            If this switch is enabled, only databases which are not User databases will be processed.

            This parameter cannot be used with -ExcludeAllSystemDb.

        .PARAMETER ExcludeAllSystemDb
            If this switch is enabled, only databases which are not System databases will be processed.

            This parameter cannot be used with -ExcludeAllUserDb.

        .PARAMETER Status
            Specifies one or more database statuses to filter on. Only databases in the status(es) listed will be returned. Valid options for this parameter are 'Emergency', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', and 'Suspect'.

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
            If this switch is enabled, only databases without a log backup recorded by SQL Server will be returned. This will also indicate which of these databases only have CopyOnly log backups.

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
            Author: Garry Bargsley (@gbargsley | http://blog.garrybargsley.com)
            Author: Klaas Vandenberghe ( @PowerDbaKlaas )
            Author: Simone Bizzotto ( @niphlod )

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaDatabase

        .EXAMPLE
            Get-DbaDatabase -SqlInstance localhost

            Returns all databases on the local default SQL Server instance.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance localhost -ExcludeAllUserDb

            Returns only the system databases on the local default SQL Server instance.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance localhost -ExcludeAllSystemDb

            Returns only the user databases on the local default SQL Server instance.

        .EXAMPLE
            'localhost','sql2016' | Get-DbaDatabase

            Returns databases on multiple instances piped into the function.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance SQL1\SQLExpress -RecoveryModel full,Simple

            Returns only the user databases in Full or Simple recovery model from SQL Server instance SQL1\SQLExpress.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance SQL1\SQLExpress -Status Normal

            Returns only the user databases with status 'normal' from SQL Server instance SQL1\SQLExpress.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance SQL1\SQLExpress -IncludeLastUsed

            Returns the databases from SQL Server instance SQL1\SQLExpress and includes the last used information
            from the sys.dm_db_index_usage_stats DMV.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -ExcludeDatabase model,master

            Returns all databases except master and model from SQL Server instances SQL1\SQLExpress and SQL2.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -Encrypted

            Returns only databases using TDE from SQL Server instances SQL1\SQLExpress and SQL2.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance SQL1\SQLExpress,SQL2 -Access ReadOnly

            Returns only read only databases from SQL Server instances SQL1\SQLExpress and SQL2.

        .EXAMPLE
            Get-DbaDatabase -SqlInstance SQL2,SQL3 -Database OneDB,OtherDB

            Returns databases 'OneDb' and 'OtherDB' from SQL Server instances SQL2 and SQL3 if databases by those names exist on those instances.
    #>
    [CmdletBinding(DefaultParameterSetName = "Default")]
    Param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias("SystemDbOnly", "NoUserDb")]
        [switch]$ExcludeAllUserDb,
        [Alias("UserDbOnly", "NoSystemDb")]
        [switch]$ExcludeAllSystemDb,
        [string[]]$Owner,
        [switch]$Encrypted,
        [ValidateSet('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect')]
        [string[]]$Status = @('EmergencyMode', 'Normal', 'Offline', 'Recovering', 'Restoring', 'Standby', 'Suspect'),
        [ValidateSet('ReadOnly', 'ReadWrite')]
        [string]$Access,
        [ValidateSet('Full', 'Simple', 'BulkLogged')]
        [string[]]$RecoveryModel = @('Full', 'Simple', 'BulkLogged'),
        [switch]$NoFullBackup,
        [datetime]$NoFullBackupSince,
        [switch]$NoLogBackup,
        [datetime]$NoLogBackupSince,
        [Alias('Silent')]
        [switch]$EnableException,
        [switch]$IncludeLastUsed,
        [switch]$OnlyAccessible
    )

    begin {

        if ($ExcludeAllUserDb -and $ExcludeAllSystemDb) {
            Stop-Function -Message "You cannot specify both ExcludeAllUserDb and ExcludeAllSystemDb." -Continue -EnableException $EnableException
        }

    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if (!$IncludeLastUsed) {
                $dblastused = $null
            }
            else {
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

            if ($ExcludeAllUserDb) {
                $DBType = @($true)
            }
            elseif ($ExcludeAllSystemDb) {
                $DBType = @($false)
            }
            else {
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
            $Encrypt = switch (Test-Bound $Encrypted) {
                $true { @($true) }
                default { @($true, $false, $null) }
            }
            function Invoke-QueryRawDatabases {
                $server.Query("SELECT *, SUSER_NAME(owner_sid) AS [Owner] FROM sys.databases")
            }
            $backed_info = Invoke-QueryRawDatabases
            $backed_info = $backed_info | Where-Object {
                ($_.name -in $Database -or !$Database) -and
                ($_.name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                ($_.Owner -in $Owner -or !$Owner) -and
                ($_.state -ne 6 -or !$OnlyAccessible)
            }

            $inputObject = @()
            foreach($dt in $backed_info) {
                $inputObject += $server.Databases[$dt.name]
            }
            $inputobject = $inputObject |
                Where-Object {
                ($_.Name -in $Database -or !$Database) -and
                ($_.Name -notin $ExcludeDatabase -or !$ExcludeDatabase) -and
                ($_.Owner -in $Owner -or !$Owner) -and
                $_.ReadOnly -in $Readonly -and
                $_.IsAccessible -in $AccessibleFilter -and
                $_.IsSystemObject -in $DBType -and
                ((Compare-Object @($_.Status.tostring().split(',').trim()) $Status -ExcludeDifferent -IncludeEqual).inputobject.count -ge 1 -or !$status) -and
                $_.RecoveryModel -in $RecoveryModel -and
                $_.EncryptionEnabled -in $Encrypt
            }
            if ($NoFullBackup -or $NoFullBackupSince) {
                $dabs = (Get-DbaBackupHistory -SqlInstance $server -LastFull )
                if ($null -ne $NoFullBackupSince) {
                    $dabsWithinScope = ($dabs | Where-Object End -lt $NoFullBackupSince)

                    $inputobject = $inputobject | Where-Object { $_.Name -in $dabsWithinScope.Database -and $_.Name -ne 'tempdb' }
                }
                else {
                    $inputObject = $inputObject | Where-Object { $_.Name -notin $dabs.Database -and $_.Name -ne 'tempdb' }
                }

            }
            if ($NoLogBackup -or $NoLogBackupSince) {
                $dabs = (Get-DbaBackupHistory -SqlInstance $server -LastLog )
                if ($null -ne $NoLogBackupSince) {
                    $dabsWithinScope = ($dabs | Where-Object End -lt $NoLogBackupSince)
                    $inputobject = $inputobject |
                        Where-Object { $_.Name -in $dabsWithinScope.Database -and $_.Name -ne 'tempdb' -and $_.RecoveryModel -ne 'Simple' }
                }
                else {
                    $inputobject = $inputObject |
                        Where-Object { $_.Name -notin $dabs.Database -and $_.Name -ne 'tempdb' -and $_.RecoveryModel -ne 'Simple' }
                }
            }

            $defaults = 'ComputerName', 'InstanceName', 'SqlInstance', 'Name', 'Status', 'IsAccessible', 'RecoveryModel',
            'LogReuseWaitStatus', 'Size as SizeMB', 'CompatibilityLevel as Compatibility', 'Collation', 'Owner',
            'LastBackupDate as LastFullBackup', 'LastDifferentialBackupDate as LastDiffBackup',
            'LastLogBackupDate as LastLogBackup'

            if ($NoFullBackup -or $NoFullBackupSince -or $NoLogBackup -or $NoLogBackupSince) {
                $defaults += ('Notes')
            }
            if ($IncludeLastUsed) {
                # Add Last Used to the default view
                $defaults += ('LastRead as LastIndexRead', 'LastWrite as LastIndexWrite')
            }

            try {
                foreach ($db in $inputobject) {

                    $Notes = $null
                    if ($NoFullBackup -or $NoFullBackupSince) {
                        if (@($db.EnumBackupSets()).count -eq @($db.EnumBackupSets() | Where-Object { $_.IsCopyOnly }).count -and (@($db.EnumBackupSets()).count -gt 0)) {
                            $Notes = "Only CopyOnly backups"
                        }
                    }

                    $lastusedinfo = $dblastused | Where-Object { $_.dbname -eq $db.name }
                    Add-Member -Force -InputObject $db -MemberType NoteProperty BackupStatus -value $Notes
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name ComputerName -value $server.NetName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name SqlInstance -value $server.DomainInstanceName
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastRead -value $lastusedinfo.last_read
                    Add-Member -Force -InputObject $db -MemberType NoteProperty -Name LastWrite -value $lastusedinfo.last_write
                    Select-DefaultView -InputObject $db -Property $defaults
                    #try { $server.Databases.Refresh() } catch {}
                }
            }
            catch {
                Stop-Function -ErrorRecord $_ -Target $instance -Message "Failure. Collection may have been modified. If so, please use parens (Get-DbaDatabase ....) | when working with commands that modify the collection such as Remove-DbaDatabase." -Continue
            }
        }
    }
}