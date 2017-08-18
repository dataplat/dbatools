Function Get-SmoServerForDynamicParams
{
	if ($fakeBoundParameter.length -eq 0) { return }
	
	$sqlserver = $fakeBoundParameter['SqlServer']
	$sqlcredential = $fakeBoundParameter['SqlCredential']
	
	if ($sqlserver -eq $null)
	{
		$sqlserver = $fakeBoundParameter['sqlinstance']
	}
	if ($sqlserver -eq $null)
	{
		$sqlserver = $fakeBoundParameter['source']
	}
	if ($sqlcredential -eq $null)
	{
		$sqlcredential = $fakeBoundParameter['Credential']
	}
	
	if ($sqlserver)
	{
		Connect-SqlServer -SqlServer $sqlserver -SqlCredential $SqlCredential -ParameterConnection
	}
}
