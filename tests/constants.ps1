# constants.ps1
if (Test-Path "$PSScriptRoot\constants.local.ps1") {
    Write-Host "Tests will use local constants file: tests\constants.local.ps1." -ForegroundColor Cyan
    . "$PSScriptRoot\constants.local.ps1"
} elseif ($env:CODESPACES -or ($env:TERM_PROGRAM -eq 'vscode' -and $env:REMOTE_CONTAINERS)) {
    Write-Host "Tests will use codespaces constants." -ForegroundColor Cyan

    # Use global variables instead of $global: for consistency
    $global:instance1 = "dbatools1"
    $global:instance2 = "dbatools2"
    $global:instance3 = "dbatools3"
    $global:instances = @($global:instance1, $global:instance2)

    # Global SQL Credential setup
    $global:SqlCred = [PSCredential]::new('sa', (ConvertTo-SecureString $env:SA_PASSWORD -AsPlainText -Force))

    # Set up default SqlCredential for all commands
    if (-not $PSDefaultParameterValues.ContainsKey('*:SqlCredential')) {
        $PSDefaultParameterValues = $PSDefaultParameterValues + @{
            "*:SqlCredential" = $global:SqlCred
        }
    }
} elseif ($env:GITHUB_WORKSPACE) {
    Write-Host "Tests will use GitHub Actions constants." -ForegroundColor Cyan

    # Use global variables for GitHub Actions constants
    $global:dbatoolsci_computer = "localhost"
    $global:instance1 = "localhost"
    $global:instance2 = "localhost:14333"
    $global:instance2SQLUserName = $null
    $global:instance2SQLPassword = $null
    $global:instance3 = "localhost"
    $global:instance2_detailed = "localhost,14333"
    $global:appveyorlabrepo = "/tmp/appveyor-lab"
    $global:instances = @($global:instance1, $global:instance2)
    $global:azureblob = "https://dbatools.blob.core.windows.net/sql"
    $global:azureblobaccount = "dbatools"
    $global:azureserver = 'psdbatools.database.windows.net'
    $global:azuresqldblogin = "appveyor@clemairegmail.onmicrosoft.com"
} else {
    Write-Host "Tests will use AppVeyor constants." -ForegroundColor Cyan

    # Global variables for AppVeyor constants
    $global:dbatoolsci_computer = "localhost"
    $global:instance1 = "localhost\sql2008r2sp2"
    $global:instance2 = "localhost\sql2016"
    $global:instance2SQLUserName = $null
    $global:instance2SQLPassword = $null
    $global:instance3 = "localhost\sql2017"
    $global:instance2_detailed = "localhost,14333\sql2016"
    $global:appveyorlabrepo = "C:\github\appveyor-lab"
    $global:instances = @($global:instance1, $global:instance2)
    $global:ssisserver = "localhost\sql2016"
    $global:azureblob = "https://dbatools.blob.core.windows.net/sql"
    $global:azureblobaccount = "dbatools"
    $global:azureserver = 'psdbatools.database.windows.net'
    $global:azuresqldblogin = "appveyor@clemairegmail.onmicrosoft.com"
}

# Set global PSDefaultParameterValues if running on AppVeyor
if ($env:appveyor) {
    $PSDefaultParameterValues['*:WarningAction'] = 'SilentlyContinue'
}
