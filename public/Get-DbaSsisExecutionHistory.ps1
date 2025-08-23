function Get-DbaSsisExecutionHistory {
    <#
    .SYNOPSIS
        Retrieves SSIS package execution history from the SSIS catalog database (SSISDB).

    .DESCRIPTION
        Retrieves detailed execution history for SSIS packages from the SSIS catalog database, including execution status, timing, and environment details. This function queries the catalog.executions view in SSISDB to provide comprehensive execution information for troubleshooting failed packages, monitoring performance, and analyzing SSIS workloads.

        Useful for identifying failed or long-running packages, tracking execution patterns over time, and investigating SSIS deployment issues. Results can be filtered by project, folder, environment, execution status, or date range to focus on specific troubleshooting scenarios.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.
        This can be a collection and receive pipeline input to allow the function
        to be executed against multiple SQL Server instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Project
        Filters results to specific SSIS projects deployed to the catalog. Accepts an array of project names for multiple projects.
        Use this when troubleshooting issues within particular projects or analyzing execution patterns for specific deployments.

    .PARAMETER Folder
        Filters results to specific SSIS catalog folders that contain projects and packages. Accepts an array of folder names.
        Useful for focusing on executions within specific organizational folders or when troubleshooting deployments in particular environments.

    .PARAMETER Environment
        Filters results to specific SSIS environments that were used during package execution. Accepts an array of environment names.
        Use this to analyze executions that used particular environment variables or to troubleshoot environment-specific configuration issues.

    .PARAMETER Status
        Filters results to specific execution statuses such as Failed, Succeeded, or Running. Accepts multiple status values.
        Commonly used to find failed executions for troubleshooting or to monitor currently running packages during peak processing times.

    .PARAMETER Since
        Limits results to executions that started on or after the specified date and time. Accepts datetime objects or strings.
        Use this to focus on recent executions when analyzing current issues or to exclude older historical data from large catalogs.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: General, SSIS
        Author: Chris Tucker (@ChrisTuc47368095)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSsisExecutionHistory

    .EXAMPLE
        PS C:\> Get-DbaSsisExecutionHistory -SqlInstance SMTQ01 -Folder SMTQ_PRC

        Get all history items for SMTQ01 in folder SMTQ_PRC.

    .EXAMPLE
        PS C:\> Get-DbaSsisExecutionHistory -SqlInstance SMTQ01 -Status Failed,Cancelled

        Gets all failed or canceled executions for SMTQ01.

    .EXAMPLE
        PS C:\> Get-DbaSsisExecutionHistory -SqlInstance SMTQ01,SMTQ02 -Status Failed,Cancelled

        Shows what would happen if the command were executed and would return the SQL statement that would be executed per instance.

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [datetime]$Since,
        [ValidateSet("Created", "Running", "Cancelled", "Failed", "Pending", "Halted", "Succeeded", "Stopping", "Completed")]
        [String[]]$Status,
        [String[]]$Project,
        [String[]]$Folder,
        [String[]]$Environment,
        [switch]$EnableException
    )
    begin {
        $params = @{ }

        #build status parameter
        $statuses = @{
            'Created'   = 1
            'Running'   = 2
            'Cancelled' = 3
            'Failed'    = 4
            'Pending'   = 5
            'Halted'    = 6
            'Succeeded' = 7
            'Stopping'  = 8
            'Completed' = 9
        }
        if ($Status) {
            $csv = ($statuses[$Status] -join ',')
            $statusq = "`n`t`tAND e.[Status] in ($csv)"
        } else {
            $statusq = ''
        }

        #construct parameterized collection predicate for project array
        if ($Project) {
            $projectq = "`n`t`tAND ( 1=0 "
            $i = 0
            foreach ($p in $Project) {
                $i ++
                $projectq += "`n`t`t`tOR e.[project_name] = @project$i"
                $params.Add("project$i", $p)
            }
            $projectq += "`n`t`t)"
        } else {
            $projectq = ''
        }

        #construct parameterized collection predicate for folder array
        if ($Folder) {
            $folderq = "`n`t`tAND ( 1=0 "
            $i = 0
            foreach ($f in $Folder) {
                $i ++
                $folderq += "`n`t`t`tOR e.[folder_name] = @folder$i"
                $params.Add("folder$i" , $f)
            }
            $folderq += "`n`t`t)"
        } else {
            $folderq = ''
        }

        #construct parameterized collection predicate for environment array
        if ($Environment) {
            $environmentq = "`n`t`tAND ( 1=0 "
            $i = 0
            foreach ($e in $Environment) {
                $i ++
                $environmentq += "`n`t`t`tOR e.[environment_name] = @environment$i"
                $params.Add("environment$i" , $e)
            }
            $environmentq += "`n`t`t)"
        } else {
            $environmentq = ''
        }

        #construct date filter for since
        if ($Since) {
            $sinceq = "`n`t`tAND e.[start_time] >= @since"
            $params.Add('since', $Since )
        }

        $sql = "
        WITH
            cteLoglevel as (
                SELECT
                    execution_id as ExecutionID,
                    cast(parameter_value AS INT) AS LoggingLevel
                FROM
                    [catalog].[execution_parameter_values]
                WHERE
                    parameter_name = 'LOGGING_LEVEL'
            )
            , cteStatus AS (
                SELECT
                     [key]
                    ,[code]
                FROM (
                    VALUES
                          ( 1,'Created'  )
                        , ( 2,'Running'  )
                        , ( 3,'Cancelled')
                        , ( 4,'Failed'   )
                        , ( 5,'Pending'  )
                        , ( 6,'Halted'   )
                        , ( 7,'Succeeded')
                        , ( 8,'Stopping' )
                        , ( 9,'Completed')
                ) codes([key],[code])
            )
            SELECT
                      e.execution_id as ExecutionID
                    , e.folder_name as FolderName
                    , e.project_name as ProjectName
                    , e.package_name as PackageName
                    , e.project_lsn as ProjectLsn
                    , Environment = isnull(e.environment_folder_name, '') + isnull('\' + e.environment_name,  '')
                    , s.code AS StatusCode
                    , start_time as StartTime
                    , end_time as EndTime
                    , ElapsedMinutes = DATEDIFF(mi, e.start_time, e.end_time)
                    , l.LoggingLevel
            FROM
                [catalog].executions e
                LEFT OUTER JOIN cteLoglevel l
                    ON e.execution_id = l.ExecutionID
                LEFT OUTER JOIN cteStatus s
                    ON s.[key] = e.status
            WHERE 1=1$statusq$projectq$folderq$environmentq$sinceq
            OPTION  ( RECOMPILE );
        "

        #debug verbose output
        Write-Message -Level Debug -Message "`nSQL statement: $sql"
        $paramout = ($params | Out-String)
        Write-Message -Level Debug -Message "`nParameters:$paramout"
    }


    process {
        foreach ($instance in $SqlInstance) {
            $results = Invoke-DbaQuery -SqlInstance $instance -Database SSISDB -Query $sql -as PSObject -SqlParameters $params -SqlCredential $SqlCredential
            foreach ($row in $results) {
                $row.StartTime = [dbadatetime]$row.StartTime.DateTime
                $row.EndTime = [dbadatetime]$row.EndTime.DateTime
                $row
            }
        }
    }
}