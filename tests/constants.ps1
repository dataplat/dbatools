# constants
if (Test-Path "$PSScriptRoot\constants.local.ps1") {
    Write-Verbose "tests\constants.local.ps1 found."
    . "$PSScriptRoot\constants.local.ps1"
} elseif ($env:CODESPACES -and ($env:TERM_PROGRAM -eq 'vscode' -and $env:REMOTE_CONTAINERS)) {
    $script:instance1 = "dbatools1"
    $script:instance2 = "dbatools2"
    $script:instance3 = "dbatools3"
    $script:instances = @($script:instance1, $script:instance2)

    $SqlCred = [PSCredential]::new('sa',(ConvertTo-SecureString $env:SA_PASSWORD -AsPlainText -Force))
    $PSDefaultParameterValues = @{
        "*:SqlCredential" = $sqlCred
    }
} else {
    $script:dbatoolsci_computer = "localhost"
    $script:instance1 = "localhost"
    $script:instance2 = "localhost\sql2016"
    $script:instance2SQLUserName = $null # placeholders for -SqlCredential testing
    $script:instance2SQLPassword = $null
    $script:instance3 = "localhost\sql2017"
    $script:instance2_detailed = "localhost,14333\sql2016" #Just to make sure things parse a port properly
    $script:appveyorlabrepo = "C:\github\appveyor-lab"
    $instances = @($script:instance1, $script:instance2)
    $ssisserver = "localhost\sql2016"
    $script:azureblob = "https://dbatools.blob.core.windows.net/sql"
    $script:azureblobaccount = "dbatools"
    $script:azureserver = 'psdbatools.database.windows.net'
    $script:azuresqldblogin = "appveyor@clemairegmail.onmicrosoft.com"
}

if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}
