Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
# Imports some assemblies
Write-Output "Importing dbatools"
Import-Module C:\github\dbatools\dbatools.psd1

# This script spins up two local instances
$sql2008 = "localhost\sql2008r2sp2"
$sql2016 = "localhost\sql2016"

Write-Output "Creating migration & backup directories"
New-Item -Path C:\temp -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
New-Item -Path C:\temp\migration -ItemType Directory -ErrorAction SilentlyContinue | Out-Null
New-Item -Path C:\temp\backups -ItemType Directory -ErrorAction SilentlyContinue | Out-Null

Write-Output "Setting sql2016 Agent to Automatic"
Set-Service -Name 'SQLAgent$sql2016' -StartupType Automatic

$instances = "sql2016", "sql2008r2sp2"

foreach ($instance in $instances) {
	$port = switch ($instance) {
		"sql2008r2sp2" { "1433" }
		"sql2016" { "14333" }
	}
	
	Write-Output "Changing the port on $instance to $port"
	$wmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer
	$uri = "ManagedComputer[@Name='$env:COMPUTERNAME']/ ServerInstance[@Name='$instance']/ServerProtocol[@Name='Tcp']"
	$Tcp = $wmi.GetSmoObject($uri)
	foreach ($ipAddress in $Tcp.IPAddresses) {
		$ipAddress.IPAddressProperties["TcpDynamicPorts"].Value = ""
		$ipAddress.IPAddressProperties["TcpPort"].Value = $port
	}
	$Tcp.Alter()
	 
	Write-Output "Starting $instance"
	Restart-Service "MSSQL`$$instance"
	
	if ($instance -eq "sql2016") {
		Write-Output "Starting Agent for $instance"
		Restart-Service 'SQLAgent$sql2016'
	}
}

do {
	Start-Sleep 1
	$null = (& sqlcmd -S localhost -b -Q "select 1" -d master)
}
while ($lastexitcode -ne 0 -and $t++ -lt 10)

do {
	Start-Sleep 1
	$null = (& sqlcmd -S localhost\sql2016 -b -Q "select 1" -d master)
}
while ($lastexitcode -ne 0 -and $s++ -lt 10)

# Agent sometimes takes a moment to start 
do {
	Write-Warning "Waiting for SQL Agent to start"
	Start-Sleep 1
}
while ((Get-Service 'SQLAgent$sql2016').Status -ne 'Running' -and $z++ -lt 10)

# Whatever, just sleep an extra 5
Start-Sleep 5

Write-Output "Executing startup scripts for SQL Server 2008"
# Add some jobs to the sql2008r2sp2 instance (1433 = default)
foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2008-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
	Invoke-Sqlcmd2 -ServerInstance localhost -InputFile $file
}

Write-Output "Executing startup scripts for SQL Server 2016"
foreach ($file in (Get-ChildItem C:\github\appveyor-lab\sql2016-startup\*.sql -Recurse -ErrorAction SilentlyContinue)) {
	Invoke-Sqlcmd2 -ServerInstance localhost\sql2016 -InputFile $file
}