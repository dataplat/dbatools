#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "New-DbaAvailabilityGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Primary",
                "PrimarySqlCredential",
                "Secondary",
                "SecondarySqlCredential",
                "Name",
                "ReuseSystemDatabases",
                "IsContained",
                "DtcSupport",
                "ClusterType",
                "AutomatedBackupPreference",
                "FailureConditionLevel",
                "HealthCheckTimeout",
                "Basic",
                "DatabaseHealthTrigger",
                "Passthru",
                "Database",
                "SharedPath",
                "UseLastBackup",
                "Force",
                "AvailabilityMode",
                "FailoverMode",
                "BackupPriority",
                "ConnectionModeInPrimaryRole",
                "ConnectionModeInSecondaryRole",
                "SeedingMode",
                "Endpoint",
                "EndpointUrl",
                "Certificate",
                "ConfigureXESession",
                "IPAddress",
                "SubnetMask",
                "Port",
                "Dhcp",
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

        $null = Get-DbaProcess -SqlInstance $TestConfig.instance3 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $databaseName = "dbatoolsci_addag_agroupdb"
        $availabilityGroupName = "dbatoolsci_addag_agroup"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $databaseName | Backup-DbaDatabase -FilePath "$($TestConfig.Temp)\$databaseName.bak"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $result = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $availabilityGroupName -Confirm:$false -ErrorAction SilentlyContinue
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false -ErrorAction SilentlyContinue
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $databaseName -Confirm:$false
        Remove-Item -Path "$($TestConfig.Temp)\$databaseName.bak" -ErrorAction SilentlyContinue
    }

    Context "When creating availability groups" {
        It "Returns an ag with a database when database is specified" {
            $splatWithDatabase = @{
                Primary      = $TestConfig.instance3
                Name         = $availabilityGroupName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Database     = $databaseName
                Certificate  = "dbatoolsci_AGCert"
                Confirm      = $false
            }
            $results = New-DbaAvailabilityGroup @splatWithDatabase
            $results.AvailabilityDatabases.Name | Should -Be $databaseName
            $results.AvailabilityDatabases.Count | Should -Be 1 -Because "There should be only the named database in the group"
        }

        It "Returns an ag with no database if one was not named" {
            $splatWithoutDatabase = @{
                Primary      = $TestConfig.instance3
                Name         = $availabilityGroupName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = "dbatoolsci_AGCert"
                Confirm      = $false
            }
            $results = New-DbaAvailabilityGroup @splatWithoutDatabase
            $results.AvailabilityDatabases.Count | Should -Be 0 -Because "No database was named"
        }
    }
} #$TestConfig.instance2 for appveyor