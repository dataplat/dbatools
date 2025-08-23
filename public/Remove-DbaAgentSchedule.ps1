function Remove-DbaAgentSchedule {
    <#
    .SYNOPSIS
        Removes SQL Server Agent schedules from one or more instances.

    .DESCRIPTION
        Removes SQL Server Agent schedules from the msdb database, handling both unused schedules and those currently assigned to jobs. The function first removes schedule associations from any jobs using the schedule, then drops the schedule itself to prevent orphaned references. Use this when cleaning up unused schedules during maintenance, consolidating multiple schedules, or removing schedules as part of job reorganization. By default, schedules in use by jobs are protected and require the -Force parameter to remove.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Schedule
        Specifies the name(s) of SQL Server Agent schedules to remove from the msdb database.
        Use this when you know the schedule name but need to be aware that multiple schedules can share the same name.
        When multiple schedules have identical names, you'll need to use -Id or -ScheduleUid to target a specific schedule.

    .PARAMETER ScheduleUid
        Specifies the unique GUID identifier of specific SQL Server Agent schedules to remove.
        Use this when you need to target an exact schedule, especially when multiple schedules share the same name.
        The ScheduleUid ensures you're removing the precise schedule without ambiguity.

    .PARAMETER Id
        Specifies the numeric schedule ID(s) to remove from SQL Server Agent.
        Use this when you have the specific schedule ID number, typically obtained from Get-DbaAgentSchedule output.
        The ID provides an alternative to name-based removal when dealing with duplicate schedule names.

    .PARAMETER InputObject
        Accepts schedule objects from the pipeline, typically from Get-DbaAgentSchedule output.
        Use this when you want to filter schedules first with Get-DbaAgentSchedule, then pipe the results for removal.
        This approach allows for complex filtering and review before deletion.

    .PARAMETER WhatIf
        Shows what would happen if the command were to run. No actions are actually performed.

    .PARAMETER Confirm
        Prompts you for confirmation before executing any changing operations within the command.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Force
        Bypasses the protection that prevents removal of schedules currently assigned to jobs.
        Without this parameter, schedules in use by jobs are protected and will not be removed.
        Use this when you need to clean up schedules and automatically remove their job associations first.

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
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateNotNullOrEmpty()]
        [Alias("Schedules", "Name")]
        [string[]]$Schedule,
        [Alias("Uid")]
        [string[]]$ScheduleUid,
        [int[]]$Id,
        [Parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.Agent.ScheduleBase[]]$InputObject,
        [switch]$EnableException,
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
        if ($InputObject -and ($Sqlinstance -or $Schedule -or $ScheduleUid -or $Id)) {
            Stop-Function -Message "You cannot use -InputObject with -SqlInstance, -Schedule, -ScheduleUid or -Id"
            return
        }
        # We have to delete in the end block to prevent "Collection was modified; enumeration operation may not execute." if directly piped from Get-DbaAgentSchedule.
        foreach ($sched in $schedules) {
            if ($sched.JobCount -ge 1 -and -not $Force) {
                Stop-Function -Message "The schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) is used in one or more jobs. If removal is neccesary use -Force." -Target $sched.Parent.Parent -Continue
            }
            if ($PSCmdlet.ShouldProcess($sched.Parent.Parent.Name, "Removing the schedule $($sched.Name) with id $($sched.Id) and uid $($sched.ScheduleUid) on $($sched.Parent.Parent.Name)")) {
                $output = [PSCustomObject]@{
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
                    Remove-TeppCacheItem -SqlInstance $sched.Parent.Parent -Type schedule -Name $sched.Name
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