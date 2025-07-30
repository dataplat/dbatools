#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName               = "dbatools",
    # $TestConfig has to be set outside of the tests by running: $TestConfig = Get-TestConfig
    # This will set $TestConfig.Defaults with the parameter defaults, including:
    # * Confirm = $false
    # * WarningVariable = 'WarnVar'
    # So you don't have to use -Confirm:$false and you can always use $WarnVar to test for warnings.
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Add-DbaAgDatabase UnitTests" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaAgDatabase
            $expected = $TestConfig.CommonParameters
            $expected += @(
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
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Add-DbaAgDatabase IntegrationTests" -Tag "IntegrationTests" {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Collect all the created files to be able to remove them in the AfterAll block.
        $filesToRemove = @( )

        # Explain what needs to be set up for the test:
        # To add a database to an availablity group, we need an availability group and a database that has been backed up.
        # For negative tests, we need a database without a backup and a non existing database.

        # Set variables. They are available in all the It blocks.
        $agName = "addagdb_group"
        $existingDbWithBackup = "dbWithBackup"
        $existingDbWithoutBackup = "dbWithoutBackup"
        $nonexistingDb = "dbdoesnotexist"

        # Create the objects.
        $splat = @{
            Primary      = $TestConfig.instance3
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splat

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $existingDbWithBackup
        $backup = Backup-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $existingDbWithBackup -Path $TestConfig.Temp
        $filesToRemove += $backup.Path

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $existingDbWithoutBackup

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        # Cleanup all created object.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $existingDbWithBackup, $existingDbWithoutBackup

        # Remove all created files.
        Remove-Item -Path $filesToRemove

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When adding AG database" {
        # We use the BeforeAll to run the test itself.
        # Results are saved in $results.
        BeforeAll {
            $splat = @{
                SqlInstance       = $TestConfig.instance3
                AvailabilityGroup = $agName
                Database          = $existingDbWithBackup
            }
            $results = Add-DbaAgDatabase @splat
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
                WarningAction     = 'SilentlyContinue'
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
                WarningAction     = 'SilentlyContinue'
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