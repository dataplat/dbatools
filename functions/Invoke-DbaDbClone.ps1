function Invoke-DbaDbClone {
    <#
    .SYNOPSIS
        Clones a database schema and statistics

    .DESCRIPTION
        Clones a database schema and statistics.

        This can be useful for testing query performance without requiring all the space needed for the data in the database.

        Read more:
            - https://sqlperformance.com/2016/08/sql-statistics/expanding-dbcc-clonedatabase
            - https://support.microsoft.com/en-us/help/3177838/how-to-use-dbcc-clonedatabase-to-generate-a-schema-and-statistics-only

        Thanks to Microsoft Tiger Team for the code and idea https://github.com/Microsoft/tigertoolbox/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Database
        The database to clone - this list is auto-populated from the server.

    .PARAMETER CloneDatabase
        The name(s) to clone to.

    .PARAMETER ExcludeStatistics
        Exclude the statistics in the cloned database

    .PARAMETER ExcludeQueryStore
        Exclude the QueryStore data in the cloned database

    .PARAMETER UpdateStatistics
        Update the statistics prior to cloning (per Microsoft Tiger Team formula)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Statistics, Performance, Clone
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaDbClone

    .EXAMPLE
        PS C:\> Invoke-DbaDbClone -SqlInstance sql2016 -Database mydb -CloneDatabase myclone

        Clones mydb to myclone on sql2016

    .EXAMPLE
        PS C:\> Invoke-DbaDbClone -SqlInstance sql2016 -Database mydb -CloneDatabase myclone, myclone2 -UpdateStatistics

        Updates the statistics of mydb then clones to myclone and myclone2

#>
    [CmdletBinding()]
    param (
        [parameter(Position = 0)]
        [Alias("ServerInstance", "SqlServer", "SqlServers")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory, ValueFromPipeline)]
        [object]$Database,
        [string[]]$CloneDatabase,
        [switch]$ExcludeStatistics,
        [switch]$ExcludeQueryStore,
        [switch]$UpdateStatistics,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {

        if (-not $Database.Name -and -not $SqlInstance) {
            Stop-Function -Message "You must specify a server name if you did not pipe a database"
        }

        $sqlStats = "DECLARE @out TABLE(id INT IDENTITY(1,1), s SYSNAME, o SYSNAME, i SYSNAME, stats_stream VARBINARY(MAX), rows BIGINT, pages BIGINT)
            DECLARE @dbcc TABLE(stats_stream VARBINARY(MAX), rows BIGINT, pages BIGINT)
            DECLARE c CURSOR FOR
                    SELECT OBJECT_SCHEMA_NAME(object_id) s, OBJECT_NAME(object_id) o, name i
                    FROM sys.indexes
                    WHERE type_desc IN ('CLUSTERED COLUMNSTORE', 'NONCLUSTERED COLUMNSTORE')
            DECLARE @s SYSNAME, @o SYSNAME, @i SYSNAME
            OPEN c
            FETCH NEXT FROM c INTO @s, @o, @i
            WHILE @@FETCH_STATUS = 0
            BEGIN
                DECLARE @showStats NVARCHAR(MAX) = N'DBCC SHOW_STATISTICS(""' + QUOTENAME(@s) + '.' + QUOTENAME(@o) + '"", ' + QUOTENAME(@i) + ') WITH stats_stream'
                INSERT @dbcc EXEC sp_executesql @showStats
                INSERT @out SELECT @s, @o, @i, stats_stream, rows, pages FROM @dbcc
                DELETE @dbcc
                FETCH NEXT FROM c INTO @s, @o, @i
            END
            CLOSE c
            DEALLOCATE c

            DECLARE @sql NVARCHAR(MAX);
            DECLARE @id INT;
            SELECT TOP 1 @id=id,@sql=
            'UPDATE STATISTICS ' + QUOTENAME(s) + '.' + QUOTENAME(o)  + '(' + QUOTENAME(i)
            + ') WITH stats_stream = ' + CONVERT(NVARCHAR(MAX), stats_stream, 1)
            + ', rowcount = ' + CONVERT(NVARCHAR(MAX), rows) + ', pagecount = '  + CONVERT(NVARCHAR(MAX), pages)
            FROM @out

            WHILE (@@ROWCOUNT <> 0)
            BEGIN
                EXEC sp_executesql @sql
                DELETE @out WHERE id = @id
                SELECT TOP 1 @id=id,@sql=
                'UPDATE STATISTICS ' + QUOTENAME(s) + '.' + QUOTENAME(o)  + '(' + QUOTENAME(i)
                + ') WITH stats_stream = ' + CONVERT(NVARCHAR(MAX), stats_stream, 1)
                + ', rowcount = ' + CONVERT(NVARCHAR(MAX), rows) + ', pagecount = '  + CONVERT(NVARCHAR(MAX), pages)
                FROM @out
            END
        "

        $noStats = "NO_STATISTICS"
        $noQueryStore = "NO_QUERYSTORE"
        if ( (Test-Bound 'ExcludeStatistics') -or (Test-Bound 'ExcludeQueryStore') ) {
            $sqlWith = ""
            if ($ExcludeStatistics) {
                $sqlWith = "WITH $noStats"
            }
            if ($ExcludeQueryStore) {
                $sqlWith = "WITH $noQueryStore"
            }
            if ($ExcludeStatistics -and $ExcludeQueryStore) {
                $sqlWith = "WITH $noStats,$noQueryStore"
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 12
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sql2012min = [version]"11.0.7001.0" # SQL 2012 SP4
            $sql2014min = [version]"12.0.5000.0" # SQL 2014 SP2
            $sql2014CuMin = [version]"12.0.5538" # SQL 2014 SP2 + CU3
            $sql2016min = [version]"13.0.4001.0" # SQL 2016 SP1

            if ($server.VersionMajor -eq 11 -and $server.Version -lt $sql2012min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2012 SP4 and above required." -Target $server -Continue
            }

            if ($server.VersionMajor -eq 12 -and $server.Version -lt $sql2014min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2014 SP2 and above required." -Target $server -Continue
            }

            if ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
            }

            if (Test-Bound 'ExcludeStatistics') {
                if ($server.VersionMajor -eq 12 -and $server.Version -lt $sql2014CuMin) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2014 SP1 + CU3 and above required." -Target $server -Continue
                }
                if ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
                }
            }

            if (Test-Bound 'ExcludeQueryStore') {
                if ($server.VersionMajor -lt 13 - ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min)) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
                }
            }

            if (-not $Database.Name) {
                [Microsoft.SqlServer.Management.Smo.Database]$database = $server.Databases[$database]
            }

            if ($Database.IsSystemObject) {
                Stop-Function -Message "Only user databases are supported" -Target $instance -Continue
            }

            if (-not $Database.Name) {
                Stop-Function -Message "Database not found" -Target $instance -Continue
            }

            if ( (Test-Bound 'UpdateStatistics') -and (Test-Bound 'ExcludeStatistics' -Not) ) {
                try {
                    Write-Message -Level Verbose -Message "Updating statistics"
                    $null = $database.Query($sqlStats)
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                }
            }

            $dbName = $database.Name

            foreach ($db in $CloneDatabase) {
                Write-Message -Level Verbose -Message "Cloning $db from $database"
                if ($server.Databases[$db]) {
                    Stop-Function -Message "Destination clone database $db already exists" -Target $instance -Continue
                } else {
                    try {
                        $sql = "DBCC CLONEDATABASE('$dbName','$db') $sqlWith"
                        Write-Message -Level Debug -Message "Sql Statement: $sql"
                        $null = $database.Query($sql)
                        Get-DbaDatabase -SqlInstance $server -Database $db
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                    }
                }
            }
        }
    }
    end {
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -EnableException:$false -Alias Invoke-DbaDatabaseClone
    }
}

