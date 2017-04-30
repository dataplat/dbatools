function New-DbaAgentJob {
    <#
.SYNOPSIS 
New-DbaAgentJob creates a new job

.DESCRIPTION
New-DbaAgentJob makes is possible to create a job in the SQL Server Agent.
It returns an array of the job(s) created  

.PARAMETER SqlInstance
SQL Server instance. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:
$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter. 
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER JobName
The name of the job. The name must be unique and cannot contain the percent (%) character.

.PARAMETER Disabled
Sets the status of the job to disabled. By default a job is enabled.

.PARAMETER Description
The description of the job.

.PARAMETER StartStepId
The identification number of the first step to execute for the job.

.PARAMETER CategoryName
The category of the job.

.PARAMETER CategoryId
A language-independent mechanism for specifying a job category.

.PARAMETER OwnerLoginName
The name of the login that owns the job.

.PARAMETER EventLogLevel
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

.PARAMETER NetsendOperatorName
The name of the operator to whom the network message is sent.

.PARAMETER PageOperatorName
The name of the operator to whom a page is sent.

.PARAMETER DeleteLevel
Specifies when to delete the job.
Allowed values 0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always"
The text value van either be lowercase, uppercase or something in between as long as the text is correct.

.PARAMETER Force
The force parameter will ignore some errors in the parameters and assume defaults.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Silent 
Use this switch to disable any kind of verbose messages


.NOTES 
Original Author: Sander Stad (@sqlstad, sqlstad.nl)
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/New-DbaAgentJob

.EXAMPLE   
New-DbaAgentJob -SqlInstance sql1 -JobName 'Job One' -Description 'Just another job'
Creates a job with the name "Job1" and a small description

.EXAMPLE   
New-DbaAgentJob -SqlInstance sql1 -JobName 'Job One' -Disabled
Creates the job but sets it to disabled

.EXAMPLE
New-DbaAgentJob -SqlInstance sql1 -JobName 'Job One' -EventLogLevel OnSuccess
Creates the job and sets the notification to write to the Windows Application event log on success

.EXAMPLE
New-DbaAgentJob -SqlInstance SSTAD-PC -JobName 'Job One' -EmailLevel OnFailure -EmailOperatorName dba
Creates the job and sets the notification to send an e-mail to the e-mail operator

.EXAMPLE   
New-DbaAgentJob -SqlInstance sql1 -JobName 'Job One' -Description 'Just another job' -Whatif
Doesn't create the job but shows what would happen.

.EXAMPLE   
New-DbaAgentJob -SqlInstance sql1, sql2, sql3 -JobName 'Job One'
Creates a job with the name "Job One" on multiple servers

.EXAMPLE   
"sql1", "sql2", "sql3" | New-DbaAgentJob -JobName 'Job One'
Creates a job with the name "Job One" on multiple servers using the pipe line
#>
	
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
	
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]$SqlCredential,
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$JobName,
        [Parameter(Mandatory = $false)]
        [switch]$Disabled,
        [Parameter(Mandatory = $false)]
        [string]$Description,
        [Parameter(Mandatory = $false)]
        [int]$StartStepId,
        [Parameter(Mandatory = $false)]
        [string]$CategoryName,
        [Parameter(Mandatory = $false)]
        [int]$CategoryId,
        [Parameter(Mandatory = $false)]
        [string]$OwnerLoginName,
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EventLogLevel,
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
        if ($EventLogLevel -notin 1, 2, 3) {
            $EventLogLevel = switch ($EventLogLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } default {0} }
        }
		
        # Check of the email level is of type string and set the integer value
        if ($EmailLevel -notin 1, 2, 3) {
            $EmailLevel = switch ($EmailLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } default {0} }
        }
		
        # Check of the net send level is of type string and set the integer value
        if ($NetsendLevel -notin 1, 2, 3) {
            $NetsendLevel = switch ($NetsendLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } default {0} }
        }
		
        # Check of the page level is of type string and set the integer value
        if ($PageLevel -notin 1, 2, 3) {
            $PageLevel = switch ($PageLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } default {0} }
        }
		
        # Check of the delete level is of type string and set the integer value
        if ($DeleteLevel -notin 1, 2, 3) {
            $DeleteLevel = switch ($DeleteLevel) { "Never" { 0 } "OnSuccess" { 1 } "OnFailure" { 2 } "Always" { 3 } default {0} }
        }

        # Check the e-mail operator name
        if (($EmailLevel -ge 1) -and (-not $EmailOperatorName)) {
            Stop-Function -Message "Please set the e-mail operator when the e-mail level parameter is set." -Target $sqlinstance
            return
        }

        # Check the e-mail operator name
        if (($NetsendLevel -ge 1) -and (-not $NetsendOperatorName)) {
            Stop-Function -Message "Please set the netsend operator when the netsend level parameter is set." -Target $sqlinstance
            return
        }

        # Check the e-mail operator name
        if (($PageLevel -ge 1) -and (-not $PageOperatorName)) {
            Stop-Function -Message "Please set the page operator when the page level parameter is set." -Target $sqlinstance
            return
        }
    }
	
    process {
		
        if (Test-FunctionInterrupt) { return }
		
        foreach ($instance in $sqlinstance) {
            # Try connecting to the instance
            Write-Message -Message "Attempting to connect to $instance" -Level Verbose
            try {
                $server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
            }
            catch {
				Stop-Function -Message "Could not connect to $instance. Message: $($_.Exception.Message)" -Target $instance -Continue -InnerErrorRecord $_
            }
			
            # Check if the job already exists
            if (-not $Force -and ($server.JobServer.Jobs.Name -contains $JobName)) {
                Stop-Function -Message "Job $jobname already exists on $instance" -Target $instance -Continue
            }
            elseif ($Force -and ($server.JobServer.Jobs.Name -contains $JobName)) {
                Write-Message -Message "Job $jobname already exists on $instance. Removing.." -Level Output

                if ($PSCmdlet.ShouldProcess($instance, "Removing the job the job $instance")) {
                    try {
                        Remove-DbaAgentJob -SqlInstance $instance -JobName $JobName -Silent
                    }
                    catch {
                        Stop-Function -Message "Couldn't remove job $jobname from $instance" -Target $instance -Continue -InnerErrorRecord $_
                    }
                }
				
            }
			
            # Create the job object
            try {
                $Job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($server.JobServer, $JobName)
            }
            catch {
                Stop-Function -Message "Something went wrong creating the job. `n$($_.Exception.Message)" -Target $JobName -Continue -InnerErrorRecord $_
            }
			
            #region job options
            # Settings the options for the job
            if ($Disabled) {
                Write-Message -Message "Setting job to disabled" -Level Verbose
                $Job.IsEnabled = $false
            }
            else {
                Write-Message -Message "Setting job to enabled" -Level Verbose
                $Job.IsEnabled = $true
            }
			
            if ($Description.Length -ge 1) {
                Write-Message -Message "Setting job description" -Level Verbose
                $Job.Description = $Description
            }
			
            if ($StartStepId -ge 1) {
                Write-Message -Message "Setting job start step id" -Level Verbose
                $Job.StartStepID = $StartStepId
            }
			
            if ($CategoryName.Length -ge 1) {
                Write-Message -Message "Setting job category" -Level Verbose
                $Job.Category = $CategoryName
            }
			
            if ($CategoryId -ge 1) {
                Write-Message -Message "Setting job category id" -Level Verbose
                $Job.CategoryID = $CategoryId
            }
			
            if ($OwnerLoginName.Length -ge 1) {
                # Check if the login name is present on the instance
                if ($server.Logins.Name -contains $OwnerLoginName) {
                    Write-Message -Message "Setting job owner login name to $OwnerLoginName" -Level Verbose
                    $Job.OwnerLoginName = $OwnerLoginName
                }
                else {
                    Stop-Function -Message "The owner $OwnerLoginName does not exist on instance $instance" -Target $JobName -Continue
                }
            }
			
            if ($EventLogLevel -ge 0) {
                Write-Message -Message "Setting job event log level" -Level Verbose
                $Job.EventLogLevel = $EventLogLevel
            }
			
            if ($EmailOperatorName) {
                if ($EmailLevel -ge 1) {
                    # Check if the operator name is present
                    if ($server.JobServer.Operators.Name -contains $EmailOperatorName) {
                        Write-Message -Message "Setting job e-mail level" -Level Verbose
                        $Job.EmailLevel = $EmailLevel
						
                        Write-Message -Message "Setting job e-mail operator" -Level Verbose
                        $Job.OperatorToEmail = $EmailOperatorName
                    }
                    else {
                        Stop-Function -Message "The e-mail operator name $EmailOperatorName does not exist on instance $instance. Exiting.." -Target $JobName -Continue
                    }
                }
                else {
                    Stop-Function -Message "Invalid combination of e-mail operator name $EmailOperatorName and email level $EmailLevel. Not setting the notification." -Target $JobName  -Continue
                }
            }
			
            if ($NetsendOperatorName) {
                if ($NetsendLevel -ge 1) {
                    # Check if the operator name is present
                    if ($server.JobServer.Operators.Name -contains $NetsendOperatorName) {
                        Write-Message -Message "Setting job netsend level" -Level Verbose
                        $Job.NetSendLevel = $NetsendLevel
						
                        Write-Message -Message "Setting job netsend operator" -Level Verbose
                        $Job.OperatorToNetSend = $NetsendOperatorName
                    }
                    else {
                        Stop-Function -Message "The netsend operator name $NetsendOperatorName does not exist on instance $instance. Exiting.." -Target $JobName -Continue
                    }
                }
                else {
                    Write-Message -Message "Invalid combination of netsend operator name $NetsendOperatorName and netsend level $NetsendLevel. Not setting the notification." 
                }
            }
			
            if ($PageOperatorName) {
                if ($PageLevel -ge 1) {
                    # Check if the operator name is present
                    if ($server.JobServer.Operators.Name -contains $PageOperatorName) {
                        Write-Message -Message "Setting job pager level" -Level Verbose
                        $Job.PageLevel = $PageLevel
						
                        Write-Message -Message "Setting job pager operator" -Level Verbose
                        $Job.OperatorToPage = $PageOperatorName
                    }
                    else {
                        Stop-Function -Message "The page operator name $PageOperatorName does not exist on instance $instance. Exiting.." -Target $JobName -Continue
                    }
                }
                else {
                    Write-Message -Message "Invalid combination of page operator name $PageOperatorName and page level $PageLevel. Not setting the notification." -Level Warning
                }
            }
			
            if ($DeleteLevel -ge 0) {
                Write-Message -Message "Setting job delete level" -Level Verbose
                $Job.DeleteLevel = $DeleteLevel
            }
            #endregion job options
			
            # Execute 
            if ($PSCmdlet.ShouldProcess($instance, "Creating the job on $instance")) {
                try {
                    Write-Message -Message "Creating the job" -Level Output
					
                    # Create the job
                    $Job.Create()
					
                    Write-Message -Message "Job created with UID $($Job.JobID)" -Level Verbose
                }
                catch {
                    Stop-Function -Message "Something went wrong creating the job. `n$($_.Exception.Message)" -Continue -InnerErrorRecord $_
                }
            }

            # Return the job
            $Job
        }
    }
	
    end {
        Write-Message -Message "Finished creating job(s)." -Level Output
    }
	
}
