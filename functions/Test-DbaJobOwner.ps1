function Test-DbaJobOwner {
    <#
		.SYNOPSIS
			Checks SQL Agent Job owners against a login to validate which jobs do not match that owner.

		.DESCRIPTION
			This function will check all SQL Agent Job on an instance against a SQL login to validate if that
			login owns those SQL Agent Jobs or not. By default, the function will check against 'sa' for 
			ownership, but the user can pass a specific login if they use something else. Only SQL Agent Jobs
			that do not match this ownership will be displayed, but if the -Detailed switch is set all
			SQL Agent Jobs will be shown.
				
			Best practice reference: http://sqlmag.com/blog/sql-server-tip-assign-ownership-jobs-sysadmin-account

		.PARAMETER SqlInstance
			SQLServer name or SMO object representing the SQL Server to connect to. This can be a
			collection and recieve pipeline input

		.PARAMETER SqlCredential
			PSCredential object to connect under. If not specified, currend Windows login will be used.

		.PARAMETER TargetLogin
			Specific login that you wish to check for ownership. This defaults to 'sa'.

		.PARAMETER Jobs
			Auto-populated list of Jobs to apply changes to. Will accept a comma separated list or a string array.

		.PARAMETER Exclude
			Jobs to exclude

		.PARAMETER Detailed
			Provides Detailed information

		.NOTES 
			Tags: Jobs, Owner
			Original Author: Michael Fal (@Mike_Fal), http://mikefal.net

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
			
		.LINK
			https://dbatools.io/Test-DbaJobOwner

		.EXAMPLE
			Test-DbaJobOwner -SqlInstance localhost

			Returns all databases where the owner does not match 'sa'.

		.EXAMPLE
			Test-DbaJobOwner -SqlInstance localhost -TargetLogin DOMAIN\account

			Returns all databases where the owner does not match DOMAIN\account. Note
			that TargetLogin must be a valid security principal that exists on the target server.
	#>
    [CmdletBinding()]
    [OutputType('System.Object[]')]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [string]$TargetLogin,
        [Switch]$Detailed
    )

    begin {
        #connect to the instance and set return array empty
        $return = @()
    }
    process {
        foreach ($servername in $SqlInstance) {
            #connect to the instance
            Write-Verbose "Connecting to $servername"
            $server = Connect-SqlInstance $servername -SqlCredential $SqlCredential
			
            # dynamic sa name for orgs who have changed their sa name
            if ($TargetLogin) {
                $TargetLogin = ($server.logins | Where-Object { $_.id -eq 1 }).Name
                
                #sql2000 id property is empty -force target login to 'sa' login
                if (($server.versionMajor -lt 9) -and ([string]::IsNullOrEmpty($TargetLogin))) {
                    $TargetLogin = "sa"
                }
            }
			
            #Validate login
            if (($server.Logins.Name) -notcontains $TargetLogin) {
                if ($SqlInstance.count -eq 1) {
                    throw "Invalid login: $TargetLogin"
                }
                else {
                    Write-Warning "$TargetLogin is not a valid login on $servername. Moving on."
                    Continue
                }
            }
			
            if ($server.logins[$TargetLogin].LoginType -eq 'WindowsGroup') {
                throw "$TargetLogin is a Windows Group and can not be a job owner."
            }
			
            #Get database list. If value for -Job is passed, massage to make it a string array.
            #Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
            Write-Verbose "Gathering jobs to Check"
			
            if ($Job.Length -gt 0) {
                $jobcollection = $server.JobServer.Jobs | Where-Object { $Job -contains $_.Name }
            }
            else {
                $jobcollection = $server.JobServer.Jobs
            }
			
            if ($Exclude.Length -gt 0) {
                $jobcollection = $jobcollection | Where-Object { $Exclude -notcontains $_.Name }
            }
			
            #for each database, create custom object for return set.
            foreach ($job in $jobcollection) {
                Write-Verbose "Checking $job"
                $row = [ordered]@{
                    Server       = $server.Name
                    Job          = $job.Name
                    CurrentOwner = $job.OwnerLoginName
                    TargetOwner  = $TargetLogin
                    OwnerMatch   = ($job.OwnerLoginName -eq $TargetLogin)
					
                }
                #add each custom object to the return array
                $return += New-Object PSObject -Property $row
            }
        }
    }
	
    END {
        #return results
        if ($Detailed) {
            Write-Verbose "Returning detailed results."
            return $return
        }
        else {
            Write-Verbose "Returning default results."
            return ($return | Where-Object { $_.OwnerMatch -eq $false })
        }
    }
	
}
