Function Connect-DbaManagedComputer
{
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[object]$Server,
		[System.Management.Automation.PSCredential]$Credential
	)
	
	if ($server.GetType() -eq [Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer])
	{
		$server.Initialize()
		return $server
	}
	
	if ($Server.GetType() -eq [Microsoft.SqlServer.Management.Smo.Server])
	{
		$server = $server.ComputerNamePhysicalNetBIOS
	}
	
	# Remove instance name if it as passed
	$server = ($Server.Split("\"))[0]
	
	try
	{
		if ($credential.username -ne $null)
		{
			$ipaddr = (Test-Connection $server -count 1).Ipv4Address
			$username = ($Credential.username).TrimStart("\")
			$server = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $ipaddr, $username, ($Credential).GetNetworkCredential().Password
		}
		else
		{
			$server = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer $ipaddr
		}
		
		$server.Initialize()
		
	}
	catch
	{
		Write-Exception $_
		throw $_
	}
	return $server
}