function Get-DbaExecutionPlan {
    <#
.SYNOPSIS
Gets execution plans and metadata

.DESCRIPTION
Gets execution plans and metadata. Can pipe to Export-DbaExecutionPlan :D

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
Return restore information for only specific databases. These are only the databases that currently exist on the server.

.PARAMETER ExcludeDatabase
Return restore information for all but these specific databases

.PARAMETER SinceCreation
Datetime object used to narrow the results to a date

.PARAMETER SinceLastExecution
Datetime object used to narrow the results to a date

.PARAMETER ExcludeEmptyQueryPlan
Exclude results with empty query plan

.PARAMETER Force
Returns a ton of raw information about the execution plans

.PARAMETER EnableException
    By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.


.NOTES
Tags: Performance
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

.LINK
https://dbatools.io/Get-DbaExecutionPlan

.EXAMPLE
Get-DbaExecutionPlan -SqlInstance sqlserver2014a

Gets all execution plans on  sqlserver2014a

.EXAMPLE
Get-DbaExecutionPlan -SqlInstance sqlserver2014a -Database db1, db2 -SinceLastExecution '7/1/2016 10:47:00'

Gets all execution plans for databases db1 and db2 on sqlserver2014a since July 1, 2016 at 10:47 AM.

.EXAMPLE
Get-DbaExecutionPlan -SqlInstance sqlserver2014a, sql2016 -Exclude db1 | Format-Table

Gets execution plan info for all databases except db1 on sqlserver2014a and sql2016 and makes the output pretty

.EXAMPLE
Get-DbaExecutionPlan -SqlInstance sql2014 -Database AdventureWorks2014, pubs -Force

Gets super detailed information for execution plans on only for AdventureWorks2014 and pubs

#>
    [CmdletBinding()]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [datetime]$SinceCreation,
        [datetime]$SinceLastExecution,
        [switch]$ExcludeEmptyQueryPlan,
        [switch]$Force,
        [switch]$EnableException
    )

    begin {

        if ($SinceCreation -ne $null) {
            $SinceCreation = $SinceCreation.ToString("yyyy-MM-dd HH:mm:ss")
        }

        if ($SinceLastExecution -ne $null) {
            $SinceLastExecution = $SinceLastExecution.ToString("yyyy-MM-dd HH:mm:ss")
        }
    }
    process {

        foreach ($instance in $sqlinstance) {
            try {
                try {
                    Write-Message -Level Verbose -Message "Connecting to $instance."
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
                }
                catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                if ($force -eq $true) {
                    $select = "SELECT * "
                }
                else {
                    $select = "SELECT DB_NAME(deqp.dbid) as DatabaseName, OBJECT_NAME(deqp.objectid) as ObjectName,
                    detqp.query_plan AS SingleStatementPlan,
                    deqp.query_plan AS BatchQueryPlan,
                    ROW_NUMBER() OVER ( ORDER BY Statement_Start_offset ) AS QueryPosition,
                    sql_handle as SqlHandle,
                    plan_handle as PlanHandle,
                    creation_time as CreationTime,
                    last_execution_time as LastExecutionTime"
                }

                $from = " FROM sys.dm_exec_query_stats deqs
                        CROSS APPLY sys.dm_exec_text_query_plan(deqs.plan_handle,
                            deqs.statement_start_offset,
                            deqs.statement_end_offset) AS detqp
                        CROSS APPLY sys.dm_exec_query_plan(deqs.plan_handle) AS deqp
                        CROSS APPLY sys.dm_exec_sql_text(deqs.plan_handle) AS execText"

                if ($ExcludeDatabase -or $Database -or $SinceCreation.length -gt 0 -or $SinceLastExecution.length -gt 0 -or $ExcludeEmptyQueryPlan -eq $true) {
                    $where = " WHERE "
                }

                $wherearray = @()

                if ($Database) {
                    $dblist = $Database -join "','"
                    $wherearray += " DB_NAME(deqp.dbid) in ('$dblist') "
                }

                if ($null -ne $SinceCreation) {
                    Write-Message -Level Verbose -Message "Adding creation time"
                    $wherearray += " creation_time >= '$SinceCreation' "
                }

                if ($null -ne $SinceLastExecution) {
                    Write-Message -Level Verbose -Message "Adding last exectuion time"
                    $wherearray += " last_execution_time >= '$SinceLastExecution' "
                }

                if ($ExcludeDatabase) {
                    $dblist = $ExcludeDatabase -join "','"
                    $wherearray += " DB_NAME(deqp.dbid) not in ('$dblist') "
                }

                if ($ExcludeEmptyQueryPlan) {
                    $wherearray += " detqp.query_plan is not null"
                }

                if ($where.length -gt 0) {
                    $wherearray = $wherearray -join " and "
                    $where = "$where $wherearray"
                }

                $sql = "$select $from $where"
                Write-Message -Level Debug -Message $sql

                if ($Force -eq $true) {
                    $server.Query($sql)
                }
                else {
                    foreach ($row in $server.Query($sql)) {
                        $simple = ([xml]$row.SingleStatementPlan).ShowPlanXML.BatchSequence.Batch.Statements.StmtSimple
                        $sqlhandle = "0x"; $row.sqlhandle | ForEach-Object { $sqlhandle += ("{0:X}" -f $_).PadLeft(2, "0") }
                        $planhandle = "0x"; $row.planhandle | ForEach-Object { $planhandle += ("{0:X}" -f $_).PadLeft(2, "0") }
                        $planWarnings = $simple.QueryPlan.Warnings.PlanAffectingConvert;

                        [pscustomobject]@{
                            ComputerName                      = $server.NetName
                            InstanceName                      = $server.ServiceName
                            SqlInstance                       = $server.DomainInstanceName
                            DatabaseName                      = $row.DatabaseName
                            ObjectName                        = $row.ObjectName
                            QueryPosition                     = $row.QueryPosition
                            SqlHandle                         = $SqlHandle
                            PlanHandle                        = $PlanHandle
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
            }
            catch {
                Stop-Function -Message "Query Failure Failure" -ErrorRecord $_ -Target $instance -Continue
            }
        }
    }
}
