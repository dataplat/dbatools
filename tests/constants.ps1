# constants
if (Test-Path C:\temp\constants.ps1) {
    Write-Verbose "C:\temp\constants.ps1 found."
    . C:\temp\constants.ps1
} elseif (Test-Path "$PSScriptRoot\constants.local.ps1") {
    Write-Verbose "tests\constants.local.ps1 found."
    . "$PSScriptRoot\constants.local.ps1"
} else {
    $script:instance1 = "LensmanSB"
    $script:instance2 = "LensmanSB"
    $script:instance3 = "localhost\sql2017"
    $script:instance2_detailed = "localhost,14333\sql2016" #Just to make sure things parse a port properly
    $script:appveyorlabrepo = "C:\github\appveyor-lab"
    $instances = @($script:instance1, $script:instance2)
    $ssisserver = "localhost\sql2016"
    $script:azureblob = "https://dbatools.blob.core.windows.net/sql"
    $script:azureblobaccount = "dbatools"
}

if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}