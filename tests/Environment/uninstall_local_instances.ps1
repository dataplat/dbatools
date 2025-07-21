$ErrorActionPreference = 'Stop'

if ((Get-ScheduledTask).TaskName -notcontains 'RunMeAtStartup') {
    $scheduledTaskActionParams = @{
        Execute  = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
        Argument = "-ExecutionPolicy RemoteSigned -NonInteractive -File $($MyInvocation.MyCommand.Path)"
    }
    $scheduledTaskParams = @{
        TaskName = 'RunMeAtStartup'
        Trigger  = New-ScheduledTaskTrigger -AtStartup
        User     = 'SYSTEM'
        Action   = New-ScheduledTaskAction @scheduledTaskActionParams
    }
    $null = Register-ScheduledTask @scheduledTaskParams
    Restart-Computer -Force
    exit
}

Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Starting uninstall"

$repoBase = 'C:\GitHub\dbatools'

Import-Module -Name "$repoBase\dbatools.psm1" -Force
$PSDefaultParameterValues['*-Dba*:EnableException'] = $true
$PSDefaultParameterValues['*-Dba*:Confirm'] = $false
$null = Set-DbatoolsInsecureConnection

$TestConfig = Get-TestConfig
$sqlInstance = $TestConfig.instance1, $TestConfig.instance2, $TestConfig.instance3

$null = Stop-DbaService -SqlInstance $sqlInstance -Type Engine -Force -ErrorAction SilentlyContinue

$instanceParams = @{
    Version         = 2022
    Path            = '\\fs\Software\SQLServer\ISO'
    Configuration   = @{ ACTION = 'Uninstall' }
    EnableException = $false
}

foreach ($instance in $sqlInstance) {
    if (-not (Get-DbaService -SqlInstance $instance)) {
        continue
    }
    Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Starting uninstall of $instance"
    $result = Install-DbaInstance @instanceParams -SqlInstance $instance
    Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Finished uninstall of $instance"
    if ($result.Successful -ne $true) {
        Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Uninstallation failed"
        Unregister-ScheduledTask -TaskName RunMeAtStartup -Confirm:$false
        exit
    }
    if ($result.Notes -match 'restart') {
        Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Restart needed"
        Restart-Computer -Force
        exit
    }
}

Remove-Item -Path 'C:\Program Files\Microsoft SQL Server', 'C:\Temp\*' -Recurse

Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Finished uninstall"

# Remove the task as we are finished
Unregister-ScheduledTask -TaskName RunMeAtStartup -Confirm:$false

# Restart the computer one last time to have everything clean
Restart-Computer -Force
