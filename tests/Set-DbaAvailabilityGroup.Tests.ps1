param($ModuleName = 'dbatools')

Describe "Set-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAvailabilityGroup
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup
        }
        It "Should have AllAvailabilityGroups as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllAvailabilityGroups
        }
        It "Should have DtcSupportEnabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DtcSupportEnabled
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
        It "Should have BasicAvailabilityGroup as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter BasicAvailabilityGroup
        }
        It "Should have DatabaseHealthTrigger as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseHealthTrigger
        }
        It "Should have IsDistributedAvailabilityGroup as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsDistributedAvailabilityGroup
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Set-DbaAvailabilityGroup Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $null = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }

    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "Sets AG properties" {
        It "Returns modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -DtcSupportEnabled:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $false
        }

        It "Returns newly modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -DtcSupportEnabled
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $true
        }
    }
} #$global:instance2 for appveyor
