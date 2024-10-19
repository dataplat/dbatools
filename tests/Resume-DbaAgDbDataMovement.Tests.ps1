param($ModuleName = 'dbatools')

Describe "Resume-DbaAgDbDataMovement" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Resume-DbaAgDbDataMovement
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "Database",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $agname = "dbatoolsci_resumeagdb_agroup"
            $dbname = "dbatoolsci_resumeagdb_agroupdb"
            $server.Query("create database $dbname")
            $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Backup-DbaDatabase
            $null = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Backup-DbaDatabase -Type Log
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert -UseLastBackup
            $null = Get-DbaAgDatabase -SqlInstance $global:instance3 -AvailabilityGroup $agname | Suspend-DbaAgDbDataMovement -Confirm:$false
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
            $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
        }

        It "resumes data movement" {
            $results = Resume-DbaAgDbDataMovement -SqlInstance $global:instance3 -Database $dbname -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $dbname
            $results.SynchronizationState | Should -Be 'Synchronized'
        }
    }
} #$global:instance2 for appveyor
