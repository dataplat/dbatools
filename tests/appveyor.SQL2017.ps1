$indent = '...'
Write-Host -Object "$indent Running $PSCommandPath" -ForegroundColor DarkGreen

# This script spins up the 2016 instance and the relative setup

$sqlinstance = "localhost\SQL2017"
$instance = "SQL2017"
$port = "14334"

Write-Host -Object "$indent Setting up AppVeyor Services" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic
Set-Service -Name "SQLAgent`$$instance" -StartupType Automatic
Start-Service -Name SQLBrowser -ErrorAction SilentlyContinue

Write-Host -Object "$indent Changing the port on $instance to $port" -ForegroundColor DarkGreen
$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -StaticPortForIPAll $port -EnableException -Confirm:$false -WarningAction SilentlyContinue

Write-Host -Object "$indent Starting $instance" -ForegroundColor DarkGreen
Restart-Service "MSSQL`$$instance" -Force
Restart-Service "SQLAgent`$$instance" -Force

Write-Host -Object "$indent Configuring $instance" -ForegroundColor DarkGreen
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name ExtensibleKeyManagementEnabled -Value $true -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'" -EnableException
$null = Enable-DbaAgHadr -SqlInstance $sqlinstance -Force -EnableException -Confirm:$false
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongPassword>'" -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CERTIFICATE dbatoolsci_AGCert WITH SUBJECT = 'AG Certificate'" -EnableException