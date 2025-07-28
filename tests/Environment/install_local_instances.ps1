$ErrorActionPreference = 'Stop'

if ((Get-ScheduledTask).TaskName -notcontains 'RunMeAtStartup') {
    Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Starting install"

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

$repoBase = 'C:\GitHub\dbatools'

Import-Module -Name "$repoBase\dbatools.psm1" -Force
$PSDefaultParameterValues['*-Dba*:EnableException'] = $true
$PSDefaultParameterValues['*-Dba*:Confirm'] = $false
$null = Set-DbatoolsInsecureConnection

$TestConfig = Get-TestConfig
$sqlInstance = $TestConfig.instance1, $TestConfig.instance2, $TestConfig.instance3

$instanceParams = @{
    Version            = 2022
    Path               = '\\fs\Software\SQLServer\ISO'
    Feature            = 'Engine'
    IFI                = $true
    Configuration      = @{
        SqlMaxMemory = '2048'
        NpEnabled    = 1
    }
    AuthenticationMode = 'Mixed'
    SaCredential       = $TestConfig.SqlCred
    AdminAccount       = "BUILTIN\Administrators"
    EnableException    = $false
}

foreach ($instance in $sqlInstance) {
    if (Get-DbaService -SqlInstance $instance) {
        continue
    }
    Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Starting install of $instance"
    $result = Install-DbaInstance @instanceParams -SqlInstance $instance
    Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Finished install of $instance"
    if ($result.Successful -ne $true) {
        Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Installation failed"
        Unregister-ScheduledTask -TaskName RunMeAtStartup -Confirm:$false
        exit
    }
    if ($result.Notes -match 'restart') {
        Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Restart needed"
        Restart-Computer -Force
        exit
    }
}

$null = Set-DbaSpConfigure -SqlInstance $sqlInstance -SqlCredential $TestConfig.SqlCred -Name IsSqlClrEnabled -Value $true
$null = Set-DbaSpConfigure -SqlInstance $sqlInstance -SqlCredential $TestConfig.SqlCred -Name ClrStrictSecurity -Value $false

$null = Set-DbaSpConfigure -SqlInstance $sqlInstance[1, 2] -SqlCredential $TestConfig.SqlCred -Name ExtensibleKeyManagementEnabled -Value $true
Invoke-DbaQuery -SqlInstance $sqlInstance[1, 2] -SqlCredential $TestConfig.SqlCred -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = '$($TestConfig.appveyorlabrepo)\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'"
$null = Enable-DbaAgHadr -SqlInstance $sqlInstance[1, 2] -Force

Invoke-DbaQuery -SqlInstance $sqlInstance[2] -SqlCredential $TestConfig.SqlCred -Query "CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongPassword>'"
Invoke-DbaQuery -SqlInstance $sqlInstance[2] -SqlCredential $TestConfig.SqlCred -Query "CREATE CERTIFICATE dbatoolsci_AGCert WITH SUBJECT = 'AG Certificate'"

$null = Set-DbaNetworkConfiguration -SqlInstance $sqlInstance[1] -StaticPortForIPAll 14333 -RestartService
$null = Set-DbaNetworkConfiguration -SqlInstance $sqlInstance[2] -StaticPortForIPAll 14334 -RestartService

Add-Content -Path $PSScriptRoot\logs\status.txt -Value "[$([datetime]::Now.ToString('HH:mm:ss'))] Finished install"

# Remove the task as we are finished
Unregister-ScheduledTask -TaskName RunMeAtStartup -Confirm:$false

# Restart the computer one last time to have everything clean
Restart-Computer -Force
