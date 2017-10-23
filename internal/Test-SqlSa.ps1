Function Test-SqlSa
{
<#
.SYNOPSIS
Internal function. Ensures sysadmin account access on SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	try
	{
		
		if ($SqlServer.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
		{
			return ($SqlServer.ConnectionContext.FixedServerRoles -match "SysAdmin")
		}
		
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		return ($server.ConnectionContext.FixedServerRoles -match "SysAdmin")
	}
	catch { return $false }
}
