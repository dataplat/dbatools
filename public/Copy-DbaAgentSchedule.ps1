function Copy-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Migrates SQL Agent shared job schedules between SQL Server instances for job schedule standardization.

    .DESCRIPTION
        Copies shared job schedules (not job-specific schedules) from the source SQL Server Agent to one or more destination instances using T-SQL scripting. This is essential when standardizing job schedules across multiple servers or migrating Agent configurations to new instances. Existing schedules are skipped by default unless -Force is specified, and schedules with associated jobs cannot be overwritten even with Force to prevent breaking existing job assignments. Use this instead of manually recreating complex recurring schedules with specific timing requirements across your SQL Server environment.

    .PARAMETER Source
        Specifies the source SQL Server instance containing the shared job schedules to copy. When specified, all shared schedules (or those filtered by Schedule/Id parameters) will be copied from this instance.
        Use this parameter when copying schedules from a specific server, or omit it when piping schedules from Get-DbaAgentSchedule.

    .PARAMETER SourceSqlCredential
        Specifies alternative credentials for connecting to the source SQL Server instance. Use this when the current Windows user lacks sufficient permissions or when connecting with SQL Server authentication.
        Accepts credentials created with Get-Credential or saved credential objects. Required when copying from instances that don't accept your current Windows authentication.

    .PARAMETER Destination
        Specifies one or more destination SQL Server instances where the shared job schedules will be copied. This parameter accepts multiple instances, allowing you to deploy schedules to several servers simultaneously.
        Use this when standardizing schedules across multiple instances or when migrating Agent configurations to new servers.

    .PARAMETER DestinationSqlCredential
        Specifies alternative credentials for connecting to the destination SQL Server instances. Use this when the current Windows user lacks sufficient permissions on the target servers or when connecting with SQL Server authentication.
        Accepts credentials created with Get-Credential or saved credential objects. Required when copying to instances that don't accept your current Windows authentication.

    .PARAMETER Schedule
        Filters the operation to copy only schedules with specific names. Accepts an array of schedule names using wildcard patterns for flexible matching.
        Use this when you need to copy only certain schedules instead of all shared schedules. Since SQL Server allows duplicate schedule names, combine with Id parameter for precise targeting.

    .PARAMETER Id
        Filters the operation to copy only schedules with specific numeric IDs. Accepts an array of schedule IDs for targeting multiple specific schedules.
        Use this instead of schedule names when you need precise identification, especially when duplicate schedule names exist on the source instance.

    .PARAMETER InputObject
        Accepts job schedule objects from the pipeline, typically from Get-DbaAgentSchedule. When provided, these specific schedule objects will be copied instead of querying the source instance.
        Use this for advanced scenarios like selective copying based on complex filtering or when working with schedules from multiple source instances.

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        Forces the overwrite of existing schedules on the destination instances by dropping and recreating them. Without this switch, existing schedules are skipped.
        Use this when you need to update existing schedules with new configurations. Note that schedules currently assigned to jobs cannot be overwritten, even with Force enabled.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Agent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaAgentSchedule

    .EXAMPLE
        PS C:\> Copy-DbaAgentSchedule -Source sqlserver2014a -Destination sqlcluster

        Copies all shared job schedules from sqlserver2014a to sqlcluster using Windows credentials. If shared job schedules with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentSchedule -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    .EXAMPLE
        PS C:\> Get-DbaAgentSchedule -SqlInstance sql2016 | Out-GridView -Passthru | Copy-DbaAgentSchedule -Destination sqlcluster

        Gets a list of schedule, outputs to a gridview which can be selected from, then copies to SqlInstance
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$Schedule,
        [int[]]$Id,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.JobSchedule[]]$InputObject,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        if ($Source) {
            try {
                $sourceServer = Connect-DbaInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $Source
                return
            }

            if (-not $InputObject) {
                $InputObject = Get-DbaAgentSchedule -SqlInstance $sourceServer -Schedule $Schedule -Id $Id
            }
        }
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if (-not $PSBoundParameters.Source -and -not $PSBoundParameters.InputObject) {
            Stop-Function -Message "You must specify either Source or pipe in results from Get-DbaAgentSchedule"
            return
        }

        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-DbaInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            # Refresh the cache before checking existing schedules
            $destServer.JobServer.SharedSchedules.Refresh()

            $destSchedules = Get-DbaAgentSchedule -SqlInstance $destServer -Schedule $Schedule

            foreach ($currentschedule in $InputObject) {
                $scheduleName = $currentschedule.Name
                $sourceServer = $currentschedule.Parent.Parent
                $copySharedScheduleStatus = [PSCustomObject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Type              = "Agent Schedule"
                    Name              = $scheduleName
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Dataplat.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                if ($destSchedules.Name -contains $scheduleName) {
                    if ($Force -ne $true) {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Shared job schedule $scheduleName exists at destination. Use -Force to drop and migrate.")) {
                            $copySharedScheduleStatus.Status = "Skipped"
                            $copySharedScheduleStatus.Notes = "Already exists on destination"
                            $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                            Write-Message -Level Verbose -Message "Shared job schedule $scheduleName exists at destination. Use -Force to drop and migrate."
                        }
                        continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Schedule [$scheduleName] has associated jobs. Skipping.")) {
                            if ($destServer.JobServer.Jobs.JobSchedules.Name -contains $scheduleName) {
                                $copySharedScheduleStatus.Status = "Skipped"
                                $copySharedScheduleStatus.Notes = "Schedule has associated jobs"
                                $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Write-Message -Level Verbose -Message "Schedule [$scheduleName] has associated jobs. Skipping."
                            }
                            continue
                        } else {
                            if ($Pscmdlet.ShouldProcess($destinstance, "Dropping schedule $scheduleName and recreating")) {
                                try {
                                    Write-Message -Level Verbose -Message "Dropping schedule $scheduleName"
                                    $destServer.JobServer.SharedSchedules[$scheduleName].Drop()
                                } catch {
                                    $copySharedScheduleStatus.Status = "Failed"
                                    $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                    Write-Message -Level Verbose -Message "Issue dropping schedule $scheduleName on $destinstance | $PSItem"
                                    continue
                                }
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating schedule $scheduleName")) {
                    try {
                        Write-Message -Level Verbose -Message "Copying schedule $scheduleName"
                        $sql = $currentschedule.Script() | Out-String

                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql)

                        $copySharedScheduleStatus.Status = "Successful"
                        $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $copySharedScheduleStatus.Status = "Failed"
                        $copySharedScheduleStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Issue creating schedule $scheduleName on $destinstance | $PSItem"
                        continue
                    }
                }
            }
        }
    }
}