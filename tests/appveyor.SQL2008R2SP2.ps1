$indent = '...'
Write-Host -Object "$indent Running $PSCommandpath" -ForegroundColor DarkGreen
$dbatools_serialimport = $true
Import-Module C:\github\dbatools\dbatools.psd1
Start-Sleep 5

# This script spins up the 2008R2SP2 instance and the relative setup

$sqlinstance = "localhost\SQL2008R2SP2"
$instance = "SQL2008R2SP2"
$port = "1433"

Write-Host -Object "$indent Setting up AppVeyor Services" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic -WarningAction SilentlyContinue
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
Restart-Service "MSSQL`$$instance" -WarningAction SilentlyContinue
$server = Connect-DbaInstance -SqlInstance $sqlinstance
$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
$server.Configuration.Alter()
$null = Set-DbaStartupParameter -SqlInstance $sqlinstance -TraceFlagsOverride -TraceFlags 7806 -Confirm:$false -ErrorAction SilentlyContinue -EnableException
Restart-Service "MSSQL`$SQL2008R2SP2" -WarningAction SilentlyContinue
$server = Connect-DbaInstance -SqlInstance $sqlinstance
$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
$server.Configuration.Alter()

do {
    Start-Sleep 1
    $null = (& sqlcmd -S "$sqlinstance" -b -Q "select 1" -d master)
}
while ($lastexitcode -ne 0 -and $t++ -lt 10)

Write-Host -Object "$indent Executing startup scripts for SQL Server 2008" -ForegroundColor DarkGreen
# Add some jobs to the sql2008r2sp2 instance (1433 = default)
foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2008-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
    Invoke-Sqlcmd2 -ServerInstance $sqlinstance -InputFile $file
}
