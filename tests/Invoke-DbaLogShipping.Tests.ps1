$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    # This is a placeholder until we decide on sql2016/sql2017
    BeforeAll {
        $dbname = "dbatoolsci_logshipping"
    }

    It -Skip "returns success" {
        $results = Invoke-DbaLogShipping -SourceSqlInstance $script:instance2 -DestinationSqlInstance $script:instance -Database $dbname -BackupNetworkPath C:\temp -BackupLocalPath "C:\temp\logshipping\backup" -GenerateFullBackup -CompressBackup -SecondaryDatabaseSuffix "_LS" -Force
        $results.Status -eq 'Success' | Should Be $true
    }
}