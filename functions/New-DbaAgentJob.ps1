function New-DbaAgentJob
{
<#
.SYNOPSIS 
New-DbaAgentJob creates a new job

.DESCRIPTION
New-DbaAgentJob makes is possible to create a job in the SQL Server Agent.
It returns an array of the job(s) created

.PARAMETER SqlServer
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
https://dbatools.io/New-DbaAgentJob

.EXAMPLE   
New-DbaAgentJob -SqlServer 'sql1' -JobName 'Job1' -Description 'Just another job'
Creates a job with the name "Job1" and a small description

.EXAMPLE   
New-DbaAgentJob -SqlServer 'sql1' -JobName 'Job1' -Disabled
Creates the job but sets it to disabled

.EXAMPLE
New-DbaAgentJob -SqlServer 'sql1' -JobName 'Job1' -EventLogLevel 'OnSuccess'
Creates the job and sets the notification to write to the Windows Application event log on success

.EXAMPLE
New-DbaAgentJob -SqlServer 'SSTAD-PC' -JobName 'Job1' -EmailLevel 'OnFailure' -EmailOperatorName 'dba'
Creates the job and sets the notification to send an e-mail to the e-mail operator

.EXAMPLE   
New-DbaAgentJob -SqlServer 'sql1' -JobName 'Job1' -Description 'Just another job' -Whatif
Doesn't create the job but shows what would happen.

.EXAMPLE   
"sql1", "sql2", "sql3" | New-DbaAgentJob -JobName 'Job1'
Creates a job with the name "Job1" on multiple servers

#>

    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]

    param(
        [parameter(Mandatory = $true, ValueFromPipeline=$true)]
		[object[]]$SqlServer,
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
        [object]$EventLogLevel = '',
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$EmailLevel = '',
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$NetsendLevel = '',
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$PageLevel = '',
        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if(($EmailLevel -in 1, "OnSuccess", 2, "OnFailure", 3, "Always") -and ($_.Length -ge 1))
            {
                $true
            }
            else
            {
                Throw "Please set the e-mail operator when the e-mail level parameter is set."
            }
        })]
        [string]$EmailOperatorName,
        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if(($NetsendLevel -in 1, "OnSuccess", 2, "OnFailure", 3, "Always") -and ($_.Length -ge 1))
            {
                $true
            }
            else
            {
                Throw "Please set the netsend operator when the netsend level parameter is set."
            }
        })]
        [string]$NetsendOperatorName,
        [Parameter(Mandatory = $false)]
        [ValidateScript({
            if(($PageLevel -in 1, "OnSuccess", 2, "OnFailure", 3, "Always") -and ($_.Length -ge 1))
            {
                $true
            }
            else
            {
                Throw "Please set the page operator when the page level parameter is set."
            }
        })]
        [string]$PageOperatorName,
        [Parameter(Mandatory = $false)]
        [ValidateSet(0, "Never", 1, "OnSuccess", 2, "OnFailure", 3, "Always")]
        [object]$DeleteLevel = '',
        [bool]$Force,
        [switch]$Silent
    )

    BEGIN
    {
        # Check the input for the job id or job name
        if($JobName.Length -lt 1)
        {
            Stop-Function -Message "Please enter a job name." -Silent $Silent -InnerErrorRecord $_ -Target $JobName
            return
        }

        # Check of the event log level is of type string and set the integer value
        if(($EmailLevel.GetType().Name -eq 'String') -and ($EventLogLevel.Length -ge 1))
        {
            switch ($EventLogLevel)
            {
                {($_ -eq "Never") -or ($_ -eq '')} { $EventLogLevel = 0 } 
                "OnSuccess" { $EventLogLevel = 1 } 
                "OnFailure" { $EventLogLevel = 2 }
                "Always" { $EventLogLevel = 3 } 
            }
        }

        # Check of the email level is of type string and set the integer value
        if(($EmailLevel.GetType().Name -eq 'String') -and ($EmailLevel.Length -ge 1))
        {
            switch ($EmailLevel)
            {
                {($_ -eq "Never") -or ($_ -eq '')} { $EmailLevel = 0 } 
                "OnSuccess" { $EmailLevel = 1 } 
                "OnFailure" { $EmailLevel = 2 }
                "Always" { $EmailLevel = 3 } 
            }
        }

        # Check of the net send level is of type string and set the integer value
        if(($NetsendLevel.GetType().Name -eq 'String') -and ($NetsendLevel.Length -ge 1))
        {
            switch ($NetsendLevel)
            {
                {($_ -eq "Never") -or ($_ -eq '')} { $NetsendLevel = 0 } 
                "OnSuccess" { $NetsendLevel = 1 } 
                "OnFailure" { $NetsendLevel = 2 }
                "Always" { $NetsendLevel = 3 } 
            }
        }

        # Check of the page level is of type string and set the integer value
        if(($PageLevel.GetType().Name -eq 'String') -and ($PageLevel.Length -ge 1))
        {
            switch ($PageLevel)
            {
                {($_ -eq "Never") -or ($_ -eq '')} { $PageLevel = 0 } 
                "OnSuccess" { $PageLevel = 1 } 
                "OnFailure" { $PageLevel = 2 }
                "Always" { $PageLevel = 3 } 
            }
        }

        # Check of the delete level is of type string and set the integer value
        if(($DeleteLevel.GetType().Name -eq 'String') -and ($DeleteLevel.Length -ge 1))
        {
            switch ($DeleteLevel)
            {
                "Never" { $DeleteLevel = 0 } 
                "OnSuccess" { $DeleteLevel = 1 } 
                "OnFailure" { $DeleteLevel = 2 }
                "Always" { $DeleteLevel = 3 } 
            }
        }

        [object[]]$JobsCreated = $null
    }

    PROCESS
    {
        # Try connecting to the instance
        Write-Message -Message "Attempting to connect to Sql Server.." -Level 2 -Silent $Silent
        try 
        {
            $Server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
        }
        catch 
        {
            Stop-Function -Message "Could not connect to Sql Server instance" -Silent $Silent -Target $SqlServer 
            return
        }

        # Check if the job already exists
        if(-not $Force -and (($Server.JobServer.Jobs).Name -contains $JobName))
        {
            Stop-Function -Message "Job '$($JobName)' already exists on '$($SqlServer)'" -Silent $Silent -Target $SqlServer 
            return
        }
        elseif($Force -and (($Server.JobServer.Jobs).Name -contains $JobName))
        {
            Write-Message -Message "Job '$($JobName)' already exists on '$($SqlServer)'. Removing.." -Level 2 -Silent $Silent
            try 
            {
                Remove-DbaAgentJob -SqlServer $SqlServer -JobName $JobName
            }
            catch 
            {
                Stop-Function -Message "Couldn't remove job '$($JobName)' from '$($SqlServer)'" -Silent $Silent -Target $SqlServer 
                return
            }
            
        }

        # Create the job object
        try 
        {
            $Job = New-Object Microsoft.SqlServer.Management.Smo.Agent.Job($Server.JobServer, $JobName)
        }
        catch 
        {
            Stop-Function -Message ("Something went wrong creating the job. `n$($_.Exception.Message)") -Silent $Silent -Target $JobName
            return
        }
        
        #region job options
        # Settings the options for the job
        if($Disabled)
        {
            Write-Message -Message "Setting job to disabled" -Level 5 -Silent $Silent
            $Job.IsEnabled = $false
        }
        else 
        {
            Write-Message -Message "Setting job to enabled" -Level 5 -Silent $Silent
            $Job.IsEnabled = $true 
        }

        if($Description.Length -ge 1)
        {
            Write-Message -Message "Setting job description" -Level 5 -Silent $Silent
            $Job.Description = $Description
        }

        if($StartStepId -ge 1)
        {
            Write-Message -Message "Setting job start step id" -Level 5 -Silent $Silent
            $Job.StartStepID = $StartStepId
        }

        if($CategoryName.Length -ge 1)
        {
            Write-Message -Message "Setting job category" -Level 5 -Silent $Silent
            $Job.Category = $CategoryName
        }

        if($CategoryId -ge 1)
        {
            Write-Message -Message "Setting job category id" -Level 5 -Silent $Silent
            $Job.CategoryID = $CategoryId
        }

        if($OwnerLoginName.Length -ge 1)
        {
            # Check if the login name is present on the instance
            if(($Server.Logins).Name -contains $OwnerLoginName)
            {
                Write-Message -Message "Setting job owner login name to $($OwnerLoginName)" -Level 5 -Silent $Silent
                $Job.OwnerLoginName = $OwnerLoginName
            }
            else 
            {
                Stop-Function -Message ("The owner '$($OwnerLoginName)' does not exist on instance '$($SqlServer)'") -Silent $Silent -Target $JobName
                return
            }
        }

        if($EventLogLevel -ge 0)
        {
            Write-Message -Message "Setting job event log level" -Level 5 -Silent $Silent
            $Job.EventLogLevel = $EventLogLevel
        }

        if($EmailOperatorName.Length -ge 1)
        {
            if($EmailLevel -ge 1)
            {
                # Check if the operator name is present
                if(($Server.JobServer.Operators).Name -contains $EmailOperatorName)
                {
                    Write-Message -Message "Setting job e-mail level" -Level 5 -Silent $Silent
                    $Job.EmailLevel = $EmailLevel

                    Write-Message -Message "Setting job e-mail operator" -Level 5 -Silent $Silent
                    $Job.OperatorToEmail = $EmailOperatorName
                }
                else 
                {
                    Stop-Function -Message ("The e-mail operator name '$($EmailOperatorName)' does not exist on instance '$($SqlServer)'. Exiting..") -Silent $Silent -Target $JobName
                    return
                }
            }
            else 
            {
                Write-Message -Message "Invalid combination of e-mail operator name '$($EmailOperatorName)' and email level $($EmailLevel). Not setting the notification." -Warning -Silent $Silent
            }
        }
        

        if($NetsendOperatorName.Length -ge 1)
        {
            if($NetsendLevel -ge 1)
            {
                # Check if the operator name is present
                if(($Server.JobServer.Operators).Name -contains $NetsendOperatorName)
                {
                    Write-Message -Message "Setting job netsend level" -Level 5 -Silent $Silent
                    $Job.NetSendLevel = $NetsendLevel

                    Write-Message -Message "Setting job netsend operator" -Level 5 -Silent $Silent
                    $Job.OperatorToNetSend = $NetsendOperatorName
                }
                else 
                {
                    Stop-Function -Message ("The netsend operator name '$($NetsendOperatorName)' does not exist on instance '$($SqlServer)'. Exiting..") -Silent $Silent -Target $JobName
                    return
                }   
            }  
            else 
            {
                Write-Message -Message "Invalid combination of netsend operator name '$($NetsendOperatorName)' and netsend level $($NetsendLevel). Not setting the notification." -Warning -Silent $Silent
            }        
        }

        if($PageOperatorName.Length -ge 1)
        {
            if($PageLevel -ge 1)
            {
                # Check if the operator name is present
                if(($Server.JobServer.Operators).Name -contains $PageOperatorName)
                {
                    Write-Message -Message "Setting job pager level" -Level 5 -Silent $Silent
                    $Job.PageLevel = $PageLevel

                    Write-Message -Message "Setting job pager operator" -Level 5 -Silent $Silent
                    $Job.OperatorToPage = $PageOperatorName
                }
                else 
                {
                    Stop-Function -Message ("The page operator name '$($PageOperatorName)' does not exist on instance '$($SqlServer)'. Exiting..") -Silent $Silent -Target $JobName
                    return
                }
            }
            else 
            {
                Write-Message -Message "Invalid combination of page operator name '$($PageOperatorName)' and page level $($PageLevel). Not setting the notification." -Warning -Silent $Silent
            }
        }

        if($DeleteLevel -ge 0)
        {
            Write-Message -Message "Setting job delete level" -Level 5 -Silent $Silent
            $Job.DeleteLevel = $DeleteLevel
        }
        #endregion job options

        # Execute 
        if($PSCmdlet.ShouldProcess($SqlServer, ("Creating the job $($SqlServer)"))) 
        {
            try
            {
                Write-Message -Message ("Creating the job") -Level 2 -Silent $Silent
                
                # Create the job
                $Job.Create()

                Write-Message -Message "Job created with UID '$($Job.JobID)'" -Level 5 -Silent $Silent
            }
            catch
            {
                Write-Message -Message ("Something went wrong creating the job. `n$($_.Exception.Message)") -Level 2 -Silent $Silent 
                
            }
        }
        
        # Add the job to the list
        $JobsCreated += $Job
    }

    END
    {
        Write-Message -Message "Finished creating job(s)." -Level 2 -Silent $Silent

        return $JobsCreated
    }
    
}