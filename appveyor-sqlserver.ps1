Import-Module C:\projects\dbatools\dbatools.psd1

git clone -q --branch=master https://github.com/sqlcollaborative/appveyor-lab.git C:\projects\appveyor-lab
mkdir C:\projects\migration

$instances = "sql2016", "sql2008r2sp2"

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
	$Tcp.Alter()
	
	Start-Service "MSSQL`$$instance"
}

$sql2008 = "localhost\sql2008r2sp2"
$sql2016 = "localhost\sql2016"

Get-ChildItem C:\projects\appveyor-lab\sql2008-backups | Restore-DbaDatabase -SqlServer $sql2008
Copy-DbaDatabase -Source $sql2008 -Destination $sql2016 -BackupRestore -NetworkShare C:\projects\migration
Invoke-DbaSqlCmd -ServerInstance $sql2016 -InputFile C:\projects\appveyor-lab\sql2008-logins.sql