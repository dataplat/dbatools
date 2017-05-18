$null = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo")
$null = [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.SqlWmiManagement")

$instances = "sql2008r2sp2", "sql2016"

foreach ($instance in $instances) {
	
	$port = switch ($instance) {
		"sql2008r2sp2" { "1433" }
		"sql2016" { "14333" }
	}
	
	$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
	$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
	$Tcp = $wmi.GetSmoObject($uri)
	foreach ($ipAddress in $Tcp.IPAddresses) {
		$ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
		$ipAddress.IPAddressProperties["TcpPort"].Value = $port
	}
	$Tcp
	$Tcp.Alter()
	
	Stop-Service SQLBrowser
	Stop-Service "MSSQL`$$instance"
	Start-Service SQLBrowser
	Start-Service "MSSQL`$$instance"
}