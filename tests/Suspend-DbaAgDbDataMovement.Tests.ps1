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
        $null = Get-DbaProcess -SqlInstance $TestConfig.InstanceHadr -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceHadr
        $agname = "dbatoolsci_suspendagdb_agroup"
        $dbname = "dbatoolsci_suspendagdb_agroupdb-$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Name $dbname
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupPath
        $null = Get-DbaDatabase -SqlInstance $TestConfig.InstanceHadr -Database $dbname | Backup-DbaDatabase -BackupDirectory $backupPath -Type Log
        $ag = New-DbaAvailabilityGroup -Primary $TestConfig.InstanceHadr -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Certificate dbatoolsci_AGCert -UseLastBackup
        $null = Get-DbaAgDatabase -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname | Resume-DbaAgDbDataMovement
    }
    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agname
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname
        Remove-Item -Path $backupPath -Recurse
    }
    Context "Suspends data movement" {
        It "Should return suspended results" {
            $results = Suspend-DbaAgDbDataMovement -SqlInstance $TestConfig.InstanceHadr -Database $dbname -OutVariable "global:dbatoolsciOutput"
            $results.AvailabilityGroup | Should -Be $agname
            $results.Name | Should -Be $dbname
            $results.SynchronizationState | Should -Be 'NotSynchronizing'
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return the correct type" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [Microsoft.SqlServer.Management.Smo.AvailabilityDatabase]
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "Microsoft\.SqlServer\.Management\.Smo\.AvailabilityDatabase"
        }
    }
}