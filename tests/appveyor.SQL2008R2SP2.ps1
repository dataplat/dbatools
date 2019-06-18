
function Invoke-TlsWebRequest {
    <#
    Internal utility that mimics invoke-webrequest
    but enables all tls available version
    rather than the default, which on a lot
    of standard installations is just TLS 1.0

    #>
    $currentVersionTls = [Net.ServicePointManager]::SecurityProtocol
    $currentSupportableTls = [Math]::Max($currentVersionTls.value__, [Net.SecurityProtocolType]::Tls.value__)
    $availableTls = [enum]::GetValues('Net.SecurityProtocolType') | Where-Object { $_ -gt $currentSupportableTls }
    $availableTls | ForEach-Object {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor $_
    }

    Invoke-WebRequest @Args

    [Net.ServicePointManager]::SecurityProtocol = $currentVersionTls
}

Function Install-ADAuthenticationLibraryforSQLServer {
    # from https://bzzzt.io/post/2018-05-25-horrible-adalsql-issue/
    $workingFolder = Join-Path $env:temp ([System.IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Force -Path $workingFolder
    $uri = "https://raw.githubusercontent.com/sqlcollaborative/appveyor-lab/master/azure/adalsql.msi"


    $splitArray = $uri -split "/"
    $fileName = $splitArray[-1]

    $Installer = Join-Path -Path $WorkingFolder -ChildPath $fileName
    try {
        Invoke-TlsWebRequest -Uri $uri -OutFile $Installer
    } catch {
        Throw $_.Exception
    }
    If (!(Test-Path $Installer)) {
        Throw "$Installer does not exist"
    }
    try {
        Write-Host "attempting to uninstall..."
        Write-Host "Running MsiExec.exe /uninstall {4EE99065-01C6-49DD-9EC6-E08AA5B13491} /quiet"
        Start-Process -FilePath "MsiExec.exe" -ArgumentList  "/uninstall {4EE99065-01C6-49DD-9EC6-E08AA5B13491} /quiet" -Wait -NoNewWindow
    } catch {
        Write-Host "oh dear install did not work"
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
        Write-Host "Attempting to install.."
        Write-Host " Running msiexec.exe $($MSIArguments)"
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

# This script spins up the 2008R2SP2 instance and the relative setup

$sqlinstance = "localhost\SQL2008R2SP2"
$instance = "SQL2008R2SP2"
$port = "1433"

Write-Host -Object "$indent Setting up AppVeyor Services" -ForegroundColor DarkGreen
Set-Service -Name SQLBrowser -StartupType Automatic -WarningAction SilentlyContinue
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