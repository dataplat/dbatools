#ValidationTags#Messaging#
function Get-DbaSsisExecutionHistory {
    <#
        .SYNOPSIS
           Get-DbaSsisHistory Retreives SSIS project and package execution History, and environments from one SQL Server to another.

        .DESCRIPTION
            This command gets execution history for SSIS executison given one or more instances and can be filtered by Project, Environment,Folder or Status.
        
        .PARAMETER SqlInstance
            SQL Server name or SMO object representing the SQL Server to connect to.
            This can be a collection and receive pipeline input to allow the function
            to be executed against multiple SQL Server instances.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER Project
            Specifies a filter by project

        .PARAMETER Folder
            Specifies a filter by folder
        
        .PARAMETER Environment
            Specifies a filter by environment

        .PARAMETER Status
            Specifies a filter by status (created,running,cancelled,failed,pending,halted,succeeded,stopping,completed)

        .PARAMETER Since
            Datetime object used to narrow the results to a date
        
            .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: Migration, SSIS
            Author: Chris Tucker (ChrisTucker, @ChrisTuc47368095)

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaSsisExecutionHistory

        .EXAMPLE
            Get-DbaSsisExecutionHistory -SqlInstance SMTQ01 -Folder SMTQ_PRC

            Get all history items for SMTQ01 in folder SMTQ_PRC.

        .EXAMPLE
            Get-DbaSsisExecutionHistory -SqlInstance SMTQ01 -Status Failed,Cancelled
            
            Gets all failed or canceled executions for SMTQ01.

        .EXAMPLE
            Get-DbaSsisExecutionHistory -SqlInstance SMTQ01,SMTQ02 -Status Failed,Cancelled -Whatif

            Shows what would happen if the command were executed and would return the SQL statement that would be executed per instance.
    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$SqlInstance,
        [PSCredential]$SqlCredential,
        [datetime]$Since,
        [ValidateSet("Created", "Running", "Cancelled", "Failed", "Pending", "Halted", "Succeeded", "Stopping", "Completed")]
        [String[]]$Status,
        [String[]]$Project,
        [String[]]$Folder,
        [String[]]$Environment,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        $params = @{}    

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
            $statusq = "AND e.[Status] in ($csv)"
        }
        else {
            $statusq = ''
        }
        
        if ($Project) {
            $csv = "`"" + ($Project -join '","') + "`""
            $projectq = "AND e.[ProjectName] in ($csv)"
        }
        else {
            $projectq = ''
        }
        
        if ($Folder) {
            $csv = "`'" + ($Folder -join "'", "'") + "`'"
            $folderq = "AND e.[FolderName] in ($csv)"
        }
        else {
            $folderq = ''
        }
        
        if ($Environment) {
            $csv = "`'" + ($Environment -join "'", "'") + "`'"
            $environmentq = "AND e.[Environment] in ($csv)"
        }
        else {
            $environmentq = ''
        }
        if($Since){
            $sinceq = 'AND e.[start_time] >= @since'
            $params.Add('since',$Since )
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
                    , ElapsedMinutes = DATEDIFF(ss, e.start_time, e.end_time)
                    , l.LoggingLevel
            FROM
                [catalog].executions e
                LEFT OUTER JOIN cteLoglevel l
                    ON e.execution_id = l.ExecutionID
                LEFT OUTER JOIN cteStatus s
                    ON s.[key] = e.status
            WHERE 1=1
                $statusq
                $projectq
                $folderq
                $environmentq
                $sinceq
                OPTION  ( RECOMPILE );"
    }


    process {
        foreach ($instance in $SqlInstance) {
            $results = Invoke-DbaSqlQuery -SqlInstance $instance -Database SSISDB -Query $sql -as PSObject -SqlParameters $params -SqlCredential $SqlCredential
            foreach ($row in $results) {
                $row.StartTime = [dbadatetime]$row.StartTime.DateTime
                $row.EndTime = [dbadatetime]$row.EndTime.DateTime
                $row
            }
        }
    }
}