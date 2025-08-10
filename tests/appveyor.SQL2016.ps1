<#
$indent = '...'
Write-Host -Object "$indent Running $PSCommandpath" -ForegroundColor DarkGreen

# This script spins up the 2016 instance and the relative setup

$sqlinstance = "localhost\SQL2016"
$instance = "SQL2016"
$port = "14333"

Write-Host -Object "$indent SQLBrowser StartType: $((Get-Service -Name SQLBrowser).StartType) / Status: $((Get-Service -Name SQLBrowser).Status)" -ForegroundColor DarkGreen
Write-Host -Object "$indent MSSQL`$$instance StartType: $((Get-Service -Name "MSSQL`$$instance").StartType) / Status: $((Get-Service -Name "MSSQL`$$instance").Status)" -ForegroundColor DarkGreen
Write-Host -Object "$indent SQLAgent`$$instance StartType: $((Get-Service -Name "SQLAgent`$$instance").StartType) / Status: $((Get-Service -Name "SQLAgent`$$instance").Status)" -ForegroundColor DarkGreen


Write-Host -Object "$indent Setting up and starting $sqlinstance" -ForegroundColor DarkGreen

# We need to configure the port first to be able to start the instances in any order.
$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -StaticPortForIPAll $port -EnableException -Confirm:$false -WarningAction SilentlyContinue

Set-Service -Name "SQLBrowser" -StartupType Automatic
Set-Service -Name "MSSQL`$$instance" -StartupType Automatic
Set-Service -Name "SQLAgent`$$instance" -StartupType Automatic
# Start-DbaService can not start service because Get-DbaService does not get the service - we have to fix this bug and then change this script
Start-Service -Name SQLBrowser
Start-DbaService -SqlInstance $sqlinstance -Type Engine, Agent -EnableException -Confirm:$false


Write-Host -Object "$indent Configuring $sqlinstance" -ForegroundColor DarkGreen

$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name RemoteDacConnectionsEnabled -Value $true -EnableException
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name ExtensibleKeyManagementEnabled -Value $true -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'" -EnableException

$null = Restart-DbaService -SqlInstance $sqlinstance -Type Engine -Force -EnableException -Confirm:$false
#>

$indent = '...'
Write-Host -Object "Running $PSCommandpath" -ForegroundColor DarkGreen
$dbatools_serialimport = $true
Import-Module C:\github\dbatools\dbatools.psd1
Start-Sleep 5
$null = Set-DbatoolsInsecureConnection
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
Restart-Service "MSSQL`$$instance" -WarningAction SilentlyContinue -Force
Restart-Service "SQLAgent`$$instance" -WarningAction SilentlyContinue -Force

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
<#

# this needs to be moved out. Tests that require these things need to run this in a BeforeAll stanza and remove the cruft in an AfterAll one
# so everybody can run tests without needing this too (which should be used strictly as appveyor-setup-related activities)
# when this fails for resource contention, the whole build stops for no reason. At most, it should fail only tests that are in the need of the reqs
Write-Host -Object "$indent Executing startup scripts for SQL Server 2016" -ForegroundColor DarkGreen
$sql2016Startup = 0
foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2016-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
    try {
        Invoke-DbaQuery -SqlInstance $sqlinstance -InputFile $file -ErrorAction Stop
    } catch {
        $sql2016Startup = 1
    }
}
try {

    $null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name ExtensibleKeyManagementEnabled -Value $true
    $sql = "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'"
    Invoke-DbaQuery -SqlInstance $sqlinstance -Query $sql
} catch {
    $sql2016Startup = 1
}
if ($sql2016Startup -eq 1) {
    Write-Host -Object "$indent something went wrong with startup scripts" -ForegroundColor DarkGreen
}
#>

$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name ExtensibleKeyManagementEnabled -Value $true -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'" -EnableException
