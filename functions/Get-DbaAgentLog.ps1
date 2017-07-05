function Get-DbaAgentLog {
<#
	.SYNOPSIS
		Gets the "SQL Agent Error Log" of an instance
	
	.DESCRIPTION
		Gets the "SQL Agent Error Log" of an instance. Returns all 10 error logs by default.

	.PARAMETER SqlInstance
		The SQL Server instance, or instances.
	
	.PARAMETER SqlCredential
		Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted.
	
	.PARAMETER LogNumber 
		An Int32 value that specifies the index number of the error log required. Error logs are listed 0 through 9 where 0 is the current error log and 9 is the oldest.
	
	.PARAMETER Silent 
		Use this switch to disable any kind of verbose messages
	
	.NOTES
		Tags: Logging
		Website: https://dbatools.io
		Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
		License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0	
	
	.LINK
		https://dbatools.io/Get-DbaAgentLog
	
	.EXAMPLE
		Get-DbaAgentLog -SqlInstance sql01\sharepoint 
		
		Returns the entire error log for the SQL Agent on sql01\sharepoint 

	.EXAMPLE
		Get-DbaAgentLog -SqlInstance sql01\sharepoint -LogNumber 3, 6
		
		Returns log numbers 3 and 6 for the SQL Agent on sql01\sharepoint 
	
	.EXAMPLE
		$servers = "sql2014","sql2016", "sqlcluster\sharepoint"
		$servers | Get-DbaAgentLog -LogNumber 0
		
		Returns the most recent error logs for "sql2014","sql2016" and "sqlcluster\sharepoint"

#>	
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[Alias("Credential")]
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[ValidateRange(0, 9)]
		[int[]]$LogNumber,
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
			
			if ($LogNumber) {
				foreach ($number in $lognumber) {
					foreach ($object in $server.JobServer.ReadErrorLog($number)) {
						Write-Message -Level Verbose -Message "Processing $object"
						Add-Member -InputObject $object -MemberType NoteProperty ComputerName -value $server.NetName
						Add-Member -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
						Add-Member -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName
						
						# Select all of the columns you'd like to show
						Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, ProcessInfo, Text
					}
				}
			}
			else {
				foreach ($object in $server.JobServer.ReadErrorLog()) {
					Write-Message -Level Verbose -Message "Processing $object"
					Add-Member -InputObject $object -MemberType NoteProperty ComputerName -value $server.NetName
					Add-Member -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
					Add-Member -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName
					
					# Select all of the columns you'd like to show
					Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, ProcessInfo, Text
				}
			}
		}
	}
}