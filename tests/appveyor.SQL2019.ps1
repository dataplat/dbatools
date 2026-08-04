$indent = '...'
Write-Host -Object "$indent Running $PSCommandPath" -ForegroundColor DarkGreen

# This script spins up the 2019 instance and the relative setup

$sqlinstance = "localhost\SQL2019"
$instance = "SQL2019"
$port = "14335"

Write-Host -Object "$indent Changing the port on $instance to $port" -ForegroundColor DarkGreen
$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -StaticPortForIPAll $port -EnableException -Confirm:$false -WarningAction SilentlyContinue

Write-Host -Object "$indent Starting $instance" -ForegroundColor DarkGreen
Start-Service -Name "MSSQL`$$instance" -WarningAction SilentlyContinue
Start-Service -Name "SQLAgent`$$instance" -WarningAction SilentlyContinue

Write-Host -Object "$indent Configuring $instance" -ForegroundColor DarkGreen
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name RemoteDacConnectionsEnabled -Value $true -EnableException
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name ExtensibleKeyManagementEnabled -Value $true -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = 'C:\github\appveyor-lab\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'" -EnableException
$null = Enable-DbaAgHadr -SqlInstance $sqlinstance -Force -EnableException -Confirm:$false
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongPassword>'" -EnableException
Invoke-DbaQuery -SqlInstance $sqlinstance -Query "CREATE CERTIFICATE dbatoolsci_AGCert WITH SUBJECT = 'AG Certificate'" -EnableException

# WindowsIdentity rather than $env:COMPUTERNAME\$env:USERNAME: for an interactive user
# both produce the same string, but for the LocalSystem service runner only the former
# yields the real principal (NT AUTHORITY\SYSTEM, already sysadmin from instance setup)
$loginName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$login = Get-AppveyorLoginWithRetry -SqlInstance $sqlinstance -Login $loginName
if (-not $login) {
    Write-Host -Object "$indent Creating login $loginName on $instance" -ForegroundColor DarkGreen
    $null = New-DbaLogin -SqlInstance $sqlinstance -Name $loginName -EnableException
}
