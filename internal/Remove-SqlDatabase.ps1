Function Remove-SqlDatabase
{
<#
.SYNOPSIS
Internal function. Uses SMO's KillDatabase to drop all user connections then drop a database. $server is
an SMO server object.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[Parameter(Mandatory = $true)]
		[string]$DBName,
		[System.Management.Automation.PSCredential]$SqlCredential
	)
	
	$escapedname = "[$dbname]"
	
	try
	{
		$server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
		$server.KillDatabase($dbname)
		$server.Refresh()
		return "Successfully dropped $dbname on $($server.name)"
	}
	catch
	{
		try
		{
			$null = $server.ConnectionContext.ExecuteNonQuery("DROP DATABASE $escapedname")
			return "Successfully dropped $dbname on $($server.name)"
		}
		catch
		{
			try
			{
				$server.databases[$dbname].Drop()
				$server.Refresh()
				return "Successfully dropped $dbname on $($server.name)"
			}
			catch
			{
				return $_
			}
		}
	}
}
