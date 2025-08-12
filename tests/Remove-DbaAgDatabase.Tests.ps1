#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgDatabase",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "AvailabilityGroup",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
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
        # To remove a database from an availability group, we need an availability group with a database already added.

        # Set variables. They are available in all the It blocks.
        $agName = "dbatoolsci_removeagdb_agroup"
        $dbName = "dbatoolsci_removeagdb_agroupdb"

        # Create the objects.
        $null = Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
        $server.Query("create database $dbName")
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName | Backup-DbaDatabase -FilePath "$backupPath\$dbName.bak"
        $null = Get-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName | Backup-DbaDatabase -FilePath "$backupPath\$dbName.trn" -Type Log
        
        $splatAg = @{
            Primary       = $TestConfig.instance3
            Name          = $agName
            ClusterType   = "None"
            FailoverMode  = "Manual"
            Database      = $dbName
            Confirm       = $false
            Certificate   = "dbatoolsci_AGCert"
            UseLastBackup = $true
        }
        $ag      = New-DbaAvailabilityGroup @splatAg

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $server -AvailabilityGroup $agName -Confirm $false
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm $false
        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbName -Confirm $false

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }
    Context "When removing database from availability group" {
        It "Should return removed results" {
            $results = Remove-DbaAgDatabase -SqlInstance $TestConfig.instance3 -Database $dbName -Confirm $false
            $results.AvailabilityGroup | Should -Be $agName
            $results.Database | Should -Be $dbName
            $results.Status | Should -Be "Removed"
        }

        It "Should have removed the database from the availability group" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
            $results.AvailabilityGroup | Should -Be $agName
            $results.AvailabilityDatabases.Name | Should -Not -Contain $dbName
        }
    }
} #$TestConfig.instance2 for appveyor
