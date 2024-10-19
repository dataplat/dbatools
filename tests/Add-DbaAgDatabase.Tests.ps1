param($ModuleName = 'dbatools')

Describe "Add-DbaAgDatabase" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaAgDatabase
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
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
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $agname = "dbatoolsci_addagdb_agroup"
            $dbname = "dbatoolsci_addagdb_agroupdb"
            $newdbname = "dbatoolsci_addag_agroupdb_2"
            $server.Query("create database $dbname")
            $backup = Get-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Backup-DbaDatabase
            $ag = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
            $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname, $newdbname -Confirm:$false
        }

        It "adds ag db and returns proper results" {
            $server.Query("create database $newdbname")
            $backup = Get-DbaDatabase -SqlInstance $global:instance3 -Database $newdbname | Backup-DbaDatabase
            $results = Add-DbaAgDatabase -SqlInstance $global:instance3 -AvailabilityGroup $agname -Database $newdbname -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $newdbname
            $results.IsJoined | Should -Be $true
        }
    }
} #$global:instance2 for appveyor
