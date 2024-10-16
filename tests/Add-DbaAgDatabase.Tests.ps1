$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Command under test
        $CommandUnderTest = Get-Command $CommandName
    }

    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
            $CommandUnderTest | Should -HaveParameter Secondary -Type DbaInstanceParameter[]
            $CommandUnderTest | Should -HaveParameter SecondarySqlCredential -Type PSCredential
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
            $CommandUnderTest | Should -HaveParameter SeedingMode -Type String
            $CommandUnderTest | Should -HaveParameter SharedPath -Type String
            $CommandUnderTest | Should -HaveParameter UseLastBackup -Type SwitchParameter
            $CommandUnderTest | Should -HaveParameter AdvancedBackupParams -Type Hashtable
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }

        It "Should have the correct common parameters" {
            $CommandUnderTest | Should -HaveParameter Verbose -Type SwitchParameter
            $CommandUnderTest | Should -HaveParameter Debug -Type SwitchParameter
            $CommandUnderTest | Should -HaveParameter ErrorAction -Type ActionPreference
            $CommandUnderTest | Should -HaveParameter WarningAction -Type ActionPreference
            $CommandUnderTest | Should -HaveParameter InformationAction -Type ActionPreference
            $CommandUnderTest | Should -HaveParameter ProgressAction -Type ActionPreference
            $CommandUnderTest | Should -HaveParameter ErrorVariable -Type String
            $CommandUnderTest | Should -HaveParameter WarningVariable -Type String
            $CommandUnderTest | Should -HaveParameter InformationVariable -Type String
            $CommandUnderTest | Should -HaveParameter OutVariable -Type String
            $CommandUnderTest | Should -HaveParameter OutBuffer -Type Int32
            $CommandUnderTest | Should -HaveParameter PipelineVariable -Type String
            $CommandUnderTest | Should -HaveParameter WhatIf -Type SwitchParameter
            $CommandUnderTest | Should -HaveParameter Confirm -Type SwitchParameter
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $agname = "dbatoolsci_addagdb_agroup"
        $dbname = "dbatoolsci_addagdb_agroupdb"
        $newdbname = "dbatoolsci_addag_agroupdb_2"
        $server.Query("create database $dbname")
        $backup = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Backup-DbaDatabase
        $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname, $newdbname -Confirm:$false
    }

    It "adds ag db and returns proper results" {
        $server.Query("create database $newdbname")
        $backup = Get-DbaDatabase -SqlInstance $script:instance3 -Database $newdbname | Backup-DbaDatabase
        $results = Add-DbaAgDatabase -SqlInstance $script:instance3 -AvailabilityGroup $agname -Database $newdbname -Confirm:$false
        $results.AvailabilityGroup | Should -Be $agname
        $results.Name | Should -Be $newdbname
        $results.IsJoined | Should -Be $true
    }
}

#$script:instance2 for appveyor
