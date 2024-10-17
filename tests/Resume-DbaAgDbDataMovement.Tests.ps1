param($ModuleName = 'dbatools')

Describe "Resume-DbaAgDbDataMovement" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Resume-DbaAgDbDataMovement
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have AvailabilityGroup parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityDatabase[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $env:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $env:instance3
            $agname = "dbatoolsci_resumeagdb_agroup"
            $dbname = "dbatoolsci_resumeagdb_agroupdb"
            $server.Query("create database $dbname")
            $null = Get-DbaDatabase -SqlInstance $env:instance3 -Database $dbname | Backup-DbaDatabase
            $null = Get-DbaDatabase -SqlInstance $env:instance3 -Database $dbname | Backup-DbaDatabase -Type Log
            $ag = New-DbaAvailabilityGroup -Primary $env:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert -UseLastBackup
            $null = Get-DbaAgDatabase -SqlInstance $env:instance3 -AvailabilityGroup $agname | Suspend-DbaAgDbDataMovement -Confirm:$false
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
            $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
        }

        It "resumes data movement" {
            $results = Resume-DbaAgDbDataMovement -SqlInstance $env:instance3 -Database $dbname -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $dbname
            $results.SynchronizationState | Should -Be 'Synchronized'
        }
    }
} #$env:instance2 for appveyor
