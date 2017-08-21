Write-Host -Object "Running $PSCommandpath" -ForegroundColor DarkGreen
# Imports some assemblies
Write-Output "Importing dbatools"
Import-Module C:\github\dbatools\dbatools.psd1

# This script spins up the 2008R2SP2 instance and the relative setup

Write-Host -Object "Setting up AppVeyor Services" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic -WarningAction SilentlyContinue
Start-Service SQLBrowser -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

$instance = "SQL2016"
$port = "14333"
Write-Host -Object "Changing the port on $instance to $port" -ForegroundColor DarkGreen
$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
$Tcp = $wmi.GetSmoObject($uri)
foreach ($ipAddress in $Tcp.IPAddresses) {
	$ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
	$ipAddress.IPAddressProperties["TcpPort"].Value = $port
}
$Tcp.Alter()
Write-Host -Object "Starting $instance" -ForegroundColor DarkGreen
Restart-Service "MSSQL`$$instance" -WarningAction SilentlyContinue
Restart-Service 'SQLAgent`$$instance' -WarningAction SilentlyContinue

do {
	Start-Sleep 1
	$null = (& sqlcmd -S "$env:MAIN_INSTANCE" -b -Q "select 1" -d master)
}
while ($lastexitcode -ne 0 -and $t++ -lt 10)

# Agent sometimes takes a moment to start 
do {
	Write-Host -Object "Waiting for SQL Agent to start" -ForegroundColor DarkGreen
	Start-Sleep 1
}
while ((Get-Service 'SQLAgent`$$instance').Status -ne 'Running' -and $z++ -lt 10)

Write-Host -Object "Executing startup scripts for SQL Server 2016" -ForegroundColor DarkGreen
foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2016-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
	Invoke-Sqlcmd2 -ServerInstance $env:MAIN_INSTANCE -InputFile $file
}