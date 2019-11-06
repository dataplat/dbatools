function Get-DbaDbSpace {
    <#
    .SYNOPSIS
        Returns database file space information for database files on a SQL instance.

    .DESCRIPTION
        This function returns database file space information for a SQL Instance or group of SQL Instances. Information is based on a query against sys.database_files and the FILEPROPERTY function to query and return information.

        File free space script borrowed and modified from Glenn Berry's DMV scripts (http://www.sqlskills.com/blogs/glenn/category/dmv-queries/)

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

    .PARAMETER InputObject
        A piped collection of database objects from Get-DbaDatabase

    .PARAMETER IncludeSystemDBs
        Deprecated - if filtering is needed, please pipe filtered results from Get-DbaDatabase

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Database, Space
        Author: Michael Fal (@Mike_Fal), http://mikefal.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbSpace

    .EXAMPLE
        PS C:\> Get-DbaDbSpace -SqlInstance localhost

        Returns all user database files and free space information for the localhost.

    .EXAMPLE
        PS C:\> Get-DbaDbSpace -SqlInstance localhost | Where-Object {$_.PercentUsed -gt 80}

        Returns all user database files and free space information for the local host. Filters the output object by any files that have a percent used of greater than 80%.

    .EXAMPLE
        PS C:\> 'localhost','localhost\namedinstance' | Get-DbaDbSpace

        Returns all user database files and free space information for the localhost and localhost\namedinstance SQL Server instances. Processes data via the pipeline.

    .EXAMPLE
        PS C:\> Get-DbaDbSpace -SqlInstance localhost -Database db1, db2 | Where-Object { $_.SpaceUntilMaxSize.Megabyte -lt 1 }

        Returns database files and free space information for the db1 and db2 on localhost where there is only 1MB left until the space is maxed out

    .EXAMPLE
        PS C:\> Get-DbaDbSpace -SqlInstance localhost -Database db1, db2 | Where-Object { $_.SpaceUntilMaxSize.Gigabyte -lt 1 }

        Returns database files and free space information for the db1 and db2 on localhost where there is only 1GB left until the space is maxed out

    #>
    [CmdletBinding()]
    param ([parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$ExcludeDatabase,
        [switch]$IncludeSystemDBs,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        $sql = "SELECT SERVERPROPERTY('MachineName') AS ComputerName,
                                   ISNULL(SERVERPROPERTY('InstanceName'), 'MSSQLSERVER') AS InstanceName,
                                   SERVERPROPERTY('ServerName') AS SqlInstance,
                    DB_NAME() as DBName
                    ,f.name AS [FileName]
                    ,fg.name AS [Filegroup]
                    ,f.physical_name AS [PhysicalName]
                    ,f.type_desc AS [FileType]
                    ,CAST(CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS FLOAT) as [UsedSpaceMB]
                    ,CAST(f.size/128.0 - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS FLOAT) AS [FreeSpaceMB]
                    ,CAST((f.size/128.0) AS FLOAT) AS [FileSizeMB]
                    ,CAST((FILEPROPERTY(f.name, 'SpaceUsed')/(f.size/1.0)) * 100 as FLOAT) as [PercentUsed]
                    ,CAST((f.growth/128.0) AS FLOAT) AS [GrowthMB]
                    ,CASE is_percent_growth WHEN 1 THEN 'pct' WHEN 0 THEN 'MB' ELSE 'Unknown' END AS [GrowthType]
                    ,CASE f.max_size WHEN -1 THEN 2147483648. ELSE CAST((f.max_size/128.0) AS FLOAT) END AS [MaxSizeMB]
                    ,CAST((f.size/128.0) AS FLOAT) - CAST(CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int)/128.0 AS FLOAT) AS [SpaceBeforeAutoGrow]
                    ,CASE f.max_size	WHEN (-1)
                                        THEN CAST(((2147483648.) - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int))/128.0 AS FLOAT)
                                        ELSE CAST((f.max_size - CAST(FILEPROPERTY(f.name, 'SpaceUsed') AS int))/128.0 AS FLOAT)
                                        END AS [SpaceBeforeMax]
                    ,CASE f.growth	WHEN 0 THEN 0.00
                                    ELSE	CASE f.is_percent_growth	WHEN 0
                                                    THEN	CASE f.max_size
                                                            WHEN (-1)
                                                            THEN CAST(((((2147483648.)-f.Size)/f.Growth)*f.Growth)/128.0 AS FLOAT)
                                                            ELSE CAST((((f.max_size-f.Size)/f.Growth)*f.Growth)/128.0 AS FLOAT)
                                                            END
                                                    WHEN 1
                                                    THEN	CASE f.max_size
                                                            WHEN (-1)
                                                            THEN CAST(CONVERT([int],f.Size*power((1)+CONVERT([float],f.Growth)/(100),CONVERT([int],log10(CONVERT([float],(2147483648.))/CONVERT([float],f.Size))/log10((1)+CONVERT([float],f.Growth)/(100)))))/128.0 AS FLOAT)
                                                            ELSE CAST(CONVERT([int],f.Size*power((1)+CONVERT([float],f.Growth)/(100),CONVERT([int],log10(CONVERT([float],f.Max_Size)/CONVERT([float],f.Size))/log10((1)+CONVERT([float],f.Growth)/(100)))))/128.0 AS FLOAT)
                                                            END
                                                    ELSE (0)
                                                    END
                                    END AS [PossibleAutoGrowthMB]
                    , CASE f.max_size	WHEN -1 THEN 0
                                        ELSE CASE f.growth
                                                WHEN 0 THEN (f.max_size - f.size)/128
                                                ELSE	CASE f.is_percent_growth
                                                        WHEN 0
                                                        THEN CAST((f.max_size - f.size - (	CONVERT(FLOAT,FLOOR((f.max_size-f.Size)/f.Growth)*f.Growth)))/128.0 AS FLOAT)
                                                        ELSE CAST((f.max_size - f.size - (	CONVERT([int],f.Size*power((1)+CONVERT([float],f.Growth)/(100),CONVERT([int],log10(CONVERT([float],f.Max_Size)/CONVERT([float],f.Size))/log10((1)+CONVERT([float],f.Growth)/(100)))))))/128.0 AS FLOAT)
                                                        END
                                                END
                                    END AS [UnusableSpaceMB]

                FROM sys.database_files AS f WITH (NOLOCK)
                LEFT OUTER JOIN sys.filegroups AS fg WITH (NOLOCK)
                ON f.data_space_id = fg.data_space_id"
    }

    process {
        if ($IncludeSystemDBs) {
            Stop-Function -Message "IncludeSystemDBs will be removed. Please pipe in filtered results from Get-DbaDatabase instead."
            return
        }
        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database -ExcludeDatabase $ExcludeDatabase
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            if ($server.VersionMajor -lt 9) {
                Stop-Function -Message "SQL Server 2000 not supported. $server skipped." -Continue
            }

            try {
                Write-Message -Level Verbose -Message "Querying $instance - $db."
                If ($db.status -ne 'Normal' -or $db.IsAccessible -eq $false) {
                    Write-Message -Level Warning -Message "$db is not accessible." -Target $db
                    continue
                }
                #Execute query against individual database and add to output
                foreach ($row in ($db.ExecuteWithResults($sql)).Tables.Rows) {
                    if ($row.UsedSpaceMB -is [System.DBNull]) {
                        $UsedMB = 0
                    } else {
                        $UsedMB = [Math]::Round($row.UsedSpaceMB)
                    }
                    if ($row.FreeSpaceMB -is [System.DBNull]) {
                        $FreeMB = 0
                    } else {
                        $FreeMB = [Math]::Round($row.FreeSpaceMB)
                    }
                    if ($row.PercentUsed -is [System.DBNull]) {
                        $PercentUsed = 0
                    } else {
                        $PercentUsed = [Math]::Round($row.PercentUsed)
                    }
                    if ($row.SpaceBeforeMax -is [System.DBNull]) {
                        $SpaceUntilMax = 0
                    } else {
                        $SpaceUntilMax = [Math]::Round($row.SpaceBeforeMax)
                    }
                    if ($row.UnusableSpaceMB -is [System.DBNull]) {
                        $UnusableSpace = 0
                    } else {
                        $UnusableSpace = [Math]::Round($row.UnusableSpaceMB)
                    }

                    [pscustomobject]@{
                        ComputerName       = $server.ComputerName
                        InstanceName       = $server.ServiceName
                        SqlInstance        = $server.DomainInstanceName
                        Database           = $row.DBName
                        FileName           = $row.FileName
                        FileGroup          = $row.FileGroup
                        PhysicalName       = $row.PhysicalName
                        FileType           = $row.FileType
                        UsedSpace          = [dbasize]($UsedMB * 1024 * 1024)
                        FreeSpace          = [dbasize]($FreeMB * 1024 * 1024)
                        FileSize           = [dbasize]($row.FileSizeMB * 1024 * 1024)
                        PercentUsed        = $PercentUsed
                        AutoGrowth         = [dbasize]($row.GrowthMB * 1024 * 1024)
                        AutoGrowType       = $row.GrowthType
                        SpaceUntilMaxSize  = [dbasize]($SpaceUntilMax * 1024 * 1024)
                        AutoGrowthPossible = [dbasize]($row.PossibleAutoGrowthMB * 1024 * 1024)
                        UnusableSpace      = [dbasize]($UnusableSpace * 1024 * 1024)
                    }
                }
            } catch {
                Stop-Function -Message "Unable to query $instance - $db." -Target $db -ErrorRecord $_ -Continue
            }
        }
    }
}