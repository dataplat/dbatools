Function Test-SqlLoginAccess
{
<#
.SYNOPSIS
Internal function. Ensures login has access on SQL Server.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[string]$Login
		#[switch]$Detailed - can return if its a login or just has access
	)
	
	if ($SqlServer.GetType() -ne [Microsoft.SqlServer.Management.Smo.Server])
	{
		$SqlServer = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
	}
	
	if (($SqlServer.Logins.Name) -notcontains $Login)
	{
		try
		{
			$rows = $SqlServer.ConnectionContext.ExecuteScalar("EXEC xp_logininfo '$Login'")
			
			if (($rows | Measure-Object).Count -eq 0)
			{
				return $false
			}
		}
		catch
		{
			return $false
		}
	}
	
	return $true
}
