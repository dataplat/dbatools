$ErrorActionPreference = 'Stop'

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
    EnableException    = $false
}

foreach ($instance in $sqlInstance) {
    if (Get-DbaService -SqlInstance $instance) {
        continue
    }
    $result = Install-DbaInstance @instanceParams -SqlInstance $instance
    if ($result.Successful -ne $true) {
        $result | Format-List *
        throw 'Installation failed'
    }
    if ($result.Notes -match 'restart') {
        $result.Notes
        throw 'Installation needs restart'
    }
}

$null = Set-DbaSpConfigure -SqlInstance $sqlInstance -Name IsSqlClrEnabled -Value $true
$null = Set-DbaSpConfigure -SqlInstance $sqlInstance -Name ClrStrictSecurity -Value $false

$null = Set-DbaSpConfigure -SqlInstance $sqlInstance[1, 2] -Name ExtensibleKeyManagementEnabled -Value $true
Invoke-DbaQuery -SqlInstance $sqlInstance[1, 2] -Query "CREATE CRYPTOGRAPHIC PROVIDER dbatoolsci_AKV FROM FILE = '$($TestConfig.appveyorlabrepo)\keytests\ekm\Microsoft.AzureKeyVaultService.EKM.dll'"
$null = Enable-DbaAgHadr -SqlInstance $sqlInstance[1, 2] -Force

Invoke-DbaQuery -SqlInstance $sqlInstance[2] -Query "IF NOT EXISTS (select * from sys.symmetric_keys where name like '%DatabaseMasterKey%') CREATE MASTER KEY ENCRYPTION BY PASSWORD = '<StrongPassword>'"
Invoke-DbaQuery -SqlInstance $sqlInstance[2] -Query "IF EXISTS ( SELECT * FROM sys.tcp_endpoints WHERE name = 'End_Mirroring') DROP ENDPOINT endpoint_mirroring"
Invoke-DbaQuery -SqlInstance $sqlInstance[2] -Query "CREATE CERTIFICATE dbatoolsci_AGCert WITH SUBJECT = 'AG Certificate'"

$null = Set-DbaNetworkConfiguration -SqlInstance $sqlInstance[1] -StaticPortForIPAll 14333 -RestartService
$null = Set-DbaNetworkConfiguration -SqlInstance $sqlInstance[2] -StaticPortForIPAll 14334 -RestartService
