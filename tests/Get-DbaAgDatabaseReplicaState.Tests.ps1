#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgDatabaseReplicaState",
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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the backups that we want to clean up after the test, we create a directory that we can delete at the end.
        # Other files can be written there as well, maybe we change the name of that variable later. But for now we focus on backups.
        $backupPath = "$($TestConfig.Temp)\$CommandName-$(Get-Random)"
        $null = New-Item -Path $backupPath -ItemType Directory

        # Explain what needs to be set up for the test:
        # To test Get-DbaAgDatabaseReplicaState, we need an availability group with a database that has been backed up.

        # Set variables. They are available in all the It blocks.
        $agName = "dbatoolsci_getagdbrepstate_agroup"
        $dbName = "dbatoolsci_getagdbrepstate_agroupdb-$(Get-Random)"

        # Create the objects.
        $null = Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $dbName
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName | Backup-DbaDatabase -Path $backupPath
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName | Backup-DbaDatabase -Path $backupPath -Type Log

        $splatAg = @{
            Primary       = $TestConfig.instance3
            Name          = $agName
            ClusterType   = "None"
            FailoverMode  = "Manual"
            Database      = $dbName
            Certificate   = "dbatoolsci_AGCert"
            UseLastBackup = $true
        }
        $ag = New-DbaAvailabilityGroup @splatAg

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    Context "When getting AG database replica state" {
        It "Returns database replica state information" {
            $results = Get-DbaAgDatabaseReplicaState -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
            $results.AvailabilityGroup | Should -Be $agName
            $results.DatabaseName | Should -Contain $dbName
            $results.SynchronizationState | Should -Not -BeNullOrEmpty
        }

        It "Filters by database name" {
            $results = Get-DbaAgDatabaseReplicaState -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -Database $dbName
            $results.DatabaseName | Should -Be $dbName
        }

        It "Accepts pipeline input from Get-DbaAvailabilityGroup" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName | Get-DbaAgDatabaseReplicaState
            $results.AvailabilityGroup | Should -Be $agName
            $results.DatabaseName | Should -Contain $dbName
        }

        It "Filters by database when piped" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName | Get-DbaAgDatabaseReplicaState -Database $dbName
            $results.DatabaseName | Should -Be $dbName
        }

        It "Returns expected properties" {
            $results = Get-DbaAgDatabaseReplicaState -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName -Database $dbName
            $results.ComputerName | Should -Not -BeNullOrEmpty
            $results.InstanceName | Should -Not -BeNullOrEmpty
            $results.SqlInstance | Should -Not -BeNullOrEmpty
            $results.PrimaryReplica | Should -Not -BeNullOrEmpty
            $results.ReplicaServerName | Should -Not -BeNullOrEmpty
            $results.ReplicaRole | Should -Not -BeNullOrEmpty
        }
    }
} #$TestConfig.instance2 for appveyor
