#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Suspend-DbaAgDbDataMovement",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "Database",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $backupPath = "$($TestConfig.Temp)\$CommandName"
        $null = New-Item -Path $backupPath -ItemType Directory
        $null = Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $agname = "dbatoolsci_suspendagdb_agroup"
        $dbname = "dbatoolsci_suspendagdb_agroupdb-$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $dbname
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupPath
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupPath -Type Log
        $ag = New-DbaAvailabilityGroup -Primary $TestConfig.instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Certificate dbatoolsci_AGCert -UseLastBackup
        $null = Get-DbaAgDatabase -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agname | Resume-DbaAgDbDataMovement
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname
        Remove-Item -Path $backupPath -Recurse
    }
    Context "Suspends data movement" {
        It "Should return suspended results" {
            $results = Suspend-DbaAgDbDataMovement -SqlInstance $TestConfig.instance3 -Database $dbname
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $dbname
            $results.SynchronizationState | Should -Be 'NotSynchronizing'
        }
    }
} #$TestConfig.instance2 for appveyor