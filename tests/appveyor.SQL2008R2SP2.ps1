$indent = '...'
Write-Host -Object "$indent Running $PSCommandpath" -ForegroundColor DarkGreen

# This script spins up the 2008R2SP2 instance and the relative setup

$sqlinstance = "localhost\SQL2008R2SP2"
$instance = "SQL2008R2SP2"
$port = "1433"

Write-Host -Object "$indent SQLBrowser StartType: $((Get-Service -Name SQLBrowser).StartType) / Status: $((Get-Service -Name SQLBrowser).Status)" -ForegroundColor DarkGreen
Write-Host -Object "$indent MSSQL`$$instance StartType: $((Get-Service -Name "MSSQL`$$instance").StartType) / Status: $((Get-Service -Name "MSSQL`$$instance").Status)" -ForegroundColor DarkGreen


Write-Host -Object "$indent Setting up and starting $sqlinstance" -ForegroundColor DarkGreen

# We need to configure the port first to be able to start the instances in any order.
$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -StaticPortForIPAll $port -EnableException -Confirm:$false -WarningAction SilentlyContinue

# SQL2008R2SP2 is an Express Edition and has no Agent to be started.
Set-Service -Name SQLBrowser -StartupType Automatic
Set-Service -Name "MSSQL`$$instance" -StartupType Automatic
# Start-DbaService can not start service because Get-DbaService does not get the service - we have to fix this bug and then change this script
Start-Service -Name SQLBrowser
Start-DbaService -SqlInstance $sqlinstance -Type Engine -EnableException -Confirm:$false


Write-Host -Object "$indent Configuring $sqlinstance" -ForegroundColor DarkGreen

$null = Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -EnableProtocol NamedPipes -RestartService -EnableException -Confirm:$false
$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name RemoteDacConnectionsEnabled -Value $true -EnableException
# To conserve resources, SQL Server Express doesn't listen on the DAC port unless started with a trace flag 7806.
$null = Set-DbaStartupParameter -SqlInstance $sqlinstance -TraceFlagOverride -TraceFlag 7806 -EnableException -Confirm:$false

$null = Restart-DbaService -SqlInstance $sqlinstance -Type Engine -Force -EnableException -Confirm:$false
