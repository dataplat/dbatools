$indent = '...'
Write-Host -Object "$indent Running $PSCommandpath" -ForegroundColor DarkGreen

# This script spins up the 2008R2SP2 instance and the relative setup

$sqlinstance = "localhost\SQL2008R2SP2"
$instance = "SQL2008R2SP2"
$port = "1433"

Write-Host -Object "$indent Setting up AppVeyor Services" -ForegroundColor DarkGreen

Write-Host -Object "$indent SQLBrowser StartType: $((Get-Service -Name SQLBrowser).StartType) / Status: $((Get-Service -Name SQLBrowser).Status)" -ForegroundColor DarkGreen
Write-Host -Object "$indent MSSQL`$$instance StartType: $((Get-Service -Name "MSSQL`$$instance").StartType) / Status: $((Get-Service -Name "MSSQL`$$instance").Status)" -ForegroundColor DarkGreen

Set-Service -Name SQLBrowser -StartupType Automatic -WarningAction SilentlyContinue
Start-Service SQLBrowser -ErrorAction SilentlyContinue -WarningAction SilentlyContinue


Write-Host -Object "$indent Configuring instance $sqlinstance" -ForegroundColor DarkGreen
Set-DbaNetworkConfiguration -SqlInstance $sqlinstance -StaticPortForIPAll $port -RestartService -Confirm:$false
Set-DbaNetworkConfiguration -SqlInstance client -EnableProtocol NamedPipes -RestartService -Confirm:$false


Write-Host -Object "$indent Starting $sqlinstance" -ForegroundColor DarkGreen
Restart-Service "MSSQL`$$instance" -WarningAction SilentlyContinue -Force

$null = Set-DbaSpConfigure -SqlInstance $sqlinstance -Name RemoteDacConnectionsEnabled -Value $true
$null = Set-DbaStartupParameter -SqlInstance $sqlinstance -TraceFlagOverride -TraceFlag 7806 -Confirm:$false -ErrorAction SilentlyContinue -EnableException
Restart-Service "MSSQL`$SQL2008R2SP2" -WarningAction SilentlyContinue -Force

do {
    Start-Sleep 1
    $null = (& sqlcmd -S "$sqlinstance" -b -Q "select 1" -d master)
}
while ($lastexitcode -ne 0 -and $t++ -lt 10)

#Write-Host -Object "$indent Executing startup scripts for SQL Server 2008" -ForegroundColor DarkGreen
# Add some jobs to the sql2008r2sp2 instance (1433 = default)
#foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2008-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
#    Invoke-DbaQuery -SqlInstance $sqlinstance -InputFile $file
#}

#Import-Module C:\github\dbatools\dbatools.psm1 -Force