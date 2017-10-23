Function Test-HostOSLinux
{
	param (
		[object]$sqlserver,
		[object]$sqlcredential
	)
	
	$server = Connect-SqlServer -SqlServer $sqlserver -SqlCredential $sqlcredential
	$server.ConnectionContext.ExecuteScalar("SELECT @@VERSION") -match "Linux"
}
