param($ModuleName = 'dbatools')

Describe "New-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAvailabilityGroup
        }
        It "Should have Primary as a parameter" {
            $CommandUnderTest | Should -HaveParameter Primary
        }
        It "Should have PrimarySqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter PrimarySqlCredential
        }
        It "Should have Secondary as a parameter" {
            $CommandUnderTest | Should -HaveParameter Secondary
        }
        It "Should have SecondarySqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecondarySqlCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have IsContained as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsContained
        }
        It "Should have ReuseSystemDatabases as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ReuseSystemDatabases
        }
        It "Should have DtcSupport as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DtcSupport
        }
        It "Should have ClusterType as a parameter" {
            $CommandUnderTest | Should -HaveParameter ClusterType
        }
        It "Should have AutomatedBackupPreference as a parameter" {
            $CommandUnderTest | Should -HaveParameter AutomatedBackupPreference
        }
        It "Should have FailureConditionLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter FailureConditionLevel
        }
        It "Should have HealthCheckTimeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter HealthCheckTimeout
        }
        It "Should have Basic as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Basic
        }
        It "Should have DatabaseHealthTrigger as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseHealthTrigger
        }
        It "Should have Passthru as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Passthru
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have SharedPath as a parameter" {
            $CommandUnderTest | Should -HaveParameter SharedPath
        }
        It "Should have UseLastBackup as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter UseLastBackup
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have AvailabilityMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityMode
        }
        It "Should have FailoverMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter FailoverMode
        }
        It "Should have BackupPriority as a parameter" {
            $CommandUnderTest | Should -HaveParameter BackupPriority
        }
        It "Should have ConnectionModeInPrimaryRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInPrimaryRole
        }
        It "Should have ConnectionModeInSecondaryRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionModeInSecondaryRole
        }
        It "Should have SeedingMode as a parameter" {
            $CommandUnderTest | Should -HaveParameter SeedingMode
        }
        It "Should have Endpoint as a parameter" {
            $CommandUnderTest | Should -HaveParameter Endpoint
        }
        It "Should have EndpointUrl as a parameter" {
            $CommandUnderTest | Should -HaveParameter EndpointUrl
        }
        It "Should have Certificate as a parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate
        }
        It "Should have ConfigureXESession as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter ConfigureXESession
        }
        It "Should have IPAddress as a parameter" {
            $CommandUnderTest | Should -HaveParameter IPAddress
        }
        It "Should have SubnetMask as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubnetMask
        }
        It "Should have Port as a parameter" {
            $CommandUnderTest | Should -HaveParameter Port
        }
        It "Should have Dhcp as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Dhcp
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
