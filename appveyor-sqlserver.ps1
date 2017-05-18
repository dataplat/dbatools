$null = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
$null = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")

$instances = "SQL2008R2SP2", "SQL2016"

foreach ($instance in $instances) {
	
	$port = switch ($instance) {
		"SQL2008R2SP2" { "1433" }
		"SQL2016" { "14333" }
	}
	
	$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
	$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
	$Tcp = $wmi.GetSmoObject($uri)
	foreach ($ipAddress in $Tcp.IPAddresses) {
		$ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
		$ipAddress.IPAddressProperties["TcpPort"].Value = $port
	}
	$Tcp.Alter()
	
	Stop-Service SQLBrowser
	Stop-Service "MSSQL`$$instance"
	Start-Service SQLBrowser
	Start-Service "MSSQL`$$instance"
}