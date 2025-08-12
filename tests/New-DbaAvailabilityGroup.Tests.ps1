#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAvailabilityGroup",
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
                "Primary",
                "PrimarySqlCredential",
                "Secondary",
                "SecondarySqlCredential",
                "Name",
                "IsContained",
                "ReuseSystemDatabases",
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
        $agDbName = "dbatoolsci_addag_agroupdb"
        $agGroupName = "dbatoolsci_addag_agroup"
        $null = New-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $agDbName | Backup-DbaDatabase -FilePath "$($TestConfig.Temp)\$agDbName.bak"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        # We want to run all commands in the AfterEach block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $result = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $agGroupName -Confirm:$false
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $agDbName -Confirm:$false
        Remove-Item -Path "$($TestConfig.Temp)\$agDbName.bak" -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When creating availability group" {
        It "Should return an AG with a database when database is specified" {
            $splatAgWithDb = @{
                Primary      = $TestConfig.instance3
                Name         = $agGroupName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Database     = $agDbName
                Certificate  = "dbatoolsci_AGCert"
                Confirm      = $false
            }
            $results = New-DbaAvailabilityGroup @splatAgWithDb
            $results.AvailabilityDatabases.Name | Should -Be $agDbName
            $results.AvailabilityDatabases.Count | Should -Be 1 -Because "There should be only the named database in the group"
        }

        It "Should return an AG with no database when no database is specified" {
            $splatAgNoDb = @{
                Primary      = $TestConfig.instance3
                Name         = $agGroupName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = "dbatoolsci_AGCert"
                Confirm      = $false
            }
            $results = New-DbaAvailabilityGroup @splatAgNoDb
            $results.AvailabilityDatabases.Count | Should -Be 0 -Because "No database was named"
        }
    }
} #$TestConfig.instance2 for appveyor