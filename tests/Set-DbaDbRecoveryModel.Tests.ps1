$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'RecoveryModel', 'Database', 'ExcludeDatabase', 'AllDatabases', 'EnableException', 'InputObject'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Recovery model is correctly set" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $dbname = "dbatoolsci_recoverymodel"
            Get-DbaDatabase -SqlInstance $server -Database $dbname | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $dbname")
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        $results = Set-DbaDbRecoveryModel -SqlInstance $script:instance2 -Database $dbname -RecoveryModel BulkLogged -Confirm:$false

        It "sets the proper recovery model" {
            $results.RecoveryModel -eq "BulkLogged" | Should Be $true
        }

        It "supports the pipeline" {
            $results = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Set-DbaDbRecoveryModel -RecoveryModel Simple -Confirm:$false
            $results.RecoveryModel -eq "Simple" | Should Be $true
        }

        It "requires Database, ExcludeDatabase or AllDatabases" {
            $results = Set-DbaDbRecoveryModel -SqlInstance $script:instance2 -RecoveryModel Simple -WarningAction SilentlyContinue -WarningVariable warn -Confirm:$false
            $warn -match "AllDatabases" | Should Be $true
        }

    }
}