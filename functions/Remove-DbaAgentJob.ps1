function Remove-DbaAgentJob {
    <#
.SYNOPSIS 
Remove-DbaAgentJob removes a job.

.DESCRIPTION
Remove-DbaAgentJob removes a a job in the SQL Server Agent.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER JobID
The id of the job. Can be null if the the job name is being used.

.PARAMETER JobName
The name of the job. Can be null if the the job id is being used.

.PARAMETER KeepHistory
Specifies to keep the history for the job. By default is history is deleted.

.PARAMETER KeepUnusedSchedule
Specifies to keep the schedules attached to this job if they are not attached to any other job. 
By default the unused schedule is deleted.

.NOTES 
Original Author: Sander Stad (@sqlstad, sqlstad.nl)
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Remove-DbaAgentJob

.EXAMPLE   
Remove-DbaAgentJob -SqlInstance 'sql1' -JobName 'Job1'
Removes the job from the instance with the name 'Job1'

.EXAMPLE   
Remove-DbaAgentJob -SqlInstance 'sql1' -JobName 'Job1' -KeepHistory
Removes the job but keeps the history

.EXAMPLE   
Remove-DbaAgentJob -SqlInstance 'sql1' -JobName 'Job1' -KeepUnusedSchedule
Removes the job but keeps the unused schedules

.EXAMPLE   
Remove-DbaAgentJob -SqlInstance 'sql1', 'sql2', 'sql3' -JobName 'Job1' 
Removes the job from multiple servers

.EXAMPLE   
'sql1', 'sql2', 'sql3' | Remove-DbaAgentJob -JobName 'Job1' 
Removes the job from multiple servers using pipe line

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]

    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory = $false)]
        [int]$JobID,
        [Parameter(Mandatory = $false)]
        [ValidateScript( {
                if (-not($JobID) -and (-not($_))) {
                    Throw "Please enter a job id or job name."
                }
                else {
                    $true    
                }
            })]
        [string]$JobName,
        [switch]$KeepHistory,
        [switch]$KeepUnusedSchedule,
        [switch]$Silent
    )

    process {

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to Sql Server.." -Level Output -Silent $Silent
            try {
                $Server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Could not connect to Sql Server instance" -Silent $Silent -InnerErrorRecord $_ -Target $instance 
                return
            }
        
            # Check if the job exists
            if (($Server.JobServer.Jobs).Name -notcontains $JobName) {
                Write-Message -Message "Job $JobName doesn't exists on $instance" -Warning -Silent $Silent
            }
            else {   
                # Get the job
                try {
                    $Job = $Server.JobServer.Jobs[$JobName] 
                }
                catch {
                    Stop-Function -Message ("Something went wrong creating the job. `n$($_.Exception.Message)") -Silent $Silent -InnerErrorRecord $_ -Target $JobName
                    return
                }

                # Delete the history
                if (-not $KeepHistory) {
                    Write-Message -Message "Purging job history" -Level Verbose -Silent $Silent
                    $Job.PurgeHistory()
                }

                # Execute 
                if ($PSCmdlet.ShouldProcess($instance, ("Removing the job on $instance"))) {
                    try {
                        Write-Message -Message ("Removing the job") -Level Output -Silent $Silent

                        if ($KeepUnusedSchedule) {
                            # Drop the job keeping the unused schedules
                            Write-Message -Message "Removing job keeping unused schedules" -Level Verbose -Silent $Silent
                            $Job.Drop($true) 
                        }
                        else {
                            # Drop the job removing the unused schedules
                            Write-Message -Message "Removing job removing unused schedules" -Level Verbose -Silent $Silent
                            $Job.Drop($false) 
                        }
                    
                    }
                    catch {
                        Write-Message -Message ("Something went wrong removing the job. `n$($_.Exception.Message)") -Level Output -Silent $Silent 
                    }
                }
            }

        }
    }

    end {
        Write-Message -Message "Finished removing jobs(s)." -Level Output -Silent $Silent
    }
}