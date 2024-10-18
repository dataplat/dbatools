param($ModuleName = 'dbatools')

Describe "Set-DbaDbRecoveryModel" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaDbRecoveryModel
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have RecoveryModel parameter" {
            $CommandUnderTest | Should -HaveParameter RecoveryModel -Type System.String -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[] -Mandatory:$false
        }
        It "Should have ExcludeDatabase parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[] -Mandatory:$false
        }
        It "Should have AllDatabases parameter" {
            $CommandUnderTest | Should -HaveParameter AllDatabases -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
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
