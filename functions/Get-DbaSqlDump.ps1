function Get-DbaSqlDump {
	<#
		.SYNOPSIS
			Locate a SQL Server that has generated any memory dump files.
  
		.DESCRIPTION
			The type of dump included in the search include minidump, all-thread dump, or a full dump.  The files have an extendion of .mdmp.
  
		.PARAMETER SqlInstance
			The SQL Server instance to connect to.
  
		.PARAMETER SqlCredential
			Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:
  
			$scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.
  
			Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.
  
			To connect as a different Windows user, run PowerShell as that user.
  
		.PARAMETER Detailed
			If parameter is used you will get detailed information for the memory dump for a SQL Instance.
  
		.NOTES
			Tags: Engine, Corruption, Failures
			Author: Garry Bargsley (@gbargsley), http://blog.garrybargsley.com
  
			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
  
		.LINK
			https://dbatools.io/Get-DbaSqlDump
  
		.EXAMPLE
			Get-DbaSqlDump -SqlInstance sql2016
  
			Shows a count of memory dump(s) for the sql2016 instance.
  
		.EXAMPLE
			Get-DbaSqlDump -SqlInstance sql2016 -Detailed
  
			Shows the detailed information for memory dump(s) located on sql2016 instance.
  
	#>
	  [CmdletBinding()]
	  Param (
		  [parameter(Mandatory = $true, ValueFromPipeline = $true)]
		  [Alias("ServerInstance", "SqlServer")]
		  [DbaInstanceParameter[]]$SqlInstance,
		  [PSCredential]$SqlCredential,
		  [switch]$Detailed
	  )
	  process {
		foreach ($servername in $SqlInstance) {
			$server = Connect-SqlInstance -SqlInstance $servername -SqlCredential $SqlCredential
  
			if ($server.versionMajor -lt 11 -and ( -not ($server.versionMajor -eq 10 -and $server.versionMinor -eq 50)) ) {
				Write-Warning "This function does not support versions lower than SQL Server 2008 R2 (v10.50). Skipping server '$servername'."
				continue
			}
  
			if ($Detailed) {
				$sql = "
				  SELECT
					  filename,
					  creation_time,
					  size_in_bytes
				  FROM sys.dm_server_memory_dumps;"
			}
			else {
				$sql = "
				  SELECT
					  COUNT(*) AS [MemoryDumpCount]
				  FROM sys.dm_server_memory_dumps;"
			}
			
			$results = $null
			try {
			  $results = $server.Query($sql)
			}
			catch {
			  Stop-Function -Message "Issue collecting data on $server" -Target $server -ErrorRecord $_ -Continue
			}
  
			if ((Measure-Object -InputObject $results) -eq 0 -or ($results.MemoryDumpCount -eq 0)) {
			  Write-Message -Level Warning -Message "Server '$servername' does not have any memory dumps." -EnableException $false
			}
			else {
			  foreach ($result in $results) {
				if ($Detailed) {
					[PSCustomObject]@{
						ComputerName    = $server.NetName
						InstanceName    = $server.ServiceName
						SqlInstance     = $server.DomainInstanceName
						FileName        = $result.filename
						CreationTime    = $result.creation_time
						size_in_bytes   = $result.size_in_bytes
					}
				}
				else {                  
				  [PSCustomObject]@{
					  ComputerName    = $server.NetName
					  InstanceName    = $server.ServiceName
					  SqlInstance     = $server.DomainInstanceName
					  MemoryDumpCount = $results.MemoryDumpCount
				  }
				}
			  }
			}
		  }
		}
	  }
	
  
  