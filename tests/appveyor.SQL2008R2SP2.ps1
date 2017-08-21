Write-Host -Object "Running $PSCommandpath" -ForegroundColor DarkGreen
# Imports some assemblies
Write-Output "Importing dbatools"
Import-Module C:\github\dbatools\dbatools.psd1

# This script spins up the 2008R2SP2 instance and the relative setup

Write-Host -Object "Setting up AppVeyor Services" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic -WarningAction SilentlyContinue
Start-Service SQLBrowser -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

$instance = "SQL2008R2SP2"
$port = "1433"
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
$server = Connect-DbaSqlServer -SqlInstance $env:MAIN_INSTANCE
$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
$server.Configuration.Alter()
$null = Set-DbaStartupParameter -SqlInstance $env:MAIN_INSTANCE -TraceFlagsOverride -TraceFlags 7806 -Confirm:$false -ErrorAction SilentlyContinue
Restart-Service "MSSQL`$SQL2008R2SP2" -WarningAction SilentlyContinue
$server = Connect-DbaSqlServer -SqlInstance $env:MAIN_INSTANCE
$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
$server.Configuration.Alter()

do {
	Start-Sleep 1
	$null = (& sqlcmd -S "$env:MAIN_INSTANCE" -b -Q "select 1" -d master)
}
while ($lastexitcode -ne 0 -and $t++ -lt 10)

Write-Host -Object "Executing startup scripts for SQL Server 2008" -ForegroundColor DarkGreen
# Add some jobs to the sql2008r2sp2 instance (1433 = default)
foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2008-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
	Invoke-Sqlcmd2 -ServerInstance $env:MAIN_INSTANCE -InputFile $file
}
