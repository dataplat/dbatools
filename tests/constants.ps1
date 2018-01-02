# constants
if (Test-Path C:\temp\constants.ps1) {
    Write-Verbose "C:\temp\constants.ps1 found."
    . C:\temp\constants.ps1
}
elseif (Test-Path "$PSScriptRoot\constants.local.ps1") {
    Write-Verbose "tests\constants.local.ps1 found."
    . "$PSScriptRoot\constants.local.ps1"
}
else {
    $script:instance1 = "localhost\sql2008r2sp2"
    $script:instance2 = "localhost\sql2016"
    $script:instance1_detailed = "localhost,1433\sql2008r2sp2" #Just to make sure things parse a port properly
    $script:appveyorlabrepo = "C:\github\appveyor-lab"
    $instances = @($script:instance1, $script:instance2)
    $ssisserver = "localhost\sql2016"
}
