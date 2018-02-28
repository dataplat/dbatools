#ValidationTags#Messaging#
function Export-DbaExecutionPlan {
    <#
        .SYNOPSIS
            Exports execution plans to disk.

        .DESCRIPTION
            Exports execution plans to disk. Can pipe from Export-DbaExecutionPlan

            Thanks to
                https://www.simple-talk.com/sql/t-sql-programming/dmvs-for-query-plan-metadata/
                and
                http://www.scarydba.com/2017/02/13/export-plans-cache-sqlplan-file/
            for the idea and query.

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER SqlCredential
            Credential object used to connect to the SQL Server as a different user

        .PARAMETER Database
            The database(s) to process - this list is auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            The database(s) to exclude - this list is auto-populated from the server

        .PARAMETER SinceCreation
            Datetime object used to narrow the results to a date

        .PARAMETER SinceLastExecution
            Datetime object used to narrow the results to a date

        .PARAMETER Path
            The directory where all of the sqlxml files will be exported

        .PARAMETER WhatIf
            Shows what would happen if the command were to run. No actions are actually performed.

        .PARAMETER Confirm
            Prompts you for confirmation before executing any changing operations within the command.

        .PARAMETER PipedObject
            Internal parameter

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Performance, ExecutionPlan
            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Export-DbaExecutionPlan

        .EXAMPLE
            Export-DbaExecutionPlan -SqlInstance sqlserver2014a

            Exports all execution plans for sqlserver2014a.

        .EXAMPLE
            Export-DbaExecutionPlan -SqlInstance sqlserver2014a -Database db1, db2 -SinceLastExecution '7/1/2016 10:47:00'

            Exports all execution plans for databases db1 and db2 on sqlserver2014a since July 1, 2016 at 10:47 AM.
    #>
    [cmdletbinding(SupportsShouldProcess = $true, DefaultParameterSetName = "Default")]
    param (
        [parameter(ParameterSetName = 'NotPiped', Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [parameter(ParameterSetName = 'NotPiped')]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [parameter(ParameterSetName = 'Piped', Mandatory)]
        [parameter(ParameterSetName = 'NotPiped', Mandatory)]
        [string]$Path,
        [parameter(ParameterSetName = 'NotPiped')]
        [datetime]$SinceCreation,
        [parameter(ParameterSetName = 'NotPiped')]
        [datetime]$SinceLastExecution,
        [Parameter(ParameterSetName = 'Piped', Mandatory, ValueFromPipeline)]
        [object[]]$PipedObject,
        [Alias('Silent')]
        [switch]$EnableException
    )

    begin {
        if ($SinceCreation -ne $null) {
            $SinceCreation = $SinceCreation.ToString("yyyy-MM-dd HH:mm:ss")
        }

        if ($SinceLastExecution -ne $null) {
            $SinceLastExecution = $SinceLastExecution.ToString("yyyy-MM-dd HH:mm:ss")
        }

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
                }
                catch {
                    Stop-Function -Message "Skipped query plan for $fileName because it is null." -Target $fileName -ErrorRecord $_ -Continue
                }
            }

            foreach ($statementPlan in $object.SingleStatementPlanRaw) {
                $fileName = "$path\$shortName.sqlplan"

                try {
                    if ($Pscmdlet.ShouldProcess("localhost", "Writing XML file to $fileName")) {
                        $statementPlan.Save($fileName)
                    }
                }
                catch {
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
        if (!(Test-Path $Path)) {
            $null = New-Item -ItemType Directory -Path $Path
        }

        if ($PipedObject) {
            foreach ($object in $pipedobject) {
                Export-Plan $object
                return
            }
        }

        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $select = "SELECT DB_NAME(deqp.dbid) as DatabaseName, OBJECT_NAME(deqp.objectid) as ObjectName,
                    detqp.query_plan AS SingleStatementPlan,
                    deqp.query_plan AS BatchQueryPlan,
                    ROW_NUMBER() OVER ( ORDER BY Statement_Start_offset ) AS QueryPosition,
                    sql_handle as SqlHandle,
                    plan_handle as PlanHandle,
                    creation_time as CreationTime,
                    last_execution_time as LastExecutionTime"

            $from = " FROM sys.dm_exec_query_stats deqs
                        CROSS APPLY sys.dm_exec_text_query_plan(deqs.plan_handle,
                            deqs.statement_start_offset,
                            deqs.statement_end_offset) AS detqp
                        CROSS APPLY sys.dm_exec_query_plan(deqs.plan_handle) AS deqp
                        CROSS APPLY sys.dm_exec_sql_text(deqs.plan_handle) AS execText"

            if ($ExcludeDatabase -or $Database -or $SinceCreation.Length -gt 0 -or $SinceLastExecution.length -gt 0 -or $ExcludeEmptyQueryPlan -eq $true) {
                $where = " WHERE "
            }

            $whereArray = @()

            if ($Database -gt 0) {
                $dbList = $Database -join "','"
                $whereArray += " DB_NAME(deqp.dbid) in ('$dbList') "
            }

            if (Test-Bound 'SinceCreation') {
                Write-Message -Level Verbose -Message "Adding creation time"
                $whereArray += " creation_time >= '$SinceCreation' "
            }

            if (Test-Bound 'SinceLastExecution') {
                Write-Message -Level Verbose -Message "Adding last execution time"
                $whereArray += " last_execution_time >= '$SinceLastExecution' "
            }

            if (Test-Bound 'ExcludeDatabase') {
                $dbList = $ExcludeDatabase -join "','"
                $whereArray += " DB_NAME(deqp.dbid) not in ('$dbList') "
            }

            if (Test-Bound 'ExcludeEmptyQueryPlan') {
                $whereArray += " detqp.query_plan is not null"
            }

            if ($where.Length -gt 0) {
                $whereArray = $whereArray -join " and "
                $where = "$where $whereArray"
            }

            $sql = "$select $from $where"
            Write-Message -Level Debug -Message "SQL Statement: $sql"
            try {
                $dataTable = $server.ConnectionContext.ExecuteWithResults($sql).Tables
            }
            catch {
                Stop-Function -Message "Issue collecting execution plans" -Target $instance -ErroRecord $_ -Continue
            }

            foreach ($row in ($dataTable.Rows)) {
                $sqlHandle = "0x"; $row.sqlhandle | ForEach-Object { $sqlHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
                $planhandle = "0x"; $row.planhandle | ForEach-Object { $planhandle += ("{0:X}" -f $_).PadLeft(2, "0") }

                $object = [pscustomobject]@{
                    ComputerName           = $server.NetName
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