#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param($ModuleName = 'dbatools')
$global:TestConfig = Get-TestConfig

Describe "Add-DbaAgDatabase" {
    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Add-DbaAgDatabase
        }
        $parms = @(
            "SqlInstance",
            "SqlCredential",
            "AvailabilityGroup",
            "Database",
            "Secondary",
            "SecondarySqlCredential",
            "InputObject",
            "SeedingMode",
            "SharedPath",
            "UseLastBackup",
            "AdvancedBackupParams",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $global:TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $global:TestConfig.instance3
            $agname = "dbatoolsci_addagdb_agroup"
            $dbname = "dbatoolsci_addagdb_agroupdb"
            $newdbname = "dbatoolsci_addag_agroupdb_2"
            $server.Query("create database $dbname")
            $backup = Get-DbaDatabase -SqlInstance $global:TestConfig.instance3 -Database $dbname | Backup-DbaDatabase
            $ag = New-DbaAvailabilityGroup -Primary $global:TestConfig.instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
            $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname, $newdbname -Confirm:$false
        }

        It "adds ag db and returns proper results" {
            $server.Query("create database $newdbname")
            $backup = Get-DbaDatabase -SqlInstance $global:TestConfig.instance3 -Database $newdbname | Backup-DbaDatabase
            $results = Add-DbaAgDatabase -SqlInstance $global:TestConfig.instance3 -AvailabilityGroup $agname -Database $newdbname -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $newdbname
            $results.IsJoined | Should -Be $true
        }
    }
}
#$global:TestConfig.instance2 for appveyor
