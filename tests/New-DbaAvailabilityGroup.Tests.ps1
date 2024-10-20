param($ModuleName = 'dbatools')

Describe "New-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAvailabilityGroup
        }

        It "has all the required parameters" {
            $params = @(
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
                "EnableException",
                "WhatIf",
                "Confirm"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $global:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $dbname = "dbatoolsci_addag_agroupdb"
            $agname = "dbatoolsci_addag_agroup"
            $null = New-DbaDatabase -SqlInstance $global:instance3 -Database $dbname | Backup-DbaDatabase
        }
        AfterEach {
            $result = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $global:instance3 -Database $dbname -Confirm:$false
        }
        It "returns an ag with a db named" {
            $results = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert
            $results.AvailabilityDatabases.Name | Should -Be $dbname
            $results.AvailabilityDatabases.Count | Should -Be 1 -Because "There should be only the named database in the group"
        }
        It "returns an ag with no database if one was not named" {
            $results = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
            $results.AvailabilityDatabases.Count | Should -Be 0 -Because "No database was named"
        }
    }
} #$global:instance2 for appveyor
