function Get-DbaDbExtentDiff {
    <#
    .SYNOPSIS
        Calculates the percentage of database extents modified since the last full backup

    .DESCRIPTION
        Analyzes database extents to determine how much data has changed since the last full backup, helping DBAs decide between differential and full backup strategies. The function examines extent-level modifications (groups of 8 pages) to provide accurate change percentages, which is essential for optimizing backup schedules and storage requirements.
        
        For SQL Server 2016 SP2 and later, uses the sys.dm_db_file_space_usage DMV for efficient analysis. For older versions, falls back to DBCC PAGE commands to examine differential bitmap pages directly.
        
        Based on the original script by Paul S. Randal: https://www.sqlskills.com/blogs/paul/new-script-how-much-of-the-database-has-changed-since-the-last-full-backup/

    .PARAMETER SqlInstance
        The target SQL Server instance

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude - this list is auto-populated from the server

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup, Database
        Author: Viorel Ciucu, cviorel.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT

    .LINK
        https://dbatools.io/Get-DbaDbExtentDiff

    .EXAMPLE
        PS C:\> Get-DbaDbExtentDiff -SqlInstance SQL2016 -Database DBA

        Get the changes for the DBA database.

    .EXAMPLE
        PS C:\> $Cred = Get-Credential sqladmin
        PS C:\> Get-DbaDbExtentDiff -SqlInstance SQL2017N1, SQL2017N2, SQL2016 -Database DB01 -SqlCredential $Cred

        Get the changes for the DB01 database on multiple servers.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$EnableException
    )

    begin {
        $rex = [regex]':(?<extent>[\d]+)\)'
        function Get-DbaExtent ([string[]]$field) {
            $res = 0
            foreach ($f in $field) {
                $extents = $rex.Matches($f)
                if ($extents.Count -eq 1) {
                    $res += 1
                } else {
                    $pages = [int]$extents[1].Groups['extent'].Value - [int]$extents[0].Groups['extent'].Value
                    $res += $pages / 8 + 1
                }
            }
            return $res
        }
    }

    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -NonPooledConnection
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases

            if ($Database) {
                $dbs = $dbs | Where-Object Name -In $Database
            }

            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            $sourcedbs = @()
            foreach ($db in $dbs) {
                if ($db.IsAccessible -ne $true) {
                    Write-Message -Level Verbose -Message "$db is not accessible on $instance, skipping"
                } else {
                    $sourcedbs += $db
                }
            }

            #Available from 2016 SP2
            if ($server.Version -ge [version]'13.0.5026') {
                foreach ($db in $sourcedbs) {
                    $DBCCPageQueryDMV = "
                        SELECT
                        SUM(total_page_count) / 8 as [ExtentsTotal],
                        SUM(modified_extent_page_count) / 8 as [ExtentsChanged],
                        100.0 * SUM(modified_extent_page_count)/SUM(total_page_count) as [ChangedPerc]
                        FROM sys.dm_db_file_space_usage
                    "
                    $DBCCPageResults = $server.Query($DBCCPageQueryDMV, $db.Name)
                    [PSCustomObject]@{
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        DatabaseName   = $db.Name
                        ExtentsTotal   = $DBCCPageResults.ExtentsTotal
                        ExtentsChanged = $DBCCPageResults.ExtentsChanged
                        ChangedPerc    = [math]::Round($DBCCPageResults.ChangedPerc, 2)
                    }
                }
            } else {
                $MasterFilesQuery = "
                        SELECT [file_id], [size], database_id, db_name(database_id) as dbname FROM master.sys.master_files
                        WHERE [type_desc] = N'ROWS'
                    "
                $MasterFiles = $server.Query($MasterFilesQuery)
                $MasterFiles = $MasterFiles | Where-Object dbname -In $sourcedbs.Name
                $MasterFilesGrouped = $MasterFiles | Group-Object -Property dbname

                foreach ($db in $MasterFilesGrouped) {
                    $sizeTotal = 0
                    $dbExtents = @()
                    foreach ($results in $db.Group) {
                        $extentID = 0
                        $sizeTotal = $sizeTotal + $results.size / 8
                        while ($extentID -lt $results.size) {
                            $pageID = $extentID + 6
                            $DBCCPageQuery = "DBCC PAGE ('$($results.dbname)', $($results.file_id), $pageID, 3)  WITH TABLERESULTS, NO_INFOMSGS"
                            $DBCCPageResults = $server.Query($DBCCPageQuery)
                            $dbExtents += $DBCCPageResults | Where-Object { $_.VALUE -eq '    CHANGED' -And $_.ParentObject -like 'DIFF_MAP*' }
                            $extentID = $extentID + 511232
                        }
                    }
                    $extents = Get-DbaExtent $dbExtents.Field
                    [PSCustomObject]@{
                        ComputerName   = $server.ComputerName
                        InstanceName   = $server.ServiceName
                        SqlInstance    = $server.DomainInstanceName
                        DatabaseName   = $db.Name
                        ExtentsTotal   = $sizeTotal
                        ExtentsChanged = $extents
                        ChangedPerc    = [math]::Round(($extents / $sizeTotal * 100), 2)
                    }
                }
            }

            # Close non-pooled connection as this is not done automatically. If it is a reused Server SMO, connection will be opened again automatically on next request.
            $null = $server | Disconnect-DbaInstance
        }
    }
}