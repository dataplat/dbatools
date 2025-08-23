function Invoke-DbaWhoIsActive {
    <#
    .SYNOPSIS
        Retrieves real-time information about active SQL Server sessions and currently running queries

    .DESCRIPTION
        Executes Adam Machanic's sp_WhoIsActive stored procedure to display detailed information about currently running sessions, active queries, and their resource consumption. This is the go-to command for troubleshooting performance issues, identifying blocking chains, and monitoring SQL Server activity in real-time. Provides comprehensive session details including wait statistics, query plans, lock information, and transaction details that would otherwise require querying multiple DMVs manually.

        This command was built with Adam's permission. To read more about sp_WhoIsActive, please visit:

        Updates: http://sqlblog.com/blogs/adam_machanic/archive/tags/who+is+active/default.aspx

        Also, consider donating to Adam if you find this stored procedure helpful: http://tinyurl.com/WhoIsActiveDonate

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER Database
        Specifies the database where sp_WhoIsActive is installed. Defaults to master if not specified.
        Use this when you've installed sp_WhoIsActive in a different database like a DBA utilities database.

    .PARAMETER Filter
        Filters results to include only sessions matching the specified criteria. Supports wildcards (% and _) for pattern matching.
        Use this to focus on specific sessions, applications, databases, logins, or hosts when troubleshooting performance issues.
        For session ID filtering, use 0 or an empty string to include all sessions.

    .PARAMETER FilterType
        Specifies what type of filtering to apply with the Filter parameter. Valid options: Session, Program, Database, Login, Host.
        Use 'Program' to filter by application name, 'Login' to filter by SQL login, or 'Host' to filter by client machine name.

    .PARAMETER NotFilter
        Excludes sessions matching the specified criteria from results. Supports wildcards (% and _) for pattern matching.
        Use this to exclude specific applications, databases, or users when you want to focus on everything else.
        For session ID filtering, use 0 or an empty string to exclude no sessions.

    .PARAMETER NotFilterType
        Specifies what type of exclusion filtering to apply with the NotFilter parameter. Valid options: Session, Program, Database, Login, Host.
        Use this in combination with NotFilter to exclude sessions by application name, database, login, or host.

    .PARAMETER ShowOwnSpid
        Includes the current session (the one running sp_WhoIsActive) in the results.
        By default, your own session is excluded to reduce clutter in the output.

    .PARAMETER ShowSystemSpids
        Includes internal SQL Server system sessions in the results.
        Use this when troubleshooting system-level performance issues or investigating background processes.

    .PARAMETER ShowSleepingSpids
        Controls which idle sessions to include based on their transaction status. 0 = no sleeping sessions, 1 = only sleeping sessions with open transactions, 2 = all sleeping sessions.
        Use 1 when investigating blocking issues or long-running transactions, or 2 for comprehensive session auditing.

    .PARAMETER GetFullInnerText
        Retrieves the complete SQL batch or stored procedure text instead of just the current statement.
        Use this when you need to see the full context of what's executing, not just the individual statement within a larger batch.

    .PARAMETER GetPlans
        Retrieves execution plans for active queries. 1 = plan for current statement only, 2 = entire plan for the batch or procedure.
        Essential for performance troubleshooting to identify inefficient queries, missing indexes, and optimization opportunities.

    .PARAMETER GetOuterCommand
        Captures the original command that initiated the current batch, including stored procedure calls with parameters.
        Useful for understanding the full call stack when procedures call other procedures or dynamic SQL.

    .PARAMETER GetTransactionInfo
        Includes transaction log usage and duration information for active sessions.
        Critical for identifying sessions with long-running transactions that may cause blocking or log space issues.

    .PARAMETER GetTaskInfo
        Controls task and wait information collection. 0 = no task info, 1 = lightweight mode with primary waits and blockers, 2 = comprehensive task metrics including I/O and context switches.
        Use level 1 for general troubleshooting or level 2 for detailed performance analysis when you need full wait statistics.

    .PARAMETER GetLocks
        Retrieves detailed lock information for each session in XML format.
        Essential for troubleshooting blocking issues and understanding what resources sessions are waiting for or holding.

    .PARAMETER GetAverageTime
        Calculates the average execution time for the currently running query based on historical execution data.
        Helps identify queries that are running longer than usual, indicating potential performance degradation.

    .PARAMETER GetAdditonalInfo
        Includes session configuration details like ANSI settings, isolation level, language, and command type information.
        Useful for troubleshooting application-specific issues where session settings affect query behavior or when investigating SQL Agent job activity.

    .PARAMETER FindBlockLeaders
        Identifies the root cause sessions in blocking chains and counts how many sessions each one is blocking.
        Critical for resolving blocking issues by showing you which sessions to focus on first when multiple blocking chains exist.

    .PARAMETER DeltaInterval
        Captures performance metrics at two points in time separated by the specified interval (in seconds) to show rate-of-change data.
        Excellent for identifying which sessions are actively consuming CPU, I/O, or memory resources during the measurement period.

    .PARAMETER OutputColumnList
        Specifies which columns to include in the results and their display order using bracket-delimited column names.
        Customize this to focus on specific metrics or reduce output complexity for your monitoring scenarios.
        Only columns related to enabled features will actually appear in the output.

    .PARAMETER SortOrder
        Controls how results are sorted using bracket-delimited column names with optional ASC/DESC direction.
        Sort by CPU, physical_io, or start_time to quickly identify the most resource-intensive or longest-running sessions.
        Defaults to sorting by start_time in ascending order.

    .PARAMETER FormatOutput
        Controls output formatting for better readability. 0 = no formatting, 1 = variable-width fonts (default), 2 = fixed-width fonts.
        Use 2 when displaying results in console windows or fixed-width displays for better column alignment.

    .PARAMETER DestinationTable
        Inserts results directly into a specified table instead of returning them to PowerShell.
        Useful for automated monitoring scripts or building historical performance data repositories.
        Table must already exist with the correct schema structure.

    .PARAMETER ReturnSchema
        Returns a CREATE TABLE statement showing the schema structure needed for the DestinationTable instead of collecting data.
        Use this to generate the correct table structure before setting up automated data collection with DestinationTable.

    .PARAMETER Schema
        Alternative parameter name for ReturnSchema functionality.
        Returns a CREATE TABLE statement for the result set structure instead of collecting actual data.

    .PARAMETER Help
        Returns detailed help information about sp_WhoIsActive parameters and their usage instead of executing the procedure.
        Use this to understand all available options when you're unsure which parameters to use for your specific troubleshooting scenario.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER As
        Specifies the PowerShell output format. Options: DataSet, DataTable, DataRow (default), PSObject.
        Use PSObject for advanced scripting scenarios where you need better handling of null values and type conversion.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Community, WhoIsActive
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        http://whoisactive.com

    .LINK
        https://dbatools.io/Invoke-DbaWhoIsActive

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a

        Execute sp_whoisactive on sqlserver2014a. This command expects sp_WhoIsActive to be in the master database. Logs into the SQL Server with Windows credentials.

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -SqlCredential $credential -Database dbatools

        Execute sp_whoisactive on sqlserver2014a. This command expects sp_WhoIsActive to be in the dbatools database. Logs into the SQL Server with SQL Authentication.

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -GetAverageTime

        Similar to running sp_WhoIsActive @get_avg_time

    .EXAMPLE
        PS C:\> Invoke-DbaWhoIsActive -SqlInstance sqlserver2014a -GetOuterCommand -FindBlockLeaders

        Similar to running sp_WhoIsActive @get_outer_command = 1, @find_block_leaders = 1
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]
        $SqlCredential,
        [string]$Database,
        [ValidateLength(0, 128)]
        [string]$Filter,
        [ValidateSet('Session', 'Program', 'Database', 'Login', 'Host')]
        [string]$FilterType = 'Session',
        [ValidateLength(0, 128)]
        [string]$NotFilter,
        [ValidateSet('Session', 'Program', 'Database', 'Login', 'Host')]
        [string]$NotFilterType = 'Session',
        [switch]$ShowOwnSpid,
        [switch]$ShowSystemSpids,
        [ValidateRange(0, 255)]
        [int]$ShowSleepingSpids,
        [switch]$GetFullInnerText,
        [ValidateRange(0, 255)]
        [int]$GetPlans,
        [switch]$GetOuterCommand,
        [switch]$GetTransactionInfo,
        [ValidateRange(0, 2)]
        [int]$GetTaskInfo,
        [switch]$GetLocks,
        [switch]$GetAverageTime,
        [switch]$GetAdditonalInfo,
        [switch]$FindBlockLeaders,
        [ValidateRange(0, 255)]
        [int]$DeltaInterval,
        [ValidateLength(0, 8000)]
        [string]$OutputColumnList = '[dd%][session_id][sql_text][sql_command][login_name][wait_info][tasks][tran_log%][cpu%][temp%][block%][reads%][writes%][context%][physical%][query_plan][locks][%]',
        [ValidateLength(0, 500)]
        [string]$SortOrder = '[start_time] ASC',
        [ValidateRange(0, 255)]
        [int]$FormatOutput = 1,
        [ValidateLength(0, 4000)]
        [string]$DestinationTable = '',
        [switch]$ReturnSchema,
        [string]$Schema,
        [switch]$Help,
        [ValidateSet("DataSet", "DataTable", "DataRow", "PSObject")]
        [string]$As = "DataRow",
        [switch]$EnableException
    )
    begin {
        $passedParams = $psboundparameters.Keys | Where-Object { 'Silent', 'SqlServer', 'SqlCredential', 'OutputAs', 'ServerInstance', 'SqlInstance', 'Database' -notcontains $_ }
        $localParams = $psboundparameters

        # The procedure sp_WhoIsActive uses only lowercase values, so we convert the input in case we have a case sensitive database.
        if ($localParams.FilterType) { $localParams.FilterType = $localParams.FilterType.ToLower() }
        if ($localParams.NotFilterType) { $localParams.NotFilterType = $localParams.NotFilterType.ToLower() }
    }
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $paramDictionary = @{
                Filter             = '@filter'
                FilterType         = '@filter_type'
                NotFilter          = '@not_filter'
                NotFilterType      = '@not_filter_type'
                ShowOwnSpid        = '@show_own_spid'
                ShowSystemSpids    = '@show_system_spids'
                ShowSleepingSpids  = '@show_sleeping_spids'
                GetFullInnerText   = '@get_full_inner_text'
                GetPlans           = '@get_plans'
                GetOuterCommand    = '@get_outer_command'
                GetTransactionInfo = '@get_transaction_info'
                GetTaskInfo        = '@get_task_info'
                GetLocks           = '@get_locks '
                GetAverageTime     = '@get_avg_time'
                GetAdditonalInfo   = '@get_additional_info'
                FindBlockLeaders   = '@find_block_leaders'
                DeltaInterval      = '@delta_interval'
                OutputColumnList   = '@output_column_list'
                SortOrder          = '@sort_order'
                FormatOutput       = '@format_output '
                DestinationTable   = '@destination_table '
                ReturnSchema       = '@return_schema'
                Schema             = '@schema'
                Help               = '@help'
            }

            Write-Message -Level Verbose -Message "Collecting sp_whoisactive data from server: $instance"
            try {
                $sqlParameter = @{ }
                foreach ($param in $passedParams) {
                    Write-Message -Level Verbose -Message "Check parameter '$param'"
                    $sqlParam = $paramDictionary[$param]
                    if ($sqlParam) {
                        $value = $localParams[$param]
                        switch ($value) {
                            $true { $value = 1 }
                            $false { $value = 0 }
                        }
                        Write-Message -Level Verbose -Message "Adding parameter '$sqlParam' with value '$value'"
                        $sqlParameter[$sqlParam] = $value
                    }
                }
                Invoke-DbaQuery -SqlInstance $server -Query "dbo.sp_WhoIsActive" -CommandType "StoredProcedure" -SqlParameter $sqlParameter -As $As -EnableException
            } catch {
                if ($_.Exception.InnerException -Like "*Could not find*") {
                    Stop-Function -Message "sp_whoisactive not found, please install using Install-DbaWhoIsActive." -Continue
                } else {
                    Stop-Function -Message "Invalid query." -Continue
                }
            }
        }
    }
}