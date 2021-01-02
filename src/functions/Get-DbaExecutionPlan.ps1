function Get-DbaExecutionPlan {
    <#
    .SYNOPSIS
        Gets execution plans and metadata

    .DESCRIPTION
        Gets execution plans and metadata. Can pipe to Export-DbaExecutionPlan

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
        Return execution plans and metadata for only specific databases.

    .PARAMETER ExcludeDatabase
        Return execution plans and metadata for all but these specific databases

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
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaExecutionPlan

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
                    $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
                } catch {
                    Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }

                if ($force -eq $true) {
                    $select = "SELECT * "
                } else {
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
                    $whereArray += " creation_time >= CONVERT(datetime,'$($SinceCreation.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126) "
                }

                if ($null -ne $SinceLastExecution) {
                    Write-Message -Level Verbose -Message "Adding last exectuion time"
                    $whereArray += " last_execution_time >= CONVERT(datetime,'$($SinceLastExecution.ToString("yyyy-MM-ddTHH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture))',126) "
                }

                if ($ExcludeDatabase) {
                    $dbList = $ExcludeDatabase -join "','"
                    $whereArray += " DB_NAME(deqp.dbid) not in ('$dbList') "
                }

                if ($ExcludeEmptyQueryPlan) {
                    $whereArray += " detqp.query_plan is not null"
                }

                if ($where.length -gt 0) {
                    $whereArray = $whereArray -join " and "
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

                        [pscustomobject]@{
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