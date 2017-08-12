Function Get-SmoServerForDynamicParams
{
	if ($fakeBoundParameter.length -eq 0) { return }
	
	$SqlInstance = $fakeBoundParameter['SqlInstance']
	$sqlcredential = $fakeBoundParameter['SqlCredential']
	
	if ($SqlInstance -eq $null)
	{
		$SqlInstance = $fakeBoundParameter['sqlinstance']
	}
	if ($SqlInstance -eq $null)
	{
		$SqlInstance = $fakeBoundParameter['source']
	}
	if ($sqlcredential -eq $null)
	{
		$sqlcredential = $fakeBoundParameter['Credential']
	}
	
	if ($SqlInstance)
	{
		Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential -ParameterConnection
	}
}
