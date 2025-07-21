$ErrorActionPreference = 'Stop'

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

Remove-Item -Path 'C:\Program Files\Microsoft SQL Server', 'C:\Temp\*' -Recurse
