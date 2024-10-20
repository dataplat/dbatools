param($ModuleName = 'dbatools')

Describe "Set-DbaDbRecoveryModel" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbRecoveryModel
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "RecoveryModel",
            "Database",
            "ExcludeDatabase",
            "AllDatabases",
            "EnableException",
            "InputObject"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Recovery model is correctly set" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $dbname = "dbatoolsci_recoverymodel"
            Get-DbaDatabase -SqlInstance $server -Database $dbname | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $dbname")
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        It "sets the proper recovery model" {
            $results = Set-DbaDbRecoveryModel -SqlInstance $global:instance2 -Database $dbname -RecoveryModel BulkLogged -Confirm:$false
            $results.RecoveryModel | Should -Be "BulkLogged"
        }

        It "supports the pipeline" {
            $results = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Set-DbaDbRecoveryModel -RecoveryModel Simple -Confirm:$false
            $results.RecoveryModel | Should -Be "Simple"
        }

        It "requires Database, ExcludeDatabase or AllDatabases" {
            $warn = $null
            $results = Set-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel Simple -WarningAction SilentlyContinue -WarningVariable warn -Confirm:$false
            $warn | Should -Match "AllDatabases"
        }
    }
}
