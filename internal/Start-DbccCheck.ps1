Function Start-DbccCheck
{
	[CmdletBinding(SupportsShouldProcess = $true)]
	param (
		[object]$server,
		[string]$dbname,
		[switch]$table
	)
	
	$servername = $server.name
	
	if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $servername"))
	{
		try
		{
			if ($table)
			{
				$null = $server.databases[$dbname].CheckTables('None')
				Write-Verbose "Dbcc CheckTables finished successfully for $dbname on $servername"
			}
			else
			{
				$null = $server.Query("dbcc checkdb ([$dbname])")
				Write-Verbose "Dbcc CHECKDB finished successfully for $dbname on $servername"
			}
			return "Success"
		}
		catch
		{
			Write-Exception $_
			$inner = $_.Exception.Message
			return "Failure: $inner"
		}
	}
}
