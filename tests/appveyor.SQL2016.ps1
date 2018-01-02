$indent = '...'
Write-Host -Object "Running $PSCommandpath" -ForegroundColor DarkGreen
$dbatools_serialimport = $true
Import-Module C:\github\dbatools\dbatools.psd1
Start-Sleep 5
# This script spins up the 2016 instance and the relative setup

$sqlinstance = "localhost\SQL2016"
$instance = "SQL2016"
$port = "14333"

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
Restart-Service "MSSQL`$$instance" -WarningAction SilentlyContinue
Restart-Service "SQLAgent`$$instance" -WarningAction SilentlyContinue

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

# Whatever, just sleep an extra 5
Start-Sleep 5

# this needs to be moved out. Tests that require these things need to run this in a BeforeAll stanza and remove the cruft in an AfterAll one
# so everybody can run tests without needing this too (which should be used strictly as appveyor-setup-related activities)
# when this fails for resource contention, the whole build stops for no reason. At most, it should fail only tests that are in the need of the reqs
Write-Host -Object "$indent Executing startup scripts for SQL Server 2016" -ForegroundColor DarkGreen
$sql2016Startup = 0
foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2016-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
    try {
        Invoke-Sqlcmd2 -ServerInstance $sqlinstance -InputFile $file -ErrorAction Stop
    } catch {
        $sql2016Startup = 1
    }
}
if ($sql2016Startup -eq 1) {
    Write-Host -Object "$indent something went wrong with startup scripts" -ForegroundColor DarkGreen
}