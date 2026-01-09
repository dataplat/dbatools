$indent = '...'
Write-Host -Object "$indent Running $PSCommandPath" -ForegroundColor DarkGreen

# This script spins up the 2017 instance and the relative setup

$sqlinstance = "localhost\SQL2017"
$instance = "SQL2017"
$port = "14334"

Write-Host -Object "$indent Changing the port on $instance to $port" -ForegroundColor DarkGreen
$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -StaticPortForIPAll $port -EnableException -Confirm:$false -WarningAction SilentlyContinue

Write-Host -Object "$indent Starting $instance" -ForegroundColor DarkGreen
Start-Service -Name "MSSQL`$$instance" -Force -WarningAction SilentlyContinue
Start-Service -Name "SQLAgent`$$instance" -Force -WarningAction SilentlyContinue

Write-Host -Object "$indent Configuring $instance" -ForegroundColor DarkGreen
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name ExtensibleKeyManagementEnabled -Value $true -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'" -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongPassword>'" -EnableException

$loginName = "$env:COMPUTERNAME\$env:USERNAME"
$login = Get-DbaLogin -SqlInstance $sqlinstance -Login $loginName
if (-not $login) {
    Write-Host -Object "$indent Creating login $env:COMPUTERNAME\$env:USERNAME on $instance" -ForegroundColor DarkGreen
    $null = New-DbaLogin -SqlInstance $sqlinstance -Name $loginName -EnableException
}