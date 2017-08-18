Function Get-SqlSaLogin
{
<#
.SYNOPSIS
Internal function. Gets the name of the sa login in case someone changed it.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	$sa = $server.Logins | Where-Object { $_.id -eq 1 }
	
	return $sa.name
	
}
