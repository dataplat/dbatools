function Get-TestConfig {
    param(
        [string]$LocalConfigPath = "$script:PSModuleRoot/tests/constants.local.ps1"
    )
    $config = [ordered]@{}

    if (Test-Path $LocalConfigPath) {
        . $LocalConfigPath
    } elseif ($env:CODESPACES -or ($env:TERM_PROGRAM -eq 'vscode' -and $env:REMOTE_CONTAINERS)) {
        $null = Set-DbatoolsInsecureConnection
        $config['Instance1'] = "dbatools1"
        $config['Instance2'] = "dbatools2"
        $config['Instance3'] = "dbatools3"
        $config['Instances'] = @($config['Instance1'], $config['Instance2'])

        $config['SqlCred'] = [PSCredential]::new('sa', (ConvertTo-SecureString $env:SA_PASSWORD -AsPlainText -Force))
        $config['Defaults'] = [System.Management.Automation.DefaultParameterDictionary]@{
            "*:SqlCredential" = $config['SqlCred']
            "*:SourceSqlCredential" = $config['SqlCred']
            "*:DestinationSqlCredential" = $config['SqlCred']
        }
    } elseif ($env:GITHUB_WORKSPACE) {
        $config['DbaToolsCi_Computer'] = "localhost"
        $config['Instance1'] = "localhost"
        $config['Instance2'] = "localhost:14333"
        $config['Instance2SQLUserName'] = $null  # placeholders for -SqlCredential testing
        $config['Instance2SQLPassword'] = $null
        $config['Instance3'] = "localhost"
        $config['Instance2_Detailed'] = "localhost,14333"  # Just to make sure things parse a port properly
        $config['AppveyorLabRepo'] = "/tmp/appveyor-lab"
        $config['Instances'] = @($config['Instance1'], $config['Instance2'])
        $config['SsisServer'] = "localhost\sql2016"
        $config['AzureBlob'] = "https://dbatools.blob.core.windows.net/sql"
        $config['AzureBlobAccount'] = "dbatools"
        $config['AzureServer'] = 'psdbatools.database.windows.net'
        $config['AzureSqlDbLogin'] = "appveyor@clemairegmail.onmicrosoft.com"
    } else {
        $config['DbaToolsCi_Computer'] = "localhost"
        $config['Instance1'] = "localhost\sql2008r2sp2"
        $config['Instance2'] = "localhost\sql2016"
        $config['Instance2SQLUserName'] = $null  # placeholders for -SqlCredential testing
        $config['Instance2SQLPassword'] = $null
        $config['Instance3'] = "localhost\sql2017"
        $config['Instance2_Detailed'] = "localhost,14333\sql2016"  # Just to make sure things parse a port properly
        $config['AppveyorLabRepo'] = "C:\github\appveyor-lab"
        $config['Instances'] = @($config['Instance1'], $config['Instance2'])
        $config['SsisServer'] = "localhost\sql2016"
        $config['AzureBlob'] = "https://dbatools.blob.core.windows.net/sql"
        $config['AzureBlobAccount'] = "dbatools"
        $config['AzureServer'] = 'psdbatools.database.windows.net'
        $config['AzureSqlDbLogin'] = "appveyor@clemairegmail.onmicrosoft.com"
        $config['BigDatabaseBackup'] = 'C:\github\StackOverflowMini.bak'
        $config['BigDatabaseBackupSourceUrl'] = 'https://github.com/BrentOzarULTD/Stack-Overflow-Database/releases/download/20230114/StackOverflowMini.bak'
    }

    if ($env:appveyor) {
        $config['Defaults'] = [System.Management.Automation.DefaultParameterDictionary]@{
            '*:WarningAction' = 'SilentlyContinue'
        }
    }

    $config['CommonParameters'] = [System.Management.Automation.PSCmdlet]::CommonParameters

    # We want the tests as readable as possible so we want to set Confirm globally to $false
    $config['Defaults']['*:Confirm'] = $false

    # We use a global warning variable so that we can always test that the command does not write a warning
    $config['Defaults']['*:WarningVariable'] = 'WarnVar'

    if (-not $config['Temp']) {
        $config['Temp'] = 'C:\Temp'
    }

    [pscustomobject]$config
}