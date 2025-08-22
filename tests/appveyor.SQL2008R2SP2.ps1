$indent = '...'
Write-Host -Object "$indent Running $PSCommandPath" -ForegroundColor DarkGreen

# This script spins up the 2008R2SP2 instance and the relative setup

$sqlinstance = "localhost\SQL2008R2SP2"
$instance = "SQL2008R2SP2"
$port = "1433"

Write-Host -Object "$indent Setting up AppVeyor Services" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic
Start-Service -Name SQLBrowser


Write-Host -Object "$indent Changing the port on $instance to $port" -ForegroundColor DarkGreen
$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -StaticPortForIPAll $port -EnableException -Confirm:$false -WarningAction SilentlyContinue

Restart-Service -Name "MSSQL`$SQL2008R2SP2" -Force


Write-Host -Object "$indent Configuring $sqlinstance" -ForegroundColor DarkGreen

$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -EnableProtocol NamedPipes -RestartService -EnableException -Confirm:$false
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name RemoteDacConnectionsEnabled -Value $true -EnableException
# To conserve resources, SQL Server Express doesn't listen on the DAC port unless started with a trace flag 7806.
$null = Set-DbaStartupParameter -SqlInstance $sqlinstance -TraceFlagOverride -TraceFlag 7806 -EnableException -Confirm:$false
Restart-Service -Name "MSSQL`$SQL2008R2SP2" -Force