function Get-DbaDefaultPath {
<#
	.SYNOPSIS
		Gets the default SQL Server paths for data, logs and backups
	
	.DESCRIPTION
		Gets the default SQL Server paths for data, logs and backups
	
	.PARAMETER SqlInstance
		The SQL Server instance, or instances.
	
	.PARAMETER SqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.
	
	.PARAMETER Silent 
		Use this switch to disable any kind of verbose messages
	
	.NOTES
		Tags: Config
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0	
	
	.LINK
		https://dbatools.io/Get-DbaDefaultPath
	
	.EXAMPLE
		Get-DbaDefaultPath -SqlInstance sql01\sharepoint 
		
		Returns the default file paths for sql01\sharepoint 
	
	.EXAMPLE
		$servers = "sql2014","sql2016", "sqlcluster\sharepoint"
		$servers | Get-DbaDefaultPath
		
		Returns the default file paths for "sql2014","sql2016" and "sqlcluster\sharepoint"

#>	
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[switch]$Silent
	)
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			
			$datapath = $server.DefaultFile
			
			if ($datapath.Length -eq 0) {
				$datapath = $server.Information.MasterDbPath
			}
			
			if ($datapath.Length -eq 0) {
				$datapath = $server.ConnectionContext.ExecuteScalar("select SERVERPROPERTY('InstanceDefaultDataPath') as physical_name")
			}
			
			$logpath = $server.DefaultLog
			
			if ($logpath.Length -eq 0) {
				$logpath = $server.Information.MasterDbLogPath
			}

			if ($logpath.Length -eq 0) {
				$logpath = $server.ConnectionContext.ExecuteScalar("select SERVERPROPERTY('InstanceDefaultLogPath') as physical_name")
			}
			
			$datapath = $datapath.Trim().TrimEnd("\")
			$logpath = $logpath.Trim().TrimEnd("\")
			
			[pscustomobject]@{
				ComputerName = $server.NetName
				InstanceName = $server.ServiceName
				SqlInstance = $server.DomainInstanceName
				Data = $datapath
				Log = $logpath
				Backup = $server.BackupDirectory
			}
		}
	}
}