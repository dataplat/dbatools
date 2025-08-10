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

Set-Service -Name SQLBrowser -StartupType Automatic
Start-Service -Name SQLBrowser

Set-Service -Name "SQLAgent`$$instance" -StartupType Automatic
Start-Service -Name "SQLAgent`$$instance"

Set-Service -Name "SQLAgent`$$instance" -StartupType Automatic
Start-Service -Name "SQLAgent`$$instance"


Write-Host -Object "$indent Configuring $sqlinstance" -ForegroundColor DarkGreen

$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -StaticPortForIPAll $port -RestartService -EnableException -Confirm:$false
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name RemoteDacConnectionsEnabled -Value $true -EnableException
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name ExtensibleKeyManagementEnabled -Value $true -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'" -EnableException

$null = Restart-DbaService -SqlInstance $sqlinstance -Type Engine -Force -EnableException -Confirm:$false
