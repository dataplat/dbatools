Function Connect-AsServer
{
<# 
.SYNOPSIS 
Internal function that creates SMO server object. Input can be text or SMO.Server.
#>	
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$AsServer,
		[switch]$ParameterConnection
	)
	
	if ($AsServer.GetType() -eq [Microsoft.AnalysisServices.Server])
	{
		
		if ($ParameterConnection)
		{
			$paramserver = New-Object Microsoft.AnalysisServices.Server
			$paramserver.Connect("Data Source=$($AsServer.Name);Connect Timeout=2")
			return $paramserver
		}
		
		if ($AsServer.Connected -eq $false) { $AsServer.Connect("Data Source=$($AsServer.Name);Connect Timeout=3") }
		return $AsServer
	}
	
	$server = New-Object Microsoft.AnalysisServices.Server
	
	try
	{
		if ($ParameterConnection)
		{
			$server.Connect("Data Source=$AsServer;Connect Timeout=2")
		}
		else { $server.Connect("Data Source=$AsServer;Connect Timeout=3") }
	}
	catch
	{
		$message = $_.Exception.InnerException
		$message = $message.ToString()
		$message = ($message -Split '-->')[0]
		$message = ($message -Split 'at System.Data.SqlClient')[0]
		$message = ($message -Split 'at System.Data.ProviderBase')[0]
		throw "Can't connect to $asserver`: $message "
	}
	
	return $server
}
