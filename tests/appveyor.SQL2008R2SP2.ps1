


Function Install-ADAuthenticationLibraryforSQLServer {
    # from https://bzzzt.io/post/2018-05-25-horrible-adalsql-issue/
    $workingFolder = Join-Path $Env:TEMP ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force -Path $workingFolder

    $Installer = 'C:\github\appveyor-lab\azure\adalsql.msi'

    If (!(Test-Path $Installer)) {
        Throw "$Installer does not exist"
    }
    try {
        #Write-Host "attempting to uninstall..."
        #Write-Host "Running MsiExec.exe /uninstall {4EE99065-01C6-49DD-9EC6-E08AA5B13491} /quiet"
        Start-Process -FilePath "MsiExec.exe" -ArgumentList  "/uninstall {4EE99065-01C6-49DD-9EC6-E08AA5B13491} /quiet" -Wait -NoNewWindow
    } catch {
        #Write-Host "oh dear install did not work"
        $fail = $_.Exception
        Write-Error $fail
        Throw
    }
    try {
        $DataStamp = get-date -Format yyyyMMddTHHmmss
        $logFile = '{0}-{1}.log' -f $Installer, $DataStamp
        $MSIArguments = @(
            "/i"
            ('"{0}"' -f $Installer)
            "/qn"
            "/norestart"
            "/L*v"
            $logFile
        )
        #Write-Host "Attempting to install.."
        #Write-Host " Running msiexec.exe $($MSIArguments)"
        Start-Process "msiexec.exe" -ArgumentList $MSIArguments -Wait -NoNewWindow
    } catch {
        $fail = $_.Exception
        Write-Error $fail
        Throw
    }
}

$null = Install-ADAuthenticationLibraryforSQLServer

$indent = '...'
Write-Host -Object "$indent Running $PSCommandpath" -ForegroundColor DarkGreen
Import-Module C:\github\dbatools\dbatools.psm1 -Force
Set-DbatoolsInsecureConnection

# This script spins up the 2008R2SP2 instance and the relative setup

$sqlinstance = "localhost\SQL2008R2SP2"
$instance = "SQL2008R2SP2"
$port = "1433"

Write-Host -Object "$indent Setting up AppVeyor Services" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic -WarningAction SilentlyContinue
Start-Service SQLBrowser -ErrorAction SilentlyContinue -WarningAction SilentlyContinue


Write-Host -Object "$indent Changing the port on $instance to $port" -ForegroundColor DarkGreen
$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
$Tcp = $wmi.GetSmoObject($uri)
foreach ($ipAddress in $Tcp.IPAddresses) {
    $ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
    $ipAddress.IPAddressProperties["TcpPort"].Value = $port
}
$Tcp.Alter()

$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ServerInstance[@Name='$instance']/ServerProtocol[@Name='Np']"
$Np = $wmi.GetSmoObject($uri)
$Np.IsEnabled = $true
$Np.Alter()

Write-Host -Object "$indent Starting $instance" -ForegroundColor DarkGreen
Restart-Service "MSSQL`$$instance" -WarningAction SilentlyContinue -Force
$server = Connect-DbaInstance -SqlInstance $sqlinstance
$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
$server.Configuration.Alter()
$null = Set-DbaStartupParameter -SqlInstance $sqlinstance -TraceFlagOverride -TraceFlag 7806 -Confirm:$false -ErrorAction SilentlyContinue -EnableException
Restart-Service "MSSQL`$SQL2008R2SP2" -WarningAction SilentlyContinue -Force
$server = Connect-DbaInstance -SqlInstance $sqlinstance
$server.Configuration.RemoteDacConnectionsEnabled.ConfigValue = $true
$server.Configuration.Alter()

do {
    Start-Sleep 1
    $null = (& sqlcmd -S "$sqlinstance" -b -Q "select 1" -d master)
}
while ($lastexitcode -ne 0 -and $t++ -lt 10)

Write-Host -Object "$indent Executing startup scripts for SQL Server 2008" -ForegroundColor DarkGreen
# Add some jobs to the sql2008r2sp2 instance (1433 = default)
foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2008-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
    Invoke-DbaQuery -SqlInstance $sqlinstance -InputFile $file
}

Import-Module C:\github\dbatools\dbatools.psm1 -Force