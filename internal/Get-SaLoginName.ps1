Function Get-SaLoginName
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	
	$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
	$saname = ($server.logins | Where-Object { $_.id -eq 1 }).Name
	
	return $saname
}
