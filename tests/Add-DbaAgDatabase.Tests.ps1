$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Mocking Get-Command for parameter validation
        Mock Get-Command {
            [PSCustomObject]@{
                Parameters = @{
                    SqlInstance          = @{Name = 'SqlInstance'}
                    SqlCredential        = @{Name = 'SqlCredential'}
                    AvailabilityGroup    = @{Name = 'AvailabilityGroup'}
                    Database             = @{Name = 'Database'}
                    Secondary            = @{Name = 'Secondary'}
                    SecondarySqlCredential = @{Name = 'SecondarySqlCredential'}
                    InputObject          = @{Name = 'InputObject'}
                    SeedingMode          = @{Name = 'SeedingMode'}
                    SharedPath           = @{Name = 'SharedPath'}
                    UseLastBackup        = @{Name = 'UseLastBackup'}
                    AdvancedBackupParams = @{Name = 'AdvancedBackupParams'}
                    EnableException      = @{Name = 'EnableException'}
                }
            }
        } -ParameterFilter { $Name -eq $CommandName }
    }

    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Database', 'Secondary', 'SecondarySqlCredential', 'InputObject', 'SeedingMode', 'SharedPath', 'UseLastBackup', 'AdvancedBackupParams', 'EnableException'
            $command = Get-Command $CommandName
            $commandParameters = $command.Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            $commandParameters | Should -Be $knownParameters
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $agname = "dbatoolsci_addagdb_agroup"
        $dbname = "dbatoolsci_addagdb_agroupdb"
        $newdbname = "dbatoolsci_addag_agroupdb_2"
        $null = $server.Query("CREATE DATABASE $dbname")
        $null = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Backup-DbaDatabase
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname, $newdbname -Confirm:$false
    }

    Context "adds ag db and returns proper results" {
        It "adds the database to the availability group" {
            $server.Query("CREATE DATABASE $newdbname")
            $null = Get-DbaDatabase -SqlInstance $script:instance3 -Database $newdbname | Backup-DbaDatabase
            $results = Add-DbaAgDatabase -SqlInstance $script:instance3 -AvailabilityGroup $agname -Database $newdbname -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $newdbname
            $results.IsJoined | Should -Be $true
        }
    }
}

#$script:instance2 for appveyor
