Function Get-SaLoginName
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$saname = ($server.logins | Where-Object { $_.id -eq 1 }).Name
	
	return $saname
}
