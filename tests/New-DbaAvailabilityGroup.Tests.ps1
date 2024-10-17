param($ModuleName = 'dbatools')

Describe "New-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAvailabilityGroup
        }
        It "Should have Primary as a parameter" {
            $CommandUnderTest | Should -HaveParameter Primary -Type DbaInstanceParameter
        }
        It "Should have PrimarySqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimarySqlCredential -Type PSCredential
        }
        It "Should have Secondary as a parameter" {
            $CommandUnderTest | Should -HaveParameter Secondary -Type DbaInstanceParameter[]
        }
        It "Should have SecondarySqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondarySqlCredential -Type PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String
        }
        It "Should have IsContained as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsContained -Type Switch
        }
        It "Should have ReuseSystemDatabases as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReuseSystemDatabases -Type Switch
        }
        It "Should have DtcSupport as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DtcSupport -Type Switch
        }
        It "Should have ClusterType as a parameter" {
            $CommandUnderTest | Should -HaveParameter ClusterType -Type String
        }
        It "Should have AutomatedBackupPreference as a parameter" {
            $CommandUnderTest | Should -HaveParameter AutomatedBackupPreference -Type String
        }
        It "Should have FailureConditionLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter FailureConditionLevel -Type String
        }
        It "Should have HealthCheckTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter HealthCheckTimeout -Type Int32
        }
        It "Should have Basic as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Basic -Type Switch
        }
        It "Should have DatabaseHealthTrigger as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseHealthTrigger -Type Switch
        }
        It "Should have Passthru as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru -Type Switch
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have SharedPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter SharedPath -Type String
        }
        It "Should have UseLastBackup as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter UseLastBackup -Type Switch
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have AvailabilityMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityMode -Type String
        }
        It "Should have FailoverMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter FailoverMode -Type String
        }
        It "Should have BackupPriority as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupPriority -Type Int32
        }
        It "Should have ConnectionModeInPrimaryRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInPrimaryRole -Type String
        }
        It "Should have ConnectionModeInSecondaryRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInSecondaryRole -Type String
        }
        It "Should have SeedingMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter SeedingMode -Type String
        }
        It "Should have Endpoint as a parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint -Type String
        }
        It "Should have EndpointUrl as a parameter" {
            $CommandUnderTest | Should -HaveParameter EndpointUrl -Type String[]
        }
        It "Should have Certificate as a parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate -Type String
        }
        It "Should have ConfigureXESession as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigureXESession -Type Switch
        }
        It "Should have IPAddress as a parameter" {
            $CommandUnderTest | Should -HaveParameter IPAddress -Type IPAddress[]
        }
        It "Should have SubnetMask as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubnetMask -Type IPAddress
        }
        It "Should have Port as a parameter" {
            $CommandUnderTest | Should -HaveParameter Port -Type Int32
        }
        It "Should have Dhcp as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Dhcp -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            $null = Get-DbaProcess -SqlInstance $env:instance3 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $dbname = "dbatoolsci_addag_agroupdb"
            $agname = "dbatoolsci_addag_agroup"
            $null = New-DbaDatabase -SqlInstance $env:instance3 -Database $dbname | Backup-DbaDatabase
        }
        AfterEach {
            $result = Remove-DbaAvailabilityGroup -SqlInstance $env:instance3 -AvailabilityGroup $agname -Confirm:$false
        }
        AfterAll {
            $null = Remove-DbaDatabase -SqlInstance $env:instance3 -Database $dbname -Confirm:$false
        }
        It "returns an ag with a db named" {
            $results = New-DbaAvailabilityGroup -Primary $env:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Database $dbname -Confirm:$false -Certificate dbatoolsci_AGCert
            $results.AvailabilityDatabases.Name | Should -Be $dbname
            $results.AvailabilityDatabases.Count | Should -Be 1 -Because "There should be only the named database in the group"
        }
        It "returns an ag with no database if one was not named" {
            $results = New-DbaAvailabilityGroup -Primary $env:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
            $results.AvailabilityDatabases.Count | Should -Be 0 -Because "No database was named"
        }
    }
} #$env:instance2 for appveyor
