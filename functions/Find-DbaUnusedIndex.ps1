function Find-DbaUnusedIndex {
    <#
        .SYNOPSIS
            Find Unused indexes

        .DESCRIPTION
            This command will help you to find Unused indexes on a database or a list of databases

            Also tells how much space you can save by dropping the index.
            We show the type of compression so you can make a more considered decision.
            For now only supported for CLUSTERED and NONCLUSTERED indexes

            You can select the indexes you want to drop on the gridview and by clicking OK the drop statement will be generated.

        .PARAMETER SqlInstance
            The SQL Server you want to check for unused indexes.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $cred = Get-Credential, then pass $cred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER FilePath
            Specifies the path of a file to write the DROP statements to.

        .PARAMETER NoClobber
            If this switch is enabled, the output file will not be overwritten.

        .PARAMETER Append
            If this switch is enabled, content will be appended to the output file.

        .PARAMETER IgnoreUptime
            Less than 7 days uptime can mean that analysis of unused indexes is unreliable, and normally no results will be returned. By setting this option results will be returned even if the Instance has been running for less that 7 days.

            .PARAMETER WhatIf
            If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

        .PARAMETER Confirm
            If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Indexes
            Author: Aaron Nelson (@SQLvariant), SQLvariant.com

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Find-DbaUnusedIndex

        .EXAMPLE
            Find-DbaUnusedIndex -SqlInstance sql2005 -FilePath C:\temp\sql2005-UnusedIndexes.sql

            Generates the SQL statements to drop the selected unused indexes on server "sql2005". The statements are written to the file "C:\temp\sql2005-UnusedIndexes.sql"

        .EXAMPLE
            Find-DbaUnusedIndex -SqlInstance sql2005 -FilePath C:\temp\sql2005-UnusedIndexes.sql -Append

            Generates the SQL statements to drop the selected unused indexes on server "sql2005". The statements are written to the file "C:\temp\sql2005-UnusedIndexes.sql", appending if the file already exists.

        .EXAMPLE
            Find-DbaUnusedIndex -SqlInstance sqlserver2016 -SqlCredential $cred

            Generates the SQL statements to drop the selected unused indexes on server "sqlserver2016", using SQL Authentication to connect to the database.

        .EXAMPLE
            Find-DbaUnusedIndex -SqlInstance sqlserver2016 -Database db1, db2

            Generates the SQL Statement to to drop selected indexes in databases db1 & db2 on server "sqlserver2016".

        .EXAMPLE
            Find-DbaUnusedIndex -SqlInstance sqlserver2016

            Generates the SQL statements to drop selected indexes on all user databases.

        .EXAMPLE
            Fine-DbaUnusedIndex -SqlInstance sqlserver2016 -IgnoreUptime

            Generates the SQL statements to drop selected indexes on all user databases even if the instance has been online for less than 7 days.
            Note that results may not have enough detail for all indexes, so care should be taken when using them or the generated scripts. Best practice is to allow a full week to capture the mmajority of index use cases

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [Alias("OutFile", "Path")]
        [string]$FilePath,
        [switch]$NoClobber,
        [switch]$Append,
        [switch]$IgnoreUptime,
        [switch][Alias('Silent')]
        $EnableException
    )

    begin {

        # Support Compression 2008+
        $unusedQuery = "
        SELECT DB_NAME(database_id) AS 'DatabaseName'
        ,s.name AS 'SchemaName'
        ,t.name AS 'TableName'
        ,i.object_id AS ObjectId
        ,i.name AS 'IndexName'
        ,i.index_id as 'IndexId'
        ,i.type_desc as 'TypeDesc'
        ,user_seeks as 'UserSeeks'
        ,user_scans as 'UserScans'
        ,user_lookups  as 'UserLookups'
        ,user_updates  as 'UserUpdates'
        ,last_user_seek  as 'LastUserSeek'
        ,last_user_scan  as 'LastUserScan'
        ,last_user_lookup  as 'LastUserLookup'
        ,last_user_UPDATE  as 'LastUserUpdate'
        ,system_seeks  as 'SystemSeeks'
        ,system_scans  as 'SystemScans'
        ,system_lookups  as 'SystemLookup'
        ,system_updates  as 'SystemUpdates'
        ,last_system_seek  as 'LastSystemSeek'
        ,last_system_scan  as 'LastSystemScan'
        ,last_system_lookup  as 'LastSystemLookup'
        ,last_system_update as 'LastSystemUpdate'
        FROM SYS.TABLES T
        JOIN SYS.SCHEMAS S
            ON T.schema_id = s.schema_id
        JOIN SYS.indexes i
            ON i.object_id = t.object_id LEFT OUTER
        JOIN sys.dm_db_index_usage_stats iu
            ON iu.object_id = i.object_id
                AND iu.index_id = i.index_id
        WHERE iu.database_id = DB_ID()
                AND OBJECTPROPERTY(i.[object_id], 'IsMSShipped') = 0
                AND user_seeks = 0
                AND user_scans = 0
                AND user_lookups = 0
                AND i.type_desc NOT IN ('HEAP', 'CLUSTERED COLUMNSTORE')"

        if ($FilePath.Length -gt 0) {
            if ($FilePath -notlike "*\*") {
                $FilePath = ".\$FilePath"
            }
            $directory = Split-Path $FilePath
            $exists = Test-Path $directory

            if ($exists -eq $false) {
                Stop-Function -Message "Parent directory $directory does not exist."
                return
            }
        }

        Write-Message -Level Output -Message "Attempting to connect to Sql Server."
        $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($server.VersionMajor -lt 9) {
            Stop-Function -Message "This function does not support versions lower than SQL Server 2005 (v9)."
            return
        }

        $lastRestart = $server.Databases['tempdb'].CreateDate
        $endDate = Get-Date -Date $lastRestart
        $diffDays = (New-TimeSpan -Start $endDate -End (Get-Date)).Days

        if ($diffDays -le 6) {
            if ($IgnoreUptime -ne $true) {
                Stop-Function -Message "The SQL Service was restarted on $lastRestart, which is not long enough for a solid evaluation."
                return
            }
            else {
                Write-Message -Level Warning -Message "The SQL Service was restarted on $lastRestart, which is not long enough for a solid evaluation."
            }
        }

        <#
            Validate if server version is:
                - sql 2012 and if have SP3 CU3 (Build 6537) or higher
                - sql 2014 and if have SP2 (Build 5000) or higher
            If the major version is the same but the build is lower, throws the message
        #>
        if (
            ($server.VersionMajor -eq 11 -and $server.BuildNumber -lt 6537) `
            -or ($server.VersionMajor -eq 12 -and $server.BuildNumber -lt 5000)
        ) {
            Stop-Function -Message "This SQL version has a known issue. Rebuilding an index clears any existing row entry from sys.dm_db_index_usage_stats for that index.`r`nPlease refer to connect item: https://connect.microsoft.com/sqlserver/feedback/details/739566/rebuilding-an-index-clears-stats-from-sys-dm-db-index-usage-stats"
            return
        }

        if ($diffDays -le 33) {
            Write-Message -Level Warning -Message "The SQL Service was restarted on $lastRestart, which may not be long enough for a solid evaluation."
        }

        if ($pipedatabase.Length -gt 0) {
            $database = $pipedatabase.name
        }

        if ($database.Count -eq 0) {
            $database = ($server.Databases | Where-Object { $_.IsSystemObject -eq 0 -and $_.IsAccessible }).Name
        }

        if ($database.Count -gt 0) {
            foreach ($db in $database) {
                if ($ExcludeDatabase -contains $db -or $null -eq $server.Databases[$db]) {
                    continue
                }
                if ($server.Databases[$db].IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "Database [$db] is not accessible."
                    continue
                }
                try {
                    Write-Message -Level Output -Message "Getting indexes from database '$db'."

                    $sql = $unusedQuery

                    $unusedIndex = $server.Databases[$db].ExecuteWithResults($sql)

                    $scriptGenerated = $false

                    if ($unusedIndex.Tables[0].Rows.Count -gt 0) {
                        $indexesToDrop = $unusedIndex.Tables[0]

                        if ($indexesToDrop.Count -gt 0 -or !([string]::IsNullOrEmpty($indexesToDrop))) {

                            foreach ($index in $indexesToDrop) {
                                if ($FilePath.Length -gt 0) {
                                    Write-Message -Level Output -Message "Exporting $($index.TableName).$($index.IndexName)"
                                    $sqlout += "USE [$($index.DatabaseName)]`r`n"
                                    $sqlout += "GO`r`n"
                                    $sqlout += "IF EXISTS (SELECT 1 FROM sys.indexes WHERE [object_id] = OBJECT_ID('$($index.SchemaName).$($index.TableName)') AND name = '$($index.IndexName)')`r`n"
                                    $sqlout += "DROP INDEX $($index.SchemaName).$($index.TableName).$($index.IndexName)`r`n"
                                    $sqlout += "GO`r`n`r`n"`

                                }
                            }

                            if ($FilePath.Length -gt 0) {
                                $sqlout | Out-File -FilePath $FilePath -Append:$Append -NoClobber:$NoClobber
                            }
                            else {
                                $indexesToDrop
                            }

                            $scriptGenerated = $true
                        }
                    }
                    else {
                        Write-Message -Level Output -Message "No Unused indexes found!"
                    }
                }
                catch {
                    Stop-Function -Message "Issue gathering indexes" -Category InvalidOperation -ErrorRecord $_ -Target $db
                }
            }

            if ($scriptGenerated) {
                Write-Message -Level Warning -Message "Confirm the generated script before execute!"
            }
            if ($FilePath.Length -gt 0) {
                Write-Message -Level Output -Message "Script generated to $FilePath"
            }
        }
        else {
            Write-Message -Level Output -Message "There are no databases to analyse."
        }
    }
    end {
        if (Test-FunctionInterrupt) {
            return
        }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Alias Get-SqlUnusedIndex
    }
}