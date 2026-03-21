function Get-DbaExecutionPlan {
    <#
    .SYNOPSIS
        Retrieves cached execution plans and metadata from SQL Server's plan cache

    .DESCRIPTION
        Retrieves execution plans from SQL Server's plan cache using Dynamic Management Views (sys.dm_exec_query_stats, sys.dm_exec_query_plan, and sys.dm_exec_text_query_plan). This is essential for performance analysis because it shows you what queries are actually running and how SQL Server is executing them, without having to capture plans in real-time.

        The function returns detailed metadata including database name, object name, creation time, last execution time, query and plan handles, plus the actual XML execution plans. You can filter results by database, creation date, or last execution time to focus on specific queries or time periods. Use this when troubleshooting performance issues, identifying resource-intensive queries, or analyzing query plan changes over time.

        The output can be piped directly to Export-DbaExecutionPlan to save plans as .sqlplan files for detailed analysis in SQL Server Management Studio or other tools.

        Thanks to following for the queries:
        https://www.simple-talk.com/sql/t-sql-programming/dmvs-for-query-plan-metadata/
        http://www.scarydba.com/2017/02/13/export-plans-cache-sqlplan-file/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to include when retrieving execution plans from the plan cache.
        Use this to focus performance analysis on specific databases instead of scanning all databases on the instance.
        Accepts multiple database names and supports wildcards for pattern matching.

    .PARAMETER ExcludeDatabase
        Specifies which databases to exclude when retrieving execution plans from the plan cache.
        Useful when you want to analyze most databases but skip system databases like tempdb or specific application databases.
        Accepts multiple database names for flexible filtering.

    .PARAMETER SinceCreation
        Filters execution plans to only those created on or after the specified date and time.
        Use this to focus on recent query plan changes after deployments, index modifications, or statistics updates.
        Helps identify new execution plans that may be causing performance issues.

    .PARAMETER SinceLastExecution
        Filters execution plans to only those executed on or after the specified date and time.
        Essential for identifying recently active queries when troubleshooting current performance problems.
        Excludes older cached plans that are no longer being used by applications.

    .PARAMETER ExcludeEmptyQueryPlan
        Excludes execution plans that have null or empty XML query plan data.
        Use this to focus only on plans with complete execution plan information for detailed performance analysis.
        Helps avoid incomplete results when you need the actual query plan XML for troubleshooting.

    .PARAMETER Force
        Returns all available columns from the Dynamic Management Views instead of the standard curated output.
        Use this when you need access to additional execution statistics, compilation details, or other raw plan cache data.
        Provides comprehensive information for advanced performance analysis and troubleshooting scenarios.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Performance
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaExecutionPlan

    .OUTPUTS
        PSCustomObject (default)

        Returns one object per execution plan found in the SQL Server plan cache. Each object contains parsed execution plan information with query metadata and cost/performance details.

        Default display properties:
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - DatabaseName: The database name where the query executes
        - ObjectName: The object name (procedure, function, or NULL for ad-hoc queries)
        - QueryPosition: Row number ordering statements within a batch
        - SqlHandle: Hexadecimal representation of the SQL handle for the query
        - PlanHandle: Hexadecimal representation of the plan handle
        - CreationTime: DateTime when the execution plan was created
        - LastExecutionTime: DateTime when the plan was last executed
        - StatementCondition: XML node containing statement conditions
        - StatementSimple: XML node for simple statements
        - StatementId: Statement identifier within the batch
        - StatementCompId: Statement compilation ID
        - StatementType: Type of statement (SELECT, INSERT, UPDATE, DELETE, etc.)
        - RetrievedFromCache: Boolean indicating if plan was retrieved from cache
        - StatementSubTreeCost: Estimated subtree cost (decimal)
        - StatementEstRows: Estimated number of rows returned (int/decimal)
        - SecurityPolicyApplied: Boolean indicating if Row-Level Security policy was applied
        - StatementOptmLevel: Optimization level (int)
        - QueryHash: Hashed identifier for the query text
        - QueryPlanHash: Hashed identifier for the query plan
        - StatementOptmEarlyAbortReason: Reason for early optimization abort if applicable
        - CardinalityEstimationModelVersion: Cardinality estimation version used (int)
        - ParameterizedText: Parameterized version of the query text
        - StatementSetOptions: SET options active during statement compilation
        - QueryPlan: XML node containing the execution plan tree structure
        - BatchConditionXml: XML node for batch-level conditions
        - BatchSimpleXml: XML node for batch-level simple statements

        Additional properties available (excluded from default view):
        - BatchQueryPlanRaw: Complete batch-level query plan as XML object
        - SingleStatementPlanRaw: Single statement plan as XML object
        - PlanWarnings: Plan warnings and advice if applicable

        System.Data.DataTable (when -Force is specified)

        Returns all columns from the Dynamic Management Views (sys.dm_exec_query_stats, sys.dm_exec_query_plan, sys.dm_exec_text_query_plan) without parsing or transformation. Provides raw access to all available execution statistics, compilation details, and metadata for advanced analysis.

    .EXAMPLE
        PS C:\> Get-DbaExecutionPlan -SqlInstance sqlserver2014a

        Gets all execution plans on  sqlserver2014a

    .EXAMPLE
        PS C:\> Get-DbaExecutionPlan -SqlInstance sqlserver2014a -Database db1, db2 -SinceLastExecution '2016-07-01 10:47:00'

        Gets all execution plans for databases db1 and db2 on sqlserver2014a since July 1, 2016 at 10:47 AM.

    .EXAMPLE
        PS C:\> Get-DbaExecutionPlan -SqlInstance sqlserver2014a, sql2016 -Exclude db1 | Format-Table

        Gets execution plan info for all databases except db1 on sqlserver2014a and sql2016 and makes the output pretty

    .EXAMPLE
        PS C:\> Get-DbaExecutionPlan -SqlInstance sql2014 -Database AdventureWorks2014, pubs -Force

        Gets super detailed information for execution plans on only for AdventureWorks2014 and pubs

    .EXAMPLE
        PS C:\> $servers = "sqlserver2014a","sql2016t"
        PS C:\> $servers | Get-DbaExecutionPlan -Force

        Gets super detailed information for execution plans on sqlserver2014a and sql2016

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [datetime]$SinceCreation,
        [datetime]$SinceLastExecution,
        [switch]$ExcludeEmptyQueryPlan,
        [switch]$Force,
        [switch]$EnableException
    )

    process {

        foreach ($instance in $SqlInstance) {
            try {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                if ($force -eq $true) {
                    $select = "SELECT * "
                } else {
                    $select = "SELECT DB_NAME(deqp.dbid) AS DatabaseName, OBJECT_NAME(deqp.objectid) AS ObjectName,
                    detqp.query_plan AS SingleStatementPlan,
                    deqp.query_plan AS BatchQueryPlan,
                    ROW_NUMBER() OVER ( ORDER BY Statement_Start_offset ) AS QueryPosition,
                    sql_handle AS SqlHandle,
                    plan_handle AS PlanHandle,
                    creation_time AS CreationTime,
                    last_execution_time AS LastExecutionTime"
                }

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

                if ($Database) {
                    $dbList = $Database -join "','"
                    $whereArray += " DB_NAME(deqp.dbid) in ('$dbList') "
                }

                if ($null -ne $SinceCreation) {
                    Write-Message -Level Verbose -Message "Adding creation time"
                    $whereArray += " creation_time >= CONVERT(DATETIME,'$($SinceCreation.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126) "
                }

                if ($null -ne $SinceLastExecution) {
                    Write-Message -Level Verbose -Message "Adding last exectuion time"
                    $whereArray += " last_execution_time >= CONVERT(DATETIME,'$($SinceLastExecution.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126) "
                }

                if ($ExcludeDatabase) {
                    $dbList = $ExcludeDatabase -join "','"
                    $whereArray += " DB_NAME(deqp.dbid) not in ('$dbList') "
                }

                if ($ExcludeEmptyQueryPlan) {
                    $whereArray += " detqp.query_plan IS NOT NULL"
                }

                if ($where.length -gt 0) {
                    $whereArray = $whereArray -join " AND "
                    $where = "$where $whereArray"
                }

                $sql = "$select $from $where"
                Write-Message -Level Debug -Message $sql

                if ($Force -eq $true) {
                    $server.Query($sql)
                } else {
                    foreach ($row in $server.Query($sql)) {
                        $simple = ([xml]$row.SingleStatementPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtSimple
                        $sqlHandle = "0x"; $row.sqlhandle | ForEach-Object { $sqlHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
                        $planHandle = "0x"; $row.planhandle | ForEach-Object { $planHandle += ("{0:X}" -f $_).PadLeft(2, "0") }
                        $planWarnings = $simple.QueryPlan.Warnings.PlanAffectingConvert;

                        [PSCustomObject]@{
                            ComputerName                      = $server.ComputerName
                            InstanceName                      = $server.ServiceName
                            SqlInstance                       = $server.DomainInstanceName
                            DatabaseName                      = $row.DatabaseName
                            ObjectName                        = $row.ObjectName
                            QueryPosition                     = $row.QueryPosition
                            SqlHandle                         = $sqlHandle
                            PlanHandle                        = $planHandle
                            CreationTime                      = $row.CreationTime
                            LastExecutionTime                 = $row.LastExecutionTime
                            StatementCondition                = ([xml]$row.SingleStatementPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtCond
                            StatementSimple                   = $simple
                            StatementId                       = $simple.StatementId
                            StatementCompId                   = $simple.StatementCompId
                            StatementType                     = $simple.StatementType
                            RetrievedFromCache                = $simple.RetrievedFromCache
                            StatementSubTreeCost              = $simple.StatementSubTreeCost
                            StatementEstRows                  = $simple.StatementEstRows
                            SecurityPolicyApplied             = $simple.SecurityPolicyApplied
                            StatementOptmLevel                = $simple.StatementOptmLevel
                            QueryHash                         = $simple.QueryHash
                            QueryPlanHash                     = $simple.QueryPlanHash
                            StatementOptmEarlyAbortReason     = $simple.StatementOptmEarlyAbortReason
                            CardinalityEstimationModelVersion = $simple.CardinalityEstimationModelVersion

                            ParameterizedText                 = $simple.ParameterizedText
                            StatementSetOptions               = $simple.StatementSetOptions
                            QueryPlan                         = $simple.QueryPlan
                            BatchConditionXml                 = ([xml]$row.BatchQueryPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtCond
                            BatchSimpleXml                    = ([xml]$row.BatchQueryPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtSimple
                            BatchQueryPlanRaw                 = [xml]$row.BatchQueryPlan
                            SingleStatementPlanRaw            = [xml]$row.SingleStatementPlan
                            PlanWarnings                      = $planWarnings
                        } | Select-DefaultView -ExcludeProperty BatchQueryPlan, SingleStatementPlan, BatchConditionXmlRaw, BatchQueryPlanRaw, SingleStatementPlanRaw, PlanWarnings
                    }
                }
            } catch {
                Stop-Function -Message "Query Failure Failure" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}