param($ModuleName = 'dbatools')

Describe "Get-DbaDbRecoveryModel" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbRecoveryModel
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have RecoveryModel as a parameter" {
            $CommandUnderTest | Should -HaveParameter RecoveryModel -Type String[] -Not -Mandatory
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Recovery model is correctly identified" {
        BeforeAll {
            $results = Get-DbaDbRecoveryModel -SqlInstance $global:instance2 -Database master
        }

        It "returns a single database" {
            $results.Count | Should -Be 1
        }

        It "returns the correct recovery model" {
            $results.RecoveryModel | Should -Be 'Simple'
        }

        It "returns accurate number of results" {
            $allResults = Get-DbaDbRecoveryModel -SqlInstance $global:instance2
            $allResults.Count | Should -BeGreaterOrEqual 4
        }
    }

    Context "RecoveryModel parameter works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $dbname = "dbatoolsci_getrecoverymodel"
            Get-DbaDatabase -SqlInstance $server -Database $dbname | Remove-DbaDatabase -Confirm:$false
            $server.Query("CREATE DATABASE $dbname; ALTER DATABASE $dbname SET RECOVERY BULK_LOGGED WITH NO_WAIT;")
        }

        AfterAll {
            Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }

        It "gets the newly created database with the correct recovery model" {
            $results = Get-DbaDbRecoveryModel -SqlInstance $global:instance2 -Database $dbname
            $results.RecoveryModel | Should -Be 'BulkLogged'
        }

        It "honors the RecoveryModel parameter filter" {
            $results = Get-DbaDbRecoveryModel -SqlInstance $global:instance2 -RecoveryModel BulkLogged
            $results.Name | Should -Contain $dbname
        }
    }
}
