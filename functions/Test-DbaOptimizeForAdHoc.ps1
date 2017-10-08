Function Test-DbaOptimizeForAdHoc
{
<# 
	.SYNOPSIS 
		Displays information relating to SQL Server Optimize for AdHoc Workloads setting.  Works on SQL Server 2008-2016.

	.DESCRIPTION 
		When this option is set, plan cache size is further reduced for single-use ad hoc OLTP workload.

		More info: https://msdn.microsoft.com/en-us/library/cc645587.aspx
		http://www.sqlservercentral.com/blogs/glennberry/2011/02/25/some-suggested-sql-server-2008-r2-instance-configuration-settings/

		These are just general recommendations for SQL Server and are a good starting point for setting the "optimize for adhoc workloads" option.

	.PARAMETER SqlInstance
		A collection of one or more SQL Server instance names to query.

	.PARAMETER SqlCredential
		Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

		$cred = Get-Credential, this pass this $cred to the param. 

		Windows Authentication will be used if SqlCredential is not specified. To connect as a different Windows user, run PowerShell as that user.	

	.NOTES 
		Author: Brandon Abshire, netnerds.net
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK 
		https://dbatools.io/Test-DbaOptimizeForAdHoc

	.EXAMPLE   
		Test-DbaOptimizeForAdHoc -SqlInstance sql2008, sqlserver2012
		
		Get Optimize for AdHoc Workloads setting for servers sql2008 and sqlserver2012 and also the recommended one.

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer", "SqlServers")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]$SqlCredential
	)
	
	BEGIN
	{
        $notesAdHocZero = "Recommended configuration is 1 (enabled)."
		$notesAsRecommended = "Configuration is already set as recommended."
	}
	
	PROCESS
	{
		
		foreach ($servername in $SqlInstance)
		{
			Write-Verbose "Attempting to connect to $servername"
			try
			{
				$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
			}
			catch
			{
				Write-Warning "Can't connect to $servername or access denied. Skipping."
				continue
			}
			
			if ($server.versionMajor -lt 10)
			{
				Write-Warning "This function does not support versions lower than SQL Server 2008 (v10). Skipping server $servername."
				
				Continue
			}
			
			#Get current configured value
            $optimizeAdHoc = $server.Configuration.OptimizeAdhocWorkloads.ConfigValue
			
			
			#Setting notes for optimize adhoc value
			if ($optimizeAdHoc -eq 1)
			{
				$notes = $notesAsRecommended
			}
			else
			{
				$notes = $notesAdHocZero
			}
			
			[pscustomobject]@{
				Instance = $server.Name
				CurrentOptimizeAdHoc = $optimizeAdHoc
        		RecommendedOptimizeAdHoc = 1
				Notes = $notes
			}
		}
	}
}
