Function Start-DbccCheck
{
	param (
		[object]$server,
		[string]$dbname
	)
	
	$servername = $server.name
	
	if ($Pscmdlet.ShouldProcess($sourceserver, "Running dbcc check on $dbname on $servername"))
	{
		try
		{
			$null = $server.databases[$dbname].CheckTables('None')
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
	$error[0]
}