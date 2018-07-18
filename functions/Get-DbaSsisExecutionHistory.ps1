#ValidationTags#Messaging#
function Get-DbaSsisExecutionHistory {
    <#
        .SYNOPSIS
           Get-DbaSsisHistory Retreives SSIS project and package execution History, and environments from one SQL Server to another.

        .DESCRIPTION
            This command gets execution history for SSIS executison given one or more instances and can be filtered by Project, Environment,Folder or Status.
        .PARAMETER Project
            Specifies a filter by project

        .PARAMETER Folder
            Specifies a filter by folder
        
        .PARAMETER Environment
            Specifies a filter by environment

        .PARAMETER Status
            Specifies a filter by status (created,running,cancelled,failed,pending,halted,succeeded,stopping,completed)

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
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true)]
        [DbaInstanceParameter]$SQLInstance,
        [PSCredential]$SqlCredential,
        [ValidateSet("Created", "Running", "Cancelled", "Failed", "Pending", "Halted", "Succeeded", "Stopping","Completed")]
        [String[]]$Status,
        [String[]]$Project,
        [String[]]$Folder,
        [String[]]$Environment,
        [Switch]$Force,
        [Alias('Silent')]
        [switch]$EnableException
    )
    begin {
        $statuses = @{
            'created'= 1
            'running'= 2
            'cancelled'= 3
            'failed'= 4
            'pending'= 5
            'halted'= 6
            'succeeded'= 7
            'stopping'= 8
            'completed'= 9
          }
            if ($Status) {
                $csv = ($statuses[$Status] -join ',')
                $statusq = "AND e.[status] in ($csv)"
            } else {
                $statusq = ''
            }

            if ($Project) {
                $csv = "`"" + ($Project -join'","') + "`""
                $projectq = "AND e.[project_name] in ($csv)"
            } else {
                $projectq = ''
            }

            if ($Folder) {
                $csv = "`'" + ($Folder -join"'","'") + "`'"
                $folderq = "AND e.[folder_name] in ($csv)"
            } else {
                $folderq = ''
            }

            if ($Environment) {
                $csv = "`'" + ($Environment -join"'","'") + "`'"
                $environmentq = "AND e.[environment] in ($csv)"
            } else {
                $environmentq = ''
            }

            $q = @"
            WITH
            cteLoglevel as (
                SELECT
                    execution_id,
                    cast(parameter_value AS INT) AS logging_level
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
                          ( 1,'created'  )
                        , ( 2,'running'  )
                        , ( 3,'cancelled')
                        , ( 4,'failed'	  )
                        , ( 5,'pending'  )
                        , ( 6,'halted'	  )
                        , ( 7,'succeeded')
                        , ( 8,'stopping' )
                        , ( 9,'completed')
                ) codes([key],[code])
            )
            SELECT
                      e.execution_id
                    , e.folder_name
                    , e.project_name
                    , e.package_name
                    , e.project_lsn
                    , environment = isnull(e.environment_folder_name, '') + isnull('\' + e.environment_name,  '')
                    , s.code AS status_code
                    , start_time
                    , end_time
                    , elapsed_time_min = DATEDIFF(ss, e.start_time, e.end_time)
                    , l.logging_level
            FROM
                [catalog].executions e
                LEFT OUTER JOIN cteLoglevel l
                    ON e.execution_id = l.execution_id
                LEFT OUTER JOIN cteStatus s
                    ON s.[key] = e.status
            WHERE 1=1
                $statusq
                $projectq
                $folderq
                $environmentq
                OPTION  ( RECOMPILE );
"@
    }
    process {
        if ($pscmdlet.ShouldProcess("$SqlInstance", "Get History")){
            foreach ($instance in $SqlInstance) {
                $x = Invoke-DbaSqlQuery -SqlInstance $instance -Database SSISDB -Query $q -as PSObject -Verbose -SqlCredential $SqlCredential
                foreach($row in $x) {
                    $row.start_time = [dbadatetime]$row.start_time.DateTime
                    $row.end_time = [dbadatetime]$row.end_time.DateTime 
                    $row
                }
            }
        }
        else{
            $q
        }
    }
}