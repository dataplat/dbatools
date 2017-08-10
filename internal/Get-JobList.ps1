function Get-JobList {
	<#
	.SYNOPSIS
		Helper function to get SQL Agent jobs.
	.DESCRIPTION
		Helper function to get all SQL Agent jobs or provide filter
	.PARAMETER SqlInstance
		SQL Server instance
	.PARAMETER SqlCredential
		Credential to use if SqlInstance did not include it.
	.PARAMETER JobFilter
		Object of jobs to filter on, also supports wildcard patterns
	.PARAMETER StepFilter
		Object of job steps to filter on, also supports wildcard patterns
	.PARAMETER Not
		Reverse results where object returned excludes filtered content.
	.PARAMETER Silent
		Shhhhhhh
	.EXAMPLE
		Get-JobList -SqlInstance sql2016

		Returns the full JobServer.Jobs object found on sql2016
	.EXAMPLE
		Get-JobList -SqlInstance sql2016 -JobFilter '*job*'

		Returns the Job object for each job name found to have "job" in the name on sql2016
	.EXAMPLE
		Get-JobList -SqlInstance sql2016 -JobFilter '*job*' -Not

		Returns any Job object that does not have "job" in the name on sql2016
	.EXAMPLE
		Get-JobList -SqlInstance YourServer -JobFilter 'JobName'

		Returns the Job object where the job name is 'JobName' on sql2016
	.EXAMPLE
		Get-JobList -SqlInstance YourServer -JobFilter 'JobName' -Not

		Returns any Job object where the job name is not 'JobName' on sql2016
	.EXAMPLE
		Get-JobList -SqlInstance YourServer -JobFilter job_3_upload, job_3_download

		Returns the Job object for where job is job_3_upload or job_3_download on sql2016
	.EXAMPLE
		Get-JobList -SqlInstance YourServer -JobFilter job_3_upload, job_3_download -Not

		Returns any Job object where job is not job_3_upload or job_3_download on sql2016
	.NOTES
		Original Author: Shawn Melton (@wsmelton)

		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
	#>
	[cmdletbinding()]
	param(
		[Parameter(ValueFromPipeline = $true)]
		[DbaInstanceParameter]$SqlInstance,
		[PSCredential]$SqlCredential,
		[string[]]$JobFilter,
		[string[]]$StepFilter,
		[switch]$Not,
		[switch]$Silent
	)
	process {
		$server= Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential

		$jobs = $server.JobServer.Jobs
		if ( (Test-Bound 'JobFilter') -or (Test-Bound 'StepFilter') ) {
			if ($JobFilter.Count -gt 1) {
				if ($Not) {
					$jobs | Where-Object Name -NotIn $JobFilter
				}
				else {
					$jobs | Where-Object Name -In $JobFilter
				}
			}
			else {
				foreach ($job in $jobs) {
					if ($JobFilter -match '`*') {
						if ($Not) {
							$job | Where-Object Name -NotLike $JobFilter
						}
						else {
							$job | Where-Object Name -Like $JobFilter
						}
					}
					else {
						if ($Not) {
							$job | Where-Object Name -NE $JobFilter
						}
						else {
							$job | Where-Object Name -EQ $JobFilter
						}
					}
					if ($StepFilter -match '`*') {
						if ($Not) {
							$job.JobSteps | Where-Object Name -NotLike $StepFilter
						}
						else {
							$job.JobSteps | Where-Object Name -Like $StepFilter
						}
					}
					elseif ($StepName.Count -gt 1) {
						if ($Not) {
							$job.JobSteps | Where-Object Name -NotIn $StepName
						}
						else {
							$job.JobSteps | Where-Object Name -In $StepName
						}
					}
					else {
						if ($Not) {
							$job.JobSteps | Where-Object Name -NE $StepName
						}
						else {
							$job.JobSteps | Where-Object Name -EQ $StepName
						}
					}
				}
			}
		}
	}
}