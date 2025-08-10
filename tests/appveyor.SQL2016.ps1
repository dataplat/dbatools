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

# Agent Service on SQL2016 is "Disabled", so we need to change the StartupType before starting.
Set-Service -Name "SQLAgent`$$instance" -StartupType Automatic

Start-DbaService -SqlInstance $sqlinstance -Type Browser, Engine, Agent -EnableException -Confirm:$false


Write-Host -Object "$indent Configuring $sqlinstance" -ForegroundColor DarkGreen

$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name RemoteDacConnectionsEnabled -Value $true -EnableException
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name ExtensibleKeyManagementEnabled -Value $true -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'" -EnableException

$null = Restart-DbaService -SqlInstance $sqlinstance -Type Engine -Force -EnableException -Confirm:$false
