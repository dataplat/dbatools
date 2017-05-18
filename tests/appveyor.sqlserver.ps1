# Imports some assemblies
Write-Output "Importing dbatools"
Import-Module C:\projects\dbatools\dbatools.psd1

# This script spins up two local instances
$sql2008 = "localhost\sql2008r2sp2"
$sql2016 = "localhost\sql2016"

Write-Output "Creating migration & backup directories"
New-Item -Path C:\projects\migration -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
New-Item -Path C:\projects\backups -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
New-Item -Path C:\github -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

Write-Output "Cloning lab materials"
git clone -q --branch=master https://github.com/sqlcollaborative/appveyor-lab.git C:\github\appveyor-lab

# Write-Output "Listing directory"
# Get-ChildItem C:\github\appveyor-lab\sql2008-backups

# Write-Output "Creating network share workaround"
# New-SmbShare -Name migration -path C:\projects\migration -FullAccess 'ANONYMOUS LOGON', 'Everyone' | Out-Null

$instances = "sql2016", "sql2008r2sp2"

foreach ($instance in $instances) {
	$port = switch ($instance) {
		"sql2008r2sp2" { "1433" }
		"sql2016" { "14333" }
	}
	
	Write-Output "Changing the port on $instance to $port"
	$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
	$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
	$Tcp = $wmi.GetSmoObject($uri)
	foreach ($ipAddress in $Tcp.IPAddresses) {
		$ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
		$ipAddress.IPAddressProperties["TcpPort"].Value = $port
	}
	$Tcp.Alter()
	
	Write-Output "Starting $instance"
	Start-Service "MSSQL`$$instance"
}

<#
Write-Output "Beginning restore"
Get-ChildItem C:\projects\appveyor-lab\sql2008-backups | Restore-DbaDatabase -SqlServer $sql2008

Write-Output "Attempting to perform migration - will bomb, need to submit a PR to not require network share"
Copy-DbaDatabase -Source $sql2008 -Destination $sql2016 -BackupRestore -NetworkShare "\\$env:computername\migration" -AllDatabases -Silent:$false

Write-Output "Trying some backups"
Backup-DbaDatabase -SqlInstance $sql2008 -BackupDirectory C:\projects\backups

Write-Output "Login import"
Invoke-DbaSqlCmd -ServerInstance $sql2016 -InputFile C:\projects\appveyor-lab\sql2008-logins.sql
#>