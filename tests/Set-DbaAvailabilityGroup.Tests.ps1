param($ModuleName = 'dbatools')

Describe "Set-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Set-DbaAvailabilityGroup
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have AvailabilityGroup as a parameter" {
            $CommandUnderTest | Should -HaveParameter AvailabilityGroup -Type String[]
        }
        It "Should have AllAvailabilityGroups as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllAvailabilityGroups -Type Switch
        }
        It "Should have DtcSupportEnabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DtcSupportEnabled -Type Switch
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
        It "Should have BasicAvailabilityGroup as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter BasicAvailabilityGroup -Type Switch
        }
        It "Should have DatabaseHealthTrigger as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter DatabaseHealthTrigger -Type Switch
        }
        It "Should have IsDistributedAvailabilityGroup as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IsDistributedAvailabilityGroup -Type Switch
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AvailabilityGroup[]
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }
}

Describe "Set-DbaAvailabilityGroup Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }

    AfterAll {
        Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "Sets AG properties" {
        It "Returns modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false -DtcSupportEnabled:$false
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $false
        }

        It "Returns newly modified results" {
            $results = Set-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false -DtcSupportEnabled
            $results.AvailabilityGroup | Should -Be $agname
            $results.DtcSupportEnabled | Should -Be $true
        }
    }
} #$script:instance2 for appveyor
