return
# constants
if (Test-Path "$TestConfig.PSModuleRoot/tests/constants.local.ps1") {
    Write-Host "Tests will use local constants file: tests\constants.local.ps1." -ForegroundColor Cyan
    . "$TestConfig.PSModuleRoot/tests/constants.local.ps1"
} elseif ($env:CODESPACES -and ($env:TERM_PROGRAM -eq 'vscode' -and $env:REMOTE_CONTAINERS)) {
    $TestConfig.instance1 = "dbatools1"
    $TestConfig.instance2 = "dbatools2"
    $TestConfig.instance3 = "dbatools3"
    $TestConfig.instances = @($TestConfig.instance1, $TestConfig.instance2)

    $SqlCred = [PSCredential]::new('sa', (ConvertTo-SecureString $env:SA_PASSWORD -AsPlainText -Force))
    $PSDefaultParameterValues = @{
        "*:SqlCredential" = $sqlCred
    }
} elseif ($env:GITHUB_WORKSPACE) {
    $TestConfig.dbatoolsci_computer = "localhost"
    $TestConfig.instance1 = "localhost"
    $TestConfig.instance2 = "localhost:14333"
    $TestConfig.instance2SQLUserName = $null # placeholders for -SqlCredential testing
    $TestConfig.instance2SQLPassword = $null
    $TestConfig.instance3 = "localhost"
    $TestConfig.instance2_detailed = "localhost,14333" #Just to make sure things parse a port properly
    $TestConfig.appveyorlabrepo = "/tmp/appveyor-lab"
    $instances = @($TestConfig.instance1, $TestConfig.instance2)
    $ssisserver = "localhost\sql2016"
    $TestConfig.azureblob = "https://dbatools.blob.core.windows.net/sql"
    $TestConfig.azureblobaccount = "dbatools"
    $TestConfig.azureserver = 'psdbatools.database.windows.net'
    $TestConfig.azuresqldblogin = "appveyor@clemairegmail.onmicrosoft.com"
} else {
    $TestConfig.dbatoolsci_computer = "localhost"
    $TestConfig.instance1 = "localhost\sql2008r2sp2"
    $TestConfig.instance2 = "localhost\sql2016"
    $TestConfig.instance2SQLUserName = $null # placeholders for -SqlCredential testing
    $TestConfig.instance2SQLPassword = $null
    $TestConfig.instance3 = "localhost\sql2017"
    $TestConfig.instance2_detailed = "localhost,14333\sql2016" #Just to make sure things parse a port properly
    $TestConfig.appveyorlabrepo = "C:\github\appveyor-lab"
    $instances = @($TestConfig.instance1, $TestConfig.instance2)
    $ssisserver = "localhost\sql2016"
    $TestConfig.azureblob = "https://dbatools.blob.core.windows.net/sql"
    $TestConfig.azureblobaccount = "dbatools"
    $TestConfig.azureserver = 'psdbatools.database.windows.net'
    $TestConfig.azuresqldblogin = "appveyor@clemairegmail.onmicrosoft.com"
    $TestConfig.bigDatabaseBackup = 'C:\github\StackOverflowMini.bak'
    $TestConfig.bigDatabaseBackupSourceUrl = 'https://github.com/BrentOzarULTD/Stack-Overflow-Database/releases/download/20230114/StackOverflowMini.bak'
}

if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}

