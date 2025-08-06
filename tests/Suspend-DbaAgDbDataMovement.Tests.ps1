$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
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
        $backupPath = "$($TestConfig.Temp)\$CommandName"
        $null = New-Item -Path $backupPath -ItemType Directory
        $null = Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $agname = "dbatoolsci_resumeagdb_agroup"
        $dbname = "dbatoolsci_resumeagdb_agroupdb"
        $server.Query("create database $dbname")
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupPath
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupPath -Type Log
        $ag = New-DbaAvailabilityGroup -Primary $TestConfig.instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert -UseLastBackup
        $null = Get-DbaAgDatabase -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname | Resume-DbaAgDbDataMovement -Confirm:$false
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname -Confirm:$false
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname -Confirm:$false
        Remove-Item -Path $backupPath -Recurse
    }
    Context "resumes  data movement" {
        It "returns resumed results" {
            $results = Suspend-DbaAgDbDataMovement -SqlInstance $TestConfig.instance3 -Database $dbname -Confirm:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $dbname
            $results.SynchronizationState | Should -Be 'NotSynchronizing'
        }
    }
} #$TestConfig.instance2 for appveyor
