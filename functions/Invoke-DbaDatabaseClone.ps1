function Invoke-DbaDatabaseClone {
    <#
    .SYNOPSIS
        Clones a database schema and statistics

    .DESCRIPTION
        Clones a database schema and statistics.

        This can be useful for testing query performance without requiring all the space needed for the data in the database.

        Read more at sqlperformance: https://sqlperformance.com/2016/08/sql-statistics/expanding-dbcc-clonedatabase

        Thanks to Microsoft Tiger Team for the code and idea https://github.com/Microsoft/tigertoolbox/

    .PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.

    .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
        $cred = Get-Credential, this pass this $cred to the param.

        Windows Authentication will be used if DestinationSqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.

    .PARAMETER Database
        The database to clone - this list is auto-populated from the server.

    .PARAMETER CloneDatabase
        The name(s) to clone to.

    .PARAMETER UpdateStatistics
        Update the statistics prior to cloning (per Microsoft Tiger Team formula)

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Statistics, Performance
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

    .LINK
        https://dbatools.io/Invoke-DbaDatabaseClone

    .EXAMPLE
        Invoke-DbaDatabaseClone -SqlInstance sql2016 -Database mydb -CloneDatabase myclone
        Clones mydb to myclone on sql2016

    .EXAMPLE
        Invoke-DbaDatabaseClone -SqlInstance sql2016 -Database mydb -CloneDatabase myclone, myclone2 -UpdateStatistics
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
        [switch]$UpdateStatistics,
        [switch][Alias('Silent')]$EnableException
    )

    begin {

        if (-not $Database.Name -and -not $SqlInstance) {
            Stop-Function -Message "You must specify a server name if you did not pipe a database"
        }

        $updatestats = "declare @out table(id int identity(1,1),s sysname, o sysname, i sysname, stats_stream varbinary(max), rows bigint, pages bigint)
                    declare @dbcc table(stats_stream varbinary(max), rows bigint, pages bigint)
                    declare c cursor for
                           select object_schema_name(object_id) s, object_name(object_id) o, name i
                           from sys.indexes
                           where type_desc in ('CLUSTERED COLUMNSTORE', 'NONCLUSTERED COLUMNSTORE')
                    declare @s sysname, @o sysname, @i sysname
                    open c
                    fetch next from c into @s, @o, @i
                    while @@FETCH_STATUS = 0 begin
                           declare @showStats nvarchar(max) = N'DBCC SHOW_STATISTICS(""' + quotename(@s) + '.' + quotename(@o) + '"", ' + quotename(@i) + ') with stats_stream'
                           insert @dbcc exec sp_executesql @showStats
                           insert @out select @s, @o, @i, stats_stream, rows, pages from @dbcc
                           delete @dbcc
                           fetch next from c into @s, @o, @i
                    end
                    close c
                    deallocate c


                    declare @sql nvarchar(max);
                    declare @id int;

                    select top 1 @id=id,@sql=
                    'UPDATE STATISTICS ' + quotename(s) + '.' + quotename(o)  + '(' + quotename(i)
                    + ') with stats_stream = ' + convert(nvarchar(max), stats_stream, 1)
                    + ', rowcount = ' + convert(nvarchar(max), rows) + ', pagecount = '  + convert(nvarchar(max), pages)
                    from @out

                    WHILE (@@ROWCOUNT <> 0)
                    BEGIN
                        exec sp_executesql @sql
                        delete @out where id = @id
                        select top 1 @id=id,@sql=
                        'UPDATE STATISTICS ' + quotename(s) + '.' + quotename(o)  + '(' + quotename(i)
                        + ') with stats_stream = ' + convert(nvarchar(max), stats_stream, 1)
                        + ', rowcount = ' + convert(nvarchar(max), rows) + ', pagecount = '  + convert(nvarchar(max), pages)
                        from @out
                    END"

    }

    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"

            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 12
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $sql2012min = [version]"11.0.7001.0" # SQL 2012 SP4
            $sql2014min = [version]"12.0.5000.0" # SQL 2014 SP2
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

            if (-not $Database.Name) {
                [Microsoft.SqlServer.Management.Smo.Database]$database = $server.Databases[$database]
            }

            if ($Database.IsSystemObject) {
                Stop-Function -Message "Only user databases are supported" -Target $instance -Continue
            }

            if (-not $Database.name) {
                Stop-Function -Message "Database not found" -Target $instance -Continue
            }

            if ($UpdateStatistics) {
                try {
                    Write-Message -Level Verbose -Message "Updating statistics"
                    $null = $database.Query($updatestats)
                }
                catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                }
            }

            $dbname = $database.Name

            foreach ($db in $CloneDatabase) {
                Write-Message -Level Verbose -Message "Cloning $db from $database"
                if ($server.Databases[$db]) {
                    Stop-Function -Message "Destination clone database $db already exists" -Target $instance -Continue
                }
                else {
                    try {
                        $sql = "dbcc clonedatabase('$dbname','$db')"
                        $null = $database.Query($sql)
                        $server.Databases.Refresh()
                        Get-DbaDatabase -SqlInstance $server -Database $db
                    }
                    catch {
                        Stop-Function -Message "Failure" -ErrorRecord $_ -Target $server -Continue
                    }
                }
            }
        }
    }
}