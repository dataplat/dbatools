param($ModuleName = 'dbatools')

Describe "Remove-DbaAvailabilityGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaAvailabilityGroup
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
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $agname = "dbatoolsci_removewholegroup"
            $null = New-DbaAvailabilityGroup -Primary $global:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false
        }

        It "removes the newly created ag" {
            $results = Remove-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname -Confirm:$false
            $results.Status | Should -Be 'Removed'
            $results.AvailabilityGroup | Should -Be $agname
        }

        It "really removed the ag" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $global:instance3 -AvailabilityGroup $agname
            $results | Should -BeNullOrEmpty
        }
    }
} #$global:instance2 for appveyor
