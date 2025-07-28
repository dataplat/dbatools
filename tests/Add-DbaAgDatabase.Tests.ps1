#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    # Where do we use $ModuleName?
    # Probably for mocking - but I'm not sure.
    $ModuleName               = "dbatools",
    # The following does not work:
    #   $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
    # Only $PSDefaultParameterValues is set and available in all parts of the test script.
    # $TestConfig is not set as global as we need it, so we would need two parameters.
    # But I now vote for setting $TestConfig outside of the testfiles right after importing the module.
    # But we must set the $PSDefaultParameterValues here so that they are available in every part of the test.
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# Better add UnitTests to the description to have a unique description for all Describe blocks.
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

        # We remove all the calls to Get-DbaProcess and Stop-DbaProcess as they are not needed with correct tests.
        #$null = Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue

        # Set variables, that we need in the tests.
        # I don't see the point in prefixing them all with "dbatoolsci",
        # better give them good names that relate to the command that we test.
        $agName = "addagdb_group"
        $dbName = "addagdb_db"
        $newDbName = "addagdb_db_2"

        # Collect all the created files to be able to remove them ant the end.
        $filesToRemove = @( )

        # Connect to the instance(s) using Connect-DbaInstance only if needed.
        # It is saver to use the instance name from $TestConfig to get a fresh new SMO every time.
        # In the future, we should also test with pre-opened connection.
        # Use dbatools commands whenever possible, so that these are tested here as well.
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $dbName
        $backup = Backup-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName -Path $TestConfig.Temp
        $filesToRemove += $backup.Path

        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Name $newDbName
        $backup = Backup-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $newDbName -Path $TestConfig.Temp
        $filesToRemove += $backup.Path

        $splatNewAg = @{
            Primary      = $TestConfig.instance3
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Database     = $dbName
            Certificate  = "dbatoolsci_AGCert"
        }
        $null = New-DbaAvailabilityGroup @splatNewAg

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove('*-Dba*:EnableException')
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues['*-Dba*:EnableException'] = $true

        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint
        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $dbName, $newDbName
        Remove-Item -Path $filesToRemove

        # As this is the last block we do not need to rest the $PSDefaultParameterValues.
    }

    Context "When adding AG database" {
        # We use the BeforeAll to run the test itself.
        # Results are saved in $results.
        BeforeAll {
            $splatAddAgDb = @{
                SqlInstance       = $TestConfig.instance3
                AvailabilityGroup = $agName
                Database          = $newDbName
            }
            $results = Add-DbaAgDatabase @splatAddAgDb
        }

        It "Does not warn" {
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Returns proper results" {
            $results.AvailabilityGroup | Should -Be $agName
            $results.Name | Should -Be $newDbName
            $results.IsJoined | Should -Be $true
        }
    }

    Context "When adding AG database that does not exists" {
        BeforeAll {
            $splatAddAgDb = @{
                SqlInstance       = $TestConfig.instance3
                AvailabilityGroup = $agName
                Database          = 'DoesNotExists'
                # As we don't want an output, we suppress the warning.
                # But we can still test the warning because WarningVariable is set globally.
                WarningAction     = 'SilentlyContinue'
            }
            $results = Add-DbaAgDatabase @splatAddAgDb
        }

        It "Does warn" {
            $WarnVar | Should -Match 'Database  is not found'
        }

        It "Does not return results" {
            $results | Should -BeNullOrEmpty
        }
    }
} #$TestConfig.instance2 for appveyor
