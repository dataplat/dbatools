Function Get-SqlSaLogin
{
<#
.SYNOPSIS
Internal function. Gets the name of the sa login in case someone changed it.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]$SqlCredential
	)
	$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
	$sa = $server.Logins | Where-Object { $_.id -eq 1 }
	
	return $sa.name
	
}
