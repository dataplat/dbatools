# constants
if (Test-Path "$PSScriptRoot\constants.local.ps1") {
    Write-Host "Tests will use local constants file: tests\constants.local.ps1." -ForegroundColor Cyan
    . "$PSScriptRoot\constants.local.ps1"
} elseif ($env:CODESPACES -and ($env:TERM_PROGRAM -eq 'vscode' -and $env:REMOTE_CONTAINERS)) {
    $global:instance1 = "dbatools1"
    $global:instance2 = "dbatools2"
    $global:instance3 = "dbatools3"
    $global:instances = @($global:instance1, $global:instance2)

    $SqlCred = [PSCredential]::new('sa', (ConvertTo-SecureString $env:SA_PASSWORD -AsPlainText -Force))
    $PSDefaultParameterValues = @{
        "*:SqlCredential" = $sqlCred
    }
} elseif ($env:GITHUB_WORKSPACE) {
    $global:dbatoolsci_computer = "localhost"
    $global:instance1 = "localhost"
    $global:instance2 = "localhost:14333"
    $global:instance2SQLUserName = $null # placeholders for -SqlCredential testing
    $global:instance2SQLPassword = $null
    $global:instance3 = "localhost"
    $global:instance2_detailed = "localhost,14333" #Just to make sure things parse a port properly
    $global:appveyorlabrepo = "/tmp/appveyor-lab"
    $instances = @($global:instance1, $global:instance2)
    $ssisserver = "localhost\sql2016"
    $global:azureblob = "https://dbatools.blob.core.windows.net/sql"
    $global:azureblobaccount = "dbatools"
    $global:azureserver = 'psdbatools.database.windows.net'
    $global:azuresqldblogin = "appveyor@clemairegmail.onmicrosoft.com"
} else {
    $global:dbatoolsci_computer = "localhost"
    $global:instance1 = "localhost\sql2008r2sp2"
    $global:instance2 = "localhost\sql2016"
    $global:instance2SQLUserName = $null # placeholders for -SqlCredential testing
    $global:instance2SQLPassword = $null
    $global:instance3 = "localhost\sql2017"
    $global:instance2_detailed = "localhost,14333\sql2016" #Just to make sure things parse a port properly
    $global:appveyorlabrepo = "C:\github\appveyor-lab"
    $instances = @($global:instance1, $global:instance2)
    $ssisserver = "localhost\sql2016"
    $global:azureblob = "https://dbatools.blob.core.windows.net/sql"
    $global:azureblobaccount = "dbatools"
    $global:azureserver = 'psdbatools.database.windows.net'
    $global:azuresqldblogin = "appveyor@clemairegmail.onmicrosoft.com"
    $global:bigDatabaseBackup = 'C:\github\StackOverflowMini.bak'
    $global:bigDatabaseBackupSourceUrl = 'https://github.com/BrentOzarULTD/Stack-Overflow-Database/releases/download/20230114/StackOverflowMini.bak'
}

if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}
