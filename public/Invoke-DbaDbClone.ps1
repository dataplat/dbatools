function Invoke-DbaDbClone {
    <#
    .SYNOPSIS
        Creates lightweight database clones containing schema and statistics but no table data

    .DESCRIPTION
        Creates schema-only database clones using SQL Server's DBCC CLONEDATABASE command. The cloned database contains all database objects (tables, indexes, views, procedures) and statistics, but no actual table data.

        This is particularly valuable for performance troubleshooting scenarios where you need to analyze query execution plans and optimizer behavior without the storage overhead of copying entire tables. DBAs commonly use this for reproducing performance issues in test environments or sharing database structures with vendors for support cases.

        Read more:
            - https://sqlperformance.com/2016/08/sql-statistics/expanding-dbcc-clonedatabase
            - https://support.microsoft.com/en-us/help/3177838/how-to-use-dbcc-clonedatabase-to-generate-a-schema-and-statistics-only

        Thanks to Microsoft Tiger Team for the code and idea https://github.com/Microsoft/tigertoolbox/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies the source database(s) to clone from the SQL Server instance. Accepts multiple database names for batch operations.
        Use this when connecting directly to an instance rather than piping database objects from Get-DbaDatabase.

    .PARAMETER InputObject
        Accepts database objects from Get-DbaDatabase through the pipeline, allowing for filtered operations.
        This method provides more flexibility than the Database parameter for complex database selection scenarios.

    .PARAMETER CloneDatabase
        Specifies the name(s) for the new cloned database(s). If not provided, defaults to adding '_clone' suffix to the source database name.
        Each clone must have a unique name on the target instance and cannot already exist.

    .PARAMETER ExcludeStatistics
        Excludes table and index statistics from the cloned database, creating only the schema structure without statistical metadata.
        Use this when you only need the database structure for schema comparison or when statistics would interfere with your testing scenario. Requires SQL Server 2014 SP2 CU3+ or SQL Server 2016 SP1+.

    .PARAMETER ExcludeQueryStore
        Excludes Query Store data from the cloned database, preventing historical query execution data from being copied.
        Use this when you want a clean slate for query performance analysis or when Query Store data is not relevant to your testing scenario. Requires SQL Server 2016 SP1 or higher.

    .PARAMETER UpdateStatistics
        Updates column store index statistics in the source database before cloning using Microsoft Tiger Team methodology.
        Use this when working with column store indexes to ensure the clone contains current statistical information for accurate query plan generation.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

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
        PS C:\> Get-DbaDatabase -SqlInstance sql2016 -Database mydb | Invoke-DbaDbClone -CloneDatabase myclone, myclone2 -UpdateStatistics

        Updates the statistics of mydb then clones to myclone and myclone2

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject,
        [string[]]$CloneDatabase,
        [switch]$ExcludeStatistics,
        [switch]$ExcludeQueryStore,
        [switch]$UpdateStatistics,
        [switch]$EnableException
    )

    begin {
        if (-not $Database -and $SqlInstance) {
            Stop-Function -Message "You must specify a database name if you did not pipe a database"
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
        if ( (Test-Bound -ParameterName 'ExcludeStatistics') -or (Test-Bound -ParameterName 'ExcludeQueryStore') ) {
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

        $sql2012min = [version]"11.0.7001" # SQL 2012 SP4
        $sql2014min = [version]"12.0.5000" # SQL 2014 SP2
        $sql2014CuMin = [version]"12.0.5538" # SQL 2014 SP2 + CU3
        $sql2016min = [version]"13.0.4001" # SQL 2016 SP1
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        }

        foreach ($db in $InputObject) {
            $server = $db.Parent
            $instance = $server.Name

            if (-not (Test-Bound -ParameterName CloneDatabase)) {
                $CloneDatabase = "$($db.Name)_clone"
            }

            if ($server.VersionMajor -eq 11 -and $server.Version -lt $sql2012min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2012 SP4 and above required." -Target $server -Continue
            }

            if ($server.VersionMajor -eq 12 -and $server.Version -lt $sql2014min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2014 SP2 and above required." -Target $server -Continue
            }

            if ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min) {
                Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
            }

            if (Test-Bound -ParameterName 'ExcludeStatistics') {
                if ($server.VersionMajor -eq 12 -and $server.Version -lt $sql2014CuMin) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2014 SP1 + CU3 and above required." -Target $server -Continue
                }
                if ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
                }
            }

            if (Test-Bound -ParameterName 'ExcludeQueryStore') {
                if ($server.VersionMajor -lt 13 - ($server.VersionMajor -eq 13 -and $server.Version -lt $sql2016min)) {
                    Stop-Function -Message "Unsupported version for $instance. SQL Server 2016 SP1 and above required." -Target $server -Continue
                }
            }

            if ($db.IsSystemObject) {
                Stop-Function -Message "Only user databases are supported" -Target $instance -Continue
            }

            if ( (Test-Bound -ParameterName 'UpdateStatistics') -and (Test-Bound -ParameterName 'ExcludeStatistics' -Not) ) {
                if ($Pscmdlet.ShouldProcess($instance, "Update statistics in $($db.Name)")) {
                    try {
                        Write-Message -Level Verbose -Message "Updating statistics"
                        $null = $db.Invoke($sqlStats)
                    } catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                    }
                }
            }

            $dbName = $db.Name

            foreach ($clonedb in $CloneDatabase) {
                Write-Message -Level Verbose -Message "Cloning $clonedb from $db"
                if ($server.Databases[$clonedb]) {
                    Stop-Function -Message "Destination clone database $clonedb already exists" -Target $instance -Continue
                } else {
                    if ($Pscmdlet.ShouldProcess($instance, "Execute DBCC CloneDatabase($dbName, $clonedb)")) {
                        try {
                            $sql = "DBCC CLONEDATABASE('$dbName','$clonedb') $sqlWith"
                            Write-Message -Level Debug -Message "Sql Statement: $sql"
                            $null = $db.Invoke($sql)
                            $server.Databases.Refresh()
                            Get-DbaDatabase -SqlInstance $server -Database $clonedb
                        } catch {
                            Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                        }
                    }
                }
            }
        }
    }
}