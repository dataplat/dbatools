#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaAgDatabase",
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
                "Secondary",
                "SecondarySqlCredential",
                "InputObject",
                "SeedingMode",
                "SharedPath",
                "UseLastBackup",
                "AdvancedBackupParams",
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
        # To add a database to an availablity group, we need an availability group and a database that has been backed up.
        # For negative tests, we need a database without a backup and a non existing database.

        # Set variables. They are available in all the It blocks.
        $agName = "addagdb_group"
        $existingDbWithBackup = "dbWithBackup"
        $existingDbWithoutBackup = "dbWithoutBackup"
        $nonexistingDb = "dbdoesnotexist"

        # Create the objects.
        $splatAg = @{
            Primary      = $TestConfig.instance3
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatAg

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $existingDbWithBackup
        $null = Backup-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $existingDbWithBackup -Path $backupPath

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $existingDbWithoutBackup

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created object.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $existingDbWithBackup, $existingDbWithoutBackup

        # Remove the backup directory.
        Remove-Item -Path $backupPath -Recurse

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding AG database" {
        # We use the BeforeAll to run the test itself.
        # Results are saved in $results.
        BeforeAll {
            $splatAddAgDatabase = @{
                SqlInstance       = $TestConfig.instance3
                AvailabilityGroup = $agName
                Database          = $existingDbWithBackup
            }
            $results = Add-DbaAgDatabase @splatAddAgDatabase
        }

        # Always include this test to be sure that the command runs without warnings.
        It "Does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Returns proper results" {
            $results.AvailabilityGroup | Should -Be $agName
            $results.Name | Should -Be $existingDbWithBackup
            $results.IsJoined | Should -BeTrue
        }
    }

    Context "When adding AG database that does not have a backup" {
        BeforeAll {
            $splatAddAgDb = @{
                SqlInstance       = $TestConfig.instance3
                AvailabilityGroup = $agName
                Database          = $existingDbWithoutBackup
                # As we don't want an output, we suppress the warning.
                # But we can still test the warning because WarningVariable is set globally to WarnVar.
                WarningAction     = "SilentlyContinue"
            }
            $results = Add-DbaAgDatabase @splatAddAgDb
        }

        It "Does warn" {
            $WarnVar | Should -Match "Failed to add database $existingDbWithoutBackup to Availability Group $agName"
        }

        It "Does not return results" {
            $results | Should -BeNullOrEmpty
        }
    }

    Context "When adding AG database that does not exists" {
        BeforeAll {
            $splatAddAgDb = @{
                SqlInstance       = $TestConfig.instance3
                AvailabilityGroup = $agName
                Database          = $nonexistingDb
                WarningAction     = "SilentlyContinue"
            }
            $results = Add-DbaAgDatabase @splatAddAgDb
        }

        It "Does warn" {
            $WarnVar | Should -Match ([regex]::Escape("Database [$nonexistingDb] is not found"))
        }

        It "Does not return results" {
            $results | Should -BeNullOrEmpty
        }
    }
} #$TestConfig.instance2 for appveyor