function Export-DbaExecutionPlan {
    <#
    .SYNOPSIS
        Extracts execution plans from plan cache and saves them as .sqlplan files for analysis

    .DESCRIPTION
        Queries the SQL Server plan cache using dynamic management views and exports execution plans as XML files with .sqlplan extensions. These files can be opened directly in SQL Server Management Studio for detailed analysis and troubleshooting. The function retrieves both single statement plans and batch query plans from sys.dm_exec_query_stats, allowing you to analyze query performance patterns and identify optimization opportunities. You can filter results by database, creation time, or last execution time to focus on specific time periods or problematic queries. This eliminates the need to manually capture plans during query execution or dig through plan cache DMVs.

        Thanks to
        https://www.simple-talk.com/sql/t-sql-programming/dmvs-for-query-plan-metadata/
        and
        http://www.scarydba.com/2017/02/13/export-plans-cache-sqlplan-file/
        for the idea and query.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to export execution plans from. Accepts wildcards for pattern matching.
        Use this when you need to focus on specific databases instead of analyzing plans from all databases on the instance.
        Helps reduce output volume and processing time when troubleshooting database-specific performance issues.

    .PARAMETER ExcludeDatabase
        Specifies which databases to exclude from execution plan export. Accepts wildcards for pattern matching.
        Use this to skip system databases or databases that are known to be performing well when doing instance-wide plan analysis.
        Common exclusions include tempdb, model, or development databases that don't need performance review.

    .PARAMETER SinceCreation
        Filters execution plans to only include those created after the specified date and time.
        Use this when investigating performance issues that started after a specific deployment, configuration change, or known incident.
        Helps focus analysis on recently compiled plans rather than older cached plans that may no longer be relevant.

    .PARAMETER SinceLastExecution
        Filters execution plans to only include those last executed after the specified date and time.
        Use this when you want to analyze only actively used plans rather than stale plans sitting in cache.
        Particularly useful for identifying currently problematic queries during active performance issues or recent workload changes.

    .PARAMETER Path
        Specifies the directory path where .sqlplan files will be saved. Defaults to the dbatools export configuration path.
        Files are named using a pattern that includes instance name, database, query position, and SQL handle for easy identification.
        Ensure the path exists and has sufficient space, as large plan caches can generate hundreds of files.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER InputObject
        Accepts execution plan objects from the pipeline, typically from Get-DbaExecutionPlan.
        Use this when you want to filter or process plans with Get-DbaExecutionPlan first, then export specific results.
        Allows for more complex filtering scenarios before exporting plans to files.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, Performance, ExecutionPlan
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaExecutionPlan

    .EXAMPLE
        PS C:\> Export-DbaExecutionPlan -SqlInstance sqlserver2014a -Path C:\Temp

        Exports all execution plans for sqlserver2014a. Files saved in to C:\Temp

    .EXAMPLE
        PS C:\> Export-DbaExecutionPlan -SqlInstance sqlserver2014a -Database db1, db2 -SinceLastExecution '2016-07-01 10:47:00' -Path C:\Temp

        Exports all execution plans for databases db1 and db2 on sqlserver2014a since July 1, 2016 at 10:47 AM. Files saved in to C:\Temp

    .EXAMPLE
        PS C:\> Get-DbaExecutionPlan -SqlInstance sqlserver2014a | Export-DbaExecutionPlan -Path C:\Temp

        Gets all execution plans for sqlserver2014a. Using Pipeline exports them all to C:\Temp

    .EXAMPLE
        PS C:\> Get-DbaExecutionPlan -SqlInstance sqlserver2014a | Export-DbaExecutionPlan -Path C:\Temp -WhatIf

        Gets all execution plans for sqlserver2014a. Then shows what would happen if the results where piped to Export-DbaExecutionPlan

    #>
    [cmdletbinding(SupportsShouldProcess, DefaultParameterSetName = "Default")]
    param (
        [parameter(ParameterSetName = 'NotPiped', Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(ParameterSetName = 'NotPiped')]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ParameterSetName = 'Piped')]
        [parameter(ParameterSetName = 'NotPiped')]
        # No file path because this needs a directory
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [parameter(ParameterSetName = 'NotPiped')]
        [datetime]$SinceCreation,
        [parameter(ParameterSetName = 'NotPiped')]
        [datetime]$SinceLastExecution,
        [Parameter(ParameterSetName = 'Piped', Mandatory, ValueFromPipeline)]
        [object[]]$InputObject,
        [switch]$EnableException
    )

    begin {

        function Export-Plan {
            param(
                [object]$object
            )
            $instanceName = $object.SqlInstance
            $dbName = $object.DatabaseName
            $queryPosition = $object.QueryPosition
            $sqlHandle = "0x"; $object.SqlHandle | ForEach-Object { $sqlHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
            $sqlHandle = $sqlHandle.TrimStart('0x02000000').TrimEnd('0000000000000000000000000000000000000000')
            $shortName = "$instanceName-$dbName-$queryPosition-$sqlHandle"

            foreach ($queryPlan in $object.BatchQueryPlanRaw) {
                $fileName = "$path\$shortName-batch.sqlplan"

                try {
                    if ($Pscmdlet.ShouldProcess("localhost", "Writing XML file to $fileName")) {
                        $queryPlan.Save($fileName)
                    }
                } catch {
                    Stop-Function -Message "Skipped query plan for $fileName because it is null." -Target $fileName -ErrorRecord $_ -Continue
                }
            }

            foreach ($statementPlan in $object.SingleStatementPlanRaw) {
                $fileName = "$path\$shortName.sqlplan"

                try {
                    if ($Pscmdlet.ShouldProcess("localhost", "Writing XML file to $fileName")) {
                        $statementPlan.Save($fileName)
                    }
                } catch {
                    Stop-Function -Message "Skipped statement plan for $fileName because it is null." -Target $fileName -ErrorRecord $_ -Continue
                }
            }

            if ($Pscmdlet.ShouldProcess("console", "Showing output object")) {
                Add-Member -Force -InputObject $object -MemberType NoteProperty -Name OutputFile -Value $fileName
                Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, DatabaseName, SqlHandle, CreationTime, LastExecutionTime, OutputFile
            }
        }
    }

    process {

        if ((Test-Bound -ParamterName Path) -and ((Get-Item $Path -ErrorAction Ignore) -isnot [System.IO.DirectoryInfo])) {
            if ($Path -eq (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport')) {
                $null = New-Item -ItemType Directory -Path $Path
            } else {
                Stop-Function -Message "Path ($Path) must be a directory"
                return
            }
        }

        if ($InputObject) {
            foreach ($object in $InputObject) {
                Export-Plan $object
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $select = "SELECT DB_NAME(deqp.dbid) AS DatabaseName, OBJECT_NAME(deqp.objectid) AS ObjectName,
                    detqp.query_plan AS SingleStatementPlan,
                    deqp.query_plan AS BatchQueryPlan,
                    ROW_NUMBER() OVER ( ORDER BY Statement_Start_offset ) AS QueryPosition,
                    sql_handle AS SqlHandle,
                    plan_handle AS PlanHandle,
                    creation_time AS CreationTime,
                    last_execution_time AS LastExecutionTime"

            $from = " FROM sys.dm_exec_query_stats deqs
                        CROSS APPLY sys.dm_exec_text_query_plan(deqs.plan_handle,
                            deqs.statement_start_offset,
                            deqs.statement_end_offset) AS detqp
                        CROSS APPLY sys.dm_exec_query_plan(deqs.plan_handle) AS deqp
                        CROSS APPLY sys.dm_exec_sql_text(deqs.plan_handle) AS execText"

            if ($ExcludeDatabase -or $Database -or $SinceCreation -or $SinceLastExecution -or $ExcludeEmptyQueryPlan -eq $true) {
                $where = " WHERE "
            }

            $whereArray = @()

            if ($Database -gt 0) {
                $dbList = $Database -join "','"
                $whereArray += " DB_NAME(deqp.dbid) IN ('$dbList') "
            }

            if (Test-Bound 'SinceCreation') {
                Write-Message -Level Verbose -Message "Adding creation time"
                $whereArray += " creation_time >= CONVERT(DATETIME,'$($SinceCreation.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126) "
            }

            if (Test-Bound 'SinceLastExecution') {
                Write-Message -Level Verbose -Message "Adding last execution time"
                $whereArray += " last_execution_time >= CONVERT(DATETIME,'$($SinceLastExecution.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126) "
            }

            if (Test-Bound 'ExcludeDatabase') {
                $dbList = $ExcludeDatabase -join "','"
                $whereArray += " DB_NAME(deqp.dbid) NOT IN ('$dbList') "
            }

            if (Test-Bound 'ExcludeEmptyQueryPlan') {
                $whereArray += " detqp.query_plan IS NOT NULL"
            }

            if ($where.Length -gt 0) {
                $whereArray = $whereArray -join " AND "
                $where = "$where $whereArray"
            }

            $sql = "$select $from $where"
            Write-Message -Level Debug -Message "SQL Statement: $sql"
            try {
                $dataTable = $server.ConnectionContext.ExecuteWithResults($sql).Tables
            } catch {
                Stop-Function -Message "Issue collecting execution plans" -Target $instance -ErroRecord $_ -Continue
            }

            foreach ($row in ($dataTable.Rows)) {
                $sqlHandle = "0x"; $row.sqlhandle | ForEach-Object { $sqlHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
                $planhandle = "0x"; $row.planhandle | ForEach-Object { $planhandle += ("{0:X}" -f $_).PadLeft(2, "0") }

                $object = [PSCustomObject]@{
                    ComputerName           = $server.ComputerName
                    InstanceName           = $server.ServiceName
                    SqlInstance            = $server.DomainInstanceName
                    DatabaseName           = $row.DatabaseName
                    SqlHandle              = $sqlHandle
                    PlanHandle             = $planhandle
                    SingleStatementPlan    = $row.SingleStatementPlan
                    BatchQueryPlan         = $row.BatchQueryPlan
                    QueryPosition          = $row.QueryPosition
                    CreationTime           = $row.CreationTime
                    LastExecutionTime      = $row.LastExecutionTime
                    BatchQueryPlanRaw      = [xml]$row.BatchQueryPlan
                    SingleStatementPlanRaw = [xml]$row.SingleStatementPlan
                }
                Export-Plan $object
            }
        }
    }
}