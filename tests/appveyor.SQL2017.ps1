$indent = '...'
Write-Host -Object "Running $PSCommandpath" -ForegroundColor DarkGreen
$dbatools_serialimport = $true
Import-Module C:\github\dbatools\dbatools.psd1
Start-Sleep 5
# This script spins up the 2016 instance and the relative setup

$sqlinstance = "localhost\SQL2017"
$instance = "SQL2017"
$port = "14334"

Write-Host -Object "$indent Setting up AppVeyor Services" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic -WarningAction SilentlyContinue
Set-Service -Name "SQLAgent`$$instance" -StartupType Automatic -WarningAction SilentlyContinue
Start-Service SQLBrowser -ErrorAction SilentlyContinue -WarningAction SilentlyContinue

Write-Host -Object "$indent Changing the port on $instance to $port" -ForegroundColor DarkGreen
$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
$Tcp = $wmi.GetSmoObject($uri)
foreach ($ipAddress in $Tcp.IPAddresses) {
    $ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
    $ipAddress.IPAddressProperties["TcpPort"].Value = $port
}
$Tcp.Alter()
Write-Host -Object "$indent Starting $instance" -ForegroundColor DarkGreen
#Restart-Service "MSSQL`$$instance" -WarningAction SilentlyContinue -Force
#Restart-Service "SQLAgent`$$instance" -WarningAction SilentlyContinue -Force

$null = Enable-DbaAgHadr -SqlInstance $sqlinstance -Confirm:$false -Force

do {
    Start-Sleep 1
    $null = (& sqlcmd -S "$sqlinstance" -b -Q "select 1" -d master)
}
while ($lastexitcode -ne 0 -and $t++ -lt 10)

# Agent sometimes takes a moment to start
do {
    Write-Host -Object "$indent Waiting for SQL Agent to start" -ForegroundColor DarkGreen
    Start-Sleep 1
}
while ((Get-Service "SQLAgent`$$instance").Status -ne 'Running' -and $z++ -lt 10)


$server = Connect-DbaInstance -SqlInstance $sqlinstance
$computername = $server.NetName
$servicename = $server.ServiceName
if ($servicename -eq 'MSSQLSERVER') {
    $instancename = "$computername"
} else {
    $instancename = "$computername\$servicename"
}

$server = Connect-DbaInstance -SqlInstance $sqlinstance
$server.Query("IF NOT EXISTS (select * from sys.symmetric_keys where name like '%DatabaseMasterKey%') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongPassword>'")
$server.Query("IF EXISTS ( SELECT * FROM sys.tcp_endpoints WHERE name = 'End_Mirroring') DROP ENDPOINT endpoint_mirroring")
$server.Query("CREATE CERTIFICATE dbatoolsci_AGCert WITH SUBJECT = 'AG Certificate'")