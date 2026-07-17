<#
.SYNOPSIS
    Phase 0 inventory of the legacy golden image, executed via az vm run-command.

.DESCRIPTION
    Reports the facts that decide the runner-pool design: OS build, PowerShell and
    .NET versions, TLS posture, SQL instances with versions and ports, tooling, and
    leftovers from the previous CI attempt. Output stays compact because run-command
    caps returned stdout at about 4KB.

        az vm run-command invoke --resource-group dbatools-ci-phase0 --name dbat-phase0 --command-id RunPowerShellScript --scripts "@.github/runners/phase0/inventory.ps1"

.NOTES
    Author: the dbatools team + Claude
    PowerShell 3.0 compatible.
#>
$ErrorActionPreference = "SilentlyContinue"

"=== OS / PowerShell ==="
$os = Get-WmiObject -Class Win32_OperatingSystem
"OS       : $($os.Caption) ($($os.Version)) $($os.OSArchitecture)"
"PS       : $($PSVersionTable.PSVersion)"
"CLR      : $($PSVersionTable.CLRVersion)"
$net4 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
".NET 4.x : release $($net4.Release) (461808+ is 4.7.2, 528040+ is 4.8)"
"UCRT     : present=$(Test-Path -Path C:\Windows\System32\ucrtbase.dll) (needed by the .NET 8 runner)"

"=== TLS ==="
"SecurityProtocol default : $([System.Net.ServicePointManager]::SecurityProtocol)"
$crypto64 = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
"SchUseStrongCrypto (64)  : $($crypto64.SchUseStrongCrypto) / SystemDefaultTlsVersions: $($crypto64.SystemDefaultTlsVersions)"

"=== Disks ==="
Get-WmiObject -Class Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    "$($_.DeviceID) $([math]::Round($_.FreeSpace / 1GB, 1)) GB free of $([math]::Round($_.Size / 1GB, 1)) GB"
}

"=== Tooling ==="
$gitCommand = Get-Command -Name git.exe -ErrorAction SilentlyContinue
if ($gitCommand) {
    "git      : $($gitCommand.Path)"
} else {
    "git      : not on PATH"
}

"=== Directories ==="
foreach ($dir in "C:\github-runner", "C:\github", "C:\github\appveyor-lab", "C:\github\dbatools", "C:\temp") {
    if (Test-Path -Path $dir) {
        $children = (Get-ChildItem -Path $dir | Select-Object -First 6 | ForEach-Object { $_.Name }) -join ", "
        "$dir : $children"
    } else {
        "$dir : (missing)"
    }
}

"=== SQL Server services ==="
Get-WmiObject -Class Win32_Service -Filter "Name LIKE `"MSSQL%`" OR Name LIKE `"SQLAgent%`" OR Name = `"SQLBrowser`"" | ForEach-Object {
    "$($_.Name) : $($_.State) / $($_.StartMode)"
}

"=== SQL Server instances ==="
$instanceKey = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL"
if ($instanceKey) {
    foreach ($property in $instanceKey.PSObject.Properties) {
        if ($property.Name -match "^PS") { continue }
        $instanceId = $property.Value
        $setup = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\Setup"
        $tcp = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$instanceId\MSSQLServer\SuperSocketNetLib\Tcp\IPAll"
        "$($property.Name) : $instanceId / v$($setup.PatchLevel) $($setup.Edition) / port=$($tcp.TcpPort) dynamic=$($tcp.TcpDynamicPorts)"
    }
} else {
    "(no instances registered)"
}
