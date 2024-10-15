param($ModuleName = 'dbatools')

Describe "Add-DbaAgDatabase Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Import the function
        . (Join-Path -Path $PSScriptRoot -ChildPath '..\functions\Add-DbaAgDatabase.ps1')
    }

    Context "Validate parameters" {
        BeforeDiscovery {
            $commandInfo = Get-Command Add-DbaAgDatabase
            $parameterInfo = $commandInfo.Parameters
        }

        It "Should have parameter <_>" -ForEach @(
            'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Database', 'Secondary', 'SecondarySqlCredential',
            'InputObject', 'SeedingMode', 'SharedPath', 'UseLastBackup', 'AdvancedBackupParams', 'EnableException'
        ) {
            $parameterInfo.ContainsKey($_) | Should -Be $true
        }

        It "SqlInstance parameter should be mandatory" {
            $parameterInfo['SqlInstance'].Attributes.Mandatory | Should -Be $true
        }

        It "AvailabilityGroup parameter should be mandatory" {
            $parameterInfo['AvailabilityGroup'].Attributes.Mandatory | Should -Be $true
        }

        It "SeedingMode parameter should accept 'Automatic' and 'Manual'" {
            $parameterInfo['SeedingMode'].Attributes.ValidValues | Should -Be @('Automatic', 'Manual')
        }
    }
}

Describe "Add-DbaAgDatabase Integration Tests" -Tag "IntegrationTests" {
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
