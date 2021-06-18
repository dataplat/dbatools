function Remove-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Removes job schedules.

    .DESCRIPTION
        Removes the schedules that have passed through the pipeline.

        If not used with a pipeline, Get-DbaAgentSchedule will be executed with the parameters provided
        and the returned schedules will be removed.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Schedule
        The name of the job schedule.

        Please note that there can be several schedules with the same name. These differ then only in the Id or the ScheduleUid.

    .PARAMETER ScheduleUid
        The unique identifier of the schedule.

    .PARAMETER Id
        The Id of the schedule.

    .PARAMETER InputObject
        A collection of schedules (such as returned by Get-DbaAgentSchedule), to be removed.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Remove the schedules even if they where used in one or more jobs.

    .NOTES
        Tags: Agent, Job, Schedule
        Author: Sander Stad (@sqlstad), sqlstad.nl

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaAgentSchedule

    .EXAMPLE
        PS C:\> Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule weekly

        Remove the schedule weekly.

    .EXAMPLE
        PS C:\> Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule weekly -Force

        Remove the schedule weekly even if the schedule is being used by jobs.

    .EXAMPLE
        PS C:\> Remove-DbaAgentSchedule -SqlInstance sql1 -Schedule daily, weekly

        Remove multiple schedules.

    .EXAMPLE
        PS C:\> Remove-DbaAgentSchedule -SqlInstance sql1, sql2, sql3 -Schedule daily, weekly

        Remove the schedule on multiple servers for multiple schedules.

    .EXAMPLE
        Get-DbaAgentSchedule -SqlInstance sql1 -Schedule sched1, sched2, sched3 | Remove-DbaAgentSchedule

        Remove the schedules using a pipeline.

    .EXAMPLE
        Remove-DbaAgentSchedule -SqlInstance sql1, sql2, sql3 -ScheduleUid 'bf57fa7e-7720-4936-85a0-87d279db7eb7'

        Remove the schedules using the schedule uid.

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param (
        [Parameter(ParameterSetName = 'NonPipeline', Mandatory = $true, Position = 0)]
        [DbaInstanceParameter[]]$SqlInstance,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [PSCredential]$SqlCredential,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [ValidateNotNullOrEmpty()]
        [Alias("Schedules", "Name")]
        [string[]]$Schedule,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [Alias("Uid")]
        [string[]]$ScheduleUid,
        [Parameter(ParameterSetName = 'NonPipeline')]
        [int[]]$Id,
        [parameter(ValueFromPipeline, ParameterSetName = 'Pipeline', Mandatory = $true)]
        [Microsoft.SqlServer.Management.Smo.Agent.ScheduleBase[]]$InputObject,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$EnableException,
        [Parameter(ParameterSetName = 'NonPipeline')][Parameter(ParameterSetName = 'Pipeline')]
        [switch]$Force
    )

    begin {
        $schedules = @( )
    }

    process {

        if ($SqlInstance) {
            $params = $PSBoundParameters
            $null = $params.Remove('Force')
            $null = $params.Remove('WhatIf')
            $null = $params.Remove('Confirm')
            $schedules = Get-DbaAgentSchedule @params
        } else {
            $schedules += $InputObject
        }
    }
    end {
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentSchedule.
        foreach ($sched in $schedules) {
            if ($sched.JobCount -ge 1 -and -not $Force) {
                Stop-Function -Message "The schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) is used in one or more jobs. If removal is neccesary use -Force." -Target $sched.Parent.Parent -Continue
            }
            if ($PSCmdlet.ShouldProcess($sched.Parent.Parent.Name, "Removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) on $($sched.Parent.Parent.Name)")) {
                $output = [pscustomobject]@{
                    ComputerName = $sched.Parent.Parent.ComputerName
                    InstanceName = $sched.Parent.Parent.ServiceName
                    SqlInstance  = $sched.Parent.Parent.DomainInstanceName
                    Schedule     = $sched.Name
                    ScheduleId   = $sched.Id
                    ScheduleUid  = $sched.ScheduleUid
                    Status       = $null
                    IsRemoved    = $false
                }
                try {
                    if ($sched.JobCount -ge 1) {
                        foreach ($jobId in $sched.EnumJobReferences()) {
                            $jobSchedule = $sched.Parent.GetJobByID($jobId).JobSchedules | Where-Object { $_.ScheduleUid -eq $sched.ScheduleUid }
                            Write-Message -Level Verbose -Message "Removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) from job $($jobSchedule.Parent)"
                            $jobSchedule.Drop($true)   # $true = we keep the schedule and drop it later
                        }
                    }
                    Write-Message -Level Verbose -Message "Removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) on $($sched.Parent.Parent.Name)"
                    $sched.Drop()
                    $output.Status = "Dropped"
                    $output.IsRemoved = $true
                } catch {
                    Stop-Function -Message "Failed removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) on $($sched.Parent.Parent.Name)" -ErrorRecord $_
                    $output.Status = (Get-ErrorMessage -Record $_)
                    $output.IsRemoved = $false
                }
                $output
            }
        }
    }
}
