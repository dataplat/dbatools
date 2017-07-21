Function Update-SqlDbReadOnly
{
<#
.SYNOPSIS
Internal function. Updates specified database to read-only or read-write. Necessary because SMO doesn't appear to support NO_WAIT.
#>
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[Alias("ServerInstance", "SqlServer")]
		[object]$SqlInstance,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[string]$dbname,
		[Parameter(Mandatory = $true)]
		[ValidateNotNullOrEmpty()]
		[bool]$readonly
	)
	
	if ($readonly)
	{
		$sql = "ALTER DATABASE [$dbname] SET READ_ONLY WITH NO_WAIT"
	}
	else
	{
		$sql = "ALTER DATABASE [$dbname] SET READ_WRITE WITH NO_WAIT"
	}
	
	try
	{
		$server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
		$null = $server.Query($sql)
		Write-Output "Changed ReadOnly status to $readonly for $dbname on $($server.name)"
		return $true
	}
	catch
	{
		Write-Error "Could not change readonly status for $dbname on $($server.name)"
		return $false
	}
}
