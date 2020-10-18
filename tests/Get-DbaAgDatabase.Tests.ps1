$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Database', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $null = Get-DbaProcess -SqlInstance $script:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance3
        $agname = "dbatoolsci_getagdb_agroup"
        $dbname = "dbatoolsci_getagdb_agroupdb"
        $server.Query("create database $dbname")
        $null = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Backup-DbaDatabase
        $null = Get-DbaDatabase -SqlInstance $script:instance3 -Database $dbname | Backup-DbaDatabase -Type Log
        $ag = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert -UseLastBackup
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
    }
    Context "gets ag db" {
        It "returns results" {
            $results = Get-DbaAgDatabase -SqlInstance $script:instance3 -Database $dbname
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $dbname
            $results.Replica | Should -Not -Be $null
        }
    }
} #$script:instance2 for appveyor