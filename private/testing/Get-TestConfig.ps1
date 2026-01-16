function Get-TestConfig {
    param(
        [string]$LocalConfigPath = "$script:PSModuleRoot/tests/constants.local.ps1"
    )

    $config = [ordered]@{
        CommonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters
        Defaults         = [System.Management.Automation.DefaultParameterDictionary]@{
            # We want the tests as readable as possible so we want to set Confirm globally to $false.
            '*-Dba*:Confirm'         = $false
            # We use a global warning variable so that we can always test
            # that the command does not write a warning
            # or that the command does write the expected warning.
            '*-Dba*:WarningVariable' = 'WarnVar'
        }
        # We want all the tests to only write to this location.
        # When testing a remote SQL Server instance this must be a network share
        # where both the SQL Server instance and the test script can write to.
        Temp             = 'C:\Temp'
    }

    if (Test-Path $LocalConfigPath) {
        . $LocalConfigPath
    } elseif ($env:CODESPACES -or ($env:TERM_PROGRAM -eq 'vscode' -and $env:REMOTE_CONTAINERS)) {
        $null = Set-DbatoolsInsecureConnection

        $config['Instance1'] = "dbatools1"
        $config['Instance2'] = "dbatools2"

        $config['SqlCred'] = [PSCredential]::new('sa', (ConvertTo-SecureString $env:SA_PASSWORD -AsPlainText -Force))
        $config['Defaults']['*:SqlCredential'] = $config['SqlCred']
        $config['Defaults']['*:SourceSqlCredential'] = $config['SqlCred']
        $config['Defaults']['*:DestinationSqlCredential'] = $config['SqlCred']
    } elseif ($env:GITHUB_WORKSPACE) {
        $config['DbaToolsCi_Computer'] = "localhost"

        $config['Instance1'] = "localhost"
        $config['Instance2'] = "localhost:14333"

        $config['SQLUserName'] = $null  # placeholders for -SqlCredential testing
        $config['SQLPassword'] = $null

        $config['AppveyorLabRepo'] = "/tmp/appveyor-lab"

        $config['AzureBlob'] = "https://dbatools.blob.core.windows.net/sql"
        $config['AzureBlobAccount'] = "dbatools"
        $config['AzureServer'] = 'psdbatools.database.windows.net'
        $config['AzureSqlDbLogin'] = "appveyor@clemairegmail.onmicrosoft.com"
    } else {
        # This configuration is used for the automated test on AppVeyor
        $config['DbaToolsCi_Computer'] = "$(hostname)"

        $config['InstanceSingle'] = "$(hostname)\sql2008r2sp2"
        $config['InstanceMulti1'] = "$(hostname)\sql2008r2sp2"
        $config['InstanceMulti2'] = "$(hostname)\sql2017"
        $config['InstanceCopy1'] = "$(hostname)\sql2008r2sp2"
        $config['InstanceCopy2'] = "$(hostname)\sql2017"
        $config['InstanceHadr'] = "$(hostname)\sql2017"
        $config['InstanceRestart'] = "$(hostname)\sql2008r2sp2"

        $config['SQLUserName'] = $null  # placeholders for -SqlCredential testing
        $config['SQLPassword'] = $null

        $config['AppveyorLabRepo'] = "C:\github\appveyor-lab"

        $config['AzureBlob'] = "https://dbatools.blob.core.windows.net/sql"
        $config['AzureBlobAccount'] = "dbatools"
        $config['AzureServer'] = 'psdbatools.database.windows.net'
        $config['AzureSqlDbLogin'] = "appveyor@clemairegmail.onmicrosoft.com"

        $config['BigDatabaseBackup'] = 'C:\github\StackOverflowMini.bak'
        $config['BigDatabaseBackupSourceUrl'] = 'https://github.com/BrentOzarULTD/Stack-Overflow-Database/releases/download/20230114/StackOverflowMini.bak'
    }

    [pscustomobject]$config
}