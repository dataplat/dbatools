function Test-DbaJobOwner {
	<#
		.SYNOPSIS
			Checks SQL Agent Job owners against a login to validate which jobs do not match that owner.

		.DESCRIPTION
			This function will check all SQL Agent Job on an instance against a SQL login to validate if that
			login owns those SQL Agent Jobs or not. 
			
			By default, the function will check against 'sa' for ownership, but the user can pass a specific 
			login if they use something else. 
			
			Only SQL Agent Jobs that do not match this ownership will be displayed, but if the -Detailed 
			switch is set all SQL Agent Jobs will be shown.

			Best practice reference: http://sqlmag.com/blog/sql-server-tip-assign-ownership-jobs-sysadmin-account

		.PARAMETER SqlInstance
			SQLServer name or SMO object representing the SQL Server to connect to. This can be a
			collection and recieve pipeline input

		.PARAMETER SqlCredential
			PSCredential object to connect under. If not specified, currend Windows login will be used.

		.PARAMETER Job
			The job(s) to process - this list is auto populated from the server. If unspecified, all jobs will be processed.

		.PARAMETER ExcludeJob
			The job(s) to exclude - this list is auto populated from the server.

		.PARAMETER Login
			Specific login that you wish to check for ownership - this list is auto populated from the server. This defaults to 'sa' or the sysadmin name if sa was renamed.

		.PARAMETER Detailed
			Provides Detailed information

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages

		.NOTES
			Tags: Agent, Job, Owner
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
			Test-DbaJobOwner -SqlInstance localhost -Login DOMAIN\account

			Returns all databases where the owner does not match DOMAIN\account. Note
			that Login must be a valid security principal that exists on the target server.
	#>
	[CmdletBinding()]
	[OutputType('System.Object[]')]
	param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential = [System.Management.Automation.PSCredential]::Empty,
		[object[]]$Job,
		[object[]]$ExcludeJob,
		[object]$Login,
		[Switch]$Detailed,
		[switch]$Silent
	)

	begin {
		#connect to the instance and set return array empty
		$return = @()
	}
	process {
		foreach ($servername in $SqlInstance) {
			#connect to the instance
			Write-Message -Level Verbose -Message "Connecting to $servername"
			$server = Connect-SqlInstance $servername -SqlCredential $SqlCredential

			#Validate login
			if ($Login -and ($server.Logins.Name) -notcontains $Login) {
				if ($SqlInstance.count -eq 1) {
					Stop-Function -Message "Invalid login: $Login"
					return
				}
				else {
					Write-Message -Level Warning -Message "$Login is not a valid login on $servername. Moving on."
					continue
				}
			}
			if ($Login -and $server.Logins[$Login].LoginType -eq 'WindowsGroup') {
				Stop-Function -Message "$Login is a Windows Group and can not be a job owner."
				return
			}

			#sql2000 id property is empty -force target login to 'sa' login
			if ($Login -and ( ($server.VersionMajor -lt 9) -and ([string]::IsNullOrEmpty($Login)) )) {
				$Login = "sa"
			}
			# dynamic sa name for orgs who have changed their sa name
			if ($Login -eq "sa") {
				$Login = ($server.Logins | Where-Object { $_.id -eq 1 }).Name
			}

			#Get database list. If value for -Job is passed, massage to make it a string array.
			#Otherwise, use all jobs on the instance where owner not equal to -TargetLogin
			Write-Message -Level Verbose -Message "Gathering jobs to Check"
			if ($Job) {
				$jobCollection = $server.JobServer.Jobs | Where-Object { $Job -contains $_.Name }
			}
			elseif ($ExcludeJob) {
				$jobCollection = $jobCollection | Where-Object { $ExcludeJob -notcontains $_.Name }
			}
			else {
				$jobCollection = $server.JobServer.Jobs
			}

			#for each database, create custom object for return set.
			foreach ($j in $jobCollection) {
				Write-Message -Level Verbose -Message "Checking $j"
				$row = [ordered]@{
					Server       = $server.Name
					Job          = $j.Name
					CurrentOwner = $j.OwnerLoginName
					TargetOwner  = $Login
					OwnerMatch   = ($j.OwnerLoginName -eq $Login)

				}
				#add each custom object to the return array
				$return += New-Object PSObject -Property $row
			}
		}
	}
	end {
		#return results
		if ($Detailed) {
			Write-Message -Level Verbose -Message "Returning detailed results."
			return $return
		}
		else {
			Write-Message -Level Verbose -Message "Returning default results."
			return ($return | Where-Object { $_.OwnerMatch -eq $false })
		}
	}

}
