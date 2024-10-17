param($ModuleName = 'dbatools')

Describe "Remove-DbaAgDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAgDatabase
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "Remove-DbaAgDatabase Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        $null = Get-DbaProcess -SqlInstance $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $global:instance3
        $agname = "dbatoolsci_removeagdb_agroup"
        $dbname = "dbatoolsci_removeagdb_agroupdb"
        $server.Query("create database $dbname")
        $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Backup-DbaDatabase
        $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Backup-DbaDatabase -Type Log
        $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert -UseLastBackup
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
    }
    Context "removes ag db" {
        It "returns removed results" {
            $results = Remove-DbaAgDatabase -SqlInstance $global:instance3 -Database $dbname -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.Database | Should -Be $dbname
            $results.Status | Should -Be 'Removed'
        }

        It "really removed the db from the ag" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname
            $results.AvailabilityGroup | Should -Be $agname
            $results.AvailabilityDatabases.Name | Should -Not -Contain $dbname
        }
    }
} #$global:instance2 for appveyor
