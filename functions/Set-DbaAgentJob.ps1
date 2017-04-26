function Set-DbaAgentJob {
    <#
.SYNOPSIS 
Set-DbaAgentJob updates a job.

.DESCRIPTION
Set-DbaAgentJob updates a job in the SQL Server Agent with parameters supplied.

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER JobName
The name of the job. Can be null if the the job id is being used.

.PARAMETER NewName
The new name for the job. 

.PARAMETER Enabled
Enabled the job.

.PARAMETER Disabled
Disabled the job

.PARAMETER Description
The description of the job.

.PARAMETER StartStepId
The identification number of the first step to execute for the job.

.PARAMETER CategoryName
The category of the job.

.PARAMETER OwnerLoginName
The name of the login that owns the job.

.PARAMETER EventlogLevel
Specifies when to place an entry in the Microsoft Windows application log for this job.
Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER EmailLevel
Specifies when to send an e-mail upon the completion of this job.
Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER NetsendLevel
Specifies when to send a network message upon the completion of this job.
Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER PageLevel
Specifies when to send a page upon the completion of this job.
Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER EmailOperatorName
The e-mail name of the operator to whom the e-mail is sent when EmailLevel is reached.

.PARAMETER NetsendOperator
The name of the operator to whom the network message is sent.

.PARAMETER PageOperator
The name of the operator to whom a page is sent.

.PARAMETER DeleteLevel
Specifies when to delete the job.
Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.NOTES 
Original Author: Sander Stad (@sqlstad, sqlstad.nl)
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Set-DbaAgentJob

.EXAMPLE   
Set-DbaAgentJob 'sql1' -JobName 'Job1' -Disabled
Changes the job to disabled

.EXAMPLE
Set-DbaAgentJob 'sql1' -JobName 'Job1' -OwnerLoginName 'user1'
Changes the owner of the job

.EXAMPLE
Set-DbaAgentJob -SqlInstance 'sql1' -JobName 'Job1' -EventLogLevel 'OnSuccess'
Changes the job and sets the notification to write to the Windows Application event log on success

.EXAMPLE
Set-DbaAgentJob -SqlInstance 'sql1' -JobName 'Job1' -EmailLevel 'OnFailure' -EmailOperatorName 'dba'
Changes the job and sets the notification to send an e-mail to the e-mail operator

.EXAMPLE   
Set-DbaAgentJob -SqlInstance 'sql1' -JobName 'Job1' -Description 'Just another job' -Whatif
Doesn't Change the job but shows what would happen.

.EXAMPLE   
Set-DbaAgentJob -SqlInstance "sql1", "sql2", "sql3" -JobName 'Job1' -Description 'Job1'
Changes a job with the name "Job1" on multiple servers to have another description

.EXAMPLE   
"sql1", "sql2", "sql3" | Set-DbaAgentJob -JobName 'Job1' -Description 'Job1'
Changes a job with the name "Job1" on multiple servers to have another description using pipe line

#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]

    param(
        [parameter(Mandatory = $true, ValueFromPipeline=$true)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$JobName,
        [Parameter(Mandatory = $false)]
        [string]$NewName,
        [Parameter(Mandatory = $false)]
        [switch]$Enabled,
        [Parameter(Mandatory = $false)]
        [switch]$Disabled,
        [Parameter(Mandatory = $false)]
        [string]$Description,
        [Parameter(Mandatory = $false)]
        [int]$StartStepId,
        [Parameter(Mandatory = $false)]
        [string]$CategoryName,
        [Parameter(Mandatory = $false)]
        [string]$OwnerLoginName,
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EventLogLevel = $null,
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EmailLevel,
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$NetsendLevel,
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$PageLevel,
        [Parameter(Mandatory = $false)]
        [string]$EmailOperatorName,
        [Parameter(Mandatory = $false)]
        [string]$NetsendOperatorName,
        [Parameter(Mandatory = $false)]
        [string]$PageOperatorName,
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$DeleteLevel,
        [bool]$Force,
        [switch]$Silent
    )

    begin {
        # Check of the event log level is of type string and set the integer value
        if (($EventLogLevel -notin 0, 1, 2, 3) -and ($EventLogLevel -ne $null)) {
            $EventLogLevel = switch ($EventLogLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }
		
        # Check of the email level is of type string and set the integer value
        if (($EmailLevel -notin 0, 1, 2, 3) -and ($EmailLevel -ne $null)) {
            $EmailLevel = switch ($EmailLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }
		
        # Check of the net send level is of type string and set the integer value
        if (($NetsendLevel -notin 0, 1, 2, 3) -and ($NetsendLevel -ne $null)) {
            $NetsendLevel = switch ($NetsendLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }
		
        # Check of the page level is of type string and set the integer value
        if (($PageLevel -notin 0, 1, 2, 3) -and ($PageLevel -ne $null)) {
            $PageLevel = switch ($PageLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }
		
        # Check of the delete level is of type string and set the integer value
        if (($DeleteLevel -notin 0, 1, 2, 3) -and ($DeleteLevel -ne $null)) {
            $DeleteLevel = switch ($DeleteLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } }
        }

        # Check the e-mail operator name
			Stop-Function -Message "Please set the e-mail operator when the e-mail level parameter is set." -Target $sqlinstance
            return
		}

		# Check the e-mail operator name
			Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $sqlinstance
            return
		}

		# Check the e-mail operator name
			Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $sqlinstance
            return
		}
    }

    process {

        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
			Write-Message -Message "Attempting to connect to $instance" -Level Verbose
			try {
				$server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Could not connect to Sql Server instance" -Target $instance -Continue
			}

            # Check if the job exists
            if (($Server.JobServer.Jobs).Name -notcontains $JobName) {
                Stop-Function -Message "Job $JobName doesn't exists on $instance"  -Target $instance 
                return
            }
            else {
                # Get the job
                try {
                    $Job = $server.JobServer.Jobs[$JobName] 
                }
                catch {
                    Stop-Function -Message ("Something went wrong retrieving the job. `n$($_.Exception.Message)")  -Target $JobName
                    return
                }

                #region job options
                # Settings the options for the job
                if ($NewName) {
                    Write-Message -Message "Setting job name to $NewName" -Level Verbose
                    $Job.Rename($NewName)
                }

                if ($Enabled) {
                    Write-Message -Message "Setting job to enabled" -Level Verbose
                    $Job.IsEnabled = $true
                }

                if ($Disabled) {
                    Write-Message -Message "Setting job to disabled" -Level Verbose
                    $Job.IsEnabled = $false
                }

                if ($Description) {
                    Write-Message -Message "Setting job description to $Description" -Level Verbose
                    $Job.Description = $Description
                }

                if ($StartStepId) {
                    # Get the job steps
                    $JobSteps = $Job.JobSteps

                    # Check if there are any job steps
                    if ($JobSteps.Count -ge 1) {
                        # Check if the start step id value is one of the job steps in the job
                        if ($JobSteps.ID -contains $StartStepId) {
                            Write-Message -Message "Setting job start step id to $($StartStepId)" -Level Verbose
                            $Job.StartStepID = $StartStepId
                        }
                        else {
                            Write-Message -Message "The step id is not present in job $JobName on instance $instance" -Warning 
                        }
                    
                    }
                    else {
                        Stop-Function -Message "There are no job steps present for job $JobName on instance $instance" -Target $instance
                        return
                    }

                }

                if ($CategoryName) {
                    Write-Message -Message "Setting job category to $($CategoryName)" -Level Verbose
                    $Job.Category = $CategoryName
                }

                if ($OwnerLoginName) {
                    # Check if the login name is present on the instance
                    if (($Server.Logins).Name -contains $OwnerLoginName) {
                        Write-Message -Message "Setting job owner login name to $($OwnerLoginName)" -Level Verbose
                        $Job.OwnerLoginName = $OwnerLoginName
                    }
                    else {
                        Stop-Function -Message "The given owner log in name $OwnerLoginName does not exist on instance $instance"  -Target $instance
                        return
                    }
                }

                if ($EventLogLevel) {
                    Write-Message -Message "Setting job event log level to $($EventlogLevel)" -Level Verbose
                    $Job.EventLogLevel = $EventLogLevel
                }

                if ($EmailLevel) {
                    # Check if the notifiction needs to be removed
                    if ($EmailLevel -eq 0) {
                        # Remove the operator
                        $Job.OperatorToEmail = $null

                        # Remove the notification
                        $Job.EmailLevel = $EmailLevel
                    }
                    else {
                        # Check if either the operator e-mail parameter is set or the operator is set in the job
                        if (($EmailOperatorName.Length -ge 1) -or ($Job.OperatorToEmail.Length -ge 1)) {
                            Write-Message -Message "Setting job e-mail level to $($EmailLevel)" -Level Verbose
                            $Job.EmailLevel = $EmailLevel
                        }
                        else {
                            Write-Message -Message "Cannot set e-mail level $EmailLevel without a valid e-mail operator name" -Warning 
                        }
                    }
                }

                if ($NetsendLevel) {
                    # Check if the notifiction needs to be removed
                    if ($NetsendLevel -eq 0) {
                        # Remove the operator
                        $Job.OperatorToNetSend = $null

                        # Remove the notification
                        $Job.NetSendLevel = $NetsendLevel
                    }
                    else {
                        # Check if either the operator netsend parameter is set or the operator is set in the job
                        if (($NetsendOperatorName.Length -ge 1) -or ($Job.OperatorToNetSend.Length -ge 1)) {
                            Write-Message -Message "Setting job netsend level to $NetsendLevel" -Level Verbose
                            $Job.NetSendLevel = $NetsendLevel
                        }
                        else {
                            Write-Message -Message "Cannot set netsend level $NetsendLevel without a valid netsend operator name" -Warning 
                        }
                    }
                }

                if ($PageLevel) {
                    # Check if the notifiction needs to be removed
                    if ($PageLevel -eq 0) {
                        # Remove the operator
                        $Job.OperatorToPage = $null

                        # Remove the notification
                        $Job.PageLevel = $PageLevel
                    }
                    else {
                        # Check if either the operator pager parameter is set or the operator is set in the job
                        if (($PageOperatorName.Length -ge 1) -or ($Job.OperatorToPage.Length -ge 1)) {
                            Write-Message -Message "Setting job pager level to $PageLevel" -Level Verbose
                            $Job.PageLevel = $PageLevel
                        }
                        else {
                            Write-Message -Message "Cannot set page level $PageLevel without a valid netsend operator name" -Warning 
                        }
                    }
                }

                # Check the current setting of the job's email level
                if ($EmailOperatorName) {
                    # Check if the operator name is present
                    if (($Server.JobServer.Operators).Name -contains $EmailOperatorName) {
                        Write-Message -Message "Setting job e-mail operator to $EmailOperatorName" -Level Verbose
                        $Job.OperatorToEmail = $EmailOperatorName
                    }
                    else {
                        Stop-Function -Message ("The e-mail operator name $EmailOperatorName does not exist on instance $instance. Exiting..")  -Target $JobName
                        return
                    }
                }

                if ($NetsendOperatorName) {
                    # Check if the operator name is present
                    if (($Server.JobServer.Operators).Name -contains $NetsendOperatorName) {
                        Write-Message -Message "Setting job netsend operator to $($NetsendOperatorName)" -Level Verbose
                        $Job.OperatorToNetSend = $NetsendOperatorName
                    }
                    else {
                        Stop-Function -Message ("The netsend operator name $NetsendOperatorName does not exist on instance $instance. Exiting..")  -Target $JobName
                        return
                    }
                }

                if ($PageOperatorName) {
                    # Check if the operator name is present
                    if (($Server.JobServer.Operators).Name -contains $PageOperatorName) {
                        Write-Message -Message "Setting job pager operator to $($PageOperatorName)" -Level Verbose
                        $Job.OperatorToPage = $PageOperatorName
                    }
                    else {
                        Stop-Function -Message ("The page operator name $PageOperatorName does not exist on instance $instance. Exiting..")  -Target $instance
                        return
                    }
                }

                if ($DeleteLevel) {
                    Write-Message -Message "Setting job delete level to $DeleteLevel" -Level Verbose
                    $Job.DeleteLevel = $DeleteLevel
                }
                #endregion job options

                # Execute 
                if ($PSCmdlet.ShouldProcess($SqlInstance, ("Changing the job $JobName"))) {
                    try {
                        Write-Message -Message ("Changing the job") -Level Output
                    
                        # Change the job
                        $Job.Alter()
                    }
                    catch {
                        Write-Message -Message ("Something went wrong changing the job. `n$($_.Exception.Message)") -Level Output 
                    }
                }
            }
        }

    }

    END {
        Write-Message -Message "Finished changing job(s)." -Level Output
    }
}