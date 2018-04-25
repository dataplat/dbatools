function Get-DbaDbPageCount {
    [CmdLetBinding()]

    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(Mandatory = $true)]
        [object[]]$Database,
        [string[]]$Schema,
        [string[]]$Table,
        [switch]$EnableException
    )

    begin {
        # Create array list to hold the results
        $collection = New-Object System.Collections.ArrayList
    }

    process {

        if (Test-FunctionInterrupt) { return }

        # Loop through all the instances
        foreach ($instance in $SqlInstance) {

            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # Get all the databases that compare to the database parameter
            $databaseCollection = $server.Databases | Where-Object {$_.Name -in $Database}

            # Loop through each of databases
            foreach ($db in $databaseCollection) {

                # Check the version of the server to setup the correct version of the query
                if ($server.VersionMajor -lt 9) {
                    Stop-Function -Message "SQL Server version of instance $instance should be at least 2005" -Target $instance -Continue
                }
                elseif ($server.VersionMajor -ge 9 -and $server.VersionMajor -le 10) {
                    $query = "
SELECT '$instance' AS Instance,
    '$($db.Name)' AS [Database],
    ss.name AS [Schema],
    st.name AS [Table],
    SUM(ps.reserved_page_count) AS TotalPages,
    (SUM(ps.reserved_page_count) - SUM(ps.used_page_count)) AS UnusedPages,
    SUM(ps.used_page_count) AS UsedPages
FROM sys.dm_db_partition_stats ps
    INNER JOIN sys.tables st
        ON st.object_id = ps.object_id
    INNER JOIN sys.schemas AS ss
        ON ss.schema_id = st.schema_id
GROUP BY ss.name,
         st.name
HAVING SUM(ps.reserved_page_count) > 0
ORDER BY ss.name,
         st.name;
                    "
                }
                elseif ($server.VersionMajor -ge 11) {
                    $query = "
SELECT '$instance' AS Instance,
    '$($db.Name)' AS [Database],
    ss.name AS [Schema],
    st.name AS [Table],
    COUNT(*) AS TotalPages,
    SUM(   CASE
               WHEN is_allocated = 0 THEN
                   1
               ELSE
                   0
           END
       ) AS UnusedPages,
    SUM(   CASE
               WHEN is_allocated = 1 THEN
                   1
               ELSE
                   0
           END
       ) AS UsedPages
FROM sys.dm_db_database_page_allocations(DB_ID(), NULL, NULL, NULL, 'DETAILED') AS dbpa
 INNER JOIN sys.tables AS st
     ON st.object_id = dbpa.object_id
 INNER JOIN sys.schemas AS ss
     ON ss.schema_id = st.schema_id
GROUP BY OBJECT_NAME(dbpa.object_id),
      st.name,
      ss.name;
                "
                }

                # Get the results
                try {
                    $results = Invoke-DbaSqlQuery -SqlInstance $instance -Database $db.Name -Query $query
                }
                catch {
                    Stop-Function -Message "Something went wrong executing the query" -ErrorRecord $_ -Target $instance
                }

                # Filter the results if neccesary
                if ($Schema) {
                    $results = $results | Where-Object {$_.Schema -in $Schema}
                }

                if ($Table) {
                    $results = $results | Where-Object {$_.Table -in $Table}
                }

                # Add the results to the collection
                $collection += $results
            }

        }

        return $collection

    }

    end {
        if (Test-FunctionInterrupt) { return }

        Write-Message -Message "Finished retrieving page count for database" -Level Verbose
    }

}