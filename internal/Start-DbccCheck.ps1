Function Start-DbccCheck
{
	param (
		[object]$server,
		[string]$dbname
	)
	
	$servername = $server.name
	$db = $server.databases[$dbname]
	
	if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $servername"))
	{
		try
		{
			$null = $db.CheckTables('None')
			Write-Verbose "Dbcc CHECKDB finished successfully for $dbname on $servername"
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